---
layout: article
title: 시스템 관리_37 운영 데이터베이스 블로킹 세션 및 데드락 식별과 안전한 강제 종료 해결 가이드
tags: [Linux, Database, Blocking-Session, Deadlock, Lock-Contention, PostgreSQL, MySQL, Oracle, SQL-Server, DBA, Troubleshooting]
keys: 261019-linux-db-infra-037
---

- 출처 / 참고: PostgreSQL Official Documentation (Viewing Locks, pg_stat_activity), MySQL Reference Manual (InnoDB Lock and Lock-Wait Information), Oracle Database Reference (V$LOCK, V$SESSION)

> 명령어: `psql`, `mysql`, `sqlcmd`, `sqlplus`, `kill`, `awk`  
> 키워드: Blocking Session, Deadlock, Lock Wait, pg_blocking_pids, sys.innodb_lock_waits, v$lock, KILL SESSION, Root Blocker  
> 사용처: 운영 DB에서 락(Lock) 경합으로 인한 트랜잭션 대기열 급증, 커넥션 풀 고갈 및 서비스 응답 정지 긴급 복구

---

> 실행예제

운영 DB에서 특정 세션이 락을 선점한 채 끝나지 않아 수십~수백 개의 후속 쿼리가 줄줄이 멈추는 블로킹(Blocking) 상황이 발생했을 때, 데이터베이스 엔진별로 문제를 일으킨 최상위 원인 세션(Root Blocker)을 식별하고 리눅스 OS 레벨의 프로세스 상태를 점검합니다.

```bash
# 1. PostgreSQL: pg_blocking_pids() 함수를 이용한 블로킹 트리 및 락 대기 세션 즉시 조회
$ psql -U postgres -d mydb -c "
SELECT 
    blocked.pid AS blocked_pid,
    blocked.usename AS blocked_user,
    blocking.pid AS blocking_pid,
    blocking.usename AS blocking_user,
    now() - blocked.query_start AS blocked_duration,
    blocked.query AS blocked_query,
    blocking.query AS current_blocking_query
FROM pg_stat_activity blocked
JOIN unnest(pg_blocking_pids(blocked.pid)) blk(pid) ON true
JOIN pg_stat_activity blocking ON blocking.pid = blk.pid
WHERE NOT blocked.wait_event IS NULL
ORDER BY blocked_duration DESC;
"

# 2. MySQL / MariaDB: sys.innodb_lock_waits 뷰를 이용한 블로킹 및 블록당한 스레드 추적
$ mysql -u root -p -e "
SELECT 
    waiting_account,
    waiting_pid,
    waiting_query,
    blocking_account,
    blocking_pid,
    blocking_query,
    wait_age
FROM sys.innodb_lock_waits;
"

# 3. SQL Server (Linux/Windows): sys.dm_os_waiting_tasks로 블로커 SPID 식별
$ sqlcmd -S localhost -U sa -P 'MyStrongPassword123!' -Q "
SELECT 
    blocking_session_id AS Blocker_SPID,
    session_id AS Blocked_SPID,
    wait_type,
    wait_duration_ms,
    resource_description
FROM sys.dm_os_waiting_tasks
WHERE blocking_session_id IS NOT NULL AND blocking_session_id != 0;
"

# 4. OS 관점: 해당 블로커 프로세스가 CPU 폭주 중인지 I/O 대기(D 상태)인지 확인
$ ps -ef | grep -E "postgres|mysqld|oracle|sqlservr" | grep -v grep
```

&nbsp;
&nbsp;

## 스크립트

현재 운영 중인 PostgreSQL 데이터베이스를 기준으로 락 경합 상태를 전수 조사하여, 후속 트랜잭션을 가로막고 있는 최상위 원인 세션(Root Blocker)의 PID, 클라이언트 IP, 지속 시간, 쿼리 내용을 시각화하고 안전하게 종료(`pg_cancel_backend` / `pg_terminate_backend`)할 수 있도록 지원하는 진단 쉘 스크립트입니다.

```bash
#!/bin/bash
# find_blocking_sessions.sh - Identify and safely terminate database blocking sessions (PostgreSQL)

DB_NAME=${1:-"postgres"}
DB_USER=${2:-"postgres"}
MIN_SECONDS=${3:-10}

echo "=========================================="
echo " [운영 DB 블로킹 세션 진단] 대상 DB: ${DB_NAME}"
echo " 최소 대기 시간 기준: ${MIN_SECONDS}초 이상"
echo "=========================================="

if ! command -v psql &>/dev/null; then
    echo "  [오류] psql 유틸리티를 찾을 수 없습니다."
    exit 1
fi

# 1. 블로킹 관계 트리 및 지속 시간 쿼리 실행
QUERY="
WITH RECURSIVE lock_tree AS (
    SELECT 
        bl.pid AS blocked_pid,
        pg_blocking_pids(bl.pid) AS blocker_pids,
        now() - bl.query_start AS duration,
        bl.state,
        bl.query AS blocked_query
    FROM pg_stat_activity bl
    WHERE cardinality(pg_blocking_pids(bl.pid)) > 0
)
SELECT 
    l.blocker_pids[1] AS root_blocker,
    l.blocked_pid,
    EXTRACT(EPOCH FROM l.duration)::int AS duration_sec,
    l.state,
    LEFT(REGEXP_REPLACE(l.blocked_query, '\s+', ' ', 'g'), 60) AS summary_query
FROM lock_tree l
WHERE EXTRACT(EPOCH FROM l.duration) >= ${MIN_SECONDS}
ORDER BY duration_sec DESC;
"

BLOCK_RESULTS=$(psql -U "$DB_USER" -d "$DB_NAME" -t -A -F'|' -c "$QUERY" 2>/dev/null)

if [ -z "$BLOCK_RESULTS" ]; then
    echo "  [정상] ${MIN_SECONDS}초 이상 지연 중인 블로킹 세션이 없습니다."
    exit 0
fi

echo -e "\n[1] 락 대기 상태인 세션 목록:"
printf "  %-12s | %-12s | %-10s | %-12s | %-30s\n" "원인PID(Blocker)" "대기PID(Blocked)" "지연(초)" "상태" "대기 쿼리 요약"
echo "  -------------------------------------------------------------------------------------"

ROOT_BLOCKERS=()

while IFS='|' read -r BLOCKER BLOCKED DUR STATE QUERY_TEXT; do
    [ -z "$BLOCKER" ] && continue
    printf "  %-12s | %-12s | %-10s | %-12s | %-30s\n" "$BLOCKER" "$BLOCKED" "${DUR}s" "$STATE" "$QUERY_TEXT"
    ROOT_BLOCKERS+=("$BLOCKER")
done <<< "$BLOCK_RESULTS"

# 2. 최상위 블로커(Root Blocker) 세부 정보 분석
UNIQUE_BLOCKERS=$(echo "${ROOT_BLOCKERS[@]}" | tr ' ' '\n' | sort -u)

echo -e "\n[2] 최상위 원인 세션(Root Blocker) 상세 정보:"
for BPID in $UNIQUE_BLOCKERS; do
    echo "------------------------------------------------------------------"
    echo "  >> 블로커 PID: ${BPID}"
    psql -U "$DB_USER" -d "$DB_NAME" -x -c "
        SELECT 
            pid, usename, client_addr, state,
            now() - state_change AS idle_duration,
            now() - xact_start AS transaction_duration,
            query
        FROM pg_stat_activity 
        WHERE pid = ${BPID};
    " 2>/dev/null | sed 's/^/    /'
    
    echo "  [권장 긴급 조치 명령어]:"
    echo "  - 부드러운 쿼리 취소 : SELECT pg_cancel_backend(${BPID});"
    echo "  - 강제 세션 연결 단절: SELECT pg_terminate_backend(${BPID});"
done

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

운영 데이터베이스에서 트랜잭션이 처리되지 못하고 시스템이 멈추는 현상은 크게 **블로킹(Blocking)**과 **데드락(Deadlock)**으로 구분되며, 해결 절차와 발생 메커니즘이 전혀 다릅니다.

### 1. 블로킹(Blocking) vs 데드락(Deadlock) 핵심 차이

| 구분 | 발생 원리 | DB 엔진의 대응 | 해결 주체 |
| :--- | :--- | :--- | :--- |
| **블로킹 (Blocking)** | 세션 A가 특정 레코드/테이블의 배타적 락(X-Lock)을 쥔 채 커밋하지 않아, 동일 자원을 요구하는 세션 B, C, D가 무한 대기열을 형성함 | 엔진이 자동으로 개입하지 않고 세션 A가 끝날 때까지 대기 | **DBA/운영자 수동 개입** (원인 세션 식별 후 롤백 또는 Kill) |
| **데드락 (Deadlock)** | 세션 A가 락1을 잡고 락2를 요청하며, 동시에 세션 B가 락2를 잡고 락1을 요청하여 상호 순환 대기(Circular Wait)에 빠짐 | **DB 엔진의 Deadlock Detector가 감지**하여 둘 중 비용이 적은 세션을 강제 롤백(희생자 선택) | **자동 복구됨** (애플리케이션에 데드락 재시도 로직 구현 필요) |

### 2. 최상위 블로커(Root Blocker)의 주요 원인

1. **`idle in transaction` 방치**:
   * 애플리케이션 코드가 트랜잭션을 시작(`BEGIN`)하여 `UPDATE`를 수행한 후, 외부 서드파티 HTTP API 호출이 지연되거나 예외가 발생했으나 `COMMIT` 또는 `ROLLBACK`을 호출하지 않고 방치된 경우.
2. **트랜잭션 격리 수준 및 대규모 배치 쿼리**:
   * 서비스 피크 타임에 인덱스를 타지 않는 대량의 `DELETE` 또는 `UPDATE` 배치가 실행되어 수만 건의 레코드 또는 테이블 락(Table Lock)을 장시간 점유하는 경우.
3. **인덱스 누락으로 인한 락 에스컬레이션(Lock Escalation)**:
   * 외래 키(Foreign Key) 칼럼에 인덱스가 누락되어 부모 테이블 수정 시 자식 테이블 전체에 락이 걸리는 현상.

### 3. 데이터베이스 엔진별 안전한 강제 종료(Kill) 명령어

대기 중인 불쌍한 희생자(Blocked) 세션을 죽이면 안 되며, 반드시 **트리의 최상단에 있는 원인 세션(Root Blocker)**을 종료해야 전체 병목이 풀립니다.

#### 1) PostgreSQL
```sql
-- 1단계: 실행 중인 쿼리만 안전하게 취소 (세션 유지는 됨)
SELECT pg_cancel_backend(12345);

-- 2단계: 응답이 없거나 idle in transaction 상태인 경우 세션 강제 종료 (SIGTERM)
SELECT pg_terminate_backend(12345);
```

#### 2) MySQL / MariaDB
```sql
-- 연결된 스레드 강제 종료 (롤백 수행)
KILL CONNECTION 5421;

-- 실행 중인 쿼리만 중단
KILL QUERY 5421;
```

#### 3) Oracle Database
```sql
-- 세션 즉시 종료 (SID, SERIAL# 필요)
ALTER SYSTEM KILL SESSION '145, 23412' IMMEDIATE;

-- RAC 환경인 경우 (SID, SERIAL#, @INST_ID)
ALTER SYSTEM KILL SESSION '145, 23412, @1' IMMEDIATE;
```

#### 4) Microsoft SQL Server
```sql
-- 특정 세션 SPID 강제 종료 및 롤백 유도
KILL 78;

-- 진행 중인 롤백 완료율(%) 확인
KILL 78 WITH STATUSONLY;
```

&nbsp;
&nbsp;

## 주의사항

1. **대형 트랜잭션 Kill 시 롤백(Rollback) 지연 시간 고려**:
   * 수백만 건의 데이터를 변경한 대형 트랜잭션을 `KILL`하면 즉시 끝나는 것이 아니라, 언두(Undo) 로그를 바탕으로 **이전 상태로 되돌리는 롤백 작업**을 수행합니다. 롤백 중인 프로세스를 OS 레벨에서 `kill -9`로 강제 종료하면 데이터 파일 손상이나 재부팅 시 장시간 크래시 복구(Crash Recovery) 상태에 빠지므로 절대로 OS 강제 종료를 남발해서는 안 됩니다.

2. **희생자(Victim) 세션을 오인하여 종료하지 말 것**:
   * 대기 목록에서 가장 오래 기다리고 있는 세션은 피해자일 뿐입니다. 피해자를 종료하면 잠시 대기 목록은 줄어들지만 즉시 다른 신규 세션들이 다시 블로킹에 걸립니다. 반드시 락을 잡고 놓아주지 않는 `Root Blocker PID`를 찾아 종료해야 합니다.

3. **DB 레벨의 타임아웃 파라미터 사전 구성**:
   * 블로킹이 발생했을 때 시스템 전체 마비를 예방하기 위해 세션/락 타임아웃을 안전장치로 지정해야 합니다.
     * **PostgreSQL**: `lock_timeout = '5s'`, `idle_in_transaction_session_timeout = '30s'`
     * **MySQL**: `innodb_lock_wait_timeout = 50`
     * **Oracle**: `ALTER SESSION SET DDL_LOCK_TIMEOUT = 10;`