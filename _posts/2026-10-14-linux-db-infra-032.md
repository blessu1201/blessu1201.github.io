---
layout: article
title: 시스템 관리_32 오라클 ORA-00020 maximum number of processes exceeded 오류 원인 분석 및 긴급 조치 가이드
tags: [Linux, Oracle, Database, ORA-00020, Processes, Sessions, SPFILE, Connection-Leak, DBA, Troubleshooting]
keys: 261014-linux-db-infra-032
---

- 출처 / 참고: Oracle Database Reference (PROCESSES parameter, SESSIONS parameter), Oracle Error Messages (ORA-00020)

> 명령어: `sqlplus`, `ps`, `kill`, `grep`, `awk`, `ipcs`  
> 키워드: ORA-00020, maximum number of processes exceeded, v$process, v$session, SPFILE, processes, sessions, Connection Leak  
> 사용처: 오라클 DB 신규 접속 전면 차단 장애 긴급 복구, 애플리케이션 커넥션 누수 추적, DB 프로세스 한도 증설 및 재기동

---

> 실행예제

오라클 데이터베이스에 신규 접속 시 `ORA-00020: maximum number of processes (xxx) exceeded` 에러가 발생하며 일반 접속이 거절될 때, OS 프로세스 현황과 데이터베이스 내부 프로세스 점유 상태를 파악합니다. 프로세스가 가득 차 일반 계정은 물론 일반 `sysdba` 접속마저 실패할 수 있으므로 전용 진단 접속 옵션(`-prelim`)을 활용합니다.

```bash
# 1. 애플리케이션 또는 SQL*Plus 접속 시 ORA-00020 오류 확인
$ sqlplus scott/tiger@orcl
# ERROR:
# ORA-00020: maximum number of processes (300) exceeded

# 2. OS 레벨에서 현재 실행 중인 오라클 서버 프로세스(oracle<SID>) 개수 확인
$ ps -ef | grep -E "oracle${ORACLE_SID}" | grep -v grep | wc -l
301
# -> 파라미터 한도(300)에 도달하여 추가 포크(fork)가 불가능한 상태 확인

# 3. 프로세스 고갈로 인해 sqlplus 접속이 거부될 경우 prelim 모드로 긴급 진단 연결
$ sqlplus -prelim "/ as sysdba"

# 4. 일반 sysdba 접속이 가능할 때 현재 프로세스 및 세션 사용률 조회
$ sqlplus -s / as sysdba << 'EOF'
SET LINESIZE 200 PAGESIZE 100
COL resource_name FORMAT A20
COL current_utilization FORMAT 999,999
COL max_utilization FORMAT 999,999
COL initial_allocation FORMAT A20
COL limit_value FORMAT A20

SELECT resource_name, current_utilization, max_utilization, initial_allocation, limit_value
FROM v$resource_limit
WHERE resource_name IN ('processes', 'sessions');
EXIT;
EOF
# [출력 예시]
# RESOURCE_NAME        CURRENT_UTILIZATION MAX_UTILIZATION INITIAL_ALLOCATION   LIMIT_VALUE
# -------------------- ------------------- --------------- -------------------- --------------------
# processes                            300             300 300                  300
# sessions                             452             460 472                  472

# 5. 어떤 클라이언트 머신(IP/호스트)과 프로그램이 프로세스를 대량 점유 중인지 조회
$ sqlplus -s / as sysdba << 'EOF'
SET LINESIZE 200 PAGESIZE 100
COL machine FORMAT A30
COL program FORMAT A30
COL session_count FORMAT 999,999

SELECT machine, program, count(*) AS session_count
FROM v$session
GROUP BY machine, program
ORDER BY session_count DESC;
EXIT;
EOF
```

&nbsp;
&nbsp;

## 스크립트

현재 오라클의 `processes` 한도 대비 실제 OS 프로세스 점유율을 실시간 계산하고, 특정 클라이언트 머신이나 프로그램별 점유 순위를 추출하여 연결 누수(Connection Leak) 유발 원인을 식별하는 쉘 스크립트입니다.

```bash
#!/bin/bash
# check_oracle_processes.sh - Diagnose Oracle ORA-00020 process exhaustion

export ORACLE_SID=${ORACLE_SID:-"orcl"}
export ORAENV_ASK=NO
[ -f /usr/local/bin/oraenv ] && . /usr/local/bin/oraenv >/dev/null 2>&1

echo "=========================================="
echo " [오라클 프로세스 점유율 및 ORA-00020 진단]"
echo " ORACLE_SID: ${ORACLE_SID}"
echo "=========================================="

# 1. OS 프로세스 카운트
OS_PROC_COUNT=$(ps -ef | grep -E "oracle${ORACLE_SID}" | grep -v grep | wc -l)
echo -e "\n[1] OS 레벨 오라클 프로세스 카운트:"
echo "  - 현재 기동 중인 oracle${ORACLE_SID} 프로세스 수: ${OS_PROC_COUNT}개"

# 2. v$resource_limit 조회
echo -e "\n[2] 오라클 v\$resource_limit 파라미터 한도 점검:"
SQL_RES=$(sqlplus -s / as sysdba << 'EOF'
SET FEEDBACK OFF HEADING OFF ECHO OFF VERIFY OFF LINESIZE 200
SELECT resource_name || '|' || current_utilization || '|' || max_utilization || '|' || TRIM(limit_value)
FROM v$resource_limit
WHERE resource_name IN ('processes', 'sessions');
EXIT;
EOF
)

if [ -z "$SQL_RES" ]; then
    echo "  [오류] DB 연결 실패. ORA-00020 한도 초과로 sysdba 접속이 차단되었을 수 있습니다."
    echo "  -> 긴급 조치: 'sqlplus -prelim / as sysdba' 또는 비정상 WAS 프로세스 정리가 필요합니다."
    exit 1
fi

while IFS='|' read -r R_NAME CURR_UTIL MAX_UTIL LIMIT_VAL; do
    [ -z "$R_NAME" ] && continue
    PCT=$(awk "BEGIN {printf \"%.2f\", ($CURR_UTIL/$LIMIT_VAL)*100}")
    echo "  - ${R_NAME^^} : 현재 ${CURR_UTIL} / 한도 ${LIMIT_VAL} (사용률: ${PCT}%, 최대기록: ${MAX_UTIL})"
    
    IS_FULL=$(echo "$CURR_UTIL >= $LIMIT_VAL" | bc -l 2>/dev/null)
    if [ "$IS_FULL" -eq 1 ]; then
        echo "    [치명적 위험] ${R_NAME^^} 한도에 도달하여 신규 커넥션이 전면 차단 중입니다!"
    fi
done <<< "$SQL_RES"

# 3. 상위 커넥션 점유 클라이언트 머신 분석
echo -e "\n[3] 상위 세션 점유 클라이언트 머신 Top 5:"
sqlplus -s / as sysdba << 'EOF'
SET FEEDBACK OFF HEADING ON LINESIZE 160 PAGESIZE 50
COL machine FORMAT A35
COL program FORMAT A30
COL count FORMAT 999,999
SELECT machine, program, status, count(*) AS count
FROM v$session
GROUP BY machine, program, status
ORDER BY count DESC
FETCH FIRST 5 ROWS ONLY;
EXIT;
EOF

# 4. INACTIVE 상태로 장시간 방치된 세션 수 확인
echo -e "\n[4] 유휴(INACTIVE) 방치 세션 수 집계:"
sqlplus -s / as sysdba << 'EOF'
SET FEEDBACK OFF HEADING OFF LINESIZE 100
SELECT '  - INACTIVE 세션 수: ' || count(*) || '개'
FROM v$session
WHERE status = 'INACTIVE';
EXIT;
EOF

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

`ORA-00020: maximum number of processes (xxx) exceeded`는 오라클 인스턴스의 초기화 파라미터 파일(SPFILE/PFILE)에 정의된 `processes` 제한값에 도달하여, **오라클 커널이 새로운 백그라운드 프로세스 또는 사용자 전용 서버 프로세스(Dedicated Server Process)를 운영체제에 포크(fork)할 수 없을 때** 발생하는 치명적인 장애입니다.

### 1. 주요 발생 원인

1. **애플리케이션 커넥션 누수 (Connection Leak)**:
   * 백엔드 애플리케이션(Spring Boot, MyBatis, JPA 등)에서 트랜잭션 종료 후 `connection.close()` 호출을 누락하여 반환되지 않은 세션이 DB에 `INACTIVE` 상태로 계속 쌓이는 경우.
2. **WAS 커넥션 풀(HikariCP, DBCP 등) 과다 설정**:
   * 여러 대의 WAS 인스턴스가 각각 과도한 `maximumPoolSize`(예: 서버당 100~200개)를 잡고 구동되면서 합산 커넥션 수가 DB의 `processes` 설정치를 훌쩍 초과한 경우.
3. **DB 프로세스 한도(`processes`)의 절대적 부족**:
   * 시스템 메모리 및 동시 접속자 규모는 성장했으나, 초기 기본값(보통 150 또는 300)으로 방치되어 있는 경우.
4. **오라클 Dead Connection 축적**:
   * 클라이언트 PC나 네트워크 단절로 인해 연결이 비정상 종료되었으나, DB 서버가 이를 감지하지 못하고 좀비 세션으로 물고 있는 경우.

### 2. 단계별 복구 및 해결 방법

#### 1) 긴급 조치: 유휴 좀비 세션 강제 종료 (Kill)
우선 DB 접속을 재개하기 위해 장시간 방치된 `INACTIVE` 세션을 정리합니다.

```sql
-- 1시간 이상 비활성 상태인 특정 머신의 세션 식별
SELECT 'ALTER SYSTEM KILL SESSION ''' || sid || ',' || serial# || ''' IMMEDIATE;'
FROM v$session
WHERE status = 'INACTIVE'
  AND last_call_et > 3600
  AND type != 'BACKGROUND';

-- 위 쿼리 결과로 출력된 구문을 실행하여 세션 강제 종료
```

* 만약 `sqlplus` 접속 자체가 거절된다면 OS 레벨에서 특정 시간 이상 유휴 상태인 프로세스를 식별하여 `kill -9 <PID>`로 정리하거나, 긴급용으로 진단 모드(`sqlplus -prelim "/ as sysdba"`)를 통해 진입해야 합니다.

#### 2) 영구 증설: SPFILE의 `processes` 및 `sessions` 파라미터 증설
시스템 RAM 사양을 고려하여 파라미터를 상향 조정합니다. (`processes`는 정적 파라미터이므로 DB 재기동이 필요합니다.)

```sql
-- 1. 파라미터 값 변경 (예: 300 -> 1000)
ALTER SYSTEM SET processes=1000 SCOPE=SPFILE;

-- 2. sessions 값도 processes 공식에 맞게 상향
-- 오라클 권장 공식: sessions = (1.5 * processes) + 22
ALTER SYSTEM SET sessions=1522 SCOPE=SPFILE;

-- 3. 설정 반영을 위한 인스턴스 재기동
SHUTDOWN IMMEDIATE;
STARTUP;

-- 4. 변경 결과 확인
SHOW PARAMETER processes;
SHOW PARAMETER sessions;
```

#### 3) 데드 커넥션 감지(DCD) 활성화
네트워크 비정상 단절 세션을 오라클이 주기적으로 체크하여 자동 정리하도록 설정합니다.
```ini
# $ORACLE_HOME/network/admin/sqlnet.ora
SQLNET.EXPIRE_TIME = 10
```
* 10분마다 클라이언트에 프로브(Probe) 패킷을 보내 응답이 없으면 세션을 자동 회수합니다.

&nbsp;
&nbsp;

## 주의사항

1. **`processes` 무조건적인 과다 증설 주의**:
   * 전용 서버(Dedicated Server) 환경에서 프로세스 1개당 통상 수 MB에서 수십 MB의 PGA 및 OS 메모리를 소비합니다. 호스트 물리 RAM 용량을 고려하지 않고 무작정 3,000~5,000 단위로 늘리면 OS 메모리 고갈로 인한 스왑(Swap) 폭증 및 커널 패닉을 유발할 수 있습니다.

2. **OS 커널 세마포어(Semaphores) 및 nproc 한도 확인 필수**:
   * 오라클의 `processes`를 늘릴 때는 리눅스 커널 파라미터인 `kernel.sem`의 `SEMMNS`(세마포어 총량)와 `oracle` OS 계정의 `nproc`(`ulimit -u`) 한도도 반드시 함께 늘려주어야 합니다. 커널 한도가 낮으면 DB 기동 시 `ORA-27154: post/wait create failed` 또는 `ORA-27300: OS system dependant operation:fork failed`가 발생합니다.

3. **근본적인 커넥션 누수(Connection Leak) 해결 선행**:
   * `processes` 파라미터를 늘려주는 것은 임시방편일 뿐입니다. 소스 코드 상에서 DB 커넥션을 반환하지 않는 버그가 남아있다면 한도를 2,000으로 늘려도 시간문제일 뿐 다시 ORA-00020을 마주하게 됩니다. 반드시 APM 도구(Scouter, Jennifer 등)나 세션 모니터링을 통해 누수 지점을 찾아 코드를 수정해야 합니다.