---
layout: article
title: 시스템 관리_73 방화벽 비대칭 라우팅 Asymmetric Routing 및 TCP 상태 불일치 패킷 드롭 해결 가이드
tags: [Network, Firewall, Asymmetric-Routing, Stateful-Inspection, TCP-State, FortiGate, iptables, tcpdump, Routing, Troubleshooting]
keys: 261125-linux-network-073
---

- 출처 / 참고: Fortinet Knowledge Base (Technical Tip: Asymmetric routing and FortiGate - FD30040), IETF RFC 793 (Transmission Control Protocol), Linux Netfilter Stateful Inspection Documentation

> 명령어: `tcpdump`, `ip`, `traceroute`, `conntrack`, `diagnose sniffer packet`, `sysctl`  
> 키워드: Asymmetric Routing, Stateful Firewall, Out-of-State Drop, SYN-ACK Drop, RPF Check, rp_filter, ECMP, Policy-Based Routing  
> 사용처: 다중 회선(ISP 이중화) 또는 L3 코어 스위치-방화벽 연동 구간에서 Ping(ICMP)은 되지만 TCP(HTTP/DB/SSH) 통신만 타임아웃으로 끊기는 현상 해결

---

> 실행예제

다중 게이트웨이 또는 방화벽 이중화 구성 이후 `ping` 통신은 정상인데 웹(TCP 80/443)이나 DB(TCP 1521/3306) 접속 시 연결이 수립되지 않고 멈출 때, 리눅스 호스트와 방화벽에서 **비대칭 라우팅(갈 때 경로와 올 때 경로가 다름)**으로 인한 상태 기반 방화벽(Stateful Firewall) 패킷 드롭을 진단합니다.

```bash
# 1. 리눅스 서버 관점: tcpdump로 TCP 3-way 핸드셰이크 중 SYN-ACK 또는 ACK 누락 캡처
$ sudo tcpdump -ni any host 10.20.30.50 and port 443 -c 10
# 16:10:01.101 IP 10.10.10.20.51234 > 10.20.30.50.443: Flags [S], seq 1001, win 64240
# 16:10:02.105 IP 10.10.10.20.51234 > 10.20.30.50.443: Flags [S], seq 1001, win 64240
# 16:10:04.110 IP 10.10.10.20.51234 > 10.20.30.50.443: Flags [S], seq 1001, win 64240
# -> SYN 패킷을 보냈으나 방화벽이 리턴 경로의 SYN-ACK 또는 이후 데이터 패킷을 'Out-of-State'로 드롭시켜 재전송만 반복함

# 2. 리눅스 커널 역방향 경로 필터링(Reverse Path Filtering) 드롭 통계 확인
$ sysctl -a | grep "\.rp_filter"
# net.ipv4.conf.all.rp_filter = 1
# net.ipv4.conf.default.rp_filter = 1
# net.ipv4.conf.eth0.rp_filter = 1
# net.ipv4.conf.eth1.rp_filter = 1
# -> 엄격 모드(rp_filter = 1)일 때, 패킷이 들어온 인터페이스(eth1)와 라우팅 테이블 상의 출발지 반환 인터페이스(eth0)가 다르면 커널이 패킷을 즉각 폐기함

# 3. Netfilter Conntrack에서 INVALID(상태 불일치) 패킷 상태 확인
$ sudo conntrack -S
# cpu=0 found=145020 invalid=48210 ignore=0 insert=0 insert_failed=0 drop=1240
# -> invalid 카운터가 수만 건 이상 급증 중이면 비대칭 경로로 유입된 비정상 시퀀스 패킷이 대량 발생 중임을 의미

# 4. 출발지/목적지 양방향 경로 대조 (traceroute)
$ traceroute -n -T -p 443 10.20.30.50
# -> 목적지 서버에서도 동일하게 출발지 IP(10.10.10.20)로 traceroute를 실행하여 경유하는 홉(Gateway IP)이 일치하는지 대조
```

&nbsp;
&nbsp;

## 스크립트

다중 NIC(eth0, eth1 등)가 장착된 리눅스 서버 및 게이트웨이에서 **1) 라우팅 테이블 충돌(다중 디폴트 게이트웨이) 여부, 2) 커널 `rp_filter` 엄격 모드 차단 위험, 3) Netfilter `INVALID` 상태 패킷 누적 현황**을 진단하고 출발지 기반 정책 라우팅(PBR: Policy-Based Routing) 구성을 점검하는 쉘 스크립트입니다.

```bash
#!/bin/bash
# diagnose_asymmetric_routing.sh - Diagnose asymmetric routing, rp_filter drops, and PBR configuration on Linux

echo "=========================================="
echo " [비대칭 라우팅 및 상태 불일치 패킷 진단기]"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] 커널 네트워크 및 라우팅 점검을 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

# 1. 다중 기본 게이트웨이(Default Gateway) 충돌 검사
echo -e "\n[1] 메인 라우팅 테이블 기본 게이트웨이(Default Route) 점검:"
DEF_ROUTES=$(ip route show default)
DEF_COUNT=$(echo "$DEF_ROUTES" | grep -c "default")

echo "$DEF_ROUTES" | sed 's/^/  - /'
if [ "$DEF_COUNT" -gt 1 ]; then
    echo "  [치명적 경고] 메인 라우팅 테이블에 기본 게이트웨이가 ${DEF_COUNT}개 중복 등록되어 있습니다!"
    echo "  -> 현상: eth1으로 인입된 외부 요청의 응답 패킷이 우선순위가 높은 eth0 게이트웨이로 빠져나가 방화벽에서 드롭됩니다."
    echo "  -> 조치: 보조 인터페이스(eth1) 전용 정책 라우팅 테이블(ip rule / ip route table)을 분리해야 합니다."
fi

# 2. 커널 역방향 경로 필터(rp_filter) 설정 점검
echo -e "\n[2] 커널 역방향 경로 필터링(rp_filter) 모드 점검:"
STRICT_FOUND=0
for CONF in /proc/sys/net/ipv4/conf/*/rp_filter; do
    IFACE=$(echo "$CONF" | awk -F'/' '{print $(NF-1)}')
    VAL=$(cat "$CONF")
    if [ "$VAL" -eq 1 ]; then
        echo "  - 인터페이스 ${IFACE}: rp_filter = 1 (Strict 엄격 모드 - 비대칭 트래픽 자동 폐기)"
        STRICT_FOUND=1
    elif [ "$VAL" -eq 2 ]; then
        echo "  - 인터페이스 ${IFACE}: rp_filter = 2 (Loose 느슨한 모드 - 다중 회선 허용)"
    fi
done

if [ "$STRICT_FOUND" -eq 1 ] && [ "$DEF_COUNT" -gt 1 ]; then
    echo "  [위험] 다중 게이트웨이 환경에서 rp_filter=1 이 켜져 있어 인입 패킷이 커널 수준에서 드롭되고 있습니다!"
fi

# 3. Conntrack INVALID 상태 패킷 통계 확인
echo -e "\n[3] 방화벽 상태 추적(Conntrack) INVALID 패킷 통계:"
if command -v conntrack &>/dev/null; then
    INVALID_CNT=$(conntrack -S 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^invalid=/) {split($i,a,"="); sum+=a[2]}} END {print sum}')
    echo "  - 누적 상태 불일치(INVALID) 패킷 수: ${INVALID_CNT:-0} 건"
    if [ "${INVALID_CNT:-0}" -gt 1000 ]; then
        echo "  [경고] INVALID 패킷이 다수 감지되었습니다. 경로 비대칭 또는 방화벽 세션 타임아웃 의심."
    fi
else
    echo "  - conntrack 유틸리티가 설치되어 있지 않습니다. (/proc/net/stat/nf_conntrack 참조 가능)"
fi

# 4. 정책 라우팅(Policy-Based Routing) 규칙 현황 확인
echo -e "\n[4] 현재 활성화된 IP Policy Routing 규칙 (ip rule):"
ip rule show | sed 's/^/  /'

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

엔터프라이즈 네트워크에서 방화벽이나 L3 스위치를 이중화하거나, 서버에 망분리/백업/외부망 용도로 2개 이상의 NIC(예: `eth0` 내부망, `eth1` 외부망)를 장착할 때 가장 빈번하게 겪는 장애가 **비대칭 라우팅(Asymmetric Routing)**입니다.

### 1. 상태 기반 방화벽(Stateful Firewall)이 비대칭 패킷을 버리는 원리

현대 방화벽(FortiGate, Palo Alto, Cisco ASA, Linux iptables/nftables)은 패킷의 출발지/목적지 IP만 보는 것이 아니라 **TCP 3-Way Handshake(`SYN` $\rightarrow$ `SYN-ACK` $\rightarrow$ `ACK`)의 상태 전이와 시퀀스 번호를 메모리 세션 테이블에 추적**합니다.

```
[정상 대칭 경로]
클라이언트 ──(1. SYN)──▶ [방화벽 A] ──▶ 서버
클라이언트 ◀─(2. SYN-ACK)─ [방화벽 A] ◀── 서버  (방화벽 A가 SYN을 기억하므로 정상 통과)

[비대칭 장애 경로]
클라이언트 ──(1. SYN)──▶ [방화벽 A] ──▶ 서버 (eth1 인입)
클라이언트 ◀─(2. SYN-ACK)─ [방화벽 B] ◀── 서버 (기본 게이트웨이 eth0으로 이탈!)
  └─▶ [방화벽 B]는 1번 SYN 패킷을 본 적이 없으므로 SYN-ACK를 비정상 공격(Out-of-State)으로 간주하여 즉시 폐기(Drop)!
```

* **`ping`(ICMP)은 되는데 TCP만 안 되는 이유**: ICMP는 연결 상태가 없는(Stateless) 단순 에코 프로토콜이거나 방화벽에서 관대하게 허용되는 경우가 많지만, TCP는 엄격한 상태 머신 검사를 거치기 때문에 첫 패킷(`SYN`)을 못 본 방화벽을 타는 순간 통신이 100% 차단됩니다.

### 2. 리눅스 서버 다중 NIC 환경에서의 근본 해결: 정책 라우팅 (PBR)

서버에 `eth0`(10.10.1.10, GW 10.10.1.1)과 `eth1`(192.168.100.10, GW 192.168.100.1)이 동시에 있을 때, 들어온 인터페이스로 정확히 되돌려 보내려면 **출발지 IP 기반 정책 라우팅(Source-Based Policy Routing)**을 구성해야 합니다.

```bash
# 1. 보조 라우팅 테이블 정의 (/etc/iproute2/rt_tables)
echo "200 dmz_table" | sudo tee -a /etc/iproute2/rt_tables

# 2. dmz_table에 eth1 전용 서브넷 및 게이트웨이 라우트 등록
sudo ip route add 192.168.100.0/24 dev eth1 src 192.168.100.10 table dmz_table
sudo ip route add default via 192.168.100.1 dev eth1 table dmz_table

# 3. 출발지 IP가 192.168.100.10인 패킷은 무조건 dmz_table을 타도록 정책 규칙(ip rule) 추가
sudo ip rule add from 192.168.100.10/32 table dmz_table
sudo ip rule add to 192.168.100.10/32 table dmz_table

# 4. 다중 인터페이스 환경에 맞게 rp_filter를 Loose 모드(2)로 완화
sudo sysctl -w net.ipv4.conf.all.rp_filter=2
sudo sysctl -w net.ipv4.conf.eth1.rp_filter=2
```

### 3. 방화벽 및 스위치 구간의 해결 방법

1. **ECMP(Equal-Cost Multi-Path) 해싱 기준 통일**:
   * L3 코어 스위치와 방화벽 간 다중 경로 구성 시, 트래픽 분산 기준을 패킷 단위(Per-Packet)가 아닌 **출발지/목적지 IP 및 포트 해시 기반(Per-Flow / L4 Hash)**으로 맞추어 동일 세션은 항상 같은 방화벽을 왕복하도록 고정합니다.
2. **방화벽 HA(Active-Active) 구성 시 세션 동기화(Session Sync) 활성화**:
   * 두 대의 방화벽이 동시에 트래픽을 처리해야 하는 구조라면 전용 HA Sync 인터페이스를 연결해 세션 테이블을 실시간 복제하도록 구성합니다.

&nbsp;
&nbsp;

## 주의사항

1. **방화벽에서 `asymroute enable` (비대칭 라우팅 전역 허용) 설정 지양**:
   * FortiGate 등의 방화벽 CLI에는 `set asymroute enable` 명령어가 존재하지만, 이를 켜면 방화벽이 TCP 상태 검사를 포기하고 모든 비상태 패킷을 무방비로 통과시켜 **스푸핑 및 TCP 세션 하이재킹 보안 취약점**이 열립니다. 불가피한 과도기 우회가 아니라면 반드시 라우팅 테이블을 수정해 대칭 경로로 복원해야 합니다.

2. **`ip route` / `ip rule` 수동 추가 후 재부팅 시 설정 유실 주의**:
   * 터미널에서 직접 입력한 `ip rule`과 `ip route table` 명령어는 메모리에만 임시 저장되므로 서버 재부팅 시 사라집니다. 반드시 NetworkManager(`nmcli connection modify eth1 ipv4.routes ... ipv4.routing-rules ...`) 또는 `/etc/network/interfaces` 영구 설정 파일에 등록한 뒤 재부팅 테스트를 거쳐야 합니다.

3. **L4 로드밸런서 DSR(Direct Server Return) 구성 시 `rp_filter` 주의**:
   * DSR 구성에서는 요청 패킷이 L4 VIP를 거쳐 서버의 `lo` 루프백으로 들어오고, 응답 패킷은 물리 NIC(`eth0`)로 직접 클라이언트로 나가는 의도된 비대칭 구조를 가집니다. 이때 서버의 `rp_filter`가 `1`로 되어 있으면 정상 VIP 트래픽이 모두 드롭되므로 DSR 백엔드 서버는 반드시 `rp_filter=0` 또는 `2`로 설정해야 합니다.