---
layout: article
title: 시스템 관리_74 BGP 및 OSPF 동적 라우팅 플랩 Flapping 원인 분석과 BFD 고속 장애 감지 해결 가이드
tags: [Network, Routing, BGP, OSPF, Flapping, BFD, FRRouting, Graceful-Restart, Keepalive, Troubleshooting]
keys: 261126-linux-network-074
---

- 출처 / 참고: IETF RFC 4271 (A Border Gateway Protocol 4 - BGP-4), IETF RFC 2328 (OSPF Version 2), IETF RFC 5880 (Bidirectional Forwarding Detection - BFD), FRRouting Official Documentation

> 명령어: `vtysh`, `ip`, `ss`, `tcpdump`, `systemctl`, `dmesg`  
> 키워드: BGP Flapping, OSPF Neighbor Down, BFD, Bidirectional Forwarding Detection, Hold Timer, Graceful Restart, Route Dampening, FRRouting  
> 사용처: 전용선이나 하이브리드 클라우드(Direct Connect/VPN) 연동 구간에서 BGP/OSPF 이웃(Neighbor) 세션이 반복적으로 끊겼다 붙었다 하며 라우팅 테이블이 요동치는 장애 해결

---

> 실행예제

코어 스위치, 방화벽 또는 리눅스 라우터(FRRouting)에서 외부 피어(Peer)와의 BGP 또는 OSPF 인접 관계(Neighbor)가 수 분 간격으로 끊어졌다가 재수립되는 **라우팅 플랩(Flapping)** 현상이 발생하여 내부 서비스 전체가 순단될 때, 데몬 상태와 타이머 만료 원인을 진단합니다.

```bash
# 1. FRRouting(vtysh) 관점: BGP 피어 상태, 업타임(Up/Down) 및 세션 리셋 횟수 확인
$ sudo vtysh -c "show ip bgp summary"
# Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd
# 10.254.1.1      4      64512      1420      1435        0    0    0 00:01:12           18
# -> Up/Down 시간이 몇 시간/며칠이 아니라 '00:01:12'(1분 12초)로 짧다면 방금 세션이 끊겼다 재연결된 것임

# 2. 특정 BGP 이웃의 상세 상태 및 마지막 리셋 사유(Last reset) 추출
$ sudo vtysh -c "show ip bgp neighbors 10.254.1.1" | grep -iE "BGP state|Last reset|Hold time|Keepalive"
#   BGP state = Established, up for 00:01:15
#   Last reset 00:01:16, due to Hold Timer Expired
#   Hold time is 180, keepalive interval is 60 seconds
# -> 상대방으로부터 180초 동안 Keepalive 패킷을 받지 못해 'Hold Timer Expired'로 세션을 끊어버림 확인

# 3. OSPF 인접(Neighbor) 상태 및 Dead Timer 만료 여부 확인
$ sudo vtysh -c "show ip ospf neighbor"
# Neighbor ID     Pri State           Dead Time Address         Interface
# 192.168.255.2     1 Full/Backup       31.420s 10.10.20.2      eth1:10.10.20.1
# -> Dead Time이 40초에서 계속 10초 미만으로 떨어졌다 올라가면 Hello 패킷이 중간에 드롭되고 있음을 의미

# 4. 인터페이스 물리 계층 에러(CRC/Drop) 및 BGP(TCP 179) 패킷 캡처
$ ip -s link show eth1
$ sudo tcpdump -ni eth1 tcp port 179 or proto ospf -c 15
```

&nbsp;
&nbsp;

## 스크립트

리눅스 라우터 및 게이트웨이(FRRouting 기반)에서 동작하여 **1) BGP 피어와 OSPF 네이버의 업타임 및 상태 불안정(Flapping)을 자동 탐지**하고, **2) 물리 NIC의 RX/TX 에러와 MTU 불일치(OSPF ExStart/Exchange 멈춤 주원인)를 점검**하며, **3) 고속 장애 감지를 위한 BFD(Bidirectional Forwarding Detection) 활성화 상태**를 검증하는 진단 쉘 스크립트입니다.

```bash
#!/bin/bash
# diagnose_routing_flapping.sh - Diagnose BGP/OSPF route flapping, MTU mismatch, and BFD status

echo "=========================================="
echo " [BGP / OSPF 동적 라우팅 플랩 정밀 진단기]"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] 라우팅 데몬 및 네트워크 분석을 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

if ! command -v vtysh &>/dev/null; then
    echo "  [오류] FRRouting(vtysh) 패키지가 설치되어 있지 않습니다."
    exit 1
fi

# 1. BGP 피어 세션 안정성 및 최근 리셋 사유 점검
echo -e "\n[1] BGP 피어(Neighbor) 세션 및 업타임 분석:"
BGP_SUM=$(vtysh -c "show ip bgp summary" 2>/dev/null)

if echo "$BGP_SUM" | grep -q "Neighbor"; then
    echo "$BGP_SUM" | awk 'NR>=6 && NF>=10 {printf "  - 피어 IP: %-16s | AS: %-8s | 업타임/상태: %-10s | 수신프리픽스: %s\n", $1, $3, $9, $10}'
    
    # 업타임이 10분 미만(00:0X:XX)이거나 Active/Idle 상태인 불안정 피어 추출
    UNSTABLE_PEERS=$(echo "$BGP_SUM" | awk 'NR>=6 && NF>=10 && ($9 ~ /^00:0[0-9]:/ || $10 ~ /Active|Idle|Connect/) {print $1}')
    for PEER in $UNSTABLE_PEERS; do
        RESET_REASON=$(vtysh -c "show ip bgp neighbors ${PEER}" 2>/dev/null | grep "Last reset" | head -n 1)
        echo "    [!] 경고: 피어 ${PEER} 세션 불안정 감지! (${RESET_REASON:-"초기 연결 실패"})"
    done
else
    echo "  - 구성된 BGP 인스턴스가 없습니다."
fi

# 2. OSPF 인접(Neighbor) 상태 및 ExStart/Exchange 교착 상태 점검
echo -e "\n[2] OSPF 인접(Neighbor) 상태 분석:"
OSPF_NEI=$(vtysh -c "show ip ospf neighbor" 2>/dev/null)

if echo "$OSPF_NEI" | grep -q "Neighbor ID"; then
    echo "$OSPF_NEI" | awk 'NR>=2 && NF>=6 {printf "  - 이웃 ID: %-16s | 상태: %-15s | DeadTime: %-8s | 인터페이스: %s\n", $1, $3, $4, $6}'
    
    if echo "$OSPF_NEI" | grep -qiE "ExStart|Exchange|Init"; then
        echo "    [!] 치명적 경고: OSPF가 Full 상태에 도달하지 못하고 ExStart/Exchange에 멈춰 있습니다!"
        echo "    -> 주원인: 양단 인터페이스의 MTU 크기 불일치 (DBD 패킷 드롭)."
    fi
else
    echo "  - 구성된 OSPF 인스턴스가 없습니다."
fi

# 3. BFD(고속 장애 감지) 활성화 여부 점검
echo -e "\n[3] BFD (Bidirectional Forwarding Detection) 세션 점검:"
BFD_PEERS=$(vtysh -c "show bfd peers brief" 2>/dev/null)
if echo "$BFD_PEERS" | grep -q "SessionId"; then
    echo "$BFD_PEERS" | sed 's/^/  /'
else
    echo "  [권고] 활성화된 BFD 세션이 없습니다."
    echo "  -> 기본 BGP Hold Time(180초)은 링크 단절 시 최대 3분간 트래픽 블랙홀을 유발하므로 BFD 연동을 권장합니다."
fi

# 4. 물리 인터페이스 드롭 및 MTU 불일치 확인
echo -e "\n[4] 라우팅 인터페이스 물리 에러 및 MTU 확인:"
for IFACE in $(ip -o link show up | awk -F': ' '{print $2}' | grep -v "^lo"); do
    MTU_VAL=$(cat "/sys/class/net/${IFACE}/mtu" 2>/dev/null)
    RX_ERR=$(cat "/sys/class/net/${IFACE}/statistics/rx_errors" 2>/dev/null || echo 0)
    RX_DROP=$(cat "/sys/class/net/${IFACE}/statistics/rx_dropped" 2>/dev/null || echo 0)
    printf "  - %-10s | MTU: %-5s | RX Errors: %-6s | RX Drops: %s\n" "$IFACE" "$MTU_VAL" "$RX_ERR" "$RX_DROP"
done

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

동적 라우팅 프로토콜(BGP, OSPF)이 적용된 코어 망이나 하이브리드 클라우드 전용선 환경에서 링크가 완전히 죽지 않고 **끊겼다 살아났다를 반복하는 라우팅 플랩(Flapping)**은 단순 단일 단절보다 훨씬 더 심각한 서비스 장애를 초래합니다. 경로가 바뀔 때마다 전체 라우터의 FIB(Forwarding Information Base) 재계산과 TCP 세션 리셋이 연쇄적으로 일어나기 때문입니다.

### 1. BGP 및 OSPF 플랩의 4대 핵심 원인

1. **트래픽 폭주 시 제어 평면(Control Plane) 패킷 드롭 (QoS 미적용)**:
   * 대용량 백업이나 DDoS 트래픽이 회선 대역폭(예: 1Gbps 전용선)을 100% 포화시키면, BGP의 `Keepalive` 패킷이나 OSPF의 `Hello` 패킷이 일반 데이터 패킷과 함께 버퍼에서 버려집니다.
   * 결국 라우터는 상대방이 죽은 것으로 오인하여 Hold Timer(기본 180초) 또는 Dead Timer(기본 40초) 만료로 세션을 끊어버립니다.
2. **양단 인터페이스 MTU 불일치 (OSPF ExStart 교착 및 BGP 경로 블랙홀)**:
   * OSPF는 인접 수립 시 `DBD(Database Description)` 패킷에 자신의 인터페이스 MTU 값을 실어 보냅니다. 한쪽은 MTU 9000(Jumbo)이고 반대쪽은 MTU 1500이면 OSPF는 절대 `Full`로 넘어가지 못하고 `ExStart`와 `Down`을 무한 반복합니다.
3. **물리 광모듈(SFP) 감쇄 및 회선 순단 (Micro-flapping)**:
   * 통신사 전용선 장비(L2/OTN)의 미세한 오류로 링크가 수 밀리초(ms) 단위로 흔들리면 BGP는 즉각 세션을 초기화합니다.
4. **CPU 과부하로 인한 라우팅 데몬 스케줄링 지연**:
   * 라우터 또는 리눅스 게이트웨이의 CPU가 100% 포화되어 `bgpd`나 `ospfd` 프로세스가 타이머 주기 내에 패킷을 처리하지 못하는 경우입니다.

### 2. BFD (Bidirectional Forwarding Detection)를 통한 고속 장애 감지

기본 BGP 타이머(Keepalive 60초 / Hold 180초)를 쓰면 회선이 끊어져도 최대 **3분 동안 죽은 경로로 패킷을 쏘는 블랙홀 현상**이 생깁니다. 반대로 BGP 타이머 자체를 1초로 줄이면 라우터 CPU에 큰 부하를 줍니다.

이를 해결하는 표준 기술이 **BFD**입니다. BFD는 경량 UDP 패킷을 하드웨어/커널 레벨에서 50ms~300ms 간격으로 주고받아 **1초 이내(Sub-second)에 링크 단절을 감지하고 즉시 BGP/OSPF 우회 경로로 절체**시킵니다.

#### FRRouting BGP + BFD 표준 설정 예시

```text
router bgp 65001
 bgp router-id 10.254.1.2
 neighbor 10.254.1.1 remote-as 64512
 ! BFD 연동 활성화 (300ms 간격, 3회 실패 시 0.9초 만에 즉시 우회)
 neighbor 10.254.1.1 bfd 3 300 300
 !
 address-family ipv4 unicast
  network 10.10.0.0/16
 exit-address-family
```

### 3. 제어 트래픽 QoS 최우선 순위 보장 (CoPP)

회선이 포화되어도 라우팅 세션이 끊기지 않도록 라우터/스위치의 QoS 정책에서 **TCP 179(BGP), IP Proto 89(OSPF), UDP 3784/4784(BFD)** 패킷을 최상위 우선순위 큐(CS6 / EF)로 분류해 보호해야 합니다.

&nbsp;
&nbsp;

## 주의사항

1. **BGP Route Dampening(경로 감쇠) 설정 시 복구 지연 주의**:
   * 플랩이 심한 경로를 억제하기 위해 `bgp dampening`을 켜두면, 장애가 완전히 복구된 이후에도 페널티 점수가 낮아질 때까지 최대 30분~1시간 동안 해당 경로를 의도적으로 차단하여 서비스 복구가 늦어질 수 있습니다. 내부 프라이빗 망이나 전용선 피어링에는 Dampening을 끄거나 임계치를 매우 보수적으로 잡아야 합니다.

2. **Graceful Restart(무중단 재시작) 활성화 권장**:
   * 방화벽이나 라우터의 OS 패치 또는 관리 데몬 재시작 시 데이터 평면(포워딩 테이블)은 그대로 유지하면서 제어 평면만 재협상하도록 양단 모두 `bgp graceful-restart`를 켜두면 계획된 유지보수 중 패킷 유실을 방지할 수 있습니다.

3. **OSPF `mtu-ignore` 명령어는 최후의 임시 우회책으로만 사용**:
   * 양단 MTU가 다를 때 `ip ospf mtu-ignore`를 넣으면 인접 관계는 `Full`로 올라오지만, 이후 실제 대용량 데이터 패킷 전송 시 패킷 단편화 실패로 통신 불능에 빠집니다. 반드시 물리 포트 양단의 MTU 수치를 동일하게 일치시켜야 합니다.