---
layout: article
title: 시스템 관리_38 MySQL 및 MariaDB Error 1040 Too many connections 커넥션 초과 오류 원인 분석 및 긴급 해결 가이드
tags: [Linux, MySQL, MariaDB, Database, Error-1040, Too-many-connections, max_connections, wait_timeout, Connection-Pool, DBA, Troubleshooting]
keys: 261020-linux-db-infra-038
---

- 출처 / 참고: MySQL 8.0 Reference Manual (Server System Variables - max_connections), MariaDB Knowledge Base (Handling Too Many Connections)

> 명령어: `mysql`, `mysqladmin`, `ss`, `netstat`, `ps`, `systemctl`  
> 키워드: Error 1040, Too many connections, max_connections, max_user_connections, wait_timeout, Sleep connections, Connection Pool, CONNECTION_ADMIN  
> 사용처: 웹 서비스 트래픽 폭증 또는 커넥션 누수로 인한 DB 신규 접속 차단 장애 긴급 복구 및 파라미터 최적화

---

> 실행예제

애플리케이션 또는 터미널에서 접속 시 `ERROR 1040 (HY000): Too many connections` 오류가 발생했을 때, OS 수준의 소켓 연결 상태와 MySQL 내부의 활성 커넥션 수치, 그리고 관리자용 예약 포트 접속 여부를 확인합니다.

```bash
# 1. 클라이언트 관점: mysql 접속 시 Error 1040 발생 확인
$ mysql -u appuser -p -h 127.0.0.1
# Enter password:
# ERROR 1040 (HY000): Too many connections

# 2. OS 관점: 3306 포트에 연결된 ESTABLISHED 상태의 클라이언트 커넥션 수 카운트
$ ss -tan state established '( sport = :3306 )' | wc -l
# 152
# -> 현재 DB 포트에 맺어져 있는 활성 TCP 세션 수 확인

# 3. 관리자 전용 계정으로 로컬 소켓 또는 관리 포트를 통한 긴급 접속 시도
# MySQL은 일반 사용자가 max_connections에 도달해도 CONNECTION_ADMIN(SUPER) 권한을 가진 계정을 위해 1개의 추가 연결을 보장함
$ mysql -u root -p -S /var/run/mysqld/mysqld.sock

# 4. MySQL 내부 현재 커넥션 설정치 및 상태 통계 확인
mysql> SHOW VARIABLES LIKE 'max_connections';
+-----------------+-------+
| Variable_name   | Value |
+-----------------+-------+
| max_connections | 151   |
+-----------------+-------+

mysql> SHOW GLOBAL STATUS LIKE 'Threads_connected';
+-------------------+-------+
| Variable_name     | Value |
+-------------------+-------+
| Threads_connected | 151   |
+-------------------+-------+

# 5. 장시간 Sleep 상태로 커넥션을 점유하고 있는 좀비 세션 식별
mysql> SELECT id, user, host, db, command, time, state 
       FROM information_schema.processlist 
       WHERE command = 'Sleep' AND time > 60 
       ORDER BY time DESC LIMIT 10;
```

&nbsp;
&nbsp;

## 스크립트

현재 실행 중인 MySQL 또는 MariaDB의 `max_connections` 설정값 대비 실제 연결 점유율을 실시간 계산하고, 장시간 방치된 `Sleep` 세션을 탐색하여 임계치 초과 여부와 긴급 증설 쿼리를 제시하는 진단 쉘 스크립트입니다.

```bash
#!/bin/bash
# check_mysql_connections.sh - Diagnose MySQL/MariaDB Error 1040 and connection pool state

MYSQL_USER=${1:-"root"}
MYSQL_PASS=${2:-""}
SOCKET_PATH=${3:-"/var/run/mysqld/mysqld.sock"}

echo "=========================================="
echo " [MySQL/MariaDB 커넥션 고갈 진단 (Error 1040)]"
echo "=========================================="

# MySQL 실행 확인
if ! pgrep -x "mysqld" &>/dev/null && ! pgrep -x "mariadbd" &>/dev/null; then
    echo "  [오류] mysqld 또는 mariadbd 데몬이 실행 중이지 않습니다."
    exit 1
fi

MYSQL_CMD="mysql -u$MYSQL_USER"
[ -n "$MYSQL_PASS" ] && MYSQL_CMD="$MYSQL_CMD -p$MYSQL_PASS"
[ -S "$SOCKET_PATH" ] && MYSQL_CMD="$MYSQL_CMD -S $SOCKET_PATH"

# 1. 커넥션 변수 및 상태 조회
CONN_DATA=$($MYSQL_CMD -N -B -e "
SELECT 
    (SELECT variable_value FROM performance_schema.global_variables WHERE variable_name = 'max_connections'),
    (SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Threads_connected'),
    (SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Max_used_connections'),
    (SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Connection_errors_max_connections');
" 2>/dev/null)

if [ -z "$CONN_DATA" ]; then
    echo "  [주의] performance_schema 조회가 실패하여 information_schema/SHOW 명령어로 재시도합니다."
    MAX_CONN=$($MYSQL_CMD -N -B -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk '{print $2}')
    CURR_CONN=$($MYSQL_CMD -N -B -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk '{print $2}')
    PEAK_CONN=$($MYSQL_CMD -N -B -e "SHOW STATUS LIKE 'Max_used_connections';" 2>/dev/null | awk '{print $2}')
    ERR_CONN="N/A"
else
    MAX_CONN=$(echo "$CONN_DATA" | awk '{print $1}')
    CURR_CONN=$(echo "$CONN_DATA" | awk '{print $2}')
    PEAK_CONN=$(echo "$CONN_DATA" | awk '{print $3}')
    ERR_CONN=$(echo "$CONN_DATA" | awk '{print $4}')
fi

if [ -z "$MAX_CONN" ]; then
    echo "  [오류] MySQL에 접속할 수 없습니다. 비밀번호 또는 소켓 경로를 확인하세요."
    exit 1
fi

echo -e "\n[1] 커넥션 수치 분석:"
echo "  - 최대 허용 커넥션 (max_connections) : ${MAX_CONN}"
echo "  - 현재 활성 커넥션 (Threads_connected) : ${CURR_CONN}"
echo "  - 가동 중 최대 피크치 (Max_used_connections): ${PEAK_CONN}"
echo "  - 1040 에러 발생 누적 횟수            : ${ERR_CONN}"

USAGE_PCT=$(awk "BEGIN {printf \"%.2f\", ($CURR_CONN / $MAX_CONN) * 100}")
echo "  - 현재 커넥션 점유율                 : ${USAGE_PCT}%"

if [ "$CURR_CONN" -ge "$MAX_CONN" ]; then
    echo "  [치명적 위험] 커넥션이 한계에 도달했습니다! 일반 사용자의 모든 신규 접속이 거부됩니다."
elif [ $(echo "$USAGE_PCT > 85.0" | bc -l) -eq 1 ]; then
    echo "  [경고] 커넥션 점유율이 85%를 초과하여 임계치에 도달했습니다."
else
    echo "  [정상] 커넥션 풀 여유 공간이 확보되어 있습니다."
fi

# 2. Sleep 상태의 유휴 세션 분석
echo -e "\n[2] 유휴(Sleep) 방치 커넥션 현황:"
SLEEP_COUNT=$($MYSQL_CMD -N -B -e "
SELECT count(*) FROM information_schema.processlist WHERE command = 'Sleep';
" 2>/dev/null)
echo "  - 총 Sleep 상태 커넥션 수: ${SLEEP_COUNT}개"

LONG_SLEEP=$($MYSQL_CMD -N -B -e "
SELECT count(*) FROM information_schema.processlist WHERE command = 'Sleep' AND time > 60;
" 2>/dev/null)
echo "  - 60초 이상 방치된 Sleep 커넥션 수: ${LONG_SLEEP}개"

# 3. 호스트별 커넥션 점유 상위 5개 추출
echo -e "\n[3] 클라이언트 호스트(IP)별 커넥션 점유 순위 Top 5:"
$MYSQL_CMD -e "
SELECT SUBSTRING_INDEX(host, ':', 1) AS client_ip, count(*) AS connection_count 
FROM information_schema.processlist 
GROUP BY client_ip 
ORDER BY connection_count DESC 
LIMIT 5;
" 2>/dev/null | sed 's/^/  /'

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

`ERROR 1040 (HY000): Too many connections`는 MySQL 또는 MariaDB 인스턴스가 동시에 허용하도록 설정된 커넥션 수(`max_connections`) 한도에 도달하여, **신규 클라이언트 연결 요청을 즉시 거절(Reject)할 때** 발생하는 데이터베이스 가용성 장애입니다.

### 1. 주요 발생 원인

1. **`max_connections` 기본값 방치 (기본값: 151)**:
   * MySQL 설치 시 기본값은 151로 설정되어 있습니다. 여러 대의 웹/WAS 서버(Spring Boot, Node.js, PHP 등)가 각각 커넥션 풀을 생성하면 손쉽게 151개를 초과하게 됩니다.
2. **과도하게 긴 `wait_timeout` 설정과 유휴(Sleep) 세션 누적**:
   * 기본 `wait_timeout`과 `interactive_timeout`은 28800초(8시간)입니다. 웹 애플리케이션에서 쿼리 완료 후 연결을 풀에 반환하지 않거나 소켓을 제대로 닫지 않으면 프로세스 목록에 `Sleep` 상태로 수 시간 동안 커넥션 슬롯을 차지하여 슬롯이 고갈됩니다.
3. **슬로우 쿼리(Slow Query) 폭증에 따른 커넥션 적체**:
   * 특정 테이블에 락(Lock)이 걸리거나 인덱스가 없는 무거운 쿼리가 실행되어 쿼리 수행 시간이 늘어나면, 요청을 끝내지 못한 워커 스레드가 커넥션을 계속 붙잡고 있게 되어 신규 커넥션이 폭발적으로 늘어납니다.

### 2. 긴급 복구 및 단계별 해결 방법

#### 1) 긴급 조치: root 계정 예약 접속을 통한 max_connections 즉시 증설
MySQL은 `max_connections`에 도달해도 `CONNECTION_ADMIN`(또는 `SUPER`) 권한을 가진 사용자 1명을 위해 1개의 추가 접속 여유분(`max_connections + 1`)을 항상 남겨둡니다. 로컬 소켓을 통해 root로 접속한 후 재기동 없이 즉시 한도를 늘립니다.

```sql
-- 현재 실행 중인 서버에 즉각 적용 (재기동 불필요)
SET GLOBAL max_connections = 1000;

-- 장시간 방치된 Sleep 연결 정리를 위해 타임아웃 단축 (예: 60초)
SET GLOBAL wait_timeout = 60;
SET GLOBAL interactive_timeout = 60;
```

#### 2) 장시간 Sleep 커넥션 일괄 강제 종료 (Kill)
이미 가득 찬 Sleep 세션들을 빠르게 회수하여 가용 슬롯을 확보합니다.

```sql
-- 120초 이상 Sleep 상태인 세션을 강제 종료하는 구문 생성 후 실행
SELECT CONCAT('KILL ', id, ';') 
FROM information_schema.processlist 
WHERE command = 'Sleep' AND time > 120;
```

#### 3) 설정 파일 영구 반영 (`my.cnf` 또는 `mysqld.cnf`)
서버가 재부팅되어도 증설된 값이 유지되도록 설정 파일을 수정합니다.

```ini
# /etc/mysql/mysql.conf.d/mysqld.cnf (Ubuntu/Debian)
# 또는 /etc/my.cnf (RHEL/Rocky/CentOS)

[mysqld]
max_connections = 1000
max_connect_errors = 10000

# 유휴 커넥션 타임아웃을 8시간(28800)에서 10분(600초)으로 현실화
wait_timeout = 600
interactive_timeout = 600

# 특정 단일 계정이 전체 커넥션을 독점하는 현상 방지
max_user_connections = 800
```

&nbsp;
&nbsp;

## 주의사항

1. **`max_connections` 무분별한 과다 증설 시 OOM(Out Of Memory) 위험**:
   * MySQL은 커넥션 하나가 연결될 때마다 스레드별 버퍼(`sort_buffer_size`, `read_buffer_size`, `join_buffer_size` 등)를 추가로 메모리에 할당합니다. 호스트 RAM 용량을 고려하지 않고 무작정 5,000~10,000개로 올리면 동시 접속 폭증 시 리눅스 커널의 OOM Killer가 `mysqld` 프로세스를 강제 종료(`kill -9`)시키는 참사가 발생할 수 있습니다.

2. **OS 시스템 파일 디스크립터(open_files_limit) 동기화 필수**:
   * MySQL의 `max_connections`를 늘릴 때는 반드시 `open_files_limit` 설정도 함께 늘려주어야 합니다. 리눅스 systemd 유닛 파일(`/etc/systemd/system/mysql.service.d/override.conf`)에서 `LimitNOFILE=65535` 수준으로 상향하지 않으면 MySQL이 OS 파일 디스크립터 한도에 막혀 설정한 커넥션 수를 다 열지 못합니다.

3. **WAS 커넥션 풀(HikariCP, DBCP 등) 총합 관리**:
   * DB의 `max_connections`만 올리는 것은 미봉책입니다. 전체 WAS 인스턴스 수 $\times$ WAS당 최대 풀 크기(`maximumPoolSize`)의 합산이 DB의 `max_connections`를 넘지 않도록 애플리케이션 단의 풀 사이즈를 엄격히 제한해야 합니다.