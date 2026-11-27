---
layout: article
title: 시스템 관리_75 Linux iptables 및 nftables 방화벽 규칙 우선순위 충돌과 패킷 드롭 추적 가이드
tags: [Linux, Security, Firewall, iptables, nftables, firewalld, Netfilter, Packet-Drop, TRACE, Troubleshooting]
keys: 261127-linux-network-075
---

- 출처 / 참고: Netfilter Project Documentation (iptables-extensions(8), nft(8)), Red Hat Enterprise Linux Securing Networks Guide (Using nftables and firewalld)

> 명령어: `iptables`, `nft`, `firewall-cmd`, `conntrack`, `dmesg`, `tcpdump`  
> 키워드: iptables, nftables, firewalld, Netfilter Hook, Rule Priority, DROP, REJECT, NFLOG, TRACE, DOCKER-USER  
> 사용처: 리눅스 서버에 방화벽 규칙(ALLOW)을 추가했음에도 불구하고 상위 규칙의 DROP/REJECT에 걸리거나 Docker/firewalld 규칙과 충돌하여 특정 포트 접속이 차단되는 장애 해결

---

> 실행예제

리눅스 서버에 방화벽 허용 규칙을 정상적으로 추가했으나 클라이언트에서 해당 포트로 여전히 접속이 거부될 때, 실제 커널 Netfilter 테이블에 적용된 규칙 순서(Line Number), 패킷 히트 카운터(Packet Counter), 그리고 `iptables`와 `nftables` 백엔드 혼용 충돌 여부를 진단합니다.

```bash
# 1. iptables 규칙을 줄 번호(--line-numbers) 및 패킷/바이트 카운터(-v)와 함께 조회
$ sudo iptables -L INPUT -n -v --line-numbers
# Chain INPUT (policy DROP 1420 packets, 85200 bytes)
# num   pkts bytes target     prot opt in     out     source               destination
# 1    45210 3840K ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
# 2      840 50400 REJECT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            reject-with icmp-host-prohibited
# 3        0     0 ACCEPT     tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:8080
# -> 2번 규칙(REJECT all)이 3번 규칙(ACCEPT tcp 8080)보다 위에 위치하여 8080 포트로 가는 패킷이 3번에 도달하기 전 2번에서 모두 차단됨!

# 2. Docker 실행 환경에서 외부 접근이 차단될 때 FORWARD 및 DOCKER-USER 체인 점검
$ sudo iptables -L DOCKER-USER -n -v --line-numbers
# -> Docker는 일반 INPUT 체인이 아니라 PREROUTING -> FORWARD -> DOCKER-USER 체인을 타므로 INPUT에 허용 규칙을 넣어도 효과가 없음

# 3. 최신 배포판(RHEL 8/9, Ubuntu 22.04+)에서 iptables-nft 백엔드와 순수 nftables 혼용 여부 확인
$ iptables -V
# iptables v1.8.8 (nf_tables)
$ sudo nft list ruleset | head -n 30
# -> firewalld가 생성한 nftables 테이블(inet firewalld)과 수동 iptables 규칙이 동시에 존재하여 패킷이 두 번 평가되는지 확인

# 4. 특정 포트(예: 8080)로 들어오는 패킷이 커널 Netfilter의 어느 체인/규칙에서 버려지는지 실시간 추적(TRACE)
$ sudo iptables -t raw -A PREROUTING -p tcp --dport 8080 -j TRACE
$ sudo modprobe nf_log_ipv4
$ sudo sysctl -w net.netfilter.nf_log.2=nf_log_ipv4
# 이후 다른 터미널에서 접속 시도 후 커널 로그에서 패킷 이동 경로 확인:
$ sudo dmesg -T | grep "TRACE:" | tail -n 10
# [Fri Nov 27 15:10:05 2026] TRACE: filter:INPUT:rule:2 IN=eth0 SRC=192.168.1.50 DST=192.168.1.10 PROTO=TCP DPT=8080
# -> filter 테이블의 INPUT 체인 2번 규칙에서 패킷이 종료됨을 100% 정확히 특정함 (확인 후 -D 옵션으로 TRACE 규칙 삭제 필수)
```

&nbsp;
&nbsp;

## 스크립트

리눅스 호스트에서 현재 활성화된 방화벽 백엔드(`firewalld`, `ufw`, `nftables`, `iptables`)의 충돌 여부를 식별하고, **`ACCEPT` 규칙보다 상위에 위치하여 트래픽을 가로채는 조기 `DROP`/`REJECT` 규칙(Shadowed Rules)**과 누적 패킷 드롭 카운터 상위 규칙을 자동 탐지해 주는 진단 쉘 스크립트입니다.

```bash
#!/bin/bash
# audit_linux_firewall_conflicts.sh - Detect firewall backend conflicts and shadowed DROP/REJECT rules

echo "=========================================="
echo " [Linux 방화벽 규칙 충돌 및 패킷 드롭 진단기]"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] 커널 Netfilter 규칙 검사를 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

# 1. 활성 방화벽 관리 데몬 중복 실행 점검
echo -e "\n[1] 방화벽 서비스 데몬 중복 활성화 점검:"
ACTIVE_FW=0
for SVC in firewalld ufw netfilter-persistent iptables nftables; do
    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        echo "  - 활성 서비스 감지: ${SVC}"
        ACTIVE_FW=$((ACTIVE_FW + 1))
    fi
done

if [ "$ACTIVE_FW" -gt 1 ]; then
    echo "  [치명적 경고] 2개 이상의 방화벽 관리 데몬이 동시에 실행 중입니다!"
    echo "  -> 규칙 덮어쓰기 및 우선순위 충돌의 주원인이므로 하나의 관리 도구로 통일하십시오."
elif [ "$ACTIVE_FW" -eq 0 ]; then
    echo "  - 별도 상위 데몬 없이 커널 직접 규칙(iptables/nft) 사용 중"
fi

# 2. iptables 버전 및 백엔드(legacy vs nf_tables) 확인
if command -v iptables &>/dev/null; then
    IPT_VER=$(iptables -V)
    echo -e "\n[2] iptables 바이너리 백엔드 정보:"
    echo "  - ${IPT_VER}"
fi

# 3. INPUT 및 FORWARD 체인에서 하위 ACCEPT 규칙을 가리는 조기 전체 차단(Catch-all DROP/REJECT) 탐지
echo -e "\n[3] 규칙 우선순위 충돌(Shadowed Rules) 검사:"
for CHAIN in INPUT FORWARD; do
    echo "  >> 체인 검사: ${CHAIN}"
    RULES_OUT=$(iptables -L "$CHAIN" -n -v --line-numbers 2>/dev/null)
    
    # 출발지/목적지가 모두 0.0.0.0/0 이고 프로토콜이 all 인 무조건 차단 규칙 번호 찾기
    CATCHALL_LINE=$(echo "$RULES_OUT" | awk '$4 ~ /^(DROP|REJECT)$/ && $5 == "all" && $8 == "0.0.0.0/0" && $9 == "0.0.0.0/0" {print $1; exit}')
    LAST_LINE=$(echo "$RULES_OUT" | awk 'END {print $1}')
    
    if [ -n "$CATCHALL_LINE" ] && [ -n "$LAST_LINE" ] && [ "$CATCHALL_LINE" -lt "$LAST_LINE" ]; then
        echo "    [!] 충돌 감지: ${CATCHALL_LINE}번 규칙(전체 DROP/REJECT)이 맨 마지막(${LAST_LINE}번)이 아닌 중간에 위치합니다!"
        echo "    -> ${CATCHALL_LINE}번 이후에 등록된 모든 허용(ACCEPT) 규칙은 무시됩니다."
    else
        echo "    [정상] 우선순위 가림 현상이 발견되지 않았습니다."
    fi
done

# 4. 실제로 패킷을 가장 많이 차단하고 있는 규칙 Top 5 추출
echo -e "\n[4] 누적 패킷 드롭(DROP/REJECT)이 발생 중인 규칙 목록:"
iptables -L -n -v --line-numbers 2>/dev/null | awk '$4 ~ /^(DROP|REJECT)$/ && $2 > 0 {printf "  - 줄번호: %-3s | 차단패킷: %-10s | 타겟: %-7s | 출발지: %-16s | 상세: %s %s\n", $1, $2, $4, $8, $10, $11}' | head -n 10

# 5. nftables 독립 테이블 공존 여부 확인
if command -v nft &>/dev/null; then
    NFT_TABLES=$(nft list tables 2>/dev/null)
    if [ -n "$NFT_TABLES" ]; then
        echo -e "\n[5] 커널 내 활성화된 nftables 테이블 목록:"
        echo "$NFT_TABLES" | sed 's/^/  - /'
    fi
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

리눅스 서버의 방화벽 트러블슈팅에서 가장 흔한 실수는 **"규칙을 추가(-A: Append)하기만 하고 전체 규칙의 평가 순서(Top-Down)와 상위 관리 데몬의 작동 방식을 간과하는 것"**입니다.

### 1. Netfilter 방화벽 규칙 충돌의 3대 핵심 원인

1. **`-A` (Append) 명령어로 인한 규칙 가림 (Shadowed Rules)**:
   * 방화벽은 위에서 아래로(1번 $\rightarrow$ 2번 $\rightarrow$ 3번) 순차적으로 매칭되며, **조건이 일치하는 첫 번째 규칙을 만나는 즉시 평가가 종료(First-Match Wins)**됩니다.
   * RHEL/CentOS 기본 방화벽이나 기존 보안 스크립트는 보통 맨 끝에 `REJECT all -- 0.0.0.0/0 0.0.0.0/0` 규칙을 두고 있습니다. 이때 관리자가 `iptables -A INPUT -p tcp --dport 8080 -j ACCEPT`로 규칙을 맨 뒤에 추가하면, 패킷은 `REJECT all`에 먼저 걸려 버려지므로 새 규칙은 영원히 실행되지 않습니다.
   * 반드시 `-I INPUT <줄번호>`(Insert)를 사용해 차단 규칙보다 위쪽에 삽입해야 합니다.
2. **Docker 컨테이너 포트와 호스트 방화벽(`INPUT` 체인) 우회 문제**:
   * Docker 엔진은 컨테이너 포트를 외부에 매핑(`-p 8080:80`)할 때, 호스트의 `INPUT` 체인을 거치지 않고 **`PREROUTING(DNAT)` $\rightarrow$ `FORWARD` $\rightarrow$ `DOCKER-USER` $\rightarrow$ `DOCKER`** 체인으로 패킷을 직접 라우팅합니다.
   * 따라서 일반 `INPUT` 체인이나 `ufw`에 차단 규칙을 걸어두어도 Docker 컨테이너 포트는 외부로 무방비 노출되며, 반대로 Docker 컨테이너 트래픽을 통제하려면 반드시 **`DOCKER-USER` 체인** 최상단에 규칙을 넣어야 합니다.
3. **`firewalld` / `ufw`와 수동 `iptables` / `nftables` 혼용 충돌**:
   * RHEL 8/9 및 Ubuntu 22.04 이상에서는 커널 기본 프레임워크가 레거시 `iptables`에서 **`nftables`**로 완전히 전환되었습니다.
   * `firewalld`가 `inet firewalld` 테이블을 관리하고 있는데 관리자가 터미널에서 `iptables`나 `nft` 명령어로 규칙을 수동 주입하면, `firewall-cmd --reload` 실행 시 수동 규칙이 모두 증발하거나 두 테이블 중 어느 한쪽의 기본 정책(`policy drop`)에 걸려 통신이 차단됩니다.

### 2. 안전한 규칙 삽입 및 `DOCKER-USER` 통제 예시

#### 1) 기존 차단 규칙 위쪽으로 정확한 위치 삽입 (`-I`)
```bash
# INPUT 체인의 2번 위치에 8080 포트 허용 규칙 삽입
sudo iptables -I INPUT 2 -p tcp --dport 8080 -j ACCEPT
```

#### 2) Docker 컨테이너 외부 접근 화이트리스트 통제 (`DOCKER-USER`)
```bash
# 허용된 관리망(10.10.0.0/16) 외에 외부(eth0)에서 컨테이너로 들어오는 모든 트래픽 차단
sudo iptables -I DOCKER-USER -i eth0 ! -s 10.10.0.0/16 -j DROP
```

&nbsp;
&nbsp;

## 주의사항

1. **원격 SSH 접속 상태에서 `policy DROP` 변경 시 영구 잠금(Lockout) 주의**:
   * SSH 포트(`22/tcp`) 및 기존 연결 유지(`ctstate ESTABLISHED,RELATED`) 허용 규칙을 먼저 등록하지 않은 상태에서 `iptables -P INPUT DROP`을 실행하는 순간 현재 접속된 SSH 세션이 즉각 끊어지며 서버에 다시는 접속할 수 없게 됩니다. 원격 방화벽 작업 시에는 항상 `at` 명령어나 백그라운드 `sleep 180 && iptables -F` 안전장치를 걸어둔 상태에서 테스트해야 합니다.

2. **`TRACE` 디버깅 규칙 사용 후 즉시 삭제 필수**:
   * 패킷 추적(`-j TRACE`)을 켜두면 해당 포트로 유입되는 모든 패킷마다 커널 링 버퍼(`/var/log/messages`, `dmesg`)에 수십 줄의 로그가 폭주하여 디스크 I/O 고갈 및 시스템 지연을 유발합니다. 원인 파악 직후 반드시 `-D` 옵션으로 추적 규칙을 제거해야 합니다.

3. **방화벽 설정 영구 저장(`iptables-save` / `nft list ruleset`)**:
   * CLI로 수정한 커널 규칙은 재부팅 시 초기화됩니다. `firewalld` 환경이라면 `firewall-cmd --runtime-to-permanent`를 실행하고, 순수 `iptables`/`nftables` 환경이라면 설정 파일(`/etc/sysconfig/iptables` 또는 `/etc/nftables.conf`)로 저장 후 부팅 시 자동 로드 서비스가 활성화되어 있는지 확인해야 합니다.