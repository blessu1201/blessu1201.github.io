---
layout: article
title: 시스템 관리_31 오라클 ORA-01653 unable to extend table 테이블스페이스 공간 부족 오류 원인 분석 및 긴급 증설 해결 가이드
tags: [Linux, Oracle, Database, ORA-01653, Tablespace, Datafile, AUTOEXTEND, DBA, Troubleshooting]
keys: 261013-linux-db-infra-031
---

- 출처 / 참고: Oracle Database Administrator's Guide (Managing Tablespaces), Oracle Database Error Messages (ORA-01653)

> 명령어: `sqlplus`, `df`, `asmcmd`, `oerr`, `du`, `tail`  
> 키워드: ORA-01653, unable to extend table, Tablespace Full, AUTOEXTEND, Datafile, RESIZE, Smallfile, Bigfile  
> 사용처: 오라클 DB 배치 작업 또는 웹 서비스 인서트 트랜잭션 중 테이블스페이스 공간 고갈로 인한 쿼리 중단 긴급 복구

---

> 실행예제

데이터베이스 애플리케이션 로그 또는 Alert log에서 `ORA-01653: unable to extend table ... by ... in tablespace ...` 오류가 발생했을 때 OS 파일시스템 디스크 여유 공간과 오라클 내부 테이블스페이스의 실제 사용률 및 자동 확장(`AUTOEXTEND`) 설정 상태를 확인합니다.

```bash
# 1. 오라클 alert.log 파일에서 ORA-01653 발생 내역 확인
$ tail -n 50 $ORACLE_BASE/diag/rdbms/$ORACLE_SID/$ORACLE_SID/trace/alert_$ORACLE_SID.log
# [출력 예시]
# ORA-01653: unable to extend table SCOTT.ORDER_HISTORY by 8192 in tablespace USERS
# Completed checkpoint up to RBA ...

# 2. OS 레벨에서 오라클 데이터파일이 위치한 파일시스템 디스크 여유 공간 확인
$ df -h /u01 /u02 /data
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/sdb1       500G  485G  2.1G  99% /data
# -> 디스크 마운트 포인트 자체가 99%에 도달했는지 확인

# 3. SQL*Plus로 접속하여 테이블스페이스별 가용량 및 사용률 조회
$ sqlplus -s / as sysdba << 'EOF'
SET LINESIZE 200 PAGESIZE 100
COL tablespace_name FORMAT A20
COL total_mb FORMAT 999,999,999
COL used_mb FORMAT 999,999,999
COL free_mb FORMAT 999,999,999
COL used_pct FORMAT 990.99

SELECT 
    d.tablespace_name,
    ROUND(d.bytes / 1024 / 1024) AS total_mb,
    ROUND((d.bytes - NVL(f.bytes, 0)) / 1024 / 1024) AS used_mb,
    ROUND(NVL(f.bytes, 0) / 1024 / 1024) AS free_mb,
    ROUND(((d.bytes - NVL(f.bytes, 0)) / d.bytes) * 100, 2) AS used_pct
FROM 
    (SELECT tablespace_name, SUM(bytes) AS bytes FROM dba_data_files GROUP BY tablespace_name) d
    LEFT JOIN 
    (SELECT tablespace_name, SUM(bytes) AS bytes FROM dba_free_space GROUP BY tablespace_name) f
    ON d.tablespace_name = f.tablespace_name
ORDER BY used_pct DESC;
EXIT;
EOF

# 4. 대상 테이블스페이스에 속한 데이터파일 목록 및 자동확장(AUTOEXTEND) 여부 조회
$ sqlplus -s / as sysdba << 'EOF'
SET LINESIZE 200 PAGESIZE 100
COL file_name FORMAT A50
COL autoextensible FORMAT A10
COL maxbytes_mb FORMAT 999,999,999

SELECT 
    file_id, 
    file_name, 
    ROUND(bytes/1024/1024) AS size_mb, 
    autoextensible, 
    ROUND(maxbytes/1024/1024) AS maxbytes_mb
FROM dba_data_files
WHERE tablespace_name = 'USERS';
EXIT;
EOF
```

&nbsp;
&nbsp;

## 스크립트

오라클 환경에서 테이블스페이스별 점유율을 계산하여 90% 이상 차 있는 테이블스페이스를 경고하고, 해당 데이터파일들의 `AUTOEXTEND` 상태와 최대 한도 도달 여부를 진단하는 쉘 스크립트입니다.

```bash
#!/bin/bash
# check_oracle_tablespace.sh - Diagnose Oracle Tablespace usage and ORA-01653 risks

export ORACLE_SID=${ORACLE_SID:-"orcl"}
export ORAENV_ASK=NO
[ -f /usr/local/bin/oraenv ] && . /usr/local/bin/oraenv >/dev/null 2>&1

echo "=========================================="
echo " [오라클 테이블스페이스 공간 진단] SID: ${ORACLE_SID}"
echo "=========================================="

# 1. 오라클 인스턴스 접속 가능 여부 점검
if ! command -v sqlplus &>/dev/null; then
    echo "  [오류] sqlplus 명령어를 찾을 수 없습니다. 환경변수(ORACLE_HOME/PATH)를 확인하세요."
    exit 1
fi

# 2. 테이블스페이스 사용률 점검 쿼리 실행
SQL_OUTPUT=$(sqlplus -s / as sysdba << 'EOF'
SET FEEDBACK OFF HEADING OFF ECHO OFF VERIFY OFF LINESIZE 300
SELECT 
    d.tablespace_name || '|' ||
    ROUND(d.bytes / 1024 / 1024) || '|' ||
    ROUND((d.bytes - NVL(f.bytes, 0)) / 1024 / 1024) || '|' ||
    ROUND(NVL(f.bytes, 0) / 1024 / 1024) || '|' ||
    TO_CHAR(ROUND(((d.bytes - NVL(f.bytes, 0)) / d.bytes) * 100, 2), 'FM990.00')
FROM 
    (SELECT tablespace_name, SUM(bytes) AS bytes FROM dba_data_files GROUP BY tablespace_name) d
    LEFT JOIN 
    (SELECT tablespace_name, SUM(bytes) AS bytes FROM dba_free_space GROUP BY tablespace_name) f
    ON d.tablespace_name = f.tablespace_name
ORDER BY 5 DESC;
EXIT;
EOF
)

if [ -z "$SQL_OUTPUT" ]; then
    echo "  [오류] 테이블스페이스 정보를 조회할 수 없습니다. DB 상태를 확인하세요."
    exit 1
fi

echo -e "\n[1] 테이블스페이스별 점유율 분석:"
printf "  %-20s | %-12s | %-12s | %-12s | %-8s\n" "테이블스페이스명" "전체(MB)" "사용(MB)" "여유(MB)" "사용률(%)"
echo "  -------------------------------------------------------------------------------"

CRITICAL_TS=()

while IFS='|' read -r TS_NAME TOTAL_MB USED_MB FREE_MB USED_PCT; do
    [ -z "$TS_NAME" ] && continue
    printf "  %-20s | %-12s | %-12s | %-12s | %-8s\n" "$TS_NAME" "$TOTAL_MB" "$USED_MB" "$FREE_MB" "${USED_PCT}%"
    
    IS_CRITICAL=$(echo "$USED_PCT >= 90.0" | bc -l 2>/dev/null)
    if [ "$IS_CRITICAL" -eq 1 ]; then
        CRITICAL_TS+=("$TS_NAME")
    fi
done <<< "$SQL_OUTPUT"

# 3. 고갈 임박 테이블스페이스에 대한 세부 데이터파일 진단
echo -e "\n[2] 고갈 임박 테이블스페이스(90% 이상) 데이터파일 세부 분석:"
if [ ${#CRITICAL_TS[@]} -eq 0 ]; then
    echo "  [정상] 사용률 90%를 초과하는 위험 테이블스페이스가 없습니다."
else
    for TS in "${CRITICAL_TS[@]}"; do
        echo "  [경고] 테이블스페이스 '${TS}' 정밀 진단:"
        
        DATAFILE_INFO=$(sqlplus -s / as sysdba << EOF
SET FEEDBACK OFF HEADING OFF ECHO OFF VERIFY OFF LINESIZE 300
SELECT 
    file_name || '|' ||
    ROUND(bytes/1024/1024) || '|' ||
    autoextensible || '|' ||
    ROUND(maxbytes/1024/1024)
FROM dba_data_files
WHERE tablespace_name = '${TS}';
EXIT;
EOF
)
        while IFS='|' read -r F_NAME F_SIZE F_AUTO F_MAX; do
            [ -z "$F_NAME" ] && continue
            echo "    - 파일: $F_NAME"
            echo "      현재 크기: ${F_SIZE}MB | 자동확장: ${F_AUTO} | 최대 한도: ${F_MAX}MB"
            if [ "$F_AUTO" == "NO" ]; then
                echo "      [!] AUTOEXTEND가 비활성화되어 있습니다. 추가 할당이 불가능합니다."
            elif [ "$F_SIZE" -ge "$F_MAX" ] && [ "$F_MAX" -gt 0 ]; then
                echo "      [!] 파일이 설정된 최대 한도(MAXBYTES)에 이미 도달했습니다."
            fi
        done <<< "$DATAFILE_INFO"
    done
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

`ORA-01653: unable to extend table <SCHEMA>.<TABLE> by <NUM> in tablespace <NAME>` 에러는 오라클 데이터베이스가 테이블에 새로운 행(Row)을 삽입하거나 인덱스를 갱신하는 과정에서 다음 익스텐트(Next Extent)를 할당하려고 시도했으나, **해당 테이블스페이스에 연속된 여유 블록 공간이 전혀 남아있지 않을 때** 발생합니다.

### 1. 주요 발생 원인

1. **테이블스페이스 여유 공간 고갈**:
   * 테이블스페이스에 할당된 데이터파일의 용량이 가득 찼고 여유 공간이 부족한 경우.
2. **`AUTOEXTEND` 비활성화 (OFF 상태)**:
   * 데이터파일 생성 시 자동 확장 옵션을 주지 않아 파일 크기가 초기 설정 크기에 고정되어 있는 경우.
3. **데이터파일 최대 크기(MAXBYTES) 도달**:
   * `AUTOEXTEND ON` 상태라 하더라도 `MAXSIZE`를 명시했거나, 오라클의 Smallfile Tablespace 한계치(8KB 블록 기준 최대 32GB)에 도달하여 물리적으로 더 이상 파일이 커질 수 없는 경우.
4. **OS 파일시스템/디스크 용량 100% 고갈**:
   * 오라클 내부적으로는 `AUTOEXTEND`가 켜져 있어도 데이터파일이 저장된 리눅스 마운트 포인트(`/data` 등)에 디스크 여유 공간이 0바이트여서 OS 수준에서 쓰기 할당이 실패하는 경우.

### 2. 긴급 해결 방법

문제가 발생한 테이블스페이스를 식별한 후 아래 3가지 방법 중 상황에 맞게 적용합니다.

#### 방법 1: 신규 데이터파일 추가 (가장 안전하고 권장되는 방법)
기존 데이터파일이 Smallfile 한계(32GB)에 도달했거나 여유 공간을 안전하게 확보할 때 사용합니다.

```sql
-- 10GB 크기로 생성 후 100MB씩 최대 30GB까지 자동 확장되도록 추가
ALTER TABLESPACE USERS 
ADD DATAFILE '/u01/app/oracle/oradata/orcl/users02.dbf' 
SIZE 10G AUTOEXTEND ON NEXT 100M MAXSIZE 30G;

-- ASM 환경인 경우 예시
ALTER TABLESPACE USERS 
ADD DATAFILE '+DATA' 
SIZE 10G AUTOEXTEND ON NEXT 100M MAXSIZE 30G;
```

#### 방법 2: 기존 데이터파일 크기 수동 확장 (RESIZE)
기존 데이터파일이 32GB 미만이고 즉시 공간을 늘려야 할 때 사용합니다.

```sql
-- 기존 파일(예: users01.dbf)을 즉시 20GB로 확장
ALTER DATABASE DATAFILE '/u01/app/oracle/oradata/orcl/users01.dbf' RESIZE 20G;
```

#### 방법 3: 기존 데이터파일의 AUTOEXTEND 활성화
자동 확장이 꺼져 있거나 `MAXSIZE`가 너무 작게 묶여 있을 때 변경합니다.

```sql
ALTER DATABASE DATAFILE '/u01/app/oracle/oradata/orcl/users01.dbf' 
AUTOEXTEND ON NEXT 100M MAXSIZE 30G;
```

&nbsp;
&nbsp;

## 주의사항

1. **Smallfile Tablespace의 32GB 단일 파일 한계**:
   * 오라클 기본 설정인 Smallfile 테이블스페이스는 데이터파일 하나당 최대 블록 수가 $2^{22}-1$ (4,194,303)개로 고정되어 있습니다. 일반적인 8KB 블록 사이즈 환경에서는 **데이터파일 1개당 최대 크기가 약 32GB (32,767MB)**입니다. 따라서 파일이 이미 31.9GB 수준이라면 RESIZE나 AUTOEXTEND로 늘릴 수 없으며, 반드시 **새로운 데이터파일을 `ADD DATAFILE`로 추가**해야 합니다.

2. **OS 디스크 여유 공간 확인 필수**:
   * 오라클 쿼리로 `AUTOEXTEND ON MAXSIZE UNLIMITED`를 지정하더라도 호스트 OS의 볼륨(`df -h`)이 가득 차면 결국 파일 확장이 실패하면서 인스턴스 행(Hang) 또는 추가적인 입출력 에러(`ORA-01110`, `ORA-27072`)를 유발합니다. 반드시 파일시스템 디스크 잔여량을 먼저 확인해야 합니다.

3. **인덱스 파편화 및 불필요 데이터 세그먼트 정리**:
   * 무조건 데이터파일만 늘리기 전에 대량의 DELETE 작업 후 방치된 대형 테이블의 High Water Mark(HWM)를 정리하거나(`ALTER TABLE ... SHRINK SPACE;`), 사용하지 않는 임시 테이블 및 휴지통(`PURGE RECYCLEBIN;`)을 비워 숨은 여유 공간을 회수할 수 있는지 점검하는 것이 좋습니다.