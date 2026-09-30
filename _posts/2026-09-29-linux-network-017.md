---
layout: article
title: 시스템 관리_17 VPN 및 터널 패킷 드롭을 유발하는 MTU 불일치(Mismatch) 원인과 해결 방법
tags: [Linux, Network, VPN, WireGuard, OpenVPN, MTU, MSS, PMTUD, iptables, Troubleshooting]
keys: 260930-linux-network-017
---

- 출처 / 참고: Linux man-pages (ip-link(8), ping(8)), RFC 1191 (Path MTU Discovery), RFC 4459 (MTU and Fragmentation Issues with In-the-Network Tunneling)

> 명령어: `ip link`, `ping`, `tracepath`, `iptables`, `tcpdump`, `ss`  
> 키워드: MTU Mismatch, Packet Drop, PMTUD, Black Hole Router, MSS Clamping, DF Flag, Fragmentation  
> 사용처: VPN(OpenVPN, WireGuard, IPsec) 또는 GRE/IPIP 터널 연결 후 대용량 데이터 전송 지연 및 연결 멈춤 현상(Stall) 해결  

---

> 실행예제

VPN 또는 터널 인터페이스 환경에서 소형 패킷(ping, ssh 로그인)은 정상 작동하지만, 대용량 파일 전송(`scp`), 웹 브라우징(`HTTPS`), 패키지 다운로드(`apt`/`yum`) 시 통신이 멈추는(Stall) 현상을 점검합니다.

```bash
# 1. 시스템의 모든 인터페이스 MTU 값 확인 (물리 인터페이스 vs 터널 인터페이스 비교)
$ ip link show
# 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
# 5: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
# 8: tun0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UNKNOWN mode DEFAULT group default qlen 500
# -> tun0이 물리 인터페이스(1500)와 동일한 1500으로 잡혀 있다면 헤더 오버헤드로 인해 패킷 드롭 발생 가능성 높음

# 2. DF(Don't Fragment) 플래그를 설정하여 터널 경로상 최대 허용 패킷 크기(MTU) 측정
# 1472 bytes (데이터) + 20 bytes (IP 헤더) + 8 bytes (ICMP 헤더) = 1500 MTU 테스트
$ ping -M do -s 1472 10.8.0.1
PING 10.8.0.1 (10.8.0.1) 1472(1500) bytes of data.
ping: local error: Message too long, mtu=1420

# 3. Path MTU 탐색(PMTUD) 도구로 경로상 MTU 병목 지점 추적
$ tracepath 10.8.0.1
 1?: [LOCALHOST]     pmtu 1500
 1:  10.8.0.1                                              15.210ms pmtu 1420
     TooHashTable...
     Resume: pmtu 1420 

# 4. TCP 3-Way Handshake 시 협상되는 MSS 값 덤프 확인
$ sudo tcpdump -nn -i any "tcp[tcpflags] & (tcp-syn) != 0" and host 10.8.0.1
# [출력 예시] MSS 1460이 확인되는 경우 터널 헤더 오버헤드를 반영하지 못한 상태임
```

&nbsp;
&nbsp;

## 스크립트

터널 경로상에서 단편화(Fragmentation) 없이 통과할 수 있는 최적의 MTU 크기를 이진 탐색(Binary Search) 방식으로 자동 측정하고, 임시 또는 영구 적용 방안을 제시하는 쉘 스크립트입니다.

```bash
#!/bin/bash
# test_tunnel_mtu.sh - Find optimal MTU size through VPN/Tunnel and verify MSS clamping

TARGET_IP=${1:-"10.8.0.1"}
DEV_NAME=${2:-""}

echo "=========================================="
echo " [MTU 병목 진단 시작] 대상 IP: ${TARGET_IP}"
echo "=========================================="

# 1. 대상 IP 도달 가능 여부 기본 검사
if ! ping -c 1 -W 2 "$TARGET_IP" &>/dev/null; then
    echo "  [오류] 대상 IP($TARGET_IP)와 기본 ICMP 통신이 불가능합니다."
    exit 1
fi

echo -e "\n[1] 단편화 금지(DF 플래그) 최적 패킷 크기 탐색 중..."

LOW=1200
HIGH=1500
OPTIMAL_PAYLOAD=1200

while [ "$LOW" -le "$HIGH" ]; do
    MID=$(( (LOW + HIGH) / 2 ))
    # ICMP 패킷 전송 (단편화 방지: -M do)
    if ping -c 1 -W 1 -M do -s "$MID" "$TARGET_IP" &>/dev/null; then
        OPTIMAL_PAYLOAD=$MID
        LOW=$(( MID + 1 ))
    else
        HIGH=$(( MID - 1 ))
    fi
done

TOTAL_MTU=$(( OPTIMAL_PAYLOAD + 28 ))

echo "  -> 단편화 없이 도달 가능한 최대 ICMP 페이로드: ${OPTIMAL_PAYLOAD} bytes"
echo "  -> 권장 경로 MTU (Payload + 28 byte 헤더): ${TOTAL_MTU} bytes"

# 2. 현재 인터페이스 설정값과 비교
if [ -n "$DEV_NAME" ]; then
    echo -e "\n[2] 인터페이스 '${DEV_NAME}' 상태 비교:"
    CURRENT_MTU=$(ip -o link show dev "$DEV_NAME" | awk '{print $5}')
    echo "  - 현재 인터페이스 MTU: ${CURRENT_MTU}"
    echo "  - 추천 설정 MTU      : ${TOTAL_MTU}"

    if [ "$CURRENT_MTU" -gt "$TOTAL_MTU" ]; then
        echo "  [경고] 인터페이스 MTU가 경로 허용치보다 큽니다! 패킷 드롭 발생 위험."
        echo "  -> 수정 명령어: sudo ip link set dev ${DEV_NAME} mtu ${TOTAL_MTU}"
    else
        echo "  [정상] 인터페이스 MTU가 안전 범위 내에 설정되어 있습니다."
    fi
fi

# 3. TCP MSS Clamping 규칙 적용 여부 검사
echo -e "\n[3] 방화벽 TCP-MSS 클램핑 규칙 검사:"
if command -v iptables &>/dev/null; then
    MSS_RULES=$(sudo iptables -t mangle -S | grep -E "TCPMSS.*clamp-mss-to-pmtu")
    if [ -n "$MSS_RULES" ]; then
        echo "  [정상] iptables mangle 테이블에 TCPMSS 클램핑 규칙이 활성화되어 있습니다:"
        echo "  $MSS_RULES"
    else
        echo "  [주의] TCPMSS 클램핑 규칙이 발견되지 않았습니다."
        echo "  -> VPN 라우터 또는 방화벽에 아래 규칙 추가 권장:"
        echo "     iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu"
    fi
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

VPN(OpenVPN, WireGuard, IPsec)이나 터널(GRE, VXLAN, IPIP) 인터페이스를 사용할 때 흔히 겪는 "SSH 텍스트는 잘 쳐지는데 대용량 파일(`scp`)이나 웹 접속(`curl`, 브라우저)만 시도하면 멈추는" 현상의 주원인은 **MTU 불일치(MTU Mismatch)**와 **블랙홀 라우터(Black Hole Router)** 문제입니다.

### 1. MTU 불일치 및 패킷 드롭 메커니즘

1. **터널 오버헤드(Capsulation Overhead)**:
   * 표준 이더넷의 기본 MTU는 `1500 bytes`입니다.
   * 패킷이 터널을 통과할 때 터널 프로토콜의 추가 헤더(IP 헤더, UDP 헤더, 암호화 헤더 등)가 덧붙여집니다.
     * **WireGuard**: 60 ~ 80 bytes (권장 MTU: `1420`)
     * **OpenVPN**: 40 ~ 100 bytes (권장 MTU: `1400` ~ `1450`)
     * **IPsec / GRE**: 50 ~ 90 bytes (권장 MTU: `1400` 이하)
2. **DF(Don't Fragment) 플래그와 PMTUD 실패**:
   * 대부분의 현대 TCP 스택은 성능 향상을 위해 IP 패킷에 `DF=1`(단편화 금지) 플래그를 설정합니다.
   * 1500바이트 크기의 TCP 패킷이 터널 인터페이스로 들어오면 헤더가 추가되어 1500바이트를 초과(`1560 bytes`)하게 됩니다.
   * 라우터는 패킷을 버리고(Drop), 송신자에게 **ICMP Type 3, Code 4(Destination Unreachable, Fragmentation Needed and DF set)** 패킷을 되돌려주어야 합니다(Path MTU Discovery).
   * 그러나 중간 방화벽이나 클라우드 보안 그룹이 ICMP를 차단해버리면 송신자는 패킷이 왜 버려졌는지 알지 못한 채 계속 재전송만 시도하다가 타임아웃에 빠집니다(**ICMP Black Hole**).

### 2. 해결 방법

#### 방법 1: 터널 인터페이스의 MTU 크기 하향 조정
터널 어댑터 자체의 MTU를 헤더 오버헤드를 감안하여 안전한 크기로 줄입니다.
```bash
# WireGuard 예시 (/etc/wireguard/wg0.conf)
[Interface]
MTU = 1420

# 수동 즉시 변경
sudo ip link set dev tun0 mtu 1400
```

#### 방법 2: TCP MSS Clamping 적용 (가장 강력하고 권장되는 방법)
터널 게이트웨이 또는 서버에서 TCP 3-Way Handshake 과정의 `SYN` 패킷을 감시하여, MTU 크기에 맞게 MSS(Maximum Segment Size) 값을 자동으로 강제 축소(Clamping)합니다.

* **iptables 사용 시**:
  ```bash
  sudo iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
  ```
* **nftables 사용 시**:
  ```bash
  sudo nft add rule inet filter forward tcp flags syn tcp option maxseg size set rt mtu
  ```

&nbsp;
&nbsp;

## 주의사항

1. **ICMP Type 3(Fragmentation Needed) 차단 금지**:
   * "보안 강화" 목적으로 방화벽에서 모든 ICMP 패킷을 일괄 `DROP`하는 정책을 적용하면 PMTUD(경로 MTU 탐색)가 완전히 동작하지 않게 됩니다. ICMP Type 3(Destination Unreachable) 패킷은 네트워크 정상 동작을 위해 반드시 허용해야 합니다.

2. **UDP 기반 트래픽(DNS, VoIP, 영상 스트리밍) 주의**:
   * TCP MSS Clamping은 **TCP 트래픽에만 적용**됩니다. UDP 트래픽은 핸드셰이크가 없어 MSS를 조절할 수 없으므로, UDP 기반 대용량 통신(예: DNS EDNS0, QUIC, 비디오 스트림) 장애를 예방하려면 반드시 인터페이스 자체의 MTU(`ip link set mtu`)를 적정값으로 낮춰야 합니다.

3. **클라우드(AWS/GCP/Azure)의 점보 프레임(Jumbo Frame) 환경**:
   * VPC 내부 통신은 점보 프레임(`MTU 9001`)을 지원하지만, 인터넷 게이트웨이(IGW)나 온프레미스 연동 VPN/DirectConnect 구간으로 나갈 때는 즉시 `1500` 또는 그 이하로 줄어듭니다. VPC 내부에서 생성된 대형 패킷이 터널을 타는 순간 드롭되지 않도록 주의해야 합니다.