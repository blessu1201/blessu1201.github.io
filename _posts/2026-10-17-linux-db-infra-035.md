---
layout: article
title: 시스템 관리_35 SQL Server TempDB 할당 경합으로 인한 CPU 고부하 현상 원인 분석 및 완벽 해결 가이드
tags: [Linux, Windows, SQL-Server, MSSQL, TempDB, PAGELATCH, Allocation-Contention, High-CPU, PFS, GAM, SGAM, DBA, Troubleshooting]
keys: 261017-linux-db-infra-035
---

- 출처 / 참고: Microsoft Learn (Troubleshoot TempDB contention in SQL Server), Microsoft SQL Server Internals (TempDB Allocation Architecture)

> 명령어: `sqlcmd`, `top`, `pidstat`, `grep`, `systemctl`  
> 키워드: TempDB Contention, PAGELATCH_UP, PAGELATCH_EX, PFS, GAM, SGAM, High CPU, Trace Flag 1118, Multiple Data Files  
> 사용처: 임시 테이블 및 테이블 변수 과다 사용 시 SQL Server CPU 점유율 100% 폭증 및 쿼리 병목(Latch Wait) 해결

---

> 실행예제

SQL Server 인스턴스에서 CPU 사용량이 비정상적으로 치솟고 쿼리 응답이 지연될 때, OS 레벨의 프로세스 CPU 사용률을 확인하고 데이터베이스 내부에서 `TempDB` 특화 대기 유형인 `PAGELATCH_UP`, `PAGELATCH_EX` 발생 여부 및 경합이 일어나는 시스템 페이지를 점검합니다.

```bash
# 1. OS 관점: sqlservr 프로세스의 CPU 점유율 및 스레드별 부하 확인
$ top -b -n 1 -p $(pgrep sqlservr | head -n 1)
# PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
# 1420 mssql     20   0 18.520g 12.150g  32450 R 785.4  38.2  42:15.80 sqlservr
# -> 다중 코어 환경에서 CPU 점유율이 수백 %에 도달한 상태 확인

# 2. 현재 SQL Server 전체에서 가장 높은 대기 시간을 기록 중인 Wait Type 확인
$ sqlcmd -S localhost -U sa -P 'MyStrongPassword123!' -Q "
SELECT TOP 5 
    wait_type, 
    waiting_tasks_count, 
    wait_time_ms, 
    ROUND(wait_time_ms * 1.0 / NULLIF(waiting_tasks_count, 0), 2) AS avg_wait_ms
FROM sys.dm_os_wait_stats
WHERE wait_type LIKE 'PAGELATCH_%'
ORDER BY wait_time_ms DESC;
"
# [출력 예시]
# wait_type        waiting_tasks_count  wait_time_ms         avg_wait_ms
# ---------------- -------------------- -------------------- ------------
# PAGELATCH_UP                  1542100             45214050        29.32
# PAGELATCH_EX                   421050             12540120        29.78
# -> PAGELATCH_UP/EX 대기 시간이 압도적이면 TempDB 할당 페이지 경합 가능성 매우 높음

# 3. 실시간으로 TempDB(database_id = 2) 할당 페이지에서 대기 중인 세션 추적
$ sqlcmd -S localhost -U sa -P 'MyStrongPassword123!' -Q "
SELECT 
    session_id, 
    wait_type, 
    wait_duration_ms, 
    resource_description
FROM sys.dm_os_waiting_tasks
WHERE wait_type LIKE 'PAGELATCH_%' 
  AND resource_description LIKE '2:%';
"
# [출력 예시]
# session_id wait_type     wait_duration_ms resource_description
# ---------- ------------- ---------------- --------------------
# 78         PAGELATCH_UP  45               2:1:1
# 84         PAGELATCH_UP  52               2:1:3
# -> resource_description이 '2:1:1'(PFS), '2:1:2'(GAM), '2:1:3'(SGAM)을 가리키면 전형적인 메타데이터 할당 경합임

# 4. 현재 TempDB 데이터파일 개수 및 크기/자동확장 균등 여부 확인
$ sqlcmd -S localhost -U sa -P 'MyStrongPassword123!' -Q "
SELECT 
    file_id, 
    name, 
    physical_name, 
    size * 8 / 1024 AS size_mb, 
    growth * 8 / 1024 AS growth_mb, 
    is_percent_growth
FROM sys.master_files
WHERE database_id = 2 AND type = 0;
"
```

&nbsp;
&nbsp;

## 스크립트

SQL Server의 CPU 코어 수 대비 `TempDB` 데이터파일 개수를 비교 검증하고, 현재 활성화된 세션 중 TempDB 시스템 페이지(PFS, GAM, SGAM) 경합에 묶여 있는 세션 및 원인 쿼리를 실시간 감지하는 진단 쉘 스크립트입니다.

```bash
#!/bin/bash
# diagnose_tempdb_contention.sh - Diagnose SQL Server TempDB Allocation Contention & High CPU

SQL_HOST=${1:-"localhost"}
SQL_USER=${2:-"sa"}
SQL_PASS=${3:-"MyStrongPassword123!"}

echo "=========================================="
echo " [SQL Server TempDB 경합 및 CPU 고부하 진단]"
echo " 대상 호스트: ${SQL_HOST}"
echo "=========================================="

if ! command -v sqlcmd &>/dev/null; then
    echo "  [오류] sqlcmd 명령어를 찾을 수 없습니다. mssql-tools 설치 여부를 확인하세요."
    exit 1
fi

# 1. CPU 논리 코어 수와 TempDB 데이터파일 수 대조
echo -e "\n[1] CPU 코어 수 대비 TempDB 데이터파일 구성 점검:"
CORE_COUNT=$(nproc 2>/dev/null || echo 4)

TEMPDB_FILE_COUNT=$(sqlcmd -S "$SQL_HOST" -U "$SQL_USER" -P "$SQL_PASS" -h -1 -W -Q "
SET NOCOUNT ON;
SELECT COUNT(*) FROM sys.master_files WHERE database_id = 2 AND type = 0;
" 2>/dev/null)

TEMPDB_FILE_COUNT=$(echo "$TEMPDB_FILE_COUNT" | tr -d '[:space:]')

echo "  - 시스템 논리 CPU 코어 수: ${CORE_COUNT}개"
echo "  - TempDB 데이터파일 개수 : ${TEMPDB_FILE_COUNT}개"

if [ "${TEMPDB_FILE_COUNT:-0}" -eq 1 ]; then
    echo "  [치명적 경고] TempDB 데이터파일이 1개뿐입니다!"
    echo "  -> 대량 동시 요청 시 PFS/SGAM 단일 페이지 병목으로 심각한 CPU 스핀 및 래치 경합 유발."
elif [ "${TEMPDB_FILE_COUNT:-0}" -lt "$CORE_COUNT" ] && [ "${CORE_COUNT}" -le 8 ]; then
    echo "  [주의] 데이터파일 개수가 논리 코어 수(${CORE_COUNT}개)보다 적습니다. 코어 수에 맞추어 증설을 권장합니다."
else
    echo "  [정상] 데이터파일 개수가 적정 수준으로 분산 구성되어 있습니다."
fi

# 2. 파일별 크기 및 자동확장(Growth) 동일성 점검
echo -e "\n[2] TempDB 파일 크기 및 증가폭 균등 여부 점검:"
FILE_CHECK=$(sqlcmd -S "$SQL_HOST" -U "$SQL_USER" -P "$SQL_PASS" -W -Q "
SET NOCOUNT ON;
SELECT 
    name, 
    size * 8 / 1024 AS size_mb, 
    growth * 8 / 1024 AS growth_mb, 
    CASE WHEN is_percent_growth = 1 THEN 'PERCENT' ELSE 'MB' END AS growth_type
FROM sys.master_files 
WHERE database_id = 2 AND type = 0;
" 2>/dev/null)
echo "$FILE_CHECK" | sed 's/^/  /'

# 3. 실시간 TempDB 할당 페이지 경합(PFS/GAM/SGAM) 발생 여부
echo -e "\n[3] 실시간 TempDB 할당 페이지(PFS/GAM/SGAM) 대기 세션 추적:"
WAITING_SESSIONS=$(sqlcmd -S "$SQL_HOST" -U "$SQL_USER" -P "$SQL_PASS" -W -Q "
SET NOCOUNT ON;
SELECT 
    wt.session_id, 
    wt.wait_type, 
    wt.wait_duration_ms, 
    wt.resource_description,
    SUBSTRING(st.text, (r.statement_start_offset/2)+1, 
        ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE r.statement_end_offset END - r.statement_start_offset)/2) + 1) AS current_query
FROM sys.dm_os_waiting_tasks wt
JOIN sys.dm_exec_requests r ON wt.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE wt.wait_type LIKE 'PAGELATCH_%' 
  AND wt.resource_description LIKE '2:%';
" 2>/dev/null)

if echo "$WAITING_SESSIONS" | grep -q "PAGELATCH"; then
    echo "  [위험] 현재 TempDB 페이지 래치 경합에 걸린 세션이 포착되었습니다!"
    echo "$WAITING_SESSIONS" | head -n 15 | sed 's/^/    /'
else
    echo "  [정상] 현재 시점에 TempDB 시스템 페이지 경합은 감지되지 않았습니다."
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

SQL Server에서 쿼리 자체의 연산량이나 인덱스 누락이 없음에도 불구하고 CPU 점유율이 90~100%까지 치솟는 장애가 발생할 때, 가장 먼저 의심해야 할 병목 지점 중 하나가 바로 **TempDB 할당 경합(TempDB Allocation Contention)**입니다.

### 1. TempDB 할당 경합의 동작 원리

임시 테이블(`#table`), 테이블 변수(`@table`), 정렬(`ORDER BY`), 해시 조인(`HASH JOIN`) 연산 시 SQL Server는 메모리 또는 디스크의 TempDB 공간을 동적으로 할당받아 사용합니다. 이때 데이터베이스 내부 공간을 관리하는 특수 시스템 페이지를 반복 참조합니다.

* **PFS (Page Free Space)**: 각 페이지의 여유 공간 비율을 기록 (약 8,000페이지(64MB)마다 1페이지씩 존재, 첫 페이지: `2:1:1`).
* **GAM (Global Allocation Map)**: 어떤 익스텐트(Extent)가 할당되었는지 추적 (약 64,000익스텐트(4GB)마다 1페이지, 첫 페이지: `2:1:2`).
* **SGAM (Shared Global Allocation Map)**: 혼합 익스텐트(Mixed Extent)의 여유 상태 추적 (첫 페이지: `2:1:3`).

수백 개의 동시 접속 세션이 임시 객체를 빈번하게 생성/삭제하면, 모든 세션이 단 하나의 시스템 페이지(`2:1:1` 또는 `2:1:3`)를 변경하기 위해 메모리 상에서 배타적/갱신 래치(`PAGELATCH_UP`, `PAGELATCH_EX`)를 획득하려고 경쟁합니다. 이 과정에서 CPU 코어들은 락을 얻기 위해 초당 수만 회 이상 스핀(Spin)을 돌게 되며, 이는 **시스템 전반의 CPU 100% 포화 현상**으로 직결됩니다.

### 2. 단계별 튜닝 및 해결 방법

#### 1) TempDB 데이터파일 다중 분할 구성 (가장 중요)
단일 데이터파일(`tempdb.mdf`) 구조에서는 모든 스레드가 동일한 단일 PFS/SGAM 페이지만을 바라봅니다. 데이터파일을 여러 개로 쪼개면 파일마다 독립적인 시스템 페이지가 생성되어 스레드들의 경합이 물리적으로 분산됩니다.

* **권장 분할 공식 (Microsoft 가이드라인)**:
  * 논리 코어 수 $\le 8$: **논리 코어 수와 동일한 개수**의 데이터파일 생성 (예: 4코어면 4개, 8코어면 8개).
  * 논리 코어 수 $> 8$: **8개의 데이터파일**로 시작한 후, 여전히 경합이 관측되면 4개 단위로 추가 증설 (보통 8~16개 유지).

```sql
-- 예시: 4개의 2GB 크기 데이터파일로 균등 분할
ALTER DATABASE tempdb ADD FILE (NAME = N'tempdev02', FILENAME = N'/var/opt/mssql/data/tempdb_mssql_2.ndf', SIZE = 2048MB, FILEGROWTH = 256MB);
ALTER DATABASE tempdb ADD FILE (NAME = N'tempdev03', FILENAME = N'/var/opt/mssql/data/tempdb_mssql_3.ndf', SIZE = 2048MB, FILEGROWTH = 256MB);
ALTER DATABASE tempdb ADD FILE (NAME = N'tempdev04', FILENAME = N'/var/opt/mssql/data/tempdb_mssql_4.ndf', SIZE = 2048MB, FILEGROWTH = 256MB);
```

#### 2) 모든 TempDB 데이터파일의 초기 크기 및 자동 증가폭을 완전히 동일하게 설정
SQL Server는 파일 크기가 동일할 때 균등 라운드 로빈(Proportional Fill) 방식으로 데이터를 골고루 분산 할당합니다. 파일 중 하나라도 크기나 증가폭이 다르면 특정 파일로 할당이 쏠리며 다시 경합이 발생합니다.

#### 3) 단일 익스텐트 강제 할당 (Trace Flag 1118 및 1117)
* **SQL Server 2016 이상**: 기본적으로 혼합 익스텐트(Mixed Extent)를 사용하지 않고 전용 단일 익스텐트(Uniform Extent)를 사용하도록 엔진이 개선되어 있어 별도의 트레이스 플래그 없이도 SGAM 경합이 대폭 감소했습니다.
* **SQL Server 2014 이하 (레거시 환경)**:
  * 시작 파라미터에 `-T1118`(Uniform Extent 강제) 및 `-T1117`(모든 파일 동시 자동 증가)을 반드시 등록해야 합니다.

#### 4) 쿼리 레벨 최적화: 임시 객체 남발 방지
* 불필요한 임시 테이블 생성(`CREATE TABLE #TMP`) 남발을 줄이고, 가능한 경우 공통 테이블 표현식(`CTE`)이나 파생 테이블(Derived Table)로 대체합니다.
* 빈번한 DDL 호출을 피하기 위해 임시 테이블 재사용 또는 테이블 변수 크기 최적화를 검토합니다.

&nbsp;
&nbsp;

## 주의사항

1. **데이터파일 개수를 무조건 CPU 코어 수 이상으로 늘리지 말 것**:
   * 32코어 또는 64코어 머신이라고 해서 TempDB 파일을 32개, 64개로 무작정 늘리면 파일 간 체크포인트 부하와 메타데이터 관리 오버헤드가 급증하여 오히려 I/O 성능이 저하될 수 있습니다. 8개부터 시작하여 대기 현상을 모니터링하면서 점진적으로 늘려야 합니다.

2. **로그 파일(`templog.ldf`)은 1개만 유지**:
   * 데이터파일(`.ndf`)은 여러 개로 분할하여 병렬 할당 이점을 얻지만, 트랜잭션 로그 파일은 구조상 순차 쓰기(Sequential Write)로 동작하므로 파일을 여러 개 만들어도 성능 분산 효과가 전혀 없습니다. 로그 파일은 반드시 단 1개만 유지해야 합니다.

3. **고속 스토리지(NVMe SSD) 분리 배치**:
   * TempDB는 인메모리 성격의 임시 I/O가 매우 빈번한 특수 데이터베이스이므로, 일반 사용자 데이터베이스 파일과 물리 디스크 드라이브를 분리하여 독립된 NVMe SSD 파티션에 격리 배치해야 스토리지 큐 병목을 방지할 수 있습니다.