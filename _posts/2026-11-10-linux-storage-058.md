---
layout: article
title: 시스템 관리_58 Linux XFS 파일시스템 메타데이터 손상 복구와 xfs_repair 안전 적용 가이드
tags: [Linux, Storage, XFS, xfs_repair, Metadata-Corruption, Log-Inconsistency, Filesystem, Troubleshooting]
keys: 261110-linux-storage-058
---

- 출처 / 참고: Red Hat Enterprise Linux Storage Administration Guide (Repairing an XFS File System), Linux man-pages (xfs_repair(8), xfs_metadump(8), xfs_logprint(8))

> 명령어: `xfs_repair`, `xfs_metadump`, `xfs_info`, `dmesg`, `umount`, `mount`  
> 키워드: XFS, Metadata Corruption, xfs_repair, xfs_repair -L, Log Inconsistency, Superblock, Structure needs cleaning, EUCLEAN  
> 사용처: 비정상 전원 차단, 스토리지 단절 후 XFS 파티션 마운트 실패('Structure needs cleaning') 및 파일시스템 손상 복구

---

> 실행예제

XFS 파티션 마운트 시 `mount: /data: mount(2) system call failed: Structure needs cleaning` 오류가 발생하거나 커널 로그에 XFS 내부 메타데이터 불일치 에러가 기록될 때, 디바이스 상태를 먼저 진단합니다.

```bash
# 1. 커널 로그에서 XFS 메타데이터 손상 및 I/O 에러 확인
$ sudo dmesg -T | grep -iE "xfs|corrupt|euclean"
# [Tue Nov 10 09:15:10 2026] XFS (sdb1): Metadata corruption detected at xfs_dir3_block_read_verify+0x110/0x140 [xfs], xfs_dir3_block block 0x180050
# [Tue Nov 10 09:15:10 2026] XFS (sdb1): Unmount and run xfs_repair
# [Tue Nov 10 09:15:10 2026] XFS (sdb1): Corruption of in-memory data detected. Shutting down filesystem
# -> 커널이 추가 데이터 파괴를 막기 위해 파일시스템을 강제 셧다운(Shutdown) 시킨 상태 확인

# 2. 드라이런(-n) 옵션을 통한 XFS 파일시스템 읽기 전용 무결성 사전 점검 (수정 없음)
$ sudo xfs_repair -n /dev/sdb1
# Phase 1 - find and verify superblock...
# Phase 2 - using internal log
#         - zero log...
# ALERT: The filesystem has valuable metadata changes in a log which is being ignored
# because the -n option was used. Expect spurious inconsistencies which may be resolved
# by first mounting the filesystem to replay the log.
#         - scan filesystem freespace and inode maps...
# -> 저널 로그(Log)에 아직 디스크로 플러시되지 않은 변경 내역이 남아있음을 경고함

# 3. 복구 전 메타데이터 덤프(Metadump) 백업 생성 (만일의 사태 대비)
$ sudo xfs_metadump -o /dev/sdb1 /tmp/sdb1_xfs_meta.dump
# -> 실제 사용자 데이터는 제외하고 수 MB의 메타데이터 구조만 안전하게 백업

# 4. 일반 xfs_repair 실행 시 저널 로그 불일치로 중단되는 현상 확인
$ sudo xfs_repair /dev/sdb1
# ERROR: The filesystem has valuable metadata changes in a log which needs to be replayed.
# Mount the filesystem to replay the log, and unmount it before re-running xfs_repair.
# If you are unable to mount the filesystem, then use the -L option to destroy the log and attempt a repair.
```

&nbsp;
&nbsp;

## 스크립트

손상된 XFS 디바이스를 인자로 받아 마운트 해제 여부를 확인하고, 안전을 위해 `xfs_metadump`로 메타데이터를 백업한 뒤, 정상 마운트/언마운트를 통한 저널 로그 재생(Replay)을 먼저 시도하고 불가피한 경우에만 최후의 수단으로 로그 초기화(`-L`) 복구를 안내/수행하는 쉘 스크립트입니다.

```bash
#!/bin/bash
# safe_xfs_repair.sh - Safely diagnose and repair corrupted XFS filesystems

TARGET_DEV=${1:-""}
BACKUP_DIR="/var/tmp/xfs_recovery_backups"

echo "=========================================="
echo " [Linux XFS 파일시스템 안전 복구 도구]"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] 블록 장치 복구를 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

if [ -z "$TARGET_DEV" ] || [ ! -b "$TARGET_DEV" ]; then
    echo "  [오류] 유효한 블록 디바이스 경로를 입력하십시오."
    echo "  사용법: $0 /dev/sdb1"
    exit 1
fi

echo "  대상 블록 디바이스: ${TARGET_DEV}"

# 1. 마운트 상태 점검 및 언마운트 확인
if grep -qs "^${TARGET_DEV}\s" /proc/mounts; then
    MNT_PATH=$(grep "^${TARGET_DEV}\s" /proc/mounts | awk '{print $2}')
    echo "  [경고] ${TARGET_DEV} 장치가 현재 ${MNT_PATH}에 마운트되어 있습니다."
    echo "  -> xfs_repair는 반드시 언마운트 상태에서 실행해야 합니다. 언마운트 시도..."
    umount "$TARGET_DEV" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "  [실패] 장치가 사용 중(Busy)이어서 언마운트할 수 없습니다. 점유 프로세스를 먼저 종료하십시오."
        exit 1
    fi
    echo "  [성공] 언마운트 완료."
fi

# 2. 복구 전 메타데이터 스냅샷 백업
mkdir -p "$BACKUP_DIR"
DUMP_FILE="${BACKUP_DIR}/$(basename "$TARGET_DEV")_$(date +%Y%m%d_%H%M%S).metadump"
echo -e "\n[1] 메타데이터 백업 생성 중 (xfs_metadump):"
xfs_metadump -o "$TARGET_DEV" "$DUMP_FILE" 2>/dev/null
if [ -f "$DUMP_FILE" ]; then
    echo "  [완료] 메타데이터 백업 저장됨: ${DUMP_FILE}"
else
    echo "  [주의] 메타데이터 덤프 생성에 실패했습니다. (심각한 슈퍼블록 손상 가능성)"
fi

# 3. 1단계: 임시 마운트 후 언마운트를 통한 정상 저널 로그 재생(Replay) 시도
echo -e "\n[2] 1단계: 정상 마운트를 통한 저널 로그 재생(Log Replay) 시도 중..."
TMP_MNT=$(mktemp -d /mnt/xfs_replay_XXXX)
mount "$TARGET_DEV" "$TMP_MNT" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "  [성공] 임시 마운트 성공! 저널 로그가 정상적으로 디스크에 반영되었습니다."
    umount "$TMP_MNT"
    rmdir "$TMP_MNT"
    
    echo -e "\n[3] 2단계: 표준 무결성 복구(xfs_repair) 실행 중..."
    xfs_repair "$TARGET_DEV"
else
    rmdir "$TMP_MNT"
    echo "  [실패] 저널 로그 자체가 손상되어 마운트 재생이 불가능합니다."
    echo -e "\n[3] 2단계: 최후의 수단으로 저널 로그 초기화 복구(xfs_repair -L) 실행:"
    echo "  [경고] -L 옵션은 커밋되지 않은 최신 트랜잭션 일부를 유실시킬 수 있습니다."
    xfs_repair -L "$TARGET_DEV"
fi

# 4. 최종 결과 검증
if [ $? -eq 0 ]; then
    echo -e "\n=========================================="
    echo " [복구 성공] 파일시스템 정합성이 복원되었습니다."
    echo " -> lost+found 디렉터리에 고아 파일이 생성되었는지 확인하십시오."
    echo "=========================================="
else
    echo -e "\n=========================================="
    echo " [복구 실패] 하드웨어 배드 섹터 또는 스토리지 컨트롤러 장애를 점검하십시오."
    echo "=========================================="
fi
```

&nbsp;
&nbsp;

## 해설

XFS는 대용량 처리와 병렬 I/O에 최적화된 고성능 저널링 파일시스템이지만, 스토리지 경로의 갑작스러운 단절이나 전원 차단으로 디스크 쓰기가 중간에 찢어지면 커널이 파일시스템의 연쇄 파괴를 막기 위해 즉시 I/O를 차단하고 **Shutdown(`Structure needs cleaning`)** 상태로 전환합니다.

### 1. XFS 저널 로그(Journal Log)와 `xfs_repair -L`의 원리

XFS는 성능과 정합성을 위해 파일시스템 변경 메타데이터를 실제 블록에 기록하기 전 내부 저널 로그 영역(Internal Log)에 먼저 기록합니다.

* **정상 복구 흐름 (Log Replay)**:
  * 비정상 종료 후 다시 `mount`를 시도하면 XFS 커널 드라이버가 저널 로그를 읽어 미완료된 메타데이터 변경 사항을 자동으로 재생(Replay)하여 복구합니다.
  * 따라서 **`xfs_repair`를 돌리기 전에 반드시 한 번 `mount` 후 `umount`를 거쳐 로그를 비워주는 것**이 표준 절차입니다.
* **`xfs_repair -L` (Zero Log)의 의미**:
  * 저널 로그 블록 자체가 깨져서 마운트조차 실패할 때 사용하는 강제 옵션입니다.
  * `-L`은 저널 로그 영역을 강제로 `0`으로 초기화(파괴)한 뒤 디스크 상의 남은 B+트리와 아이노드(Inode)를 훑어 구조를 강제로 맞춥니다.

### 2. 단계별 복구 절차

#### 1단계: 언마운트 및 읽기 전용 드라이런 검사
```bash
sudo umount /dev/sdb1
sudo xfs_repair -n /dev/sdb1
```
* `-n` 옵션은 실제 디스크를 전혀 수정하지 않고 손상 규모만 진단합니다.

#### 2단계: 마운트/언마운트를 통한 저널 플러시 후 표준 복구
```bash
sudo mount /dev/sdb1 /mnt
sudo umount /dev/sdb1
sudo xfs_repair /dev/sdb1
```

#### 3단계: 마운트 실패 시 최후의 수단 `-L` 적용
```bash
sudo xfs_repair -L /dev/sdb1
```

&nbsp;
&nbsp;

## 주의사항

1. **마운트된 상태에서 `xfs_repair` 절대 실행 금지**:
   * 읽기/쓰기로 마운트된 파티션에 강제로 복구 도구를 실행하면 메모리 상의 페이지 캐시와 디스크 메타데이터가 충돌하여 파일시스템 전체가 영구 복구 불능 상태로 파괴됩니다.

2. **`xfs_repair -L` 사용 시 데이터 유실 및 `lost+found` 확인**:
   * `-L` 옵션은 손상 직전 수 초간 메모리에 머물던 최신 트랜잭션을 포기하는 작업입니다. 복구 후 마운트하면 디렉터리 링크가 끊어진 파일들이 최상위 경로의 `/lost+found` 디렉터리에 숫자로 된 아이노드 이름(`#124512`)으로 모이므로, 데이터베이스 파일이나 중요 설정 파일이 이동되었는지 반드시 전수 검사해야 합니다.

3. **하드웨어 스토리지 캐시 배터리(BBU) 점검**:
   * XFS 손상이 반복된다면 리눅스 버그가 아니라 하부 RAID 컨트롤러의 Write-Back 캐시 배터리가 방전되었거나, SAN 스토리지 경로의 비정상 패킷 유실이 원인일 확률이 높으므로 인프라 계층의 쓰기 배리어(Write Barrier) 설정을 점검해야 합니다.