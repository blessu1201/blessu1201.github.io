---
layout: article
title: 시스템 관리_68 Linux ZFS 및 Btrfs 파일시스템 Scrub 오류 검출과 체크섬 불일치 복구 가이드
tags: [Linux, Storage, ZFS, Btrfs, Scrub, Checksum-Mismatch, Silent-Data-Corruption, zpool, Troubleshooting]
keys: 261120-linux-storage-068
---

- 출처 / 참고: OpenZFS Documentation (ZFS Administration - Data Integrity and Scrubbing), Btrfs Wiki & Linux man-pages (btrfs-scrub(8), zpool-scrub(8))

> 명령어: `zpool`, `zfs`, `btrfs`, `dmesg`, `smartctl`, `find`  
> 키워드: ZFS, Btrfs, Scrub, Checksum Mismatch, Silent Data Corruption, Bit Rot, zpool status, btrfs scrub, Self-Healing  
> 사용처: 스토리지 장기 운영 중 발생하는 조용한 데이터 변조(Bit Rot) 탐지 및 ZFS/Btrfs 체크섬 불일치 오류 블록 자가 복구

---

> 실행예제

ZFS 또는 Btrfs 스토리지 풀에서 정기 데이터 무결성 검사(Scrub) 실행 후 체크섬 불일치(`CKSUM` 또는 `csum errors`) 에러가 보고되었을 때, 손상된 블록을 식별하고 중복성(RAIDZ/Mirror/RAID1)을 이용해 자가 치유(Self-Healing) 상태를 확인합니다.

```bash
# 1. ZFS 관점: 스토리지 풀 상태 및 체크섬(CKSUM) 오류와 손상 파일 목록 조회
$ sudo zpool status -v tank
#   pool: tank
#  state: DEGRADED
# status: One or more devices has experienced an error resulting in data
#         corruption.  Applications may be affected.
#   scan: scrub repaired 128K in 01:15:20 with 1 errors on Fri Nov 20 03:00:00 2026
# config:
#         NAME        STATE     READ WRITE CKSUM
#         tank        DEGRADED     0     0     0
#           mirror-0  DEGRADED     0     0     0
#             sda     ONLINE       0     0     0
#             sdb     DEGRADED     0     0    14
# errors: Permanent errors have been detected in the following files:
#         /tank/backups/archive_202610.tar.gz
# -> sdb 디스크에서 14건의 체크섬 오류가 발생했고, 복구 불가능한 손상 파일 1개가 특정됨 확인

# 2. Btrfs 관점: btrfs scrub 상태 및 디바이스별 I/O/체크섬 에러 통계 확인
$ sudo btrfs scrub status /mnt/btrfs_data
# UUID:             8a2b1c4d-5e6f-7890-abcd-ef1234567890
# Scrub started:    Fri Nov 20 02:00:00 2026
# Status:           finished
# Duration:         0:42:10
# Total to scrub:   1.20TiB
# Rate:             496.20MiB/s
# Error summary:    csum=3
#   Corrected:      3
#   Uncorrectable:  0
# -> 3건의 체크섬 불일치가 발견되었으나 미러링 본을 통해 100% 자가 복구(Corrected: 3)됨 확인

# 3. Btrfs 디바이스 상세 에러 카운터 조회
$ sudo btrfs device stats /mnt/btrfs_data
# [/dev/sdc].write_io_errs    0
# [/dev/sdc].read_io_errs     0
# [/dev/sdc].flush_io_errs    0
# [/dev/sdc].corruption_errs  3
# [/dev/sdc].generation_errs  0
```

&nbsp;
&nbsp;

## 스크립트

시스템에 구성된 ZFS 풀 및 Btrfs 마운트 포인트를 자동으로 탐지하여, 기존 체크섬 에러 유무를 진단하고 백그라운드 무결성 검사(Scrub)를 스케줄링하며 손상 파일 경로 리포트를 생성해 주는 통합 관리 쉘 스크립트입니다.

```bash
#!/bin/bash
# audit_storage_scrub.sh - Checksum integrity audit and scrub trigger for ZFS and Btrfs

echo "=========================================="
echo " [ZFS / Btrfs 데이터 무결성(Scrub) 감사기]"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] 파일시스템 무결성 검사를 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

# 1. ZFS 풀 점검 및 Scrub 실행
if command -v zpool &>/dev/null; then
    ZPOOLS=$(zpool list -H -o name 2>/dev/null)
    if [ -n "$ZPOOLS" ]; then
        echo -e "\n[1] ZFS 스토리지 풀 상태 점검:"
        for POOL in $ZPOOLS; do
            HEALTH=$(zpool list -H -o health "$POOL")
            echo "  - 풀 이름: ${POOL} | 상태: ${HEALTH}"
            
            # 에러 출력 확인
            ERR_FILES=$(zpool status -x "$POOL" 2>/dev/null)
            if ! echo "$ERR_FILES" | grep -q "is healthy"; then
                echo "  [경고] ${POOL} 풀에서 데이터 또는 하드웨어 오류가 감지되었습니다!"
                zpool status -v "$POOL" | grep -E "READ|WRITE|CKSUM|errors:|/" | sed 's/^/    /'
            fi
            
            # Scrub 진행 중이 아니면 새로 시작
            if ! zpool status "$POOL" | grep -q "scrub in progress"; then
                echo "  -> 백그라운드 무결성 검사(zpool scrub ${POOL}) 개시..."
                zpool scrub "$POOL"
            else
                echo "  -> 현재 Scrub 작업이 이미 진행 중입니다."
            fi
        done
    fi
fi

# 2. Btrfs 마운트 지점 점검 및 Scrub 실행
if command -v btrfs &>/dev/null; then
    BTRFS_MNTS=$(awk '$3 == "btrfs" {print $2}' /proc/mounts | sort -u)
    if [ -n "$BTRFS_MNTS" ]; then
        echo -e "\n[2] Btrfs 파일시스템 상태 점검:"
        for MNT in $BTRFS_MNTS; do
            echo "  - 마운트 경로: ${MNT}"
            
            # 디바이스 에러 카운터 요약
            DEV_ERRS=$(btrfs device stats "$MNT" 2>/dev/null | awk '$2 > 0 {print $0}')
            if [ -n "$DEV_ERRS" ]; then
                echo "  [경고] 디바이스 누적 에러 발견:"
                echo "$DEV_ERRS" | sed 's/^/    /'
            else
                echo "  [정상] 누적된 디바이스 손상(corruption_errs)이 없습니다."
            fi
            
            # Scrub 시작 (이미 실행 중이면 무시됨)
            if ! btrfs scrub status "$MNT" | grep -q "running"; then
                echo "  -> 백그라운드 무결성 검사(btrfs scrub start ${MNT}) 개시..."
                btrfs scrub start "$MNT" >/dev/null 2>&1
            else
                echo "  -> 현재 Scrub 작업이 이미 진행 중입니다."
            fi
        done
    fi
fi

echo -e "\n=========================================="
echo " [감사 및 Scrub 트리거 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

전통적인 파일시스템(Ext4, XFS)은 하드웨어 컨트롤러가 주는 데이터를 무조건 신뢰합니다. 만약 디스크 플래터의 자기 약화, 낸드 플래시 전하 누설(Bit Rot), 또는 불량 SATA/SAS 케이블로 인해 비트가 조용히 변조(Silent Data Corruption)되더라도 OS는 이를 눈치채지 못하고 깨진 데이터를 그대로 서비스합니다.

ZFS와 Btrfs는 이를 방지하기 위해 모든 데이터 블록의 메타데이터에 **별도의 암호화 해시 체크섬(Fletcher4, SHA-256, CRC32C)을 함께 저장**합니다.

### 1. Scrub(스크러빙)과 자가 치유(Self-Healing) 원리

1. **데이터 스크러빙 (Scrubbing)**:
   * 평소 잘 읽지 않는 콜드 데이터(Cold Data) 블록까지 백그라운드에서 전수 스캔하여 디스크에서 읽은 데이터의 해시값과 메타데이터에 기록된 체크섬을 대조하는 작업입니다.
2. **자가 치유 (Self-Healing)**:
   * 디스크 A에서 읽은 블록의 체크섬이 일치하지 않으면, ZFS/Btrfs는 즉시 미러(Mirror) 또는 패리티(RAIDZ/RAID5)에 있는 디스크 B의 정상 블록을 읽어 체크섬을 검증한 뒤, **디스크 A의 손상된 블록을 정상 데이터로 덮어써서 복구**합니다.

### 2. 체크섬 불일치(`CKSUM`) 발생 시 원인별 대응

* **단일 디스크에서만 `CKSUM` 에러가 계속 올라가는 경우**:
  * 해당 디스크의 배드 섹터 전조 증상이거나 연결된 SATA/SAS 케이블 불량입니다. 케이블 교체 후 에러 카운터를 초기화(`zpool clear` 또는 `btrfs device stats -z`)하여 재발 여부를 지켜봅니다.
* **모든 디스크에서 동시에 `CKSUM` 에러가 발생하는 경우**:
  * 디스크 문제가 아니라 **서버 메인보드의 ECC 미지원 RAM 불량** 또는 **HBA/RAID 컨트롤러 펌웨어 버그**로 인해 메모리를 거쳐 디스크로 내려가는 데이터 자체가 오염되고 있을 확률이 매우 높습니다.
* **복구 불가능(`Uncorrectable` / `Permanent errors`) 판정 시**:
  * 중복 구성(Mirror/RAIDZ)이 없는 단일 디스크 구성이거나 패리티 허용 한도를 초과해 복구에 실패한 파일은 `zpool status -v`에 출력된 경로를 확인한 뒤 외부 백업본에서 해당 파일만 덮어쓰고 에러를 정리해야 합니다.

&nbsp;
&nbsp;

## 주의사항

1. **Scrub 작업으로 인한 운영 디스크 I/O 부하 주의**:
   * Scrub은 디스크 전체 섹터를 순차 스캔하므로 대용량 HDD 풀에서는 스토리지 I/O 대역폭을 크게 점유합니다. 데이터베이스 서버나 피크 타임 업무 시간에는 피하고 반드시 **월 1회 주말 심야 시간대(Cron 스케줄)**에 실행되도록 제한해야 합니다.

2. **Btrfs의 RAID 5 / RAID 6 (Write Hole) 구성 지양**:
   * Btrfs는 데이터 및 메타데이터의 `RAID1` / `RAID10` 구성에서는 매우 안정적인 자가 치유를 제공하지만, `RAID5` / `RAID6` 구현체는 전원 차단 시 패리티 불일치(Write Hole) 취약점이 존재하므로 엔터프라이즈 운영 환경에서는 Btrfs RAID5/6 대신 ZFS RAIDZ 또는 Btrfs RAID1을 사용해야 합니다.

3. **에러 카운터 초기화 전 원인 규명 필수**:
   * `zpool clear tank` 또는 `btrfs device stats -z` 명령은 기록된 오류 카운터를 `0`으로 리셋할 뿐 물리적 결함을 고쳐주지 않습니다. SMART 상태(`smartctl -a`)와 케이블 점검 없이 카운터만 지우면 데이터 손실 위험을 은폐하게 됩니다.