---
layout: article
title: 시스템 관리_19 FreeRADIUS "Access-Reject" 및 Shared Secret 불일치 오류 원인과 완벽 해결 가이드
tags: [Linux, FreeRADIUS, Network, AAA, RADIUS, Authentication, Access-Reject, radtest, clients.conf, Troubleshooting]
keys: 261001-linux-network-019
---

- 출처 / 참고: FreeRADIUS Official Documentation (radiusd(8), clients.conf(5)), RFC 2865 (Remote Authentication Dial In User Service)

> 명령어: `freeradius`, `radiusd`, `radtest`, `radclient`, `ss`, `journalctl`  
> 키워드: FreeRADIUS, Access-Reject, Shared Secret Mismatch, clients.conf, radtest, Message-Authenticator, UDP 1812  
> 사용처: 기업용 Wi-Fi(802.1X), VPN 계정 인증, 스위치/라우터 관리자 로그인 실패 장애 분석 및 복구

---

> 실행예제

FreeRADIUS 인증 오류 발생 시 가장 먼저 점검해야 할 핵심은 클라이언트(NAS)와 서버 간의 **Shared Secret(공유 비밀키)** 일치 여부, `clients.conf`의 IP 등록 상태, 그리고 인증 모듈의 디버그 출력입니다.

```bash
# 1. 로컬 radtest 명령어를 통한 기본 인증 시도
# 문법: radtest <username> <password> <radius-server-ip> <nas-port-number> <secret>
$ radtest testuser password123 127.0.0.1 0 testing123
Sent Access-Request Id 164 from 0.0.0.0:41235 to 127.0.0.1:1812 length 77
Received Access-Reject Id 164 from 127.0.0.1:1812 to 0.0.0.0:0 length 20
(0) -: Received Response to request 0 code 3 (Access-Reject)
# -> Access-Reject가 반환되거나 타임아웃 발생 여부 확인

# 2. Shared Secret 불일치 시 서버 로그 확인
$ sudo journalctl -u freeradius -n 50 --no-pager | grep -E "Ignoring request|Shared secret"
# [출력 예시]
# Ignoring request to auth address * port 1812 from unknown client 192.168.1.50 port 51234
# 또는
# ERROR: Received packet from 192.168.1.50 with invalid Message-Authenticator! (Shared secret mismatch)

# 3. RADIUS 표준 포트(인증 1812/udp, 계정 1813/udp) 수신 상태 확인
$ sudo ss -ulpn | grep -E ':1812|:1813'
UNCONN 0      0            0.0.0.0:1812      0.0.0.0:*    users:(("freeradius",pid=1420,fd=8))
UNCONN 0      0            0.0.0.0:1813      0.0.0.0:*    users:(("freeradius",pid=1420,fd=9))

# 4. 실시간 디버그 모드로 FreeRADIUS 기동 (실패 원인의 정확한 추적)
# 실행 중인 서비스를 멈추고 포그라운드 디버그 모드(-X) 실행
$ sudo systemctl stop freeradius
$ sudo freeradius -X
# (인증 패킷 수신 시 어떤 모듈에서 Reject 되었는지 상세 출력됨)
```

&nbsp;
&nbsp;

## 스크립트

FreeRADIUS 서비스 상태를 확인하고, `clients.conf`에 질의 클라이언트가 등록되어 있는지 점검하며, `radtest`를 통해 Access-Accept/Reject 여부 및 Shared Secret 검증을 자동으로 수행하는 쉘 스크립트입니다.

```bash
#!/bin/bash
# test_freeradius_auth.sh - Diagnose FreeRADIUS Access-Reject and Shared Secret errors

RADIUS_SERVER=${1:-"127.0.0.1"}
TEST_USER=${2:-"testuser"}
TEST_PASS=${3:-"password123"}
SECRET=${4:-"testing123"}
CONF_DIR="/etc/freeradius/3.0"

# 배포판별 설정 디렉터리 보정 (RHEL/CentOS는 /etc/raddb)
[ -d "/etc/raddb" ] && CONF_DIR="/etc/raddb"

echo "=========================================="
echo " [FreeRADIUS 인증 진단 시작]"
echo " 대상 서버: ${RADIUS_SERVER}"
echo " 사용자명  : ${TEST_USER}"
echo "=========================================="

# 1. FreeRADIUS 프로세스 구동 확인
echo -e "\n[1] RADIUS 서비스 상태 확인:"
if systemctl is-active --quiet freeradius || systemctl is-active --quiet radiusd; then
    echo "  [정상] FreeRADIUS 서비스가 활성화되어 동작 중입니다."
else
    echo "  [경고] FreeRADIUS 서비스가 중지되어 있습니다."
fi

# 2. UDP 1812 포트 바인딩 확인
echo -e "\n[2] 인증 포트(UDP 1812) 리스닝 점검:"
if ss -ulpn | grep -q ":1812 "; then
    echo "  [정상] UDP 1812 포트가 정상 수신 대기 중입니다."
else
    echo "  [오류] UDP 1812 포트가 열려있지 않습니다."
fi

# 3. clients.conf 내 대상 IP/대역 등록 여부 점검 (로컬 실행 시)
CLIENTS_CONF="${CONF_DIR}/clients.conf"
echo -e "\n[3] clients.conf 등록 여부 점검 (${CLIENTS_CONF}):"
if [ -f "$CLIENTS_CONF" ]; then
    MATCHED_CLIENT=$(grep -E "client.*${RADIUS_SERVER}" -A 4 "$CLIENTS_CONF" 2>/dev/null)
    if [ -n "$MATCHED_CLIENT" ]; then
        echo "  [확인] 클라이언트 매칭 블록 발견:"
        echo "$MATCHED_CLIENT" | sed 's/^/    /'
    else
        echo "  [주의] clients.conf에서 '${RADIUS_SERVER}'에 대한 명시적 정의를 찾지 못했습니다."
        echo "  -> IP 대역(CIDR)으로 정의되어 있는지 수동 확인이 필요합니다."
    fi
else
    echo "  [안내] clients.conf 파일을 찾을 수 없어 검사를 건너뜁니다."
fi

# 4. radtest를 이용한 실제 인증 테스트
echo -e "\n[4] radtest 인증 질의 테스트:"
if command -v radtest &>/dev/null; then
    AUTH_RESULT=$(radtest "$TEST_USER" "$TEST_PASS" "$RADIUS_SERVER" 0 "$SECRET" 2>&1)
    
    if echo "$AUTH_RESULT" | grep -q "Access-Accept"; then
        echo "  [성공] Access-Accept 수신! 인증 및 Shared Secret이 정상입니다."
    elif echo "$AUTH_RESULT" | grep -q "Access-Reject"; then
        echo "  [실패] Access-Reject 수신!"
        echo "  -> 원인: 패스워드 불일치, 계정 비활성화, 또는 사용자 그룹 정책 거부."
    elif echo "$AUTH_RESULT" | grep -q "radclient: no response"; then
        echo "  [실패] 서버 무응답 (타임아웃)!"
        echo "  -> 원인 1: Shared Secret 불일치로 서버가 패킷을 폐기함."
        echo "  -> 원인 2: clients.conf에 요청 IP가 등록되지 않음 (Unknown client)."
        echo "  -> 원인 3: 방화벽(UDP 1812) 차단."
    else
        echo "  [기타 응답]:"
        echo "$AUTH_RESULT" | sed 's/^/    /'
    fi
else
    echo "  [오류] radtest 명령어를 찾을 수 없습니다. (freeradius-utils 패키지 설치 필요)"
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

FreeRADIUS에서 클라이언트 인증 시 발생하는 문제는 크게 **1) 아예 응답이 없는 타임아웃**과 **2) 거절 패킷을 수신하는 `Access-Reject`**로 명확히 나뉩니다.

### 1. "무응답(Timeout)" vs "Access-Reject" 차이점

| 구분 | 주요 증상 | 실제 발생 원인 |
| :--- | :--- | :--- |
| **무응답 (No response)** | `radclient: no response from server` | • **Shared Secret(공유 비밀키) 불일치**<br>• `clients.conf`에 NAS IP 미등록 (Unknown client)<br>• UDP 1812 방화벽 차단 |
| **Access-Reject** | `Received Access-Reject Id ...` | • Shared Secret은 **일치함**<br>• ID/패스워드 불일치<br>• 사용자 속성(Auth-Type, VLAN 등) 검증 실패 |

### 2. Shared Secret 불일치 시 서버 동작 메커니즘

* RADIUS 프로토콜(RFC 2865)에서 모든 `Access-Request` 패킷은 클라이언트와 서버가 공유하는 **Shared Secret**을 이용해 `MD5 Authenticator` 또는 `Message-Authenticator` 해시값을 생성합니다.
* 만약 양측의 Shared Secret이 1글자라도 다르면:
  1. 서버는 수신된 패킷의 해시 서명 검증에 실패합니다.
  2. 악의적인 공격자의 브루트포스(Brute-Force) 및 스푸핑을 방지하기 위해 서버는 `Access-Reject`조차 보내지 않고 **패킷을 즉시 조용히 폐기(Silent Drop)**합니다.
  3. 그 결과 클라이언트는 거절 메시지도 받지 못한 채 타임아웃을 겪게 됩니다.

### 3. 주요 해결 방법

#### 1) `clients.conf` 점검 및 등록
요청을 보내는 스위치, AP, VPN 장비 또는 테스트 장비의 IP와 공유 비밀키를 정확하게 정의해야 합니다.

```nginx
# /etc/freeradius/3.0/clients.conf
client vpn_gateway {
    ipaddr = 192.168.1.50
    secret = MyStrongSharedKey2026!
    require_message_authenticator = no
    nas_type = other
}
```
* **주의**: 장비가 NAT를 거쳐 서버로 들어오는 경우, 사설 IP가 아닌 **변환된 공인 IP**를 `ipaddr`에 등록해야 합니다.

#### 2) `freeradius -X` (디버그 모드) 활용
로그 파일에 기록되지 않는 세부 거절 사유는 디버그 모드에서만 완벽히 확인 가능합니다.
* `rlm_pap: Cleartext password does not match "known good" password`: 비밀번호 오류
* `Invalid user`: 사용자 DB(파일, LDAP, MySQL)에 계정이 없음
* `Ignoring request to auth address ... from unknown client`: `clients.conf`에 IP 누락

&nbsp;
&nbsp;

## 주의사항

1. **Shared Secret에 특수문자 및 공백 사용 시 주의**:
   * 비밀키 내부에 공백이나 `#`, `"`, `\` 등의 특수문자가 포함된 경우 일부 네트워크 장비(AP, VPN 게이트웨이)나 FreeRADIUS 파서에서 이스케이프 처리가 잘못되어 불일치가 발생할 수 있습니다. 영문 대소문자와 숫자 조합을 우선 권장합니다.

2. **운영 환경에서 `-X` 모드 장시간 실행 금지**:
   * `freeradius -X`는 단일 스레드로 동작하며 콘솔 I/O 부하가 매우 큽니다. 동시 접속자가 많은 운영 환경에서 서비스용으로 띄워둘 경우 인증 지연 및 타임아웃 장애가 발생하므로 디버깅 후 즉시 `systemctl start freeradius`로 원복해야 합니다.

3. **Message-Authenticator 필수 정책 충돌**:
   * 최신 FreeRADIUS 버전 및 보안 패치에서는 `require_message_authenticator = yes`가 기본 활성화되는 추세입니다. 구형 네트워크 스위치나 레거시 클라이언트가 해당 속성을 생성하지 못하면 패킷이 드롭될 수 있으므로 호환성을 확인해야 합니다.