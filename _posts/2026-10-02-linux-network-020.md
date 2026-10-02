---
layout: article
title: 시스템 관리_20 멀티홈 서버 환경의 비대칭 라우팅과 rp_filter 패킷 드롭 원인 및 정책 기반 라우팅 해결 가이드
tags: [Linux, Network, Multi-Homed, Asymmetric-Routing, rp_filter, Policy-Routing, iproute2, Troubleshooting]
keys: 261002-linux-network-020
---

- 출처 / 참고: Linux Kernel Documentation (ip-sysctl.rst - rp_filter), RFC 3704 (Ingress Filtering for Multihomed Networks)

> 명령어: `ip route`, `ip rule`, `sysctl`, `tcpdump`, `conntrack`, `nstat`  
> 키워드: Multi-Homed Server, Asymmetric Routing, rp_filter, Reverse Path Filtering, Policy Routing, ip rule, Table ID  
> 사용처: 2개 이상의 NIC를 사용하는 서버에서 두 번째 IP로 유입된 트래픽 응답 실패 및 패킷 유실 해결  

---

> 실행예제

2개 이상의 네트워크 인터페이스(NIC)가 장착된 멀티홈(Multi-Homed) 서버에서 보조 NIC(eth1)로 유입된 트래픽이 디폴트 게이트웨이(eth0)로 잘못 역라우팅되거나 커널의 역방향 경로 필터링(`rp_filter`)에 의해 드롭되는 상태를 진단합니다.

```bash
# 1. 라우팅 테이블 및 기본 게이트웨이(Default Gateway) 확인
$ ip route show
default via 192.168.1.1 dev eth0 proto static 
192.168.1.0/24 dev eth0 proto kernel scope link src 192.168.1.100 
10.0.0.0/24 dev eth1 proto kernel scope link src 10.0.0.100 
# -> 디폴트 게이트웨이가 eth0으로만 잡혀 있어 eth1로 들어온 외부 트래픽 응답도 eth0으로 나가려고 함

# 2. 커널의 역방향 경로 필터(rp_filter) 설정값 확인
$ sysctl -a | grep "\.rp_filter"
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.eth0.rp_filter = 1
net.ipv4.conf.eth1.rp_filter = 1
# -> rp_filter 값이 1(Strict Mode)이면 비대칭 경로로 들어온 패킷은 커널에서 즉시 드롭됨

# 3. rp_filter에 의해 드롭된 패킷 카운터 증가 여부 점검
$ nstat -az TcpExtIPReversePathFilter
# TcpExtIPReversePathFilter           142                0.0
# -> 카운터가 지속적으로 증가한다면 rp_filter에 의해 패킷이 폐기되고 있음을 의미

# 4. eth1로 인입되는 SYN 패킷과 응답 여부를 tcpdump로 교차 추적
# 터미널 1: eth1 캡처
$ sudo tcpdump -nn -i eth1 port 80
# 10:00:01 IP 203.0.113.5.54123 > 10.0.0.100.80: Flags [S], seq ... (SYN 유입 확인)

# 터미널 2: eth0 캡처 (비대칭 라우팅 발생 시 응답 SYN-ACK가 eth0으로 나감)
$ sudo tcpdump -nn -i eth0 port 80
# 10:00:01 IP 10.0.0.100.80 > 203.0.113.5.54123: Flags [S.], seq ... (출구 불일치 확인)
```

&nbsp;
&nbsp;

## 스크립트

멀티홈 서버의 모든 인터페이스에 대한 `rp_filter` 상태를 진단하고, 출발지 기반 정책 라우팅(Policy-Based Routing) 룰과 별도 라우팅 테이블이 정상 구성되어 있는지 점검하는 쉘 스크립트입니다.

```bash
#!/bin/bash
# check_multihome_routing.sh - Diagnose Asymmetric Routing and rp_filter issues

echo "=========================================="
echo " [멀티홈 네트워크 및 비대칭 라우팅 진단]"
echo "=========================================="

# 1. 활성 네트워크 인터페이스 목록 수집
INTERFACES=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2}')

echo -e "\n[1] 인터페이스별 rp_filter 설정 점검:"
ALL_RP=$(sysctl -n net.ipv4.conf.all.rp_filter)
echo "  - net.ipv4.conf.all.rp_filter = $ALL_RP"

for IFACE in $INTERFACES; do
    IFACE_RP=$(sysctl -n net.ipv4.conf."${IFACE}".rp_filter 2>/dev/null)
    if [ -n "$IFACE_RP" ]; then
        STATUS="정상"
        [ "$IFACE_RP" -eq 1 ] && STATUS="엄격(Strict) - 비대칭 패킷 드롭 위험"
        [ "$IFACE_RP" -eq 2 ] && STATUS="느슨(Loose) - 권장"
        [ "$IFACE_RP" -eq 0 ] && STATUS="비활성화(Off)"
        echo "  - ${IFACE}: rp_filter = ${IFACE_RP} (${STATUS})"
    fi
done

# 2. rp_filter 패킷 드롭 통계 확인
echo -e "\n[2] rp_filter 패킷 폐기 통계:"
if command -v nstat &>/dev/null; then
    DROP_COUNT=$(nstat -az TcpExtIPReversePathFilter | awk 'NR>1 {print $2}')
    echo "  - 총 폐기된 패킷 수(TcpExtIPReversePathFilter): ${DROP_COUNT:-0}"
else
    echo "  - nstat 유틸리티가 없어 통계를 건너뜁니다."
fi

# 3. 정책 기반 라우팅 규칙(ip rule) 점검
echo -e "\n[3] 정책 라우팅 규칙(ip rule) 점검:"
IP_RULES=$(ip rule show | grep -v "from all lookup" | grep -v "lookup local")
if [ -z "$IP_RULES" ]; then
    echo "  [경고] 출발지 IP 기반 라우팅 규칙(ip rule)이 정의되어 있지 않습니다."
    echo "  -> 보조 NIC로 들어온 트래픽이 기본 게이트웨이(Default GW)로 역라우팅될 가능성이 높습니다."
else
    echo "  [정상] 사용자 정의 정책 라우팅 규칙이 감지되었습니다:"
    echo "$IP_RULES" | sed 's/^/    /'
fi

# 4. /etc/iproute2/rt_tables 커스텀 테이블 등록 점검
echo -e "\n[4] 커스텀 라우팅 테이블(rt_tables) 등록 여부:"
CUSTOM_TABLES=$(grep -vE "^#|^255|^254|^253|^0" /etc/iproute2/rt_tables)
if [ -n "$CUSTOM_TABLES" ]; then
    echo "  [확인] 등록된 커스텀 테이블:"
    echo "$CUSTOM_TABLES" | sed 's/^/    /'
else
    echo "  [안내] 기본 테이블 외 추가 등록된 커스텀 테이블이 없습니다."
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

하나의 서버에 2개 이상의 네트워크 인터페이스(NIC)가 각각 다른 서브넷이나 게이트웨이를 바라보는 멀티홈(Multi-Homed) 환경에서는 **비대칭 라우팅(Asymmetric Routing)** 및 커널 보안 필터로 인한 통신 단절이 매우 흔하게 발생합니다.

### 1. 비대칭 라우팅과 rp_filter 드롭 원리

1. **단일 기본 게이트웨이 한계**:
   * 리눅스는 표준 라우팅 테이블에서 기본 게이트웨이를 1개만 갖습니다 (예: `eth0` 쪽 게이트웨이).
   * 외부 사용자가 보조 인터페이스인 `eth1`의 IP로 접속을 시도(SYN 전송)하면, 서버 애플리케이션은 응답(SYN-ACK)을 생성합니다.
   * 그러나 리눅스 커널의 기본 라우팅 테이블에는 `eth0` 게이트웨이만 등록되어 있으므로, 목적지 IP로 나가기 위해 **응답 패킷을 eth0으로 송출**합니다.

2. **클라이언트 및 방화벽 차단**:
   * 클라이언트는 `eth1` IP로 요청을 보냈는데 `eth0` IP로 응답이 오거나(NAT 환경), 상태 기반 방화벽(Stateful Firewall)이 비대칭 경로를 비정상 TCP 플로우로 판단하여 패킷을 차단합니다.

3. **리눅스 커널의 `rp_filter` (Reverse Path Filtering)**:
   * 리눅스 커널은 IP 스푸핑 공격을 막기 위해 수신된 패킷의 출발지 IP를 확인하고, **"이 패킷의 출발지로 응답할 때 패킷이 들어온 인터페이스와 동일한 인터페이스로 나갈 수 있는가?"**를 검사합니다.
   * 비대칭 라우팅 상황에서는 들어온 포트(eth1)와 나갈 포트(eth0)가 다르기 때문에, 커널은 이 패킷을 위조된 패킷으로 판단하고 인터페이스 진입 단계에서 즉시 폐기(Drop)합니다.

### 2. 해결 방법

#### 방법 1: rp_filter 모드를 Loose 모드(2)로 완화
커널이 출발지 경로를 검사할 때 "동일 인터페이스"가 아니더라도 "어떤 인터페이스를 통해서든 라우팅이 가능한지"만 검사하도록 완화합니다.

```bash
# 임시 적용
sudo sysctl -w net.ipv4.conf.all.rp_filter=2
sudo sysctl -w net.ipv4.conf.eth1.rp_filter=2

# 영구 적용 (/etc/sysctl.d/99-routing.conf)
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.eth1.rp_filter = 2
```

#### 방법 2: 출발지 기반 정책 라우팅(Policy-Based Routing) 구성 (정석 해결책)
`eth1` IP를 출발지로 하는 트래픽은 반드시 `eth1` 게이트웨이를 통해 나가도록 독립된 라우팅 테이블과 규칙을 정의합니다.

1. **커스텀 라우팅 테이블 등록**:
   ```bash
   echo "200 eth1_route" | sudo tee -a /etc/iproute2/rt_tables
   ```

2. **보조 라우팅 테이블에 게이트웨이 및 서브넷 라우트 추가**:
   ```bash
   # eth1 네트워크 대역과 게이트웨이 지정
   sudo ip route add 10.0.0.0/24 dev eth1 src 10.0.0.100 table eth1_route
   sudo ip route add default via 10.0.0.1 dev eth1 table eth1_route
   ```

3. **출발지 IP 기준 룰(ip rule) 매핑**:
   ```bash
   # eth1의 IP(10.0.0.100)를 달고 나가는 모든 트래픽은 eth1_route 테이블 참조
   sudo ip rule add from 10.0.0.100/32 table eth1_route
   sudo ip rule add to 10.0.0.100/32 table eth1_route
   
   # 라우팅 캐시 플러시
   sudo ip route flush cache
   ```

&nbsp;
&nbsp;

## 주의사항

1. **`all`과 `interface`의 max 연산 규칙**:
   * `rp_filter`는 `net.ipv4.conf.all.rp_filter`와 개별 인터페이스 `net.ipv4.conf.<iface>.rp_filter` 중 **더 큰(더 엄격한) 값**을 우선 적용합니다. 따라서 개별 인터페이스를 `2`(Loose)로 설정해도 `all`이 `1`(Strict)이면 `1`로 동작하므로 반드시 둘 다 `2`로 맞춰야 합니다.

2. **Netplan 및 ifupdown 영구 설정 누락**:
   * `ip route add ... table` 및 `ip rule` 명령어로 적용한 설정은 서버 재부팅 시 초기화됩니다. Ubuntu 환경이라면 `/etc/netplan/*.yaml`의 `routing-policy` 섹션에 등록하고, RHEL/Rocky 환경이라면 `/etc/sysconfig/network-scripts/rule-<iface>`에 영구 반영해야 합니다.

3. **기본 게이트웨이(Default Route) 중복 생성 금지**:
   * 메인 라우팅 테이블에 서로 다른 메트릭(Metric) 없이 2개의 기본 게이트웨이를 동시에 등록하면 세션별로 게이트웨이가 뒤바뀌어 간헐적인 연결 끊김이 발생할 수 있습니다. 메인 테이블의 디폴트 경로는 반드시 1개만 유지하고, 추가 회선은 정책 라우팅 테이블로 격리해야 합니다.