---
layout: article
title: 시스템 관리_05 High Memory Usage 분석 및 조치 가이드(Linux Buffer/Cache vs Actual Memory Leak)
tags: linux, memory, buffer-cache, memory-leak, troubleshooting
keys: 260917-linux-storage-005
---

- 출처 / 참고: 리눅스 파일시스템 마운트 관리 및 스토리지 복구 가이드
> 명령어: free, vmstat, slabtop, ps, sync, echo 3 > /proc/sys/vm/drop_caches  
> 키워드: Page Cache, Buffer, Dentry/Inode Cache, Memory Leak, Slab, RSS, VSZ, drop_caches  
> 사용처: Linux 서버(RHEL/CentOS, Ubuntu) 메모리 사용률 급증 시 버퍼/캐시와 실제 프로세스 메모리 누수 판별 및 메모리 반환 조치  

---

> 실행예제

리눅스 시스템에서 모니터링 알람(메모리 90% 이상 사용 등)이 발생했을 때, 이것이 I/O 작업으로 인한 정상적인 Page Cache/Buffer 축적 때문인지, 아니면 실제 프로세스의 메모리 누수(Memory Leak) 때문인지 진단하는 과정입니다.

```bash
# 1. 전체 메모리 상태 확인 (-h: 사람이 보기 편한 단위, -w: wide 모드)
$ free -wh
               total        used        free      shared     buffers       cache   available
Mem:            31Gi       2.4Gi       1.2Gi       420Mi       180Mi        27Gi        28Gi
Swap:          8.0Gi          0B       8.0Gi

# [분석] used는 2.4GiB에 불과하나 cache가 27GiB를 차지하여 free는 1.2GiB로 매우 낮아 보임.
# 하지만 available 메모리가 28GiB이므로 커널이 언제든 회수 가능한 정상 상태임.

# 2. 커널 세부 메모리 할당 상태 점검 (/proc/meminfo)
$ grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached|Slab|SReclaimable|SUnreclaim" /proc/meminfo
MemTotal:       32882348 kB
MemFree:         1258292 kB
MemAvailable:   29458210 kB
Buffers:          184320 kB
Cached:         27650048 kB
Slab:            1420500 kB
SReclaimable:    1150200 kB
SUnreclaim:       270300 kB

# 3. 프로세스별 메모리 점유율(RSS 기준) 상위 10개 정렬
$ ps -eo pid,ppid,user,%mem,rss,vsz,comm --sort=-rss | head -n 11
  PID  PPID USER     %MEM   RSS    VSZ COMMAND
 1248     1 appuser   4.2 1412000 4521000 java
 2150     1 mysql     2.8  942080 3210400 mysqld
 1089     1 root      0.4  135168  480200 systemd-journal
 3312  1248 appuser   0.2   67584  210400 node
...

# [판별 기준]
# 1) free는 적으나 available이 높고 ps 상위 프로세스들의 RSS 합이 낮다면 -> Buffer/Cache 현상 (정상)
# 2) available이 바닥나고, Swap used가 증가하며, 특정 프로세스의 RSS가 지속 상승 중이라면 -> Actual Memory Leak (장애)
```

&nbsp;
&nbsp;

## 스크립트

메모리 상태를 종합 진단하고, Buffer/Cache 점유율이 높을 경우 안전하게 동기화 후 캐시를 비워주거나, 누수 의심 프로세스를 추적하는 스크립트입니다.

```bash
#!/bin/bash
# ==============================================================================
# Script: check_and_clear_cache.sh
# Purpose: Linux Buffer/Cache vs Memory Leak 진단 및 안전 캐시 반환
# ==============================================================================

set -euo pipefail

echo "=========================================================="
echo "          [1] Linux 시스템 메모리 현황 진단"
echo "=========================================================="
free -h

# 주요 메모리 수치 추출 (MB 단위)
MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/^Mem:/ {print $3}')
MEM_BUFF_CACHE=$(free -m | awk '/^Mem:/ {print $6}')
MEM_AVAIL=$(free -m | awk '/^Mem:/ {print $7}')

CACHE_RATIO=$(awk "BEGIN {printf "%.1f", ($MEM_BUFF_CACHE / $MEM_TOTAL) * 100}")
AVAIL_RATIO=$(awk "BEGIN {printf "%.1f", ($MEM_AVAIL / $MEM_TOTAL) * 100}")

echo ""
echo "-> Total Memory    : ${MEM_TOTAL} MB"
echo "-> Used Memory     : ${MEM_USED} MB"
echo "-> Buffer/Cache    : ${MEM_BUFF_CACHE} MB (${CACHE_RATIO}%)"
echo "-> Available Memory: ${MEM_AVAIL} MB (${AVAIL_RATIO}%)"

echo ""
echo "=========================================================="
echo "          [2] 프로세스 메모리 누수 점검 (Top 5)"
echo "=========================================================="
ps -eo pid,user,%mem,rss,args --sort=-rss | head -n 6

echo ""
echo "=========================================================="
echo "          [3] 조치 제안 및 Buffer/Cache 비우기"
echo "=========================================================="

if [ "$MEM_AVAIL" -lt $((MEM_TOTAL * 15 / 100)) ] && [ "$MEM_BUFF_CACHE" -lt $((MEM_TOTAL * 20 / 100)) ]; then
    echo "(!) 경고: Available 메모리가 15% 미만이며 Buffer/Cache 비율도 낮습니다."
    echo "(!) 실제 애플리케이션의 Memory Leak 또는 과점유일 가능성이 높습니다."
    echo "(!) 위 상위 프로세스를 확인하고 서비스를 재기동하거나 덤프를 분석하십시오."
else
    echo "(*) 진단: Buffer/Cache에 의한 일시적 메모리 확보 상태이거나 정상 범위입니다."
    read -p ">> Dirty Page를 동기화하고 캐시(Drop Caches 3)를 비우시겠습니까? (y/N): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "[작업 진행] sync 수행 중..."
        sync
        echo "[작업 진행] /proc/sys/vm/drop_caches 에 3 전달..."
        echo 3 > /proc/sys/vm/drop_caches
        echo "[완료] 캐시 회수 완료 후 메모리 상태:"
        free -h
    else
        echo "[취소] 캐시 정리를 수행하지 않고 종료합니다."
    fi
fi
```

&nbsp;
&nbsp;

## 해설

1. **Linux의 Page Cache 및 Buffer 동작 원리 (Buffer/Cache)**
   - 리눅스 커널은 유휴 메모리(Free RAM)를 낭비하지 않고, 디스크 I/O 성능 향상을 위해 파일 읽기/쓰기 데이터를 Page Cache 및 Buffer 형태로 보관합니다.
   - 새 프로세스나 기존 작업에서 메모리를 요구하면 커널은 `SReclaimable`(회수 가능 Slab) 및 Page Cache를 즉시 회수하여 프로세스에 재할당하므로 `free` 수치가 낮아도 `available` 수치가 충분하다면 정상 상태입니다.

2. **Buffer/Cache vs Actual Memory Leak 판별 기준**
   - **Buffer/Cache 점유 (정상):** `free`는 적으나 `buff/cache`가 크고 `available` 메모리가 넉넉합니다. `ps` 명령어로 프로세스들의 `RSS`(물리 메모리 점유)를 합산했을 때 `used` 수치와 큰 차이가 나지 않습니다.
   - **실제 메모리 누수 (장애):** `available` 메모리가 고갈되며, 커널이 스왑(Swap) 공간을 지속적으로 사용하기 시작합니다. 특정 데몬/애플리케이션(Java, Node, C++ 데몬 등)의 RSS가 시간이 지남에 따라 줄어들지 않고 우상향합니다.

3. **drop_caches 옵션 상세**
   - `echo 1 > /proc/sys/vm/drop_caches`: Page Cache만 해제
   - `echo 2 > /proc/sys/vm/drop_caches`: Dentry 및 Inode(디렉터리/파일 메타데이터) Slab 캐시 해제
   - `echo 3 > /proc/sys/vm/drop_caches`: Page Cache, Dentry, Inode 캐시 모두 해제

&nbsp;
&nbsp;

## 주의사항

1. **`drop_caches` 실행 전 반드시 `sync` 선행 필수**
   - 아직 디스크에 기록되지 않은 Dirty Page가 손실되지 않도록 반드시 `sync` 명령어를 실행하여 커널 버퍼의 데이터를 블록 스토리지에 플러시한 후 캐시를 비워야 합니다.

2. **운영 환경(Production)에서 `drop_caches`의 잦은 주기적 실행(Crontab 등) 금지**
   - 캐시를 강제로 비우면 후속 I/O 요청이 디스크 블록 디바이스로 직접 전달되므로 일시적인 Disk I/O 부하 급증(I/O Spike) 및 응답 지연이 발생합니다. 캐시 정리는 점검/비상 조치용으로만 사용해야 합니다.

3. **Memory Leak 시 drop_caches 무효**
   - 실제 프로세스의 힙 메모리 누수(Memory Leak)인 경우 `drop_caches`를 실행해도 메모리가 회수되지 않습니다. 해당 프로세스의 Heap Dump 분석, 재기동, 또는 메모리 한도(cgroup/systemd limit) 설정이 필요합니다.