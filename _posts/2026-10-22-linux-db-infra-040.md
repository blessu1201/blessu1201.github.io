---
layout: article
title: 시스템 관리_40 슬로우 쿼리 원인 분석 인덱스 누락 풀스캔 대 스토리지 디스크 I/O 지연 식별 및 튜닝 가이드
tags: [Linux, Database, Slow-Query, Missing-Index, Disk-Latency, iostat, vmstat, EXPLAIN-ANALYZE, iowait, DBA, Performance-Tuning, Troubleshooting]
keys: 261022-linux-db-infra-040
---

- 출처 / 참고: Linux man-pages (iostat(1), vmstat(8)), PostgreSQL Documentation (Using EXPLAIN), MySQL Reference Manual (EXPLAIN Statement, Slow Query Log), Brendan Gregg (Systems Performance: Enterprise and the Cloud)

> 명령어: `iostat`, `vmstat`, `pidstat`, `explain`, `top`, `biolatency`  
> 키워드: Slow Query, Missing Index, Disk Latency, %util, await, r_await, w_await, iowait, Full Table Scan, Sequential Scan, Buffer Cache Hit Ratio  
> 사용처: 데이터베이스 응답 지연 발생 시 원인이 비효율적인 쿼리(인덱스 부재)인지 하부 스토리지의 입출력 병목(디스크 지연)인지 신속 판별 및 조치

---

> 실행예제

데이터베이스 애플리케이션의 쿼리 수행 시간이 급증했을 때, OS 수준에서 CPU iowait(`%wa`) 및 디스크 I/O 응답 지연 시간(`r_await`, `w_await`, `%util`)을 측정하고 데이터베이스 내부 실행 계획을 점검하여 병목의 근본 원인을 분리합니다.

```bash
# 1. OS 수준 종합 점검: CPU가 연산 중인지 디스크 I/O 대기(%wa)에 갇혀 있는지 확인 (1초 간격 3회)
$ vmstat 1 3
# procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
#  r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
#  1  4      0 1254300  45210 18542000    0    0 45200   120 1204 3500 12  4 10 74  0
# -> b(Blocked 프로세스 수)가 증가하고 wa(iowait)가 70%를 상회하면 디스크 I/O 지연 상태임

# 2. 스토리지 계층 정밀 진단: 특정 디스크의 응답 대기 시간(await) 및 가동률(%util) 측정
$ iostat -xz 1 3
# Device            r/s     w/s     rkB/s     wkB/s   rrqm/s   wrqm/s  r_await  w_await   aqu-sz  %util
# sdb1          4512.00   12.00 144384.00    120.00     0.00     0.00    28.50     1.20    15.40  99.80
# -> 디스크 가동률(%util)이 100%에 근접하고 읽기 지연(r_await)이 20ms 이상으로 높다면 물리 디스크 병목 상태임

# 3. DB 프로세스별 디스크 I/O 전용 점검 (pidstat)
$ sudo pidstat -d 1 3
# 14:10:02      UID       PID   kB_rd/s   kB_wr/s kB_ccwr/s iodelay  Command
# 14:10:03      999     14502 142100.00     10.00      0.00      85  postgres
# -> 특정 DB 프로세스가 초당 수백 MB씩 디스크에서 블록을 읽고 있음 확인

# 4. 데이터베이스 내부 확인 (PostgreSQL 예시): EXPLAIN ANALYZE를 통한 인덱스 누락 검증
$ psql -U postgres -d mydb -c "
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM orders WHERE customer_id = 984512 AND order_status = 'SHIPPED';
"
# [출력 예시]
# Seq Scan on orders  (cost=0.00..845120.00 rows=15 width=128) (actual time=1240.12..4812.30 rows=2 loops=1)
#   Filter: ((customer_id = 984512) AND (order_status = 'SHIPPED'::text))
#   Rows Removed by Filter: 15420000
#   Buffers: shared hit=1200 read=645000
# Execution Time: 4815.120 ms
# -> Seq Scan(풀스캔)으로 1,500만 건을 디스크 블록(read=645,000)에서 직접 읽어 지연 발생 (인덱스 부재 확정)
```

&nbsp;
&nbsp;

## 스크립트

리눅스 커널의 CPU I/O 대기율, 스토리지 디바이스 응답 시간(await), 데이터베이스 프로세스의 초당 I/O 읽기량을 종합 분석하여 슬로우 쿼리의 주원인이 **인덱스 부재로 인한 풀 테이블 스캔(Full Scan)**인지 **스토리지 디스크 하드웨어 한계(Disk Latency)**인지 자동으로 진단해 주는 쉘 스크립트입니다.

```bash
#!/bin/bash
# diagnose_db_slowdown_cause.sh - Distinguish Missing Index (Full Scan) vs High Disk Latency

echo "=========================================="
echo " [슬로우 쿼리 원인 진단: 인덱스 누락 vs 디스크 지연]"
echo "=========================================="

# 1. 필수 도구 점검
for CMD in iostat vmstat pidstat; do
    if ! command -v "$CMD" &>/dev/null; then
        echo "  [오류] $CMD 명령어가 설치되어 있지 않습니다. (sysstat 패키지 필요)"
        exit 1
    fi
done

# 2. CPU iowait 분석
echo -e "\n[1] CPU I/O 대기율(iowait) 점검 중 (3초 샘플링)..."
VM_DATA=$(vmstat 1 3 | tail -n 1)
CPU_US=$(echo "$VM_DATA" | awk '{print $13}')
CPU_SY=$(echo "$VM_DATA" | awk '{print $14}')
CPU_ID=$(echo "$VM_DATA" | awk '{print $15}')
CPU_WA=$(echo "$VM_DATA" | awk '{print $16}')

echo "  - User CPU  : ${CPU_US}%"
echo "  - System CPU: ${CPU_SY}%"
echo "  - Idle CPU  : ${CPU_ID}%"
echo "  - I/O Wait  : ${CPU_WA}%"

# 3. 디스크별 Latency(await) 및 Util 점검
echo -e "\n[2] 스토리지 디스크 응답 지연(Latency) 및 포화도 점검:"
IOSTAT_OUT=$(iostat -xz 1 2 | awk '/Device/ {found=1; next} found {print}' | tail -n +2)

HIGH_LATENCY_FOUND=0
HIGH_UTIL_FOUND=0

while read -r DEV R_S W_S RK_S WK_S RRQM WRQM R_AWAIT W_AWAIT AQU_SZ UTIL; do
    [ -z "$DEV" ] && continue
    echo "  - 디스크: $DEV | 읽기응답(r_await): ${R_AWAIT}ms | 쓰기응답(w_await): ${W_AWAIT}ms | 점유율(%util): ${UTIL}%"
    
    # NVMe/SSD 기준 10ms 초과 시 지연, HDD 기준 25ms 초과 시 지연 판정
    IS_LATENCY=$(echo "$R_AWAIT > 15.0 || $W_AWAIT > 15.0" | bc -l 2>/dev/null)
    IS_UTIL=$(echo "$UTIL > 90.0" | bc -l 2>/dev/null)
    
    [ "$IS_LATENCY" -eq 1 ] && HIGH_LATENCY_FOUND=1
    [ "$IS_UTIL" -eq 1 ] && HIGH_UTIL_FOUND=1
done <<< "$IOSTAT_OUT"

# 4. DB 프로세스별 I/O 점유 분석
echo -e "\n[3] 데이터베이스 프로세스 초당 읽기/쓰기량 추적:"
DB_IO=$(pidstat -d 1 1 | grep -E "postgres|mysqld|oracle|sqlservr" | head -n 3)
if [ -n "$DB_IO" ]; then
    echo "$DB_IO" | awk '{printf "  -> PID: %-6s | 명령: %-10s | 초당 읽기: %-10s KB/s | 초당 쓰기: %-10s KB/s\n", $4, $9, $5, $6}'
else
    echo "  - 활성화된 DB 프로세스 I/O가 미미합니다."
fi

# 5. 진단 판정 결과 도출
echo -e "\n=========================================="
echo " [진단 결과 요약]"
echo "=========================================="

if [ "$CPU_WA" -ge 30 ] && [ "$HIGH_LATENCY_FOUND" -eq 1 ]; then
    echo "  ★ 판정: [스토리지 디스크 지연 (High Disk Latency)]"
    echo "  - 사유: CPU의 iowait(${CPU_WA}%)가 높고 디스크 await 응답 시간이 15ms를 초과했습니다."
    echo "  - 조치: 스토리지 IOPS 용량 초과, RAID 컨트롤러 캐시 배터리 이상, SAN/NAS 네트워크 지연 점검."
elif [ "$CPU_US" -ge 60 ] && [ "$CPU_WA" -lt 15 ]; then
    echo "  ★ 판정: [인덱스 누락 및 풀 스캔 (Missing Index / In-Memory Scan)]"
    echo "  - 사유: 디스크 지연은 낮으나 CPU User 점유율(${CPU_US}%)이 비정상적으로 높습니다."
    echo "  - 설명: DB 메모리 버퍼(Buffer Cache) 안에서 인덱스 없이 수천만 건을 뒤지는 풀스캔이 발생 중입니다."
    echo "  - 조치: 슬로우 쿼리 로그 및 EXPLAIN 실행 계획을 확인하여 적절한 복합 인덱스를 생성하십시오."
elif [ "$CPU_WA" -ge 20 ] && [ "$HIGH_LATENCY_FOUND" -eq 0 ]; then
    echo "  ★ 판정: [인덱스 누락에 의한 디스크 물리 읽기 폭증]"
    echo "  - 사유: 스토리지는 빠르나 DB 버퍼 크기를 초과하는 대규모 테이블 풀스캔으로 물리 I/O가 과점되었습니다."
    echo "  - 조치: 쿼리 필터 컬럼 인덱스 추가 및 Buffer Cache(SGA/InnoDB Buffer Pool) 증설 검토."
else
    echo "  ★ 판정: [정상 또는 일시적 스파이크]"
    echo "  - 심각한 디스크 지연이나 CPU 병목 징후가 관측되지 않았습니다."
fi
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

운영 데이터베이스에서 쿼리가 느려지는 현상이 보고되었을 때, 엔지니어가 가장 먼저 판별해야 하는 문제는 **"비효율적인 SQL로 인해 불필요한 데이터를 과도하게 긁어오는가(인덱스 누락)?"** 아니면 **"쿼리는 정상인데 하부 저장장치가 요청을 제때 처리하지 못하는가(스토리지 지연)?"**입니다.

### 1. 두 현상의 핵심 비교 및 지표 분석

| 점검 지표 | 인덱스 누락 (Missing Index) | 디스크 지연 (High Disk Latency) |
| :--- | :--- | :--- |
| **주요 병목 자원** | **CPU** (연산량 폭증) 또는 디스크 읽기량 폭증 | **스토리지 디스크** (I/O 대기열 적체) |
| **CPU 상태 (vmstat)** | User CPU(`%us`)가 70~100%로 치솟음 (버퍼 캐시에 데이터가 올라와 있는 경우) | I/O Wait(`%wa`)가 40~90%까지 치솟고 CPU Idle 증가 |
| **디스크 지연 (iostat)** | `await`는 정상(1~5ms 미만)이나 읽기 처리량(`rkB/s`)이 비정상적으로 높음 | 처리량(`rkB/s`)은 작아도 `r_await`, `w_await`가 수십~수백 ms로 급증 |
| **디스크 점유율 (%util)** | 일시적 100% 도달 후 해소 반복 | 지속적인 100% 포화 상태 유지 |
| **DB 실행 계획** | `Seq Scan`, `Full Table Scan`, `ALL` | 인덱스를 타고 있음(`Index Scan`)에도 블록 읽기 단계에서 멈춤 |

### 2. 유형별 심층 분석 및 판별 기준

#### 1) 인덱스 누락 (Missing Index / Table Scan)
* **메모리에 데이터가 다 올라와 있는 경우**:
  * 테이블 크기가 수 GB 수준이고 DB 버퍼 캐시(PostgreSQL Shared Buffers, MySQL InnoDB Buffer Pool) 안에 전부 캐싱되어 있다면, 풀스캔을 돌려도 디스크 I/O는 거의 발생하지 않습니다.
  * 대신 CPU 코어가 메모리 상의 수천만 개 레코드를 일일이 필터링 연산하느라 **User CPU(`%us`)가 100%**를 찍습니다.
* **메모리 용량을 초과하는 대형 테이블인 경우**:
  * 캐시되지 못한 블록을 읽기 위해 대량의 순차 읽기(Sequential Read)가 발생하여 `rkB/s`가 수백 MB/s로 폭증하고 일시적인 `iowait`를 유발합니다.
  * 해결책: `EXPLAIN`으로 실행 계획을 확인하고 `WHERE`, `JOIN` 조건 컬럼에 B-Tree 인덱스를 추가하여 읽는 블록 수(Blocks Read)를 줄입니다.

#### 2) 디스크 하드웨어/스토리지 지연 (Disk Latency)
* 쿼리가 인덱스를 정상적으로 타고 있어 읽어야 할 레코드가 수십 건에 불과한데도 쿼리 실행 시간이 수 초씩 걸리는 경우입니다.
* `iostat -xz 1` 출력에서 **`r_await` 또는 `w_await`가 15~20ms(SSD/NVMe 기준 5ms)를 지속적으로 초과**합니다.
* 주원인:
  * 클라우드 EBS/스토리지 볼륨의 할당된 IOPS 또는 버스트 크레딧(Burst Balance) 고갈.
  * 하드웨어 RAID 컨트롤러의 캐시 배터리(BBU) 방전으로 인한 Write-Through 모드 자동 전환.
  * 동일 SAN/NAS 스토리지를 공유하는 다른 가상 머신(Noisy Neighbor)의 I/O 과점.

### 3. 단계별 트러블슈팅 순서

1. **`top` 및 `vmstat 1` 실행**: `%us`가 높으면 쿼리 튜닝(인덱스), `%wa`가 높으면 스토리지 또는 물리 읽기 병목으로 분류.
2. **`iostat -xz 1` 실행**: 디스크 응답 시간(`await`)이 임계치를 넘는지 확인하여 스토리지 자체 결함 여부 판별.
3. **슬로우 쿼리 로그 및 실행 계획(`EXPLAIN`) 추출**:
   * **MySQL**: `EXPLAIN FORMAT=JSON SELECT ...` -> `type: ALL`(풀스캔), `rows` 조사.
   * **PostgreSQL**: `EXPLAIN (ANALYZE, BUFFERS) SELECT ...` -> `Seq Scan`, `Buffers: read=...` 조사.
4. **인덱스 적용 후 버퍼 히트율(Buffer Cache Hit Ratio) 재검증**: 99% 이상 유지되는지 모니터링.

&nbsp;
&nbsp;

## 주의사항

1. **무분별한 인덱스 추가의 부작용**:
   * 읽기 쿼리가 느리다고 모든 컬럼에 인덱스를 마구 생성하면, `INSERT`, `UPDATE`, `DELETE` 시마다 모든 인덱스 트리를 갱신하고 트랜잭션 로그(WAL/Redo)를 쓰느라 **오히려 디스크 쓰기 I/O 지연(`w_await`)이 악화**됩니다.

2. **클라우드 환경(AWS EBS 등)의 IOPS 크레딧 고갈 착시**:
   * AWS gp2/gp3 볼륨 등에서 슬로우 쿼리가 갑자기 증가했을 때 DB 내부 문제로 오인하기 쉽습니다. AWS CloudWatch에서 `BurstBalance`가 0%로 떨어졌거나 `VolumeThroughputPercentage`가 한도에 도달했는지 인프라 메트릭을 교차 검증해야 합니다.

3. **운영 DB에서 `EXPLAIN ANALYZE` 실행 주의**:
   * PostgreSQL의 `EXPLAIN ANALYZE`는 계획만 세우는 것이 아니라 **실제 쿼리를 끝까지 실행**합니다. 대용량 테이블에서 `DELETE`나 무거운 연산에 `EXPLAIN ANALYZE`를 무심코 실행하면 운영 DB가 장시간 락(Lock)에 걸릴 수 있으므로, 단순 조회 계획만 볼 때는 `EXPLAIN`만 사용해야 합니다.