---
layout: article
title: 시스템 관리_62 IPsec VPN 터널 Phase 1 및 Phase 2 협상 실패와 DPD Dead Peer Detection 장애 해결 가이드
tags: [Network, VPN, IPsec, IKEv1, IKEv2, Phase1, Phase2, DPD, NAT-T, FortiGate, StrongSwan, Troubleshooting]
keys: 261114-linux-network-062
---

- 출처 / 참고: IETF RFC 7296 (Internet Key Exchange Protocol Version 2 - IKEv2), IETF RFC 3706 (A Traffic-Based Method of Detecting Dead Internet Key Exchange Peers - DPD), StrongSwan & Fortinet IPsec Troubleshooting Documentation

> 명령어: `ipsec`, `swanctl`, `diagnose vpn ike`, `tcpdump`, `nc`, `ss`  
> 키워드: IPsec VPN, Phase 1, Phase 2, IKEv1, IKEv2, Pre-Shared Key, Proposal Mismatch, DPD, NAT-T, UDP 500, UDP 4500  
> 사용처: 본사-지사 간 또는 온프레미스-클라우드(AWS/NCP) 간 IPsec VPN 터널이 연결되지 않거나 간헐적으로 끊기는 장애 원인 규명 및 복구

---

> 실행예제

IPsec VPN 터널이 다운되어 양단 사설 네트워크 간 통신이 두절되었을 때, 리눅스 게이트웨이(StrongSwan) 또는 방화벽에서 IKE 협상 단계(Phase 1 / Phase 2)의 어느 지점에서 거절되는지 패킷과 데몬 로그로 진단합니다.

```bash
# 1. 리눅스 StrongSwan 관점: 현재 활성화된 IPsec 터널(SA) 상태 및 협상 단계 확인
$ sudo ipsec statusall
# Security Associations (0 up, 1 connecting):
#   hq-to-branch[14]: CONNECTING, 203.0.113.10[%any]...198.51.100.20[%any]
#   hq-to-branch[14]: IKEv2 SPIs: 8a1b2c3d4e5f6a7b_i* 0000000000000000_r
#   hq-to-branch[14]: Tasks active: IKE_VENDOR IKE_INIT IKE_NATD IKE_CERT_PRE IKE_AUTH
# -> 응답 SPI가 0000000000000000_r 이면 상대방 게이트웨이로부터 IKE 응답 패킷 자체가 오지 않는 상태임

# 2. 시스템 로그에서 Phase 1 / Phase 2 실패 에러 코드 추출
$ sudo journalctl -u strongswan -n 40 --no-pager | grep -iE "no proposal|auth failed|timeout|dpd"
# [출력 예시 - 암호화 알고리즘 불일치]
# Nov 14 14:10:05 gw01 charon[1420]: 12[IKE] received NO_PROPOSAL_CHOSEN notify error
# -> 양쪽 게이트웨이의 암호화(AES256), 해시(SHA256), DH Group 설정이 서로 다름을 의미

# 3. 필수 VPN 통신 포트(UDP 500 IKE, UDP 4500 NAT-T) 패킷 송수신 캡처
$ sudo tcpdump -ni eth0 udp port 500 or udp port 4500 -c 10
# 14:12:01.102 IP 203.0.113.10.500 > 198.51.100.20.500: isakmp: phase 1 I ident
# 14:12:05.105 IP 203.0.113.10.500 > 198.51.100.20.500: isakmp: phase 1 I ident
# -> 나가는 패킷(>)만 있고 들어오는 응답 패킷(<)이 없다면 중간 ISP/방화벽에서 UDP 500/4500 차단 중

# 4. 방화벽(FortiGate 예시)에서 IKE 디버그 필터를 통한 실시간 실패 사유 확인
# diagnose vpn ike log-filter dst-addr4 198.51.100.20
# diagnose debug application ike -1
# diagnose debug enable
```

&nbsp;
&nbsp;

## 스크립트

리눅스 IPsec VPN 게이트웨이(StrongSwan)에서 동작하여 외부 통신 포트(UDP 500/4500) 방화벽 개방 여부, IKE Phase 1 및 Phase 2 SA(Security Association) 수립 상태, 그리고 터널 끊김 현상을 자동 분석하고 터널을 재수립해 주는 진단 쉘 스크립트입니다.

```bash
#!/bin/bash
# diagnose_ipsec_vpn.sh - Diagnose IPsec VPN Phase 1/2 negotiation and DPD status

CONN_NAME=${1:-""}
PEER_IP=${2:-""}

echo "=========================================="
echo " [IPsec VPN 터널 협상 및 상태 정밀 진단기]"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] VPN 데몬 및 네트워크 진단을 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

# 1. ipsec / strongswan 서비스 상태 확인
echo -e "\n[1] VPN 서비스 데몬 상태 점검:"
if systemctl is-active --quiet strongswan || systemctl is-active --quiet strongswan-starter || systemctl is-active --quiet ipsec; then
    echo "  [정상] IPsec 데몬 구동 중"
else
    echo "  [치명적] IPsec 서비스가 중지되어 있습니다! 시작 시도..."
    systemctl start strongswan 2>/dev/null || systemctl start ipsec 2>/dev/null
fi

# 2. 활성화된 Security Association(SA) 요약 분석
echo -e "\n[2] 현재 Phase 1 (IKE SA) 및 Phase 2 (CHILD SA) 상태:"
STATUS_OUT=$(ipsec statusall 2>/dev/null || swanctl --list-sas 2>/dev/null)

if [ -z "$STATUS_OUT" ]; then
    echo "  [오류] ipsec/swanctl 상태 정보를 가져올 수 없습니다."
    exit 1
fi

UP_COUNT=$(echo "$STATUS_OUT" | grep -c "ESTABLISHED")
INSTALLED_COUNT=$(echo "$STATUS_OUT" | grep -c "INSTALLED")

echo "  - Phase 1 (ESTABLISHED) 터널 수 : ${UP_COUNT}개"
echo "  - Phase 2 (INSTALLED) 터널 수   : ${INSTALLED_COUNT}개"

if [ "$UP_COUNT" -eq 0 ]; then
    echo "  [경고] 수립된 Phase 1 IKE 터널이 전혀 없습니다!"
elif [ "$UP_COUNT" -gt 0 ] && [ "$INSTALLED_COUNT" -eq 0 ]; then
    echo "  [주의] Phase 1은 성공했으나 Phase 2 협상에 실패했습니다!"
    echo "  -> 원인: 양단의 로컬/원격 서브넷(Proxy ID / Traffic Selector) 또는 PFS 설정이 불일치합니다."
fi

# 3. 원격 피어(Peer IP) UDP 500 / 4500 도달성 검증
if [ -n "$PEER_IP" ]; then
    echo -e "\n[3] 원격 피어 게이트웨이(${PEER_IP}) 포트 도달성 테스트:"
    if nc -zvu -w 3 "$PEER_IP" 500 >/dev/null 2>&1; then
        echo "  - UDP 500 (IKE)   : [열림/전송가능]"
    else
        echo "  - UDP 500 (IKE)   : [실패/차단]"
    fi
    if nc -zvu -w 3 "$PEER_IP" 4500 >/dev/null 2>&1; then
        echo "  - UDP 4500 (NAT-T): [열림/전송가능]"
    else
        echo "  - UDP 4500 (NAT-T): [실패/차단]"
    fi
fi

# 4. 최근 로그에서 전형적인 IPsec 에러 메시지 스캔
echo -e "\n[4] 최근 VPN 에러 패턴 분석:"
RECENT_ERRS=$(journalctl -u strongswan -u ipsec -n 100 --no-pager 2>/dev/null | grep -iE "NO_PROPOSAL_CHOSEN|AUTHENTICATION_FAILED|TS_UNACCEPTABLE|DPD" | tail -n 5)

if [ -n "$RECENT_ERRS" ]; then
    echo "$RECENT_ERRS" | sed 's/^/  /'
    echo -e "\n  [에러 코드 해석]:"
    echo "$RECENT_ERRS" | grep -q "NO_PROPOSAL_CHOSEN" && echo "  -> NO_PROPOSAL_CHOSEN: 암호화(AES), 해시(SHA), DH Group이 상대방과 다릅니다."
    echo "$RECENT_ERRS" | grep -q "AUTHENTICATION_FAILED" && echo "  -> AUTHENTICATION_FAILED: Pre-Shared Key(PSK) 오타 또는 Local/Remote ID 불일치입니다."
    echo "$RECENT_ERRS" | grep -q "TS_UNACCEPTABLE" && echo "  -> TS_UNACCEPTABLE: Phase 2 내부 서브넷(CIDR) 대역 정의가 어긋났습니다."
else
    echo "  [정상] 치명적인 협상 거부 에러 코드가 검출되지 않았습니다."
fi

# 5. 특정 커넥션 재시작 옵션 안내
if [ -n "$CONN_NAME" ] && [ "$INSTALLED_COUNT" -eq 0 ]; then
    echo -e "\n[5] 터널 수동 재협상(ipsec down/up) 실행 중: ${CONN_NAME}"
    ipsec down "$CONN_NAME" >/dev/null 2>&1
    ipsec up "$CONN_NAME"
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

IPsec VPN은 공중망(인터넷) 위에 암호화된 전용 사설 터널을 구축하는 표준 프로토콜이며, 크게 **제어 채널(Phase 1)**과 **데이터 암호화 채널(Phase 2)**의 2단계 협상을 거쳐 연결됩니다. 트러블슈팅 시 어느 단계에서 멈췄는지만 파악하면 원인의 90% 이상을 즉시 특정할 수 있습니다.

### 1. Phase 1 vs Phase 2 실패 원인 완벽 비교

| 협상 단계 | 역할 및 목적 | 실패 시 대표 로그 | 핵심 점검 항목 |
| :--- | :--- | :--- | :--- |
| **Phase 1 (IKE SA)** | 양단 게이트웨이 신원 인증 및 제어 터널 수립 (UDP 500 / 4500) | `NO_PROPOSAL_CHOSEN`<br>`AUTHENTICATION_FAILED`<br>`No response from peer` | 1. **Pre-Shared Key(PSK)** 오타 여부<br>2. **IKE 버전**(IKEv1 vs IKEv2) 일치 여부<br>3. 암호화(AES-256), 해시(SHA-256), **DH Group**(Group 14 등) 일치<br>4. 방화벽 UDP 500, UDP 4500, 프로토콜 50(ESP) 개방 |
| **Phase 2 (IPsec SA)** | 실제 내부 트래픽 암호화 및 라우팅 터널 수립 | `TS_UNACCEPTABLE`<br>`INVALID_ID_INFORMATION` | 1. **Proxy ID (Traffic Selector)** 양단 서브넷(Local/Remote CIDR) 일치<br>2. **PFS(Perfect Forward Secrecy)** 활성 여부 및 DH Group 일치<br>3. 양쪽 SA 수명(Key Lifetime) 설정 |

### 2. 간헐적 터널 끊김 현상: DPD(Dead Peer Detection)와 NAT-T

터널이 최초 연결은 잘 되는데 트래픽이 없을 때 끊어지거나 복구가 늦어지는 원인은 다음과 같습니다.

1. **NAT-Traversal (UDP 4500) 미동작**:
   * VPN 게이트웨이가 공인 IP를 직접 갖지 않고 앞단 공유기나 클라우드 NAT 뒤에 배치된 경우, 일반 ESP 패킷(IP Protocol 50)은 NAT 장비 통과 시 포트 번호가 없어 변환이 깨집니다.
   * 이를 해결하기 위해 ESP 패킷을 UDP 4500번으로 캡슐화하는 **NAT-T** 기능이 양쪽 모두 켜져 있어야 하며 중간 방화벽에서 UDP 4500이 열려 있어야 합니다.
2. **DPD (Dead Peer Detection) 설정 미흡**:
   * 상대방 장비가 재부팅되거나 회선이 일시 단절되었을 때, DPD가 꺼져 있으면 내 장비는 터널이 살아있는 줄 착각하여 블랙홀(Blackhole)로 계속 패킷을 버립니다.
   * `dpdaction=restart`, `dpddelay=10s`, `dpdtimeout=30s`로 설정하면 상대방 응답이 30초간 없을 시 기존 SA를 파기하고 즉시 재협상(Reconnect)을 트리거합니다.

### 3. StrongSwan 표준 구성 예시 (`/etc/ipsec.conf`)

```ini
conn hq-to-cloud
    authby=secret
    auto=start
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256-modp2048!
    keyexchange=ikev2
    left=203.0.113.10
    leftsubnet=10.10.0.0/16
    right=198.51.100.20
    rightsubnet=172.16.0.0/16
    dpdaction=restart
    dpddelay=10s
    dpdtimeout=30s
    forceencaps=yes
```

&nbsp;
&nbsp;

## 주의사항

1. **암호화 알고리즘에 느낌표(`!`) 강제 지정 시 호환성 주의**:
   * StrongSwan 설정에서 `aes256-sha256-modp2048!`처럼 끝에 `!`를 붙이면 해당 단일 조합 외의 모든 협상 제안을 거절합니다. 상대방 벤더(Cisco ASA, Juniper, AWS VPN)가 제안하는 기본 알고리즘 셋과 100% 일치하지 않으면 협상이 거부되므로 초기 연동 시에는 정확한 스펙 문서를 대조해야 합니다.

2. **클라우드(AWS/NCP) VPN 연동 시 다중 서브넷(Policy-Based vs Route-Based) 주의**:
   * 온프레미스 방화벽이 Policy-Based VPN일 경우 서브넷 개수가 여러 개면 Phase 2 SA가 서브넷 쌍만큼 개별 생성됩니다. 반면 AWS Transit Gateway 등 클라우드 측은 Route-Based(0.0.0.0/0 단일 SA)를 선호하므로, 양단 간 정책 기반과 경로 기반 모드가 충돌하여 일부 대역만 통신이 안 되는 문제가 흔히 발생합니다.

3. **방화벽에서 IP Protocol 50 (ESP) 허용 누락**:
   * NAT 환경이 아닐 경우 IPsec 데이터 패킷은 UDP 500/4500이 아닌 **IP 프로토콜 번호 50번(ESP)**으로 직접 전송됩니다. 상위 방화벽 ACL에 UDP 500만 열어두고 Protocol 50을 막아두면 Phase 1, 2 협상은 성공(UP)으로 뜨는데 실제 핑(`ping`)이나 데이터 통신만 전혀 안 되는 현상이 발생합니다.