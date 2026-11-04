---
layout: article
title: 시스템 관리_52 대용량 NAS rsync 데이터 동기화 중 IO 병목 및 퍼미션 유실 오류 원인 분석과 최적화 가이드
tags: [Linux, Storage, NAS, rsync, IO-Bottleneck, Permissions, ACL, Parallel-rsync, File-Sync, Troubleshooting]
keys: 261104-linux-storage-052
---

- 출처 / 참고: Linux man-pages (rsync(1), getfacl(1), setfacl(1)), Sambas rsync performance tuning documentation

> 명령어: `rsync`, `iostat`, `xargs`, `parallel`, `getfacl`, `setfacl`, `ionice`  
> 키워드: rsync, NAS sync, I/O Bottleneck, Permission Denied, ACL loss, --numeric-ids, parallel rsync, --inplace, whole-file  
> 사용처: 수백만 개 대용량 NAS/NFS 데이터 마이그레이션 중 전송 속도 저하, 스토리지 과부하(I/O Hang) 및 파일 소유권/권한 왜곡 복구

---

> 실행예제

수백만 개의 소용량 파일이 포함된 대규모 NAS 디렉터리를 `rsync`로 동기화할 때, 초기 파일 목록 빌드(`building file list`) 단계에서 멈추거나 디스크 I/O가 100% 포화되어 전송 속도가 극도로 떨어지고 동기화 후 권한이 누락되는 현상을 진단합니다.

```bash
# 1. 단일 rsync 실행 시 파일 목록 생성(Building file list) 정체 및 메모리 점유 확인
$ rsync -avz /mnt/nas_source/ /mnt/nas_target/
# building file list ...
# -> 수백만 개 파일 탐색 시 수 시간 동안 실제 데이터 전송 없이 메모리와 CPU를 수 GB 소모하며 멈춤

# 2. rsync 프로세스로 인한 디스크 I/O 병목 및 await 지연 확인 (iostat)
$ iostat -xz 1 3
# Device            r/s     w/s     rkB/s     wkB/s   r_await  w_await   aqu-sz  %util
# sdb1          3210.00  120.00  45200.00   1200.00     32.40    15.80    12.50  99.90
# -> 디스크 가동률(%util)이 100%에 달하고 r_await가 30ms를 초과하여 스토리지 읽기 병목 발생

# 3. 소스 및 대상 디렉터리의 파일 권한(UID/GID) 및 확장 속성(ACL) 불일치 확인
$ ls -l /mnt/nas_source/data_file.txt
# -rw-r--r--+ 1 appuser appgroup 1024 Nov  4 10:00 /mnt/nas_source/data_file.txt
$ ls -l /mnt/nas_target/data_file.txt
# -rw-r--r--  1 nobody  nobody   1024 Nov  4 10:00 /mnt/nas_target/data_file.txt
# -> 소유자가 nobody로 바뀌고 POSIX ACL 표시(+)가 사라져 권한 유실 발생

# 4. 소스 파일의 상세 POSIX ACL 정보 확인
$ getfacl /mnt/nas_source/data_file.txt
# # file: mnt/nas_source/data_file.txt
# # owner: appuser
# # group: appgroup
# user::rw-
# user:backupadmin:rwx
# group::r--
# mask::rwx
# other::r--
```

&nbsp;
&nbsp;

## 스크립트

단일 스레드 `rsync`의 병목을 해결하기 위해 최상위 디렉터리 구조를 분할하여 다중 프로세스(`parallel / xargs`)로 병렬 동기화하고, UID/GID 매핑 오류 및 POSIX ACL 유실을 방지하는 엔터프라이즈급 마이그레이션 실행 쉘 스크립트입니다.

```bash
#!/bin/bash
# parallel_rsync_sync.sh - High-performance parallel rsync with permission/ACL preservation

SRC_DIR=${1:-"/mnt/nas_source"}
DST_DIR=${2:-"/mnt/nas_target"}
JOBS=${3:-4}

echo "=========================================="
echo " [대용량 NAS 고속 병렬 rsync 동기화기]"
echo " 소스: ${SRC_DIR}"
echo " 대상: ${DST_DIR}"
echo " 병렬 스레드 수: ${JOBS}"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] 권한(UID/GID/ACL) 완벽 보존을 위해 루트(root) 권한으로 실행하십시오."
    exit 1
fi

if [ ! -d "$SRC_DIR" ] || [ ! -d "$DST_DIR" ]; then
    echo "  [오류] 소스 또는 대상 디렉터리가 존재하지 않습니다."
    exit 1
fi

# 1. rsync 필수 플래그 설정
# -a: 아카이브 (rlptgo)
# -H: 하드링크 보존
# -A: POSIX ACL 보존
# -X: 확장 속성(xattrs) 보존
# --numeric-ids: 계정명 대신 숫자 UID/GID 직접 매핑 (nobody 방지)
# --inplace: 임시 파일을 만들지 않고 대상 파일에 직접 덮어쓰기 (스토리지 쓰기 부하 및 I/O 절감)
RSYNC_OPTS="-aHAX --numeric-ids --inplace --no-whole-file --info=progress2"

# 2. 최상위 1레벨 디렉터리/파일 목록 분할 추출
echo -e "\n[1] 1차 디렉터리 구조 스캔 중..."
ITEM_LIST=$(find "$SRC_DIR" -mindepth 1 -maxdepth 1 -printf "%P\n")

if [ -z "$ITEM_LIST" ]; then
    echo "  [안내] 소스 디렉터리에 동기화할 파일이 없습니다."
    exit 0
fi

# 3. xargs 기반 병렬 rsync 전송 실행
echo -e "\n[2] 병렬 rsync 동기화 시작 (${JOBS} 프로세스 가동):"
echo "$ITEM_LIST" | xargs -I {} -P "$JOBS" bash -c '
    ITEM="{}"
    echo "  -> [작업 시작] ${ITEM}"
    ionice -c2 -n7 rsync '"$RSYNC_OPTS"' "'"$SRC_DIR"'/${ITEM}" "'"$DST_DIR"'/"
    if [ $? -eq 0 ]; then
        echo "  -> [작업 완료] ${ITEM}"
    else
        echo "  -> [오류 발생] ${ITEM}"
    fi
'

# 4. 최상위 디렉터리 자체의 메타데이터 및 권한 최종 동기화
echo -e "\n[3] 최상위 루트 디렉터리 메타데이터 동기화:"
rsync -dHAX --numeric-ids "$SRC_DIR/" "$DST_DIR/"

echo -e "\n=========================================="
echo " [동기화 작업 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

대용량 NAS 환경(수백만 개의 작은 파일, 수십 TB의 용량)에서 단순 `rsync -avz` 명령어로 동기화를 진행할 경우, 심각한 **I/O 병목에 따른 속도 저하**와 **권한/소유권 유실(Nobody 전환)** 현상이 빈번하게 발생합니다.

### 1. I/O 병목 및 속도 저하 발생 원인

1. **단일 프로세스 메모리 병목과 "Building file list" 정체**:
   * 기본 `rsync`는 단일 스레드로 동작합니다. 전송을 시작하기 전에 소스 트리의 모든 파일 메타데이터(inode, mtime, size)를 메모리에 한꺼번에 올려 정렬합니다. 파일 수가 1,000만 개를 넘어서면 목록 생성에만 수 시간 이상 소요되며 기가바이트 단위의 RAM을 소모합니다.
2. **소용량 파일에서 압축(`-z`) 사용에 따른 CPU 오버헤드**:
   * 1Gbps 이상의 고속 로컬/내부망 환경에서 이미지, 압축파일, 로그 등의 작은 파일에 `-z`(gzip 압축)를 걸면 네트워크 병목보다 CPU 압축 연산 병목이 커져 전송 속도가 최대 1/10 수준으로 급락합니다.
3. **임시 파일 생성 및 Rename 오버헤드**:
   * `rsync`는 기본적으로 전송 중 대상 디렉터리에 `.`으로 시작하는 임시 파일을 만든 뒤, 전송이 끝나면 원래 이름으로 Rename합니다. NFS/NAS 환경에서 수백만 번의 Create/Rename RPC 호출은 스토리지 메타데이터 서버에 극심한 I/O 대기열(`await`)을 유발합니다.

### 2. 퍼미션 및 소유권 유실 발생 원인

1. **`--numeric-ids` 누락으로 인한 nobody/nogroup 왜곡**:
   * 소스 서버의 계정 `appuser`(UID 1001)를 타겟 서버로 전송할 때 타겟 서버에 동일한 문자열의 계정이 없으면, rsync는 이를 기본 계정인 `nobody`(UID 65534)로 강제 변경해 버립니다.
2. **POSIX ACL(`-A`) 및 확장 속성(`-X`) 누락**:
   * 일반 아카이브 옵션인 `-a`는 표준 리눅스 권한(755, 644 등)만 보존하며, `setfacl`로 부여된 세부 사용자 권한(POSIX ACL)이나 파일 확장 속성은 기본적으로 버려집니다. 반드시 `-A`와 `-X`를 명시해야 합니다.

### 3. 단계별 성능 튜닝 및 최적화 방법

#### 1) 디렉터리 분할 병렬 처리 (Parallel rsync)
단일 스레드의 한계를 극복하기 위해 `find`와 `xargs -P` 또는 `parallel`을 결합하여 CPU 코어 수에 맞게 4~8개의 rsync 워커를 동시에 띄워 디스크 큐를 최적으로 채웁니다.

#### 2) `--inplace` 옵션 적용 (메타데이터 I/O 반감)
임시 파일을 만들지 않고 대상 블록에 직접 덮어쓰도록 유도하여 스토리지 메타데이터 RPC 부하를 절반으로 줄입니다.
```bash
rsync -aHAX --numeric-ids --inplace /source/ /target/
```

#### 3) `ionice`를 통한 운영 스토리지 I/O 보호
동기화 작업이 운영 중인 NAS의 대역폭을 모두 잠식하지 않도록 I/O 우선순위를 조절합니다.
```bash
ionice -c2 -n7 rsync ...
```

&nbsp;
&nbsp;

## 주의사항

1. **`--delete` 옵션 사용 시 반드시 드라이런(`-n`) 사전 검증**:
   * 동기화 대상에서 삭제된 파일을 타겟에서도 지우는 `--delete` 옵션은 경로 끝의 슬래시(`/`) 유무에 따라 타겟 디렉터리 전체를 삭제할 수 있습니다. 운영 환경에서는 반드시 `rsync -av --dry-run --delete`로 삭제 대상을 먼저 검증한 후 본 작업을 수행해야 합니다.

2. **`--inplace` 사용 시 장애 발생에 따른 정합성 주의**:
   * `--inplace` 옵션은 성능을 대폭 향상시키지만 전송 도중 네트워크가 끊기면 대상 파일이 부분적으로 쓰여진(Partial) 불완전 상태로 남게 됩니다. 동기화 완료 후 반드시 한 번 더 rsync를 실행하여 체크섬(`-c`) 또는 변경분을 최종 검증해야 합니다.

3. **NFS 클라이언트 속성 캐시(ac/noac) 고려**:
   * NAS가 NFS로 마운트된 상태에서 다중 rsync를 돌릴 경우, 마운트 옵션에 `actimeo=30` 이상을 주어 메타데이터 GETATTR 호출 빈도를 낮추어야 NAS 컨트롤러의 CPU 부하를 방지할 수 있습니다.