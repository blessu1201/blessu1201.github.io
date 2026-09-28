---
layout: article
title: 시스템 관리_11 리눅스 포트 접속 오류 완벽 정리 "Connection refused" vs "Connection timed out" 원인 및 해결 방법
tags: [Linux, Network, Troubleshooting, iptables, Firewall, ss, curl, netstat]
keys: 260923-linux-network-011
---

- 출처 / 참고: Linux man-pages (socket(7), tcp(7)), RFC 793 (Transmission Control Protocol)

> 명령어: `nc`, `curl`, `ss`, `netstat`, `iptables`, `nft`, `systemctl`, `journalctl`  
> 키워드: Connection refused, Connection timed out, TCP RST, SYN 패킷 드롭, 방화벽, 포트 리스닝  
> 사용처: 서버 간 통신 실패 진단, 웹 서비스(80/443) 및 DB 포트(3306/5432 등) 접속 장애 분석 및 복구  

---

> 실행예제

두 오류는 네트워크 계층에서 문제를 일으키는 원인 자체가 완전히 다릅니다. 현재 대상 포트와의 연결 상태 및 원인을 파악하기 위해 아래 명령어를 차례로 실행합니다.

```bash
# 1. 클라이언트 관점: 특정 대상 서버 및 포트 접속 테스트
# Connection refused 예시 (즉각적인 거부 응답)
$ curl -v --connect-timeout 5 http://192.168.1.100:8080
*   Trying 192.168.1.100:8080...
* connect to 192.168.1.100 port 8080 failed: Connection refused
* Failed to connect to 192.168.1.100 port 8080: Connection refused

# Connection timed out 예시 (응답 없이 대기하다 타임아웃 발생)
$ nc -zv -w 5 192.168.1.100 9000
nc: connect to 192.168.1.100 port 9000 (tcp) timed out: Operation now in progress

# 2. 서버 관점: 해당 포트가 정상적으로 Listen 상태인지 확인
# 아무것도 출력되지 않거나 127.0.0.1에만 바인딩되어 있는지 확인
$ sudo ss -tulpn | grep -E ':8080|:9000'
tcp   LISTEN 0      128        127.0.0.1:8080       0.0.0.0:*    users:(("java",pid=1234,fd=14))

# 3. 서버 관점: 방화벽(iptables/firewalld) 정책상 드롭(DROP) 또는 거부(REJECT) 룰 확인
$ sudo iptables -L INPUT -v -n --line-numbers | grep -E 'DROP|REJECT'
3    DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0
```

&nbsp;
&nbsp;

## 스크립트

서버 로컬 또는 원격지에서 포트 접속 문제를 단계별(프로세스 실행 여부, 바인딩 IP, 방화벽 차단)로 원인 분류해 주는 진단 쉘 스크립트입니다.

```bash
#!/bin/bash
# port_troubleshoot.sh - Check port listening state and firewall rules

TARGET_PORT=${1:-"80"}
echo "=========================================="
echo " [진단 시작] 대상 포트: ${TARGET_PORT}"
echo "=========================================="

# 1. 포트 Listen 상태 및 바인딩 IP 확인
echo -e "\n[1] 로컬 소켓 리스닝 상태 확인:"
LISTENING_INFO=$(ss -tulpn | grep ":${TARGET_PORT} ")

if [ -z "$LISTENING_INFO" ]; then
    echo "  [경고] 포트 ${TARGET_PORT}번을 리스닝하고 있는 프로세스가 없습니다."
    echo "  -> 원인: 서비스가 꺼져있을 확률 높음 (Connection refused 유발)"
else
    echo "  [정상] 프로세스가 바인딩되어 있습니다:"
    echo "  $LISTENING_INFO"
    
    # 127.0.0.1 바인딩 여부 검사
    if echo "$LISTENING_INFO" | grep -q "127.0.0.1:${TARGET_PORT}"; then
        echo "  [주의] 소켓이 루프백(127.0.0.1)에만 바인딩되어 있어 외부 접속 시 거부될 수 있습니다."
    fi
fi

# 2. 서비스 프로세스 상태 체크 (systemd 기반 예시)
echo -e "\n[2] 관련 실패 유닛 확인:"
FAILED_UNITS=$(systemctl --failed --type=service)
if echo "$FAILED_UNITS" | grep -q "0 loaded units listed"; then
    echo "  [정상] 비정상 종료된 systemd 서비스가 없습니다."
else
    echo "  [확인 필요] 비정상 종료된 서비스 목록:"
    echo "$FAILED_UNITS"
fi

# 3. 방화벽 차단 룰 확인 (iptables / UFW / Firewalld)
echo -e "\n[3] 방화벽 DROP / REJECT 규칙 검사:"
if command -v iptables &>/dev/null; then
    BLOCKED=$(sudo iptables -S INPUT | grep -E "(DROP|REJECT)")
    if [ -n "$BLOCKED" ]; then
        echo "  [주의] 방화벽에 DROP/REJECT 규칙이 존재합니다:"
        echo "$BLOCKED"
        echo "  -> DROP 규칙에 의해 패킷이 무시될 경우 'Connection timed out' 발생"
        echo "  -> REJECT 규칙에 의해 패킷이 거절될 경우 'Connection refused' 발생 가능"
    else
        echo "  [정상] 명시적인 DROP/REJECT 규칙이 확인되지 않았습니다."
    fi
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

두 오류는 네트워크 계층 및 TCP 3-Way Handshake 관점에서 명확한 기술적 차이가 있습니다.

### 1. `Connection refused` (연결 거부)
- **발생 원리**: 클라이언트가 `SYN` 패킷을 전송했을 때 대상 호스트에 도달은 했으나, 목적지 포트에 대해 커널이 **`RST(Reset)` 패킷**을 즉시 되돌려 보낼 때 발생합니다.
- **주요 원인**:
  1. **프로세스 미실행**: 해당 포트를 열고 수신 대기(`LISTEN`) 중인 애플리케이션/데몬이 꺼져 있거나 크래시된 경우.
  2. **잘못된 바인딩 주소**: 서비스가 외부 IP(`0.0.0.0`)가 아닌 로컬 루프백(`127.0.0.1`)에만 바인딩되어 있어 외부 네트워크의 접근을 거부하는 경우.
  3. **방화벽 `REJECT` 규칙**: 방화벽(iptables, UFW 등) 정책이 패킷을 조용히 버리는 것이 아니라 `REJECT-WITH-TCP-RESET` 또는 ICMP port-unreachable 응답을 명시적으로 반환하는 경우.
- **해결 절차**:
  - `systemctl status <서비스명>`을 통해 서비스가 살아있는지 점검.
  - 설정 파일(예: Nginx, MySQL의 `bind-address`)에서 수신 대기 주소를 `0.0.0.0`으로 변경.
  - 방화벽 설정에서 해당 포트를 명시적으로 `ACCEPT`하도록 수정.

### 2. `Connection timed out` (연결 시간 초과)
- **발생 원리**: 클라이언트가 `SYN` 패킷을 전송했으나, 아무런 응답(`SYN-ACK` 또는 `RST`)도 받지 못해 커널의 재전송 타임아웃(Timeout)이 초과될 때 발생합니다.
- **주요 원인**:
  1. **방화벽 패킷 드롭(`DROP`)**: 대상 서버의 OS 방화벽(iptables, ufw), 클라우드 보안 그룹(AWS SG, GCP 방화벽 규칙) 또는 하드웨어 방화벽이 들어오는 패킷을 응답 없이 버리는 경우.
  2. **라우팅 및 네트워크 경로 단절**: 게이트웨이 또는 중간 라우터 경로에 문제가 있어 패킷이 목적지 호스트까지 도달하지 못하는 경우.
  3. **잘못된 대상 IP / 호스트 미기동**: 대상 IP의 머신 자체가 꺼져 있거나 존재하지 않는 IP로 요청을 보낸 경우.
- **해결 절차**:
  - 클라우드 환경이라면 Security Group/방화벽 규칙에서 인바운드 허용(Inbound Rule) 여부 확인.
  - 서버 내부의 방화벽(`sudo ufw allow <port>` 또는 `firewall-cmd --add-port=<port>/tcp --permanent`) 개방.
  - `traceroute` 또는 `mtr` 명령어로 중간 경로상 끊김이 발생하는 구간 추적.

&nbsp;
&nbsp;

## 주의사항

1. **클라우드 환경(AWS, GCP, Azure 등)의 이중 방화벽**:
   - OS 내부 방화벽(`ufw`, `firewalld`)을 열었더라도 클라우드 콘솔의 Security Group / VPC 방화벽에서 포트를 차단하면 `Connection timed out`이 발생합니다. 두 계층 모두 점검해야 합니다.
2. **`DROP` vs `REJECT` 정책 차이**:
   - 보안상 외부 공격자에게 포트가 열려 있는지 탐지하지 못하게 하려면 패킷을 드롭(`DROP` - timeout 유도)하는 것이 일반적이나, 내부 서비스 연동에서는 디버깅 지연을 줄이기 위해 명시적으로 거절(`REJECT` - refused 유도)하는 방식을 쓰기도 합니다.
3. **루프백(Loopback) 바인딩 확인**:
   - 데이터베이스(MySQL, Redis 등)는 기본 설정이 보안상 `bind 127.0.0.1`로 되어 있는 경우가 많습니다. 다른 서버에서 접근해야 한다면 반드시 바인딩 주소를 확인하고 변경해야 합니다.