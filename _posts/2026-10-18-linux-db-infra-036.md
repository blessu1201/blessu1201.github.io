---
layout: article
title: 시스템 관리_36 SQL Server 트랜잭션 로그 풀 LOG_BACKUP 원인 분석 및 긴급 축소 해결 가이드
tags: [Linux, Windows, SQL-Server, MSSQL, Transaction-Log, LOG_BACKUP, DBCC-SHRINKFILE, Recovery-Model, DBA, Troubleshooting]
keys: 261018-linux-db-infra-036
---

- 출처 / 참고: Microsoft Learn (Troubleshoot a Full Transaction Log - SQL Server Error 9002), Microsoft Documentation (Manage the Size of the Transaction Log File)

> 명령어: `sqlcmd`, `df`, `ls`, `grep`, `awk`  
> 키워드: Error 9002, The transaction log for database is full due to LOG_BACKUP, log_reuse_wait_desc, DBCC SQLPERF, BACKUP LOG, DBCC SHRINKFILE, FULL Recovery Model  
> 사용처: SQL Server 데이터베이스에서 데이터 수정/추가(INSERT/UPDATE/DELETE) 트랜잭션 차단 장애 긴급 복구 및 정기 로그 백업 체계 구성

---

> 실행예제

데이터 수정 쿼리 실행 시 `Error: 9002, Severity: 17, State: 2. The transaction log for database '...' is full due to 'LOG_BACKUP'` 오류가 발생했을 때 OS 디스크 상태와 SQL Server 내부 로그 재사용 대기 사유(`log_reuse_wait_desc`) 및 로그 공간 사용률을 점검합니다.

```bash
# 1. 애플리케이션 또는 SQL Server 에러 로그에서 Error 9002 확인
$ sudo tail -n 30 /var/opt/mssql/log/errorlog | grep -E "9002|transaction log.*full"
# [출력 예시]
# Error: 9002, Severity: 17, State: 2.
# The transaction log for database 'SampleDB' is full due to 'LOG_BACKUP'.

# 2. OS 레벨에서 트랜잭션 로그 파일(.ldf)이 위치한 마운트 포인트 여유 공간 확인
$ df -h /var/opt/mssql/data
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/sdb1       200G  198G  500M  100% /var/opt/mssql/data
# -> 로그 파일 자동 증가(Auto-growth)를 위한 디스크 여유 공간이 완전히 고갈되었는지 확인

# 3. 데이터베이스별 복구 모델(Recovery Model) 및 로그 재사용 대기 원인 확인
$ sqlcmd -S localhost -U sa -P 'MyStrongPassword123!' -Q "
SELECT 
    name, 
    recovery_model_desc, 
    log_reuse_wait, 
    log_reuse_wait_desc 
FROM sys.databases 
WHERE name = 'SampleDB';
"
# [출력 예시]
# name       recovery_model_desc log_reuse_wait log_reuse_wait_desc
# ---------- ------------------- -------------- -------------------
# SampleDB   FULL                             2 LOG_BACKUP
# -> FULL 복구 모델 상태에서 로그 백업이 수행되지 않아 로그 재사용이 영구 정체 중임을 확인

# 4. 전체 데이터베이스의 트랜잭션 로그 공간 점유율(%) 및 크기 확인
$ sqlcmd -S localhost -U sa -P 'MyStrongPassword123!' -Q "
DBCC SQLPERF(LOGSPACE);
"
# [출력 예시]
# Database Name  Log Size (MB)  Log Space Used (%)  Status
# -------------  -------------  ------------------  ------
# master         3.99           35.21               0
# SampleDB       154200.50      99.85               0
# -> SampleDB의 트랜잭션 로그가 154GB에 도달하고 99.85%를 소모한 상태 확인

# 5. 대상 데이터베이스의 실제 로그 파일 논리명 확인 (DBCC SHRINKFILE에 필요)
$ sqlcmd -S localhost -U sa -P 'MyStrongPassword123!' -Q "
SELECT file_id, name, physical_name, size * 8 / 1024 AS size_mb 
FROM sys.master_files 
WHERE database_id = DB_ID('SampleDB') AND type = 1;
"
```

&nbsp;
&nbsp;

## 스크립트

SQL Server 인스턴스 내 모든 데이터베이스의 트랜잭션 로그 사용률과 `log_reuse_wait_desc` 상태를 점검하여, 로그 백업 누락으로 인해 확장이 임박하거나 정체된 데이터베이스를 탐색하고 권장 복구 쿼리를 출력하는 진단 쉘 스크립트입니다.

```bash
#!/bin/bash
# check_mssql_log_full.sh - Diagnose SQL Server Transaction Log usage and LOG_BACKUP state

SQL_HOST=${1:-"localhost"}
SQL_USER=${2:-"sa"}
SQL_PASS=${3:-"MyStrongPassword123!"}
TARGET_DB=${4:-""}

echo "=========================================="
echo " [SQL Server 트랜잭션 로그 고갈 상태 진단]"
echo " 대상 호스트: ${SQL_HOST}"
echo "=========================================="

if ! command -v sqlcmd &>/dev/null; then
    echo "  [오류] sqlcmd 명령어를 찾을 수 없습니다. mssql-tools 설치 여부를 확인하세요."
    exit 1
fi

# 1. sys.databases의 로그 재사용 대기 사유 점검
echo -e "\n[1] 데이터베이스별 복구 모델 및 로그 재사용 대기 원인:"
QUERY_DB_STATUS="
SET NOCOUNT ON;
SELECT 
    name, 
    recovery_model_desc, 
    log_reuse_wait_desc 
FROM sys.databases 
WHERE name NOT IN ('master', 'tempdb', 'model')
"
[ -n "$TARGET_DB" ] && QUERY_DB_STATUS="${QUERY_DB_STATUS} AND name = '${TARGET_DB}'"

DB_LIST=$(sqlcmd -S "$SQL_HOST" -U "$SQL_USER" -P "$SQL_PASS" -W -Q "$QUERY_DB_STATUS" 2>/dev/null)
echo "$DB_LIST" | sed 's/^/  /'

# 2. LOGSPACE 통계 확인
echo -e "\n[2] DBCC SQLPERF(LOGSPACE) 로그 사용률 통계:"
LOG_STATS=$(sqlcmd -S "$SQL_HOST" -U "$SQL_USER" -P "$SQL_PASS" -W -Q "
SET NOCOUNT ON;
CREATE TABLE #LogStats (
    DatabaseName sysname,
    LogSizeMB float,
    LogSpaceUsedPercent float,
    Status int
);
INSERT INTO #LogStats EXEC('DBCC SQLPERF(LOGSPACE)');
SELECT DatabaseName, LogSizeMB, LogSpaceUsedPercent FROM #LogStats WHERE LogSpaceUsedPercent > 80.0;
DROP TABLE #LogStats;
" 2>/dev/null)

if echo "$LOG_STATS" | grep -q "[0-9]"; then
    echo "  [경고] 로그 점유율 80% 초과 데이터베이스 감지:"
    echo "$LOG_STATS" | sed 's/^/  /'
else
    echo "  [정상] 80%를 초과하여 임계치에 도달한 데이터베이스가 없습니다."
fi

# 3. LOG_BACKUP 대기 상태에 대한 긴급 조치 가이드 생성
echo -e "\n[3] LOG_BACKUP 병목 감지 시 권장 조치 가이드:"
BLOCKED_DBS=$(sqlcmd -S "$SQL_HOST" -U "$SQL_USER" -P "$SQL_PASS" -h -1 -W -Q "
SET NOCOUNT ON;
SELECT name FROM sys.databases WHERE log_reuse_wait_desc = 'LOG_BACKUP';
" 2>/dev/null | tr -d '[:space:]')

if [ -n "$BLOCKED_DBS" ]; then
    echo "  [!] 다음 데이터베이스들이 LOG_BACKUP으로 인해 로그가 비워지지 못하고 있습니다:"
    for DB in $BLOCKED_DBS; do
        LOG_LOGICAL_NAME=$(sqlcmd -S "$SQL_HOST" -U "$SQL_USER" -P "$SQL_PASS" -h -1 -W -Q "
        SET NOCOUNT ON;
        SELECT name FROM sys.master_files WHERE database_id = DB_ID('$DB') AND type = 1;
        " 2>/dev/null | tr -d '[:space:]')
        
        echo "    - DB명: ${DB} (로그 논리 파일명: ${LOG_LOGICAL_NAME})"
        echo "      [긴급 조치 쿼리 예시]:"
        echo "      1) 트랜잭션 로그 백업 (권장):"
        echo "         BACKUP LOG [${DB}] TO DISK = '/var/opt/mssql/data/${DB}_LogBackup.trn' WITH COMPRESSION;"
        echo "      2) 로그 파일 물리적 축소:"
        echo "         DBCC SHRINKFILE (N'${LOG_LOGICAL_NAME}', 1024);"
    done
else
    echo "  [정상] 현재 LOG_BACKUP으로 정체된 데이터베이스가 없습니다."
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

`The transaction log for database is full due to 'LOG_BACKUP'` (오류 번호 9002)는 SQL Server에서 특정 데이터베이스의 트랜잭션 로그 파일(`.ldf`)이 최대 허용 크기에 도달했거나 디스크 공간 부족으로 더 이상 늘어날 수 없는데, 내부적으로 **이전 로그 공간을 비우고 재사용(Truncation)하기 위해 필요한 트랜잭션 로그 백업이 제때 수행되지 않아** 발생합니다.

### 1. 트랜잭션 로그 가상 로그 파일(VLF)과 순환 원리

SQL Server의 트랜잭션 로그는 내부적으로 여러 개의 **VLF(Virtual Log File)**로 나뉘어 원형 큐(Circular Queue) 형태로 재사용됩니다.
* **SIMPLE (단순) 복구 모델**: 체크포인트(CHECKPOINT)가 발생하면 커밋 완료된 트랜잭션의 VLF가 자동으로 비활성(Inactive) 상태로 전환되어 재사용됩니다.
* **FULL (전체) 복구 모델**: 특정 시점 복원(Point-in-Time Recovery)을 위해 커밋 완료된 트랜잭션이라도 **반드시 `BACKUP LOG` 명령어로 백업되기 전까지는 VLF를 비활성화하지 않고 보존**합니다.

따라서 데이터베이스를 FULL 복구 모델로 만들어 두고 정기적인 트랜잭션 로그 백업 스케줄(예: 15분~1시간 주기)을 걸어두지 않으면, 데이터 변경 이력이 무한정 누적되어 파일이 디스크 전체를 채우거나 최대 한도에 도달해 신규 트랜잭션이 중단됩니다.

### 2. 단계별 복구 및 해결 방법

#### 방법 1: 트랜잭션 로그 백업 수행 후 축소 (운영 환경 권장)
기존 LSN(Log Sequence Number) 백업 체인을 깨뜨리지 않고 안전하게 비활성 VLF를 만든 후 용량을 회수합니다.

```sql
-- 1. 트랜잭션 로그 백업 수행 (압축 옵션 권장)
BACKUP LOG [SampleDB] 
TO DISK = N'/var/opt/mssql/data/SampleDB_LogBackup.trn' 
WITH COMPRESSION;

-- 2. 로그 파일의 논리 파일명 확인
SELECT file_id, name, size * 8 / 1024 AS size_mb 
FROM sys.database_files 
WHERE type = 1;

-- 3. 로그 파일 축소 (예: 2GB 크기로 축소)
DBCC SHRINKFILE (N'SampleDB_log', 2048);
```

#### 방법 2: 긴급 복구 - 일시적 SIMPLE 모델 전환 후 복귀 (디스크 100% 고갈 시)
디스크 용량이 0바이트여서 로그 백업 파일 자체를 기록할 공간조차 없는 절대적인 긴급 상황일 때 사용합니다.

```sql
-- 1. 복구 모델을 SIMPLE로 임시 변경 (체크포인트 시 자동 절삭 활성화)
ALTER DATABASE [SampleDB] SET RECOVERY SIMPLE;

-- 2. 체크포인트 강제 발생
CHECKPOINT;

-- 3. 로그 파일 축소
DBCC SHRINKFILE (N'SampleDB_log', 1024);

-- 4. 복구 모델을 다시 FULL로 원복
ALTER DATABASE [SampleDB] SET RECOVERY FULL;

-- 5. ★중요★ 복구 체인이 끊어졌으므로 즉시 전체 백업(Full Backup) 수행
BACKUP DATABASE [SampleDB] 
TO DISK = N'/var/opt/mssql/data/SampleDB_Full_AfterRecovery.bak' 
WITH COMPRESSION;
```

#### 방법 3: 자동 증가 한도(Maxsize) 점검 및 수정
로그 파일의 `MAXSIZE`가 특정 용량(예: 10GB)으로 제한되어 디스크 공간이 남아있음에도 불구하고 9002 오류를 뱉는 경우 제한을 해제합니다.

```sql
ALTER DATABASE [SampleDB] 
MODIFY FILE (NAME = N'SampleDB_log', MAXSIZE = UNLIMITED, FILEGROWTH = 512MB);
```

&nbsp;
&nbsp;

## 주의사항

1. **SIMPLE 복구 모델 전환 후 전체 백업(Full Backup) 누락 주의**:
   * 방법 2처럼 긴급 해제를 위해 SIMPLE로 변경하는 순간 기존의 트랜잭션 로그 체인이 영구 파괴됩니다. 복구 모델을 FULL로 되돌린 후 **즉시 `BACKUP DATABASE`를 새로 받지 않으면 이후의 시점 복구(Point-in-Time Restore)가 불가능**해집니다.

2. **`DBCC SHRINKFILE`의 반복적인 남발 금지**:
   * 로그 파일을 수시로 수십 MB 수준으로 극단 축소하면, 트랜잭션 발생 시 파일 확장(Auto-growth)이 지속적으로 일어나면서 VLF 개수가 수천 개로 파편화(VLF Fragmentation)되어 쿼리 성능과 인스턴스 부팅/복구 시간이 급격히 저하됩니다. 로그 파일은 통상적인 일일 피크 트래픽을 여유 있게 수용할 수 있는 적정 크기(예: 데이터 파일 크기의 20~30%)를 유지하도록 설계해야 합니다.

3. **정기적인 트랜잭션 로그 백업 에이전트 잡(Job) 필수 구성**:
   * FULL 복구 모델을 유지해야 하는 운영 DB라면 반드시 SQL Server 에이전트(또는 Linux 크론탭)를 통해 15분, 30분, 혹은 1시간 단위로 `BACKUP LOG`가 자동 실행되도록 유지해야 영구적인 9002 에러 재발을 방지할 수 있습니다.