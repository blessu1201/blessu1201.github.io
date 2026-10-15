---
layout: article
title: 시스템 관리_33 오라클 ORA-12541 TNS no listener 연결 실패 오류 원인 분석 및 완벽 복구 가이드
tags: [Linux, Oracle, Database, ORA-12541, TNS, Listener, lsnrctl, tnsnames.ora, listener.ora, Port-1521, DBA, Troubleshooting]
keys: 261015-linux-db-infra-033
---

- 출처 / 참고: Oracle Database Net Services Reference (The listener.ora File, The tnsnames.ora File), Oracle Database Net Services Administrator's Guide (Troubleshooting Oracle Net Services)

> 명령어: `lsnrctl`, `tnsping`, `ss`, `netstat`, `curl`, `iptables`, `firewall-cmd`  
> 키워드: ORA-12541, TNS:no listener, lsnrctl status, listener.ora, tnsnames.ora, 1521 포트, Connection refused, 방화벽  
> 사용처: 원격 애플리케이션 및 클라이언트 툴(DBeaver, SQL Developer, Orange)에서 오라클 DB 접속 불가 장애 진단 및 리스너 복구

---

> 실행예제

클라이언트(또는 애플리케이션 서버)에서 데이터베이스 연결 시 `ORA-12541: TNS:no listener` 오류가 발생했을 때 클라이언트 관점의 연결 테스트와 DB 서버 관점의 리스너 구동 상태 및 1521 포트 개방 여부를 점검합니다.

```bash
# 1. 클라이언트 관점: tnsping 도구로 TNS 별칭 및 대상 리스너 도달 가능 여부 테스트
$ tnsping orcl
# TNS Ping Utility for Linux: Version 19.0.0.0.0 - Production on 15-OCT-2026 10:15:30
# Used parameter files:
# /u01/app/oracle/product/19.0.0/dbhome_1/network/admin/sqlnet.ora
# Used TNSNAMES.ORA entry to resolve name:
# (DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.1.100)(PORT = 1521)) (CONNECT_DATA = (SERVER = DEDICATED) (SERVICE_NAME = orcl)))
# TNS-12541: TNS:no listener

# 2. 클라이언트 관점: IP와 포트(1521) 직통 TCP 연결 가능 여부 확인 (Connection refused 여부)
$ nc -zv -w 3 192.168.1.100 1521
# nc: connect to 192.168.1.100 port 1521 (tcp) failed: Connection refused
# 또는 curl을 이용한 포트 오픈 검사:
$ curl -v telnet://192.168.1.100:1521

# 3. DB 서버 관점: 오라클 리스너 데몬의 실행 상태 점검
$ lsnrctl status
# Connecting to (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=dbserver)(PORT=1521)))
# TNS-12541: TNS:no listener
#  TNS-12560: TNS:protocol adapter error
#   TNS-00511: No listener
#    Linux Error: 111: Connection refused
# -> 리스너 프로세스가 다운되었거나 기동되지 않은 상태 확인

# 4. DB 서버 관점: 1521 포트를 리스닝 중인 프로세스 점검
$ sudo ss -tulpn | grep :1521
# 아무것도 출력되지 않는다면 리스너가 실제로 꺼져 있음을 의미

# 5. DB 서버 관점: 방화벽 정책에서 1521 포트 차단 여부 점검
$ sudo firewall-cmd --list-ports | grep 1521
$ sudo iptables -L INPUT -v -n | grep 1521
```

&nbsp;
&nbsp;

## 스크립트

오라클 DB 서버 로컬에서 실행하여 `listener.ora` 설정의 유효성(호스트명 매핑 등)을 확인하고, 리스너 프로세스 활성 상태 및 1521 포트 바인딩 여부를 단계별로 진단한 후 필요시 리스너 시작을 유도하는 쉘 스크립트입니다.

```bash
#!/bin/bash
# diagnose_oracle_listener.sh - Diagnose ORA-12541 TNS:no listener and Oracle Net Listener status

export ORACLE_SID=${ORACLE_SID:-"orcl"}
export ORAENV_ASK=NO
[ -f /usr/local/bin/oraenv ] && . /usr/local/bin/oraenv >/dev/null 2>&1

echo "=========================================="
echo " [오라클 리스너 및 ORA-12541 진단]"
echo " ORACLE_HOME: ${ORACLE_HOME:-"미설정"}"
echo "=========================================="

# 1. lsnrctl 명령어 존재 여부 점검
if ! command -v lsnrctl &>/dev/null; then
    echo "  [오류] lsnrctl 명령어를 찾을 수 없습니다. 오라클 환경변수(PATH)를 점검하세요."
    exit 1
fi

# 2. 리스너 프로세스(tnslsnr) OS 실행 여부 확인
echo -e "\n[1] OS 레벨 리스너 프로세스 점검:"
LSNR_PID=$(pgrep -f "tnslsnr" | head -n 1)

if [ -z "$LSNR_PID" ]; then
    echo "  [경고] tnslsnr 프로세스가 실행되어 있지 않습니다."
    echo "  -> 리스너 다운이 ORA-12541 오류의 직접 원인입니다."
else
    echo "  [정상] tnslsnr 프로세스 감지 (PID: ${LSNR_PID})"
fi

# 3. 1521 포트 리스닝 상태 확인
echo -e "\n[2] TCP 1521 포트 바인딩 점검:"
PORT_INFO=$(ss -tulpn | grep -E ':1521\s')

if [ -z "$PORT_INFO" ]; then
    echo "  [오류] 1521 포트가 LISTEN 상태가 아닙니다."
else
    echo "  [정상] 1521 포트 수신 대기 중:"
    echo "  $PORT_INFO"
fi

# 4. listener.ora 파일 구성 및 호스트명 점검
ADMIN_DIR="${ORACLE_HOME}/network/admin"
LISTENER_ORA="${ADMIN_DIR}/listener.ora"
echo -e "\n[3] listener.ora 설정 점검 (${LISTENER_ORA}):"

if [ -f "$LISTENER_ORA" ]; then
    grep -vE "^#|^$" "$LISTENER_ORA" | sed 's/^/    /'
    
    # 호스트명 바인딩 불일치 검사
    CONFIG_HOST=$(grep -i "HOST" "$LISTENER_ORA" | grep -oE "HOST\s*=\s*[^)]+" | awk -F'=' '{print $2}' | tr -d ' ')
    CURRENT_HOSTNAME=$(hostname)
    echo "  - listener.ora 설정 호스트: ${CONFIG_HOST}"
    echo "  - 실제 시스템 호스트명    : ${CURRENT_HOSTNAME}"
    
    if [ "$CONFIG_HOST" != "0.0.0.0" ] && [ "$CONFIG_HOST" != "$CURRENT_HOSTNAME" ] && [ "$CONFIG_HOST" != "localhost" ]; then
        echo "  [주의] 호스트명이 불일치하여 리스너 기동 실패 가능성이 있습니다. /etc/hosts 파일을 확인하세요."
    fi
else
    echo "  [안내] listener.ora 파일이 없습니다. 기본 파라미터로 구동 여부를 확인합니다."
fi

# 5. lsnrctl status 명령 실행 결과 점검
echo -e "\n[4] lsnrctl status 실행 테스트:"
STATUS_RES=$(lsnrctl status 2>&1)
if echo "$STATUS_RES" | grep -q "TNS-12541"; then
    echo "  [실패] 리스너가 중지 상태입니다 (TNS-12541 감지)."
    echo "  -> 복구 조치: 'lsnrctl start' 명령을 실행하여 리스너를 기동하십시오."
elif echo "$STATUS_RES" | grep -q "STATUS of the LISTENER"; then
    echo "  [성공] 리스너가 정상 작동 중입니다."
    # 등록된 서비스 개수 추출
    SVC_COUNT=$(echo "$STATUS_RES" | grep -c "Service.*has.*instance")
    echo "  - 서비스에 등록된 인스턴스 수: ${SVC_COUNT}개"
else
    echo "  [기타 응답]:"
    echo "$STATUS_RES" | head -n 10 | sed 's/^/    /'
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

`ORA-12541: TNS:no listener`는 오라클 클라이언트가 데이터베이스 서버에 연결을 맺기 위해 대상 IP와 포트(통상 TCP 1521)로 TCP 연결(`SYN`)을 시도했으나, **목적지 서버의 해당 포트에서 연결 요청을 수신하고 대기(`LISTEN`) 중인 리스너 프로세스(`tnslsnr`)가 없을 때** 반환되는 네트워크 계층 오류입니다.

### 1. `ORA-12541` vs `ORA-12514` 차이점

오라클 접속 문제에서 가장 자주 혼동되는 두 에러의 차이점을 명확히 알아야 합니다.

| 에러 코드 | 원인 및 상태 | 비유 |
| :--- | :--- | :--- |
| **`ORA-12541: TNS:no listener`** | 대상 IP:PORT에 **리스너 프로세스 자체가 켜져 있지 않거나(Connection refused)** 방화벽에 의해 포트 접근이 차단됨. | 건물 경비원(리스너)이 **퇴근하여 부재중**이거나 정문 문이 잠겨 있어 진입조차 못 함 |
| **`ORA-12514: TNS:listener does not currently know of service`** | 리스너는 1521번으로 잘 동작 중이나, 클라이언트가 요청한 **서비스명(SERVICE_NAME)이 리스너에 등록되어 있지 않음**. | 경비원은 만나서 대화했으나, 찾으려는 **입주자(인스턴스)가 명단에 없음** |

### 2. 주요 발생 원인

1. **오라클 리스너 데몬의 다운 또는 미기동 (가장 흔함)**:
   * DB 서버가 재부팅되었으나 `lsnrctl start`를 실행하지 않았거나 리스너 프로세스가 비정상 종료(Crash)된 경우.
2. **`tnsnames.ora`의 IP 및 포트 오설정**:
   * 클라이언트의 `tnsnames.ora` 파일에 기재된 `HOST` IP 또는 `PORT` 번호가 실제 DB 서버와 다르게 잘못 적혀 있는 경우.
3. **`listener.ora`와 `/etc/hosts` 호스트명 불일치**:
   * `listener.ora` 파일에 `(HOST = dbserver1)`로 적혀 있으나, 서버 IP가 바뀌었거나 `/etc/hosts`에 해당 호스트명에 대한 루프백/IP 매핑이 누락되어 리스너가 바인딩에 실패한 경우.
4. **OS 방화벽 또는 클라우드 보안 그룹(Security Group) 차단**:
   * 리스너는 1521 포트로 열려 있으나, 리눅스 OS 방화벽(`firewalld`, `iptables`) 또는 AWS/GCP의 보안 그룹에서 인바운드 1521 포트가 열려 있지 않아 클라이언트 패킷이 거부되는 경우 (`REJECT` 정책 시 refused 유발).

### 3. 단계별 해결 방법

#### 1) 리스너 기동 및 상태 확인
DB 서버의 `oracle` 계정으로 로그인하여 리스너를 시작합니다.

```bash
# 리스너 시작
lsnrctl start

# 리스너 상태 확인
lsnrctl status
```
* 서비스가 정상적으로 뜨면 `The command completed successfully` 메시지와 함께 1521 포트 리스닝 상태가 표시됩니다.

#### 2) `listener.ora` 파일 호스트명 점검 (`$ORACLE_HOME/network/admin/listener.ora`)
특정 호스트명 바인딩 실패를 방지하기 위해 IP 주소를 직접 지정하거나 `0.0.0.0`으로 바인딩합니다.

```ini
# $ORACLE_HOME/network/admin/listener.ora
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1521))
    )
  )
```
수정 후 리스너를 재시작합니다:
```bash
lsnrctl reload
# 또는
lsnrctl stop && lsnrctl start
```

#### 3) 방화벽 1521 포트 허용
외부 클라이언트가 DB 서버의 1521 포트에 접근할 수 있도록 방화벽을 엽니다.

* **firewalld (RHEL/Rocky/CentOS)**:
  ```bash
  sudo firewall-cmd --permanent --add-port=1521/tcp
  sudo firewall-cmd --reload
  ```
* **UFW (Ubuntu)**:
  ```bash
  sudo ufw allow 1521/tcp
```

&nbsp;
&nbsp;

## 주의사항

1. **DB 인스턴스 등록 대기 시간 (Dynamic Registration)**:
   * 리스너를 방금 켰다면(`lsnrctl start`), DB 인스턴스의 백그라운드 프로세스(PMON 또는 LREG)가 리스너에 DB 서비스를 등록(동적 서비스 등록)하는 데 보통 1분에서 최대 3분 정도의 시간이 소요됩니다. 리스너를 켠 직후에는 잠시 `ORA-12514`가 뜰 수 있으므로, 즉시 등록하려면 `sqlplus / as sysdba` 접속 후 `ALTER SYSTEM REGISTER;` 명령을 내려주어야 합니다.

2. **클라우드 환경(AWS EC2 등)의 공인 IP 바인딩 금지**:
   * AWS EC2 인스턴스의 `listener.ora`에 탄력적 공인 IP(Elastic IP)를 직접 기입하면 리스너 구동 시 `TNS-12545: Connect failed because target host or object does not exist` 에러가 발생합니다. 클라우드 환경에서는 항상 **사설 IP(Private IP)**, **내부 호스트명**, 또는 `0.0.0.0`으로 바인딩해야 합니다.

3. **`tnsnames.ora` 캐시 및 클라이언트 TNS 설정 주의**:
   * 서버 측 리스너가 정상 구동 중임에도 클라이언트 PC에서 계속 ORA-12541이 발생한다면, 클라이언트 PC의 `tnsnames.ora` 파일이 엉뚱한 구형 IP를 바라보고 있거나, 로컬 `hosts` 파일에 잘못된 IP 매핑이 캐싱되어 있을 가능성이 높으므로 클라이언트 측 네트워크 경로를 확인해야 합니다.