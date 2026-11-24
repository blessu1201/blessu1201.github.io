---
layout: article
title: 시스템 관리_69 백업 에이전트 Veeam 및 Bacula 네트워크 전송 병목과 타임아웃 장애 해결 가이드
tags: [Linux, Storage, Backup, Veeam, Bacula, Network-Bottleneck, TCP-Window, Time-Out, Troubleshooting]
keys: 261121-linux-storage-069
---

- 출처 / 참고: Veeam Backup & Replication User Guide (Network Mode NBD vs Direct SAN), Bacula Enterprise Troubleshooting Documentation, Linux Kernel TCP Tuning Guide

> 명령어: `ss`, `ethtool`, `iperf3`, `sysctl`, `tcpdump`, `netstat`  
> 키워드: Backup Agent, Veeam, Bacula, Network Bottleneck, NBD, Socket Timeout, TCP Window Scaling, Send-Q, Retransmission  
> 사용처: 대용량 백업 수행 중 네트워크 전송 지연(NBD 병목), 소켓 타임아웃 끊김 현상 진단 및 TCP 커널 파라미터 최적화

---

> 실행예제

대용량 백업 작업이 시작된 후 전송 속도가 수 MB/s 수준으로 급락하거나 백업 서버와 클라이언트 간 `Connection reset by peer` 및 `Socket read/write timeout` 에러가 발생하며 백업이 중단될 때, TCP 소켓 큐 정체와 패킷 재전송율을 점검합니다.

```bash
# 1. 백업 에이전트 포트의 TCP 소켓 송수신 대기열(Recv-Q / Send-Q) 및 혼잡 상태 확인
$ ss -tin state established '( dport = :9102 or sport = :9102 or dport = :2500 or sport = :2500 )'
# ESTAB   0      2621440    192.168.10.20:48120     192.168.10.50:2500
#         cubic wscale:7,7 rto:1200 rtt:45.2/12.1 ato:40 mss:1448 cwnd:10 retrans:42/8540
# -> Send-Q(송신 버퍼)가 2.6MB로 꽉 차 있고, retrans(패킷 재전송)가 8,540건 이상 발생하며 혼잡 윈도우(cwnd)가 10으로 축소됨

# 2. 시스템 전체 TCP 패킷 재전송율 및 소켓 버퍼 드롭 통계 확인
$ netstat -s | grep -iE "retransmitted|segments send out|packet receive errors|overflowed"
#     14502010 segments send out
#     245120 segments retransmitted
#     12405 times the listen queue of a socket overflowed
# -> 전체 패킷 대비 재전송 비율이 1.5%를 초과하여 백업 스트림 성능이 급감하는 상태 확인

# 3. 백업 전용 NIC의 물리 링크 속도, 듀플렉스 및 하드웨어 오프로드(TSO/GSO) 확인
$ ethtool eth1 | grep -iE "Speed|Duplex|Link detected"
#         Speed: 10000Mb/s
#         Duplex: Full
#         Link detected: yes
$ ethtool -k eth1 | grep -E "tcp-segmentation-offload|generic-segmentation-offload"

# 4. 백업 서버(Storage Node) 간 순수 네트워크 가용 대역폭 및 패킷 손실 측정 (iperf3)
# 백업 서버 측에서 'iperf3 -s' 실행 후 클라이언트에서 테스트:
$ iperf3 -c 192.168.10.50 -P 4 -t 10
# [SUM]   0.00-10.00  sec  1.12 GBytes   962 Mbits/sec  412             sender
# -> 10Gbps 회선임에도 실제 처리량이 1Gbps 미만으로 제한되고 다수의 재전송(Retr) 발생 확인
```

&nbsp;
&nbsp;

## 스크립트

리눅스 운영 서버에서 대용량 백업 데이터 전송 시 병목을 유발하는 커널 TCP 송수신 버퍼(`rmem_max`, `wmem_max`), 혼잡 제어 알고리즘(`BBR`), 그리고 소켓 백로그 큐를 진단하고 백업 최적화 값으로 영구 적용해 주는 튜닝 쉘 스크립트입니다.

```bash
#!/bin/bash
# tune_backup_network.sh - Diagnose backup network bottlenecks and optimize Linux TCP stack

BACKUP_TARGET_IP=${1:-""}

echo "=========================================="
echo " [대용량 백업 네트워크 병목 진단 및 TCP 튜닝]"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] 커널 네트워크 파라미터 변경을 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

# 1. 현재 커널 TCP 버퍼 및 혼잡 제어 알고리즘 점검
echo -e "\n[1] 현재 커널 네트워크 주요 파라미터:"
CUR_RMEM=$(sysctl -n net.core.rmem_max)
CUR_WMEM=$(sysctl -n net.core.wmem_max)
CUR_TCP_RMEM=$(sysctl -n net.ipv4.tcp_rmem)
CUR_TCP_WMEM=$(sysctl -n net.ipv4.tcp_wmem)
CUR_CC=$(sysctl -n net.ipv4.tcp_congestion_control)

echo "  - net.core.rmem_max           : ${CUR_RMEM} Bytes"
echo "  - net.core.wmem_max           : ${CUR_WMEM} Bytes"
echo "  - net.ipv4.tcp_rmem           : ${CUR_TCP_RMEM}"
echo "  - net.ipv4.tcp_wmem           : ${CUR_TCP_WMEM}"
echo "  - TCP 혼잡 제어 알고리즘      : ${CUR_CC}"

# 2. 패킷 재전송률 분석
echo -e "\n[2] TCP 패킷 재전송률(Retransmission) 분석:"
TCP_STATS=$(cat /proc/net/snmp | grep "^Tcp:" | tail -n 1)
OUT_SEGS=$(echo "$TCP_STATS" | awk '{print $12}')
RETRANS_SEGS=$(echo "$TCP_STATS" | awk '{print $13}')

if [ "${OUT_SEGS:-0}" -gt 0 ]; then
    RETRANS_RATE=$(awk "BEGIN {printf \"%.3f\", ($RETRANS_SEGS / $OUT_SEGS) * 100}")
    echo "  - 누적 송신 세그먼트 : ${OUT_SEGS}"
    echo "  - 재전송 세그먼트    : ${RETRANS_SEGS} (재전송률: ${RETRANS_RATE}%)"
    
    if [ $(awk "BEGIN {print ($RETRANS_RATE > 0.5)}") -eq 1 ]; then
        echo "  [경고] 재전송률이 0.5%를 초과했습니다! 스위치 버퍼 드롭 또는 케이블/MTU 불일치 의심."
    else
        echo "  [정상] 패킷 재전송률이 안정 범위 내에 있습니다."
    fi
fi

# 3. 대용량 백업 스트림 최적화 sysctl 설정 적용
echo -e "\n[3] 10Gbps+ 대용량 백업 전송을 위한 TCP 버퍼 확장 적용:"
SYSCTL_CONF="/etc/sysctl.d/99-backup-network-tuning.conf"

cat << 'EOF' > "$SYSCTL_CONF"
# High-Throughput Backup & Storage Network TCP Tuning
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
EOF

# BBR 혼잡 제어 모듈 지원 시 활성화
if modprobe tcp_bbr 2>/dev/null && grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control; then
    echo "net.core.default_qdisc = fq" >> "$SYSCTL_CONF"
    echo "net.ipv4.tcp_congestion_control = bbr" >> "$SYSCTL_CONF"
    echo "  - 최신 BBR 혼잡 제어 알고리즘 활성화 완료."
fi

sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
echo "  [성공] 영구 설정 파일(${SYSCTL_CONF}) 저장 및 커널 즉시 반영 완료."

# 4. 백업 서버 연결성 및 Keepalive 경로 테스트
if [ -n "$BACKUP_TARGET_IP" ]; then
    echo -e "\n[4] 백업 스토리지 노드(${BACKUP_TARGET_IP}) 라우팅 및 MTU 확인:"
    ip route get "$BACKUP_TARGET_IP" | sed 's/^/  /'
fi

echo -e "\n=========================================="
echo " [튜닝 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

엔터프라이즈 백업(Veeam, Bacula, NetBackup, Commvault) 환경에서 수십 TB의 데이터를 야간 백업 윈도우 내에 끝내지 못하고 타임아웃으로 실패하는 주원인은 스토리지 디스크 속도보다 **네트워크 전송 계층의 TCP 윈도우 제한 및 방화벽 유휴 세션 단절**에 있습니다.

### 1. 백업 전송 병목과 타임아웃의 3대 핵심 원인

1. **기본 TCP 송수신 버퍼(Socket Buffer)의 한계**:
   * 리눅스의 기본 `tcp_wmem` 최대값은 보통 4MB 수준입니다. 백업 데이터가 전용선이나 L3 스위치를 거쳐 수 ms의 지연 시간(RTT)을 가진 원격 백업 스토리지로 날아갈 때, 대역폭-지연 곱(BDP: Bandwidth-Delay Product)을 채우지 못해 10Gbps 회선임에도 속도가 수백 Mbps로 묶이는 현상이 발생합니다.
2. **제어 채널(Control Channel)의 방화벽 유휴 타임아웃 단절**:
   * 백업 솔루션은 데이터를 보내는 데이터 채널과 별개로 작업 상태를 주고받는 제어 채널(TCP 소켓)을 유지합니다. 대용량 파일 체크섬 계산이나 테이프/중복제거 인덱싱 동안 제어 채널에 패킷이 10~30분간 흐르지 않으면, 중간 방화벽이 이를 죽은 세션으로 간주하고 조용히 세션을 드롭시킵니다. 이후 백업 에이전트가 완료 신호를 보낼 때 `Connection timed out` 에러가 발생합니다.
3. **Veeam NBD(Network Block Device) 모드의 ESXi 관리 네트워크 포화**:
   * 가상화 백업 시 Direct SAN이나 HotAdd 대신 NBD 모드를 쓰면 ESXi 호스트의 Management VMkernel 포트(기본 1Gbps 또는 vmk0 공유)로 모든 백업 트래픽이 쏟아지면서 호스트 관리 지연 및 패킷 드롭을 유발합니다.

### 2. 단계별 해결 및 최적화 방법

#### 1) TCP Keepalive 단축을 통한 방화벽 세션 유지
제어 채널 소켓이 유휴 상태에서도 방화벽 세션 테이블에서 지워지지 않도록 리눅스 커널의 TCP Keepalive 주기를 기본 2시간(7200초)에서 60초로 단축합니다.
```bash
sudo sysctl -w net.ipv4.tcp_keepalive_time=60
sudo sysctl -w net.ipv4.tcp_keepalive_intvl=10
sudo sysctl -w net.ipv4.tcp_keepalive_probes=6
```

#### 2) BBR 혼잡 제어 알고리즘 적용
전통적인 `cubic` 알고리즘은 미세한 패킷 유실(0.1% 수준)만 발생해도 전송 윈도우를 절반으로 깎아버립니다. 구글이 개발한 `BBR(Bottleneck Bandwidth and RTT)`을 활성화하면 대역폭과 RTT를 직접 측정하여 백업 처리량을 극대화할 수 있습니다.

#### 3) 백업 전용 트래픽 격리 (Backup VLAN)
운영 서비스 NIC와 백업 트래픽 NIC를 물리적 또는 VLAN 레벨로 분리하고, 백업 백본 구간은 점보 프레임(MTU 9000)을 적용하여 CPU 인터럽트 부하를 줄입니다.

&nbsp;
&nbsp;

## 주의사항

1. **운영 DB/웹 서버에 과도한 TCP 버퍼 설정 시 메모리 압박 주의**:
   * `tcp_rmem`/`tcp_wmem`의 최대치를 64MB로 높였을 때, 수만 개의 동시 웹 세션을 처리하는 프론트엔드 서버에서는 커널 소켓 메모리(`slab`) 점유율이 급증할 수 있습니다. 백업 전용 노드나 내부 백본 인터페이스를 가진 서버 위주로 적용해야 합니다.

2. **소프트웨어 압축/암호화 위치 선정**:
   * 백업 에이전트(클라이언트) 측에서 최고 수준의 압축과 AES 암호화를 동시에 켜면 네트워크 병목이 해소되기도 전에 클라이언트 CPU가 100% 포화되어 백업 속도가 떨어집니다. 네트워크 대역폭이 충분(10Gbps 이상)하다면 압축 레벨을 낮추고 다중 스트림(Multi-stream) 개수를 늘리는 것이 훨씬 유리합니다.

3. **백업 스케줄 중첩(Overlap) 방지**:
   * 동일 스토리지 풀을 바라보는 수십 대의 서버가 정각(예: 00:00)에 일제히 백업을 시작하면 스위치 업링크 버퍼 오버플로우로 패킷 재전송이 폭발합니다. 15~30분 단위로 백업 시작 시간을 분산(Staggering) 배치해야 합니다.