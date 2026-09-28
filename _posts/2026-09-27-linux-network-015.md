---
layout: article
title: 시스템 관리_15 "iptables 및 nftables 로깅을 활용한 리눅스 패킷 드롭(Dropped Packets) 디버깅 완벽 가이드"
tags: [Linux, Network, iptables, nftables, Firewall, Packet-Drop, Kernel-Log, dmesg]
keys: 260927-linux-network-015
---

- 출처 / 참고: Linux man-pages (iptables-extensions(8), nft(8)), Netfilter Documentation (Logging subsystem)

> 명령어: `iptables`, `nft`, `dmesg`, `journalctl`, `conntrack`, `dropwatch`  
> 키워드: Dropped Packets, iptables LOG target, nftables log prefix, NFLOG, TCP RST, conntrack invalid  
> 사용처: 방화벽 정책에 의한 원인 미상의 네트워크 단절 추적, 비정상 연결 드롭 진단, 보안 감사 로깅 설정  

---

> 실행예제

특정 패킷이 방화벽 규칙에 의해 조용히 버려지고 있는지(Silent Drop) 확인하기 위해 드롭 직전에 LOG 타깃/문(statement)을 주입하고 커널 로그 링버퍼를 실시간으로 모니터링합니다.

```bash
# 1. iptables: 특정 포트(예: 8080) 또는 INPUT 체인 맨 끝 DROP 직전에 LOG 규칙 삽입
$ sudo iptables -I INPUT 1 -p tcp --dport 8080 -m limit --limit 5/min -j LOG --log-prefix "[IPTABLES-DROP-8080]: " --log-level 4

# 2. nftables: 기존 체인에 패킷 드롭 전 로깅 룰 추가
$ sudo nft add rule inet filter input tcp dport 8080 log prefix \"[NFTABLES-DROP-8080]: \" drop

# 3. 실시간 커널 로그 추적 (dmesg 또는 journalctl)
$ sudo dmesg -wT | grep -E 'IPTABLES|NFTABLES'
# 또는
$ sudo journalctl -kf | grep -E 'IPTABLES|NFTABLES'

# [출력 예시]
# [Sun Sep 28 15:30:12 2026] [IPTABLES-DROP-8080]: IN=eth0 OUT= MAC=52:54:00:12:34:56:52:54:00:ab:cd:ef:08:00 SRC=192.168.1.50 DST=192.168.1.100 LEN=60 TOS=0x00 PREC=0x00 TTL=64 ID=41235 DF PROTO=TCP SPT=54210 DPT=8080 WINDOW=64240 RES=0x00 SYN URGP=0

# 4. conntrack에서 INVALID 상태로 드롭되는 패킷 추적
$ sudo conntrack -E -e DESTROY -p tcp
```

&nbsp;
&nbsp;

## 스크립트

현재 시스템이 레거시 `iptables` 환경인지 최신 `nftables` 환경인지 감지하여, 특정 포트에 대한 임시 디버깅용 로깅 규칙을 안전하게 주입하고 커널 로그를 모니터링할 수 있도록 돕는 쉘 스크립트입니다.

```bash
#!/bin/bash
# trace_packet_drops.sh - Inject temporary firewall logging and monitor packet drops

ACTION=${1:-"start"}
TARGET_PORT=${2:-"8080"}
LOG_PREFIX="[FW-DROP-DEBUG]: "

if [ "$EUID" -ne 0 ]; then
    echo "오류: 루트(root) 권한으로 실행해야 합니다."
    exit 1
fi

check_backend() {
    if nft list tables &>/dev/null && [ $(nft list tables | wc -l) -gt 0 ]; then
        echo "nftables"
    else
        echo "iptables"
    fi
}

BACKEND=$(check_backend)

case "$ACTION" in
    start)
        echo "=========================================="
        echo " [패킷 드롭 로깅 시작] Backend: ${BACKEND}, Port: ${TARGET_PORT}"
        echo "=========================================="

        if [ "$BACKEND" == "nftables" ]; then
            # nftables 디버그용 별도 체인 및 룰 추가
            nft add table inet debug_trace 2>/dev/null || true
            nft add chain inet debug_trace prerouting '{ type filter hook prerouting priority -150; }' 2>/dev/null || true
            nft flush chain inet debug_trace prerouting
            nft add rule inet debug_trace prerouting tcp dport "$TARGET_PORT" limit rate 10/minute log prefix "\"$LOG_PREFIX\""
            echo "  -> nftables inet debug_trace 테이블에 로깅 규칙이 주입되었습니다."
        else
            # iptables INPUT 최상단에 limit가 걸린 LOG 규칙 주입
            iptables -I INPUT 1 -p tcp --dport "$TARGET_PORT" -m limit --limit 10/min -j LOG --log-prefix "$LOG_PREFIX" --log-level 4
            echo "  -> iptables INPUT 체인 1번에 로깅 규칙이 주입되었습니다."
        fi

        echo -e "\n실시간 로그 모니터링을 시작합니다 (종료: Ctrl+C)..."
        echo "추적 중: dmesg | grep '$LOG_PREFIX'"
        dmesg -wT | grep --line-buffered "$LOG_PREFIX"
        ;;

    stop)
        echo "=========================================="
        echo " [패킷 드롭 로깅 해제] Backend: ${BACKEND}"
        echo "=========================================="

        if [ "$BACKEND" == "nftables" ]; then
            nft delete table inet debug_trace 2>/dev/null || true
            echo "  -> nftables inet debug_trace 테이블을 제거했습니다."
        else
            while iptables -D INPUT -p tcp --dport "$TARGET_PORT" -m limit --limit 10/min -j LOG --log-prefix "$LOG_PREFIX" --log-level 4 2>/dev/null; do
                :
            done
            echo "  -> iptables INPUT 체인의 디버그 LOG 규칙을 제거했습니다."
        fi
        ;;

    *)
        echo "사용법: sudo $0 {start|stop} [포트번호]"
        echo "예시  : sudo $0 start 8080"
        echo "        sudo $0 stop 8080"
        exit 1
        ;;
esac
```

&nbsp;
&nbsp;

## 해설

네트워크 통신 중 `Connection timed out`이 발생하거나 패킷이 도달하지 못할 때, 방화벽 규칙이 패킷을 버리고 있는지 확인하는 가장 확실한 방법은 **드롭 직전 패킷 정보를 커널 로그에 기록하는 것**입니다.

### 1. iptables의 `LOG` 타깃 동작 원리

* `LOG`는 `DROP`이나 `ACCEPT`와 같은 종단 타깃(Terminating target)이 아닙니다. 즉, 패킷을 로깅한 후에도 패킷은 체인의 다음 규칙으로 계속 평가가 이어집니다.
* 따라서 실제 패킷을 버리면서 기록을 남기려면 반드시 **LOG 규칙을 DROP 규칙 바로 위(앞순서)**에 배치해야 합니다.
  ```text
  [규칙 N  ] -p tcp --dport 8080 -j LOG --log-prefix "[DROP]: "
  [규칙 N+1] -p tcp --dport 8080 -j DROP
  ```
* 로그 플러딩(Log Flooding) 방지를 위해 반드시 `-m limit --limit 5/min`과 같은 레이트 리밋 모듈을 함께 사용해야 디스크 I/O 고갈을 방지할 수 있습니다.

### 2. nftables의 `log` 문(Statement) 동작 원리

* `nftables`에서는 `log`가 별도의 타깃이 아닌 단일 액션 문장(Action statement)으로 취급되므로, **하나의 규칙 내에서 로깅과 드롭을 동시에 처리**할 수 있습니다.
  ```text
  nft add rule inet filter input tcp dport 8080 log prefix "DROPPED: " drop
  ```
* `nftables`는 메타데이터와 패킷 헤더 구조화 능력이 뛰어나며, 고성능 처리가 필요한 대용량 트래픽 환경에서는 `NFLOG` 서브시스템을 통해 유저스페이스 데몬(`ulogd2`)으로 로그 처리를 위임할 수 있습니다.

### 3. 주요 로그 필드 분석

* `IN=`, `OUT=`: 패킷이 유입된 인터페이스(`eth0`)와 목적지 인터페이스.
* `SRC=`, `DST=`: 출발지 IP와 도착지 IP.
* `PROTO=`: 프로토콜(TCP, UDP, ICMP 등).
* `SPT=`, `DPT=`: 출발지 포트와 도착지 포트.
* `SYN`, `ACK`, `RST`: TCP 플래그 상태. (예: `SYN`만 켜져 있다면 초기 연결 시도 패킷)

&nbsp;
&nbsp;

## 주의사항

1. **로그 폭주(Log Flooding)로 인한 서비스 장애 위험**:
   * 대규모 트래픽이 유입되는 상황에서 `limit` 없이 모든 드롭 패킷을 로깅하면 `/var/log/syslog` 또는 `/var/log/messages` 파일 용량이 순식간에 차올라 디스크 풀(Disk Full) 장애가 발생하거나 klogd가 CPU를 100% 점유할 수 있습니다. 항상 `limit`을 걸거나 디버깅 직후 즉시 규칙을 제거해야 합니다.

2. **규칙 순서(Rule Ordering)의 중요성**:
   * iptables는 위에서부터 순차 평가됩니다. 이미 앞단에서 `DROP`되거나 `REJECT`된 패킷은 체인 뒤쪽에 LOG 규칙을 추가해도 도달하지 않아 로그에 찍히지 않습니다. 로깅 규칙은 반드시 의심되는 DROP 규칙 바로 앞이나 체인 최상단에 `-I`(Insert)로 삽입해야 합니다.

3. **`conntrack` 테이블 고갈(Table Full)에 의한 드롭**:
   * 방화벽 명시적 규칙 외에도 리눅스 커널의 연결 추적 모듈(`nf_conntrack`) 용량이 가득 찰 경우 커널이 임의로 패킷을 드롭합니다. `dmesg | grep "nf_conntrack: table full"` 로그가 찍히는지 확인하고, 필요시 `sysctl net.netfilter.nf_conntrack_max` 값을 증설해야 합니다.