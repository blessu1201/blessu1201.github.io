---
layout: article
title: 시스템 관리_71 방화벽 NAT 포트 고갈 SNAT Port Exhaustion 원인 분석 및 아웃바운드 연결 실패 해결 가이드
tags: [Network, Firewall, NAT, SNAT, Port-Exhaustion, PAT, FortiGate, iptables, Conntrack, Troubleshooting]
keys: 261123-linux-network-071
---

- 출처 / 참고: IETF RFC 4787 (Network Address Translation Behavioral Requirements for Unicast UDP), Fortinet Knowledge Base (Technical Tip: IP Pool port exhaustion and NAT configuration), Linux Netfilter Conntrack Documentation

> 명령어: `ss`, `conntrack`, `sysctl`, `diagnose sys session`, `iptables`, `netstat`  
> 키워드: NAT Port Exhaustion, SNAT, PAT, IP Pool, Ephemeral Ports, TIME_WAIT, nf_conntrack, tcp_tw_reuse, Carrier-Grade NAT  
> 사용처: 수백 대의 사설망 서버나 컨테이너 클러스터가 단일 공인 IP로 외부 API/인터넷 통신 시 출발지 포트(65,535개)가 모두 소진되어 아웃바운드 연결이 실패하는 장애 해결

---

> 실행예제

사설망 내부의 웹/WAS 서버들이 외부 결제 PG사나 오픈 API 서버로 아웃바운드 HTTPS 요청을 보낼 때 간헐적으로 `Connection timed out` 또는 `Cannot assign requested address` 에러가 발생하고, 방화벽에서 NAT 변환 실패 드롭이 기록되는 현상을 진단합니다.

```bash
# 1. 리눅스 게이트웨이/NAT 서버 관점: 커널 Conntrack 테이블 점유율 및 포트 충돌 드롭 확인
$ cat /proc/sys/net/netfilter/nf_conntrack_count
# 261980
$ cat /proc/sys/net/netfilter/nf_conntrack_max
# 262144
# -> Conntrack 테이블이 99.9% 포화되어 신규 NAT 변환 엔트리를 생성하지 못함

# 2. 커널 로그에서 nf_conntrack table full 드롭 발생 확인
$ sudo dmesg -T | grep -iE "conntrack|table full|dropping packet" | tail -n 10
# [Mon Nov 23 14:15:02 2026] nf_conntrack: nf_conntrack: table full, dropping packet
# [Mon Nov 23 14:15:03 2026] nf_conntrack: nf_conntrack: table full, dropping packet

# 3. 로컬 및 NAT 구간에서 동일 목적지 IP:Port로 몰려 있는 TIME_WAIT 소켓 폭증 확인
$ ss -tan state time-wait | awk '{print $4}' | cut -d':' -f1 | sort | uniq -c | sort -nr | head -n 5
#   58420 203.0.113.10
# -> 단일 공인 IP(203.0.113.10)에서 사용할 수 있는 가용 포트 한계치(약 6만 개)에 육박하는 TIME_WAIT 점유 확인

# 4. FortiGate 방화벽 관점: IP Pool NAT 포트 고갈(nat_fail) 통계 확인
# diagnose sys session stat | grep -iE "clash|nat"
# -> clash 카운터가 급증하면 동일한 (출발지 공인 IP, 출발지 포트, 목적지 IP, 목적지 포트) 4-튜플 충돌이 발생 중임을 의미
```

&nbsp;
&nbsp;

## 스크립트

리눅스 기반 NAT 게이트웨이 및 프록시 서버에서 **1) 목적지 IP별 아웃바운드 포트 점유 현황을 스캔하여 포트 고갈(65,535 한계) 임박 여부를 경고**하고, **2) `nf_conntrack` 테이블 확장 및 `tcp_tw_reuse` 등 커널 NAT 소켓 회수 파라미터를 최적화**해 주는 진단/튜닝 쉘 스크립트입니다.

```bash
#!/bin/bash
# diagnose_nat_port_exhaustion.sh - Diagnose SNAT port exhaustion and optimize Linux NAT gateway

echo "=========================================="
echo " [방화벽/게이트웨이 SNAT 포트 고갈 정밀 진단기]"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] 커널 Conntrack 및 소켓 분석을 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

# 1. 로컬 임시 포트(Ephemeral Port) 범위 확인
PORT_RANGE=$(sysctl -n net.ipv4.ip_local_port_range)
MIN_PORT=$(echo "$PORT_RANGE" | awk '{print $1}')
MAX_PORT=$(echo "$PORT_RANGE" | awk '{print $2}')
TOTAL_AVAIL_PORTS=$((MAX_PORT - MIN_PORT + 1))

echo -e "\n[1] 가용 임시 포트(Ephemeral Port) 범위:"
echo "  - 설정 범위: ${MIN_PORT} ~ ${MAX_PORT} (단일 목적지당 최대 ${TOTAL_AVAIL_PORTS}개 연결 가능)"

# 2. 목적지 IP:Port 별 동시 활성/대기 소켓 점유 Top 5 분석 (4-Tuple 고갈 위험 탐지)
echo -e "\n[2] 목적지 엔드포인트별 소켓 점유율 Top 5:"
ss -tan | awk 'NR>1 && $1 !~ /LISTEN/ {print $5}' | sort | uniq -c | sort -nr | head -n 5 | \
while read -r CNT DST_ADDR; do
    USAGE_PCT=$(awk "BEGIN {printf \"%.1f\", ($CNT / $TOTAL_AVAIL_PORTS) * 100}")
    printf "  - 목적지: %-25s | 점유 소켓: %-6s 개 (포트 포화율: %s%%)\n" "$DST_ADDR" "$CNT" "$USAGE_PCT"
    
    if [ $(awk "BEGIN {print ($USAGE_PCT > 70.0)}") -eq 1 ]; then
        echo "    [!] 치명적 경고: 해당 목적지로 향하는 단일 공인 IP의 NAT 포트가 70% 이상 고갈되었습니다!"
        echo "    -> 조치: SNAT IP Pool에 공인 IP를 추가(다중 IP 라운드로빈)하거나 Keep-Alive 커넥션 풀을 적용하십시오."
    fi
done

# 3. Netfilter Conntrack 테이블 점유율 점검
if [ -f /proc/sys/net/netfilter/nf_conntrack_count ]; then
    CT_CURR=$(cat /proc/sys/net/netfilter/nf_conntrack_count)
    CT_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max)
    CT_PCT=$(awk "BEGIN {printf \"%.1f\", ($CT_CURR / $CT_MAX) * 100}")
    
    echo -e "\n[3] Netfilter Conntrack 테이블 상태:"
    echo "  - 현재 엔트리: ${CT_CURR} / ${CT_MAX} (사용률: ${CT_PCT}%)"
    
    if [ $(awk "BEGIN {print ($CT_PCT > 80.0)}") -eq 1 ]; then
        echo "  [경고] Conntrack 테이블 포화 임박! 패킷 드롭이 발생할 수 있습니다."
    fi
fi

# 4. 소켓 재사용 및 포트 범위 확장 커널 최적화 적용
echo -e "\n[4] SNAT 고갈 완화를 위한 커널 TCP/NAT 최적화 적용:"
SYSCTL_NAT="/etc/sysctl.d/99-nat-port-tuning.conf"

cat << 'EOF' > "$SYSCTL_NAT"
# Expand ephemeral port range to maximum safe range
net.ipv4.ip_local_port_range = 1024 65535

# Enable fast TIME_WAIT socket reuse for outbound connections
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# Expand nf_conntrack table capacity
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_established = 1800
EOF

sysctl -p "$SYSCTL_NAT" >/dev/null 2>&1
echo "  [성공] 커널 NAT 및 임시 포트 범위 확장 설정 완료 (${SYSCTL_NAT})."

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

사설 네트워크(10.x.x.x, 192.168.x.x)의 수많은 내부 서버가 외부 인터넷이나 파트너사 API 서버와 통신할 때, 경계 방화벽(또는 리눅스 NAT 게이트웨이)은 내부 사설 IP를 외부 공인 IP로 변환하는 **SNAT(Source NAT / PAT)**를 수행합니다. 이때 단일 공인 IP가 가질 수 있는 TCP/UDP 포트 번호는 **16비트(0 ~ 65,535)**로 물리적인 수학적 상한선이 존재합니다.

### 1. NAT 포트 고갈(SNAT Port Exhaustion)의 메커니즘

네트워크 커널과 방화벽은 세션을 `[출발지 공인 IP, 출발지 포트, 목적지 공인 IP, 목적지 포트, 프로토콜]`이라는 **5-튜플(5-Tuple)** 조합으로 식별합니다.

* 만약 내부의 50대 WAS 서버가 동일한 외부 API 서버(`211.x.x.x:443`)로 동시에 초당 수천 건의 HTTPS 요청을 보낸다고 가정해 봅시다.
* 목적지 IP와 목적지 포트(`443`)가 모두 고정되어 있고, 출발지 공인 IP(`203.0.113.10`)마저 1개뿐이라면, 세션을 구분할 수 있는 변수는 오직 **출발지 포트(Source Port)** 하나뿐입니다.
* 시스템 예약 포트(0~1023)를 제외한 약 64,511개의 포트가 모두 사용 중이거나 `TIME_WAIT`(기본 60~120초) 상태로 묶여 있으면, 64,512번째 요청부터는 변환할 포트가 없어 방화벽이 패킷을 즉각 폐기(**Port Exhaustion**)합니다.

### 2. 단계별 해결 및 아키텍처 개선 방법

#### 1) 방화벽 SNAT IP Pool 확장 (가장 근본적인 해결책)
단일 공인 IP(Interface IP)로 NAT하는 대신, 보유한 공인 IP 대역 중 여러 개(예: 4~8개 IP)를 **IP Pool(Overload / Port Block Allocation)**로 묶어 아웃바운드 정책에 매핑합니다.
* 공인 IP를 4개만 묶어도 동일 목적지에 대해 $64,511 \times 4 = \text{약 } 258,000\text{개}$의 동시 세션을 처리할 수 있습니다.
* FortiGate 설정 예시:
  ```text
  config firewall ippool
      edit "SNAT-Outbound-Pool"
          set type overload
          set startip 203.0.113.10
          set endip 203.0.113.13
      next
  end
  ```

#### 2) 애플리케이션 레벨 HTTP Keep-Alive (Connection Pooling) 적용
매 API 호출마다 TCP 3-way 핸드셰이크와 SSL 핸드셰이크를 새로 맺고 끊으면 포트가 순식간에 `TIME_WAIT`로 소진됩니다. WAS의 HTTP 클라이언트(Apache HttpClient, OkHttp, WebClient 등)에서 **Persistent Connection(Keep-Alive)** 풀을 활성화하면 기존 TCP 소켓 1개 위로 수천 번의 요청을 재사용하므로 포트 고갈이 원천 해결됩니다.

#### 3) 리눅스 NAT 게이트웨이 커널 튜닝
`net.ipv4.ip_local_port_range = 1024 65535`로 가용 포트 범위를 최대로 넓히고, `net.ipv4.tcp_tw_reuse = 1`을 켜서 아웃바운드 연결 시 `TIME_WAIT` 상태 소켓을 안전하게 즉시 재활용하도록 구성합니다.

&nbsp;
&nbsp;

## 주의사항

1. **`tcp_tw_recycle` 파라미터는 최신 커널에서 절대 사용 금지**:
   * 과거 블로그나 문서에 나오는 `net.ipv4.tcp_tw_recycle = 1` 옵션은 NAT 환경에서 서로 다른 클라이언트의 TCP 타임스탬프가 어긋날 때 정상 패킷을 대량 드롭시키는 심각한 결함이 있어 Linux Kernel 4.12 버전부터 완전히 제거(Deprecated/Removed)되었습니다. 반드시 아웃바운드 전용으로 안전한 `tcp_tw_reuse = 1`만 사용해야 합니다.

2. **멀티 IP Pool 구성 시 외부 파트너사 화이트리스트(ACL) 사전 등록 필수**:
   * 외부 금융권이나 공공기관 API는 보안상 사전에 등록된 단일 공인 IP만 허용하는 경우가 많습니다. SNAT IP Pool에 4개의 공인 IP를 추가하기 전에 반드시 상대방 기관 방화벽에도 해당 IP 대역을 모두 화이트리스트로 등록 요청해야 합니다.

3. **단일 포트 블록 할당(PBA: Port Block Allocation) 적용 시 로그 추적성 확보**:
   * 수만 명의 사내 사용자 트래픽을 처리하는 환경에서는 특정 사용자 IP에 256개 또는 512개 단위의 포트 블록을 고정 배정하는 PBA 모드를 쓰면 방화벽 세션 생성 부하와 보안 감사 로그 용량을 크게 줄일 수 있습니다.