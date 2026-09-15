---
layout: article
title: 시스템 관리_03 리눅스 "Read-only file system" 에러 재부팅 없이 복구하기
tags: [Linux, Filesystem, Mount, Troubleshooting, Storage, ShellScript]
keys: 260915-linux-storage-003
---

- 출처 / 참고: 리눅스 파일시스템 마운트 관리 및 스토리지 복구 가이드
> 명령어: `mount`, `dmesg`, `fsck`, `lsof`, `fuser`, `findmnt`  
> 키워드: `Read-only file system`, `remount,rw`, `dmesg I/O error`, `errors=remount-ro`, `fsck`  
> 사용처: 운영 중인 리눅스 서버에서 특정 파티션이 갑작스럽게 읽기 전용(ro)으로 전환되어 쓰기/수정이 불가능할 때, 서비스 중단(재부팅) 없이 마운트 상태를 복구하고 원인을 진단할 때  

---

> 실행예제

파일 생성, 로그 기록, 패키지 설치 등 쓰기 작업을 시도할 때 커널 레벨에서 쓰기 거부 에러(`Read-only file system`)가 발생하며 서비스 데몬이 비정상 종료되거나 파일 수정이 차단되는 상황입니다.

```bash
$ touch /data/test.txt
touch: cannot touch '/data/test.txt': Read-only file system

$ findmnt -no TARGET,FSTYPE,OPTIONS /data
/data ext4 ro,relatime,errors=remount-ro

$ dmesg -T | grep -E -i 'ext4|error|remount-ro' | tail -n 5
[Tue Sep 15 10:12:04 2026] EXT4-fs error (device sdb1): ext4_lookup:1842: inode #262145: comm mysqld: deleted inode referenced: 262150
[Tue Sep 15 10:12:04 2026] Aborting journal on device sdb1-8.
[Tue Sep 15 10:12:04 2026] EXT4-fs (sdb1): Remounting filesystem read-only
```

&nbsp;
&nbsp;

## 스크립트

마운트된 파일시스템 중 읽기 전용(ro) 플래그가 걸린 파티션을 식별하고, 커널 링 버퍼(dmesg)에서 스토리지/파일시스템 에러를 탐색한 뒤 안전하게 읽기/쓰기(rw) 재마운트를 시도하는 셸 스크립트입니다.

```bash
#!/bin/bash
# Read-only 마운트 파티션 감지 및 점검/복구 스크립트

echo "[*] Checking Read-Only (ro) Mounted Filesystems..."
echo "--------------------------------------------------"
printf "%-20s %-25s %-10s %s\n" "DEVICE" "MOUNT_POINT" "FSTYPE" "OPTIONS"

read_only_mounts=$(findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS | awk '$4 ~ /(^\vert{},)ro($|,)/ && $3 !~ /squashfs|iso9660/')

if [ -z "$read_only_mounts" ]; then
    echo "No unexpected read-only filesystems found."
else
    echo "$read_only_mounts" | while read -r src tgt fstype opts; do
        printf "%-20s %-25s %-10s %s\n" "$src" "$tgt" "$fstype" "$opts"
    done
fi

echo ""
echo "[*] Recent Kernel Filesystem / I/O Errors (dmesg)..."
echo "--------------------------------------------------"
dmesg -T --level=err,crit,alert | grep -E -i 'EXT[234]|XFS|Btrfs|I/O error|remount-ro' | tail -n 10

echo ""
echo "[*] Read-Only Remount Guide:"
echo "--------------------------------------------------"
echo "If no severe hardware I/O error occurred, run:"
echo "  sudo mount -o remount,rw <MOUNT_POINT>"
```

&nbsp;
&nbsp;

## 해설

리눅스 파일시스템이 예기치 않게 읽기 전용(Read-only)으로 전환되는 주원인은 커널의 데이터 보호 메커니즘입니다.

`/etc/fstab`에 명시된 `errors=remount-ro` 옵션(ext4 기본 동작)에 의해, 디스크 I/O 장애, 저널링 블록 손상, 메타데이터 불일치 발생 시 커널이 파일시스템 무결성을 지키기 위해 추가 쓰기를 차단하고 읽기 전용으로 자동 격리합니다.

### 1. 원인 파악 (dmesg 및 스마트 디스크 진단)

단순한 파일시스템 메타데이터 불일치인지, 물리 디스크/SAN 연결 단절인지 커널 로그를 확인합니다.

```bash
# 파일시스템 및 스토리지 관련 커널 에러 로그 확인
$ sudo dmesg -T | grep -E -i 'error|I/O|buffer|journal' | tail -n 20

# 스마트 디스크 상태 및 하드웨어 이상 점검 (SATA/NVMe)
$ sudo smartctl -H /dev/sdb
```

  - `Buffer I/O error` 또는 `blk_update_request: I/O error`가 연속 출력된다면 물리 케이블 불량, 컨트롤러 장애, 스토리지 볼륨 언마운트 가능성이 큽니다.

  - `EXT4-fs error (device ...): Remounting filesystem read-only`만 단발성으로 나타난다면 저널 손상이나 일시적 메타데이터 불일치일 확률이 높습니다.

### 2. 읽기/쓰기(rw) 재마운트 시도

스토리지 하드웨어가 정상화되었거나 일시적 오류인 경우, 시스템 재부팅 없이 마운트 옵션을 갱신하여 쓰기 가능 상태로 복귀시킵니다.

```bash
# 대상 마운트 경로 재마운트 (예: /data)
$ sudo mount -o remount,rw /data

# 루트(/) 파일시스템이 ro로 잠겼을 경우
$ sudo mount -o remount,rw /
```

  - 재마운트 성공 후 touch /data/.test && rm -f /data/.test로 쓰기 테스트를 수행합니다.

### 3. 디바이스 사용 중(Device is busy) 잠금 프로세스 해제

재마운트나 오프라인 fsck가 필요할 때 프로세스가 파일/디렉토리를 쥐고 있으면 작업이 실패합니다.

```bash
# 특정 마운트 경로를 사용 중인 프로세스 목록 확인
$ sudo lsof +f -- /data
# 또는
$ sudo fuser -vm /data

# 프로세스 안전 종료 후 강제 종료 (필요 시)
$ sudo fuser -km /data
```

### 4. 주요 원인 및 조치 방안

|원인 유형|세부 상황|조치 방안|
|파일시스템 메타데이터 불일치|비정상 종료 또는 저널 손상 감지로 errors=remount-ro 발동|mount -o remount,rw 시도, 점검 시간에 언마운트 후 fsck 수행|
|물리 스토리지 I/O 타임아웃|케이블 불량, SAN/NFS 네트워크 일시 단절, 디스크 배드섹터|스토리지 경로 복구 확인 후 remount,rw, 지속 시 디스크 교체|
|RAID 볼륨 강등(Degraded)|하드웨어 RAID 컨트롤러의 드라이브 페일오버 중 일시 잠금|RAID 컨트롤러 상태 확인(megacli, storcli), 핫스페어 리빌드 확인|
|fstab 설정 오류|부팅 옵션에 기본값으로 ro가 명시되었거나 UUID 매핑 오류|/etc/fstab 점검 후 defaults,rw,errors=remount-ro로 옵션 수정|

&nbsp;
&nbsp;

## 주의사항

### 1. 마운트된 상태에서 fsck 직접 실행 금지

mount -o remount,rw가 실패할 때 파일시스템 정밀 복구를 위해 fsck를 사용해야 합니다.

그러나 마운트되어 있는(특히 쓰기 동작 중인) 파티션에 fsck를 강제로 실행하면 inode 구조와 메타데이터가 영구 파괴될 수 있습니다. 반드시 해당 마운트 포인트를 언마운트(umount /data)한 뒤 fsck -y /dev/sdb1을 실행해야 합니다.

```bash
# 언마운트 후 단독 fsck 실행 절차
$ sudo umount /data
$sudo fsck -y /dev/sdb1$ sudo mount -a
```

### 2. 루트(/) 파티션의 복구 불가 상태 대비

루트 파일시스템(/) 자체가 물리 디스크 불량으로 ro 상태가 되고 remount,rw가 거부되는 경우, 실시간 런타임 내 조치가 제한됩니다.

이때는 커널 메모리에 로드된 sync를 통해 최대한 잔여 버퍼를 플러시하고, 즉시 싱글 유저 모드(Rescue Target)로 진입하거나 라이브 USB/ISO로 부팅하여 오프라인 점검 및 데이터 백업을 수행해야 합니다.

```bash
# 긴급 싱글 유저 모드 전환
$ sudo systemctl rescue
```