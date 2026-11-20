---
layout: article
title: 시스템 관리_67 Linux Software RAID mdadm 디스크 Degraded 상태 복구 및 리빌드 가속화 가이드
tags: [Linux, Storage, RAID, mdadm, Degraded, Rebuild, sync_speed_max, Array-Recovery, Troubleshooting]
keys: 261119-linux-storage-067
---

- 출처 / 참고: Linux man-pages (mdadm(8), md(4)), Linux Kernel Documentation (Software RAID / MD driver sysfs interface)

> 명령어: `mdadm`, `cat`, `lsblk`, `sfdisk`, `sysctl`, `watch`  
> 키워드: mdadm, Software RAID, Degraded, /proc/mdstat, RAID1, RAID5, RAID10, sync_speed_min, sync_speed_max, Rebuild  
> 사용처: 물리 디스크 불량으로 리눅스 소프트웨어 RAID 어레이가 Degraded 상태로 전환되었을 때 장애 디스크 교체 및 수십 시간 걸리는 리빌드 속도 최적화

---

> 실행예제

리눅스 서버의 `/proc/mdstat` 상태 조회 시 RAID 멤버 디스크 중 하나가 `Failed(F)`로 빠지면서 어레이가 `Degraded` 상태로 동작하고, 디스크 교체 후 리빌드(Recovery) 속도가 수 MB/s로 극도로 느리게 진행되는 현상을 진단합니다.

```bash
# 1. 현재 커널 MD(Multiple Device) RAID 어레이 전체 상태 및 동기화 속도 확인
$ cat /proc/mdstat
# Personalities : [raid1] [raid5]
# md0 : active raid5 sdc1[2] sdb1[1] sda1[0](F)
#       1953259520 blocks super 1.2 level 5, 512k chunk, algorithm 2 [3/2] [_UU]
#       bitmap: 4/8 pages [16KB], 65536KB chunk
# -> sda1[0](F)로 표시되어 장애(Faulty) 상태이며, [3/2] [_UU] 로 1개 디스크가 빠진 Degraded 상태 확인

# 2. mdadm 상세 조회로 불량 디스크 시리얼 및 이벤트 카운트 확인
$ sudo mdadm --detail /dev/md0
#         Version : 1.2
#      Raid Level : raid5
#      Array Size : 1953259520 (1862.77 GiB 2000.14 GB)
#   Rebuild Status : 2% complete
#     Number   Major   Minor   RaidDevice State
#        3       8        1        0      spare rebuilding   /dev/sda1
#        1       8       17        1      active sync   /dev/sdb1
#        2       8       33        2      active sync   /dev/sdc1

# 3. 현재 커널의 RAID 리빌드 최소/최대 속도 제한(Throttle) 확인
$ cat /proc/sys/dev/raid/speed_limit_min
# 1000   (기본값이 초당 1,000 KB = 1MB/s 로 매우 낮게 제한됨)
$ cat /proc/sys/dev/raid/speed_limit_max
# 200000 (초당 200MB/s)
```

&nbsp;
&nbsp;

## 스크립트

리눅스 `/proc/mdstat`를 분석하여 `Degraded` 상태인 어레이와 불량(`(F)`) 디스크를 자동 식별하고, 신규 교체된 디스크에 기존 정상 디스크의 파티션 테이블을 복제한 뒤 RAID 멤버로 편입시키며 리빌드 속도를 최대로 가속화해 주는 복구 쉘 스크립트입니다.

```bash
#!/bin/bash
# recover_mdadm_raid.sh - Diagnose degraded mdadm RAID, replace failed disk, and accelerate rebuild

MD_DEV=${1:-"/dev/md0"}
HEALTHY_DISK=${2:-""}
NEW_DISK=${3:-""}

echo "=========================================="
echo " [Linux Software RAID(mdadm) 진단 및 복구기]"
echo " 대상 어레이: ${MD_DEV}"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] RAID 어레이 관리를 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

# 1. 현재 RAID 상태 출력
echo -e "\n[1] 현재 /proc/mdstat 상태:"
cat /proc/mdstat | sed 's/^/  /'

if [ -z "$HEALTHY_DISK" ] || [ -z "$NEW_DISK" ]; then
    echo -e "\n[안내] 진단 모드로 실행되었습니다. 디스크 교체를 진행하려면 인자를 입력하십시오."
    echo "  사용법: $0 <MD장치> <정상_디스크_경로> <신규_교체_디스크_경로>"
    echo "  예시  : $0 /dev/md0 /dev/sdb /dev/sda"
    exit 0
fi

# 2. 불량(Faulty) 파티션 어레이에서 공식 제거
echo -e "\n[2] 장애(Faulty) 멤버 디스크 어레이 분리:"
FAULTY_PARTS=$(mdadm --detail "$MD_DEV" | awk '/faulty/ {print $NF}')
for FP in $FAULTY_PARTS; do
    echo "  -> 장애 파티션 제거 중: ${FP}"
    mdadm --manage "$MD_DEV" --remove "$FP"
done

# 3. 정상 디스크의 파티션 구조(GPT/MBR)를 신규 디스크로 1:1 복제
echo -e "\n[3] 파티션 테이블 복제 (${HEALTHY_DISK} -> ${NEW_DISK}):"
if command -v sgdisk &>/dev/null && parted -s "$HEALTHY_DISK" print 2>/dev/null | grep -q "gpt"; then
    sgdisk -R="$NEW_DISK" "$HEALTHY_DISK"
    sgdisk -G "$NEW_DISK"
    echo "  - GPT 파티션 테이블 복제 및 신규 UUID 발급 완료."
else
    sfdisk -d "$HEALTHY_DISK" | sfdisk --force "$NEW_DISK"
    echo "  - MBR 파티션 테이블 복제 완료."
fi

partprobe "$NEW_DISK"
sleep 2

# 4. 신규 파티션을 RAID 어레이에 추가(Add)하여 리빌드 시작
NEW_PART="${NEW_DISK}1"
echo -e "\n[4] 신규 파티션(${NEW_PART}) 어레이 편입 및 리빌드 개시:"
mdadm --manage "$MD_DEV" --add "$NEW_PART"

if [ $? -ne 0 ]; then
    echo "  [실패] 파티션 편입에 실패했습니다. 파티션 이름 및 크기를 확인하십시오."
    exit 1
fi

# 5. 리빌드 속도 가속화 튜닝 (SSD/NVMe 및 고속 SAS 기준)
echo -e "\n[5] 커널 RAID 리빌드 속도 제한(Throttle) 상향 튜닝:"
echo 100000 > /proc/sys/dev/raid/speed_limit_min
echo 500000 > /proc/sys/dev/raid/speed_limit_max

# 개별 MD 디바이스의 stripe_cache_size 상향 (RAID5/6 패리티 연산 대폭 가속)
MD_BASE=$(basename "$MD_DEV")
if [ -f "/sys/block/${MD_BASE}/md/stripe_cache_size" ]; then
    echo 16384 > "/sys/block/${MD_BASE}/md/stripe_cache_size"
    echo "  - ${MD_BASE} stripe_cache_size 16384 상향 완료."
fi

echo -e "\n=========================================="
echo " [복구 진행 중] 'watch cat /proc/mdstat' 로 진행률을 모니터링하십시오."
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

리눅스 소프트웨어 RAID(`mdadm`)는 별도의 고가 하드웨어 컨트롤러 없이 커널 드라이버만으로 안정적인 디스크 이중화를 제공하지만, 디스크 장애 발생 후 신규 디스크를 꽂았을 때 **기본 리빌드 속도 제한이 매우 보수적으로 잡혀 있어 수 TB 디스크 복구에 수십 시간이 걸리는 문제**가 발생합니다.

### 1. 리빌드(Rebuild)가 느려지는 이유와 3대 가속 파라미터

리빌드 도중 다른 디스크 1개가 추가로 고장 나면 RAID 1이나 RAID 5 어레이는 데이터가 영구 소실됩니다. 따라서 **Degraded 노출 시간을 최소화하기 위해 리빌드 속도를 최대한 끌어올려야** 합니다.

1. **`dev.raid.speed_limit_min` (최소 보장 속도)**:
   * 기본값은 `1000` (1MB/s)입니다. 서비스 I/O가 조금만 있어도 리빌드 속도가 초당 1MB로 떨어져 4TB 디스크 복구에 40일 이상 걸리게 됩니다. 이를 최소 `100000` (100MB/s) 이상으로 높여야 합니다.
2. **`dev.raid.speed_limit_max` (최대 허용 속도)**:
   * 기본값은 `200000` (200MB/s)입니다. NVMe나 엔터프라이즈 SSD 환경에서는 `500000` ~ `1000000`으로 높여 병목을 해제합니다.
3. **`stripe_cache_size` (RAID 5 / RAID 6 전용 핵심 튜닝)**:
   * 패리티(Parity) 계산을 동반하는 RAID 5/6에서는 기본 스트라이프 캐시가 256 페이지로 극도로 작아 CPU와 메모리 대기 병목이 생깁니다. 이를 `8192` 또는 `16384`로 늘리면 리빌드 속도가 즉각 3~5배 이상 폭증합니다.

### 2. 영구 적용 설정 (`/etc/sysctl.conf`)

```ini
# /etc/sysctl.d/99-raid-speed.conf
dev.raid.speed_limit_min = 100000
dev.raid.speed_limit_max = 500000
```
* 적용: `sudo sysctl --system`

&nbsp;
&nbsp;

## 주의사항

1. **디스크 교체 전 정상 디스크와 불량 디스크의 시리얼 번호(`smartctl`) 대조 필수**:
   * 리부팅이나 핫스왑 과정에서 리눅스 디바이스명(`/dev/sda`, `/dev/sdb`)은 언제든 뒤바뀔 수 있습니다. 파티션 복제(`sgdisk` / `sfdisk`) 명령을 실행할 때 원본과 대상 디스크를 반대로 입력하면 살아있는 정상 디스크의 파티션 테이블이 날아가 어레이 전체가 파괴됩니다. 반드시 `smartctl -i /dev/sdX`로 물리 시리얼 번호를 확인해야 합니다.

2. **교체용 신규 디스크 용량이 기존 멤버보다 작을 경우 편입 실패**:
   * 같은 "2TB" 표기 디스크라도 제조사마다 실제 섹터 수가 미세하게 다를 수 있습니다. 신규 디스크의 총 섹터 수가 기존 멤버보다 1섹터라도 작으면 `mdadm --add`가 거부되므로, 초기 RAID 구축 시 디스크 끝부분에 약 100MB 정도의 여유 마진을 두고 파티션을 나누는 것이 실무 노하우입니다.

3. **Write-Intent Bitmap 활성화 권장**:
   * 서버 강제 재부팅 시 전체 디스크를 처음부터 다시 동기화(Full Resync)하는 것을 막기 위해 어레이 생성 시 `--bitmap=internal` 옵션을 활성화해 두면 변경된 블록만 수 분 내에 동기화할 수 있습니다.