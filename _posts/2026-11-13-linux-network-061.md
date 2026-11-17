---
layout: article
title: 시스템 관리_61 FortiGate 방화벽 세션 테이블 풀 Session Exhaustion 원인 분석 및 신규 연결 차단 해결 가이드
tags: [Network, Firewall, FortiGate, FortiOS, Session-Exhaustion, Conserve-Mode, TCP-Timeout, DDoS, Troubleshooting]
keys: 261113-linux-network-061
---

- 출처 / 참고: Fortinet Knowledge Base (Technical Tip: FortiGate session table troubleshooting, Conserve Mode troubleshooting - FD33103)

> 명령어: `diagnose sys session`, `get system performance status`, `diagnose sys top`, `config system session-ttl`  
> 키워드: FortiGate, Session Exhaustion, Conserve Mode, Session Table Full, session-ttl, SYN Flood, UDP Timeout, Orphaned Session  
> 사용처: 외부 웹 트래픽 급증이나 내부 서버의 비정상 소켓 누수로 방화벽 세션 한도가 고갈되어 신규 인터넷/서비스 접속이 모두 차단되는 장애 복구

---

> 실행예제

사내망이나 IDC 방화벽(FortiGate)을 통과하는 모든 신규 웹/DB 연결이 갑자기 타임아웃되거나 드롭될 때, 방화벽 CLI에 접속하여 전체 세션 점유율, 컨저브 모드(Conserve Mode) 진입 여부, 그리고 세션을 독점하는 출발지/목적지 IP를 진단합니다.

```bash
# 1. 방화벽 시스템 성능 및 메모리/세션 한계 상태 확인
$ get system performance status
# CPU states: 15% user 5% system 0% nice 80% idle
# Memory: 8192MB total, 7250MB used (88.5%), 942MB free (11.5%)
# Average network usage: 450 / 320 kbps in 1 minute
# Average sessions: 985420 sessions in 1 minute
# -> 메모리가 88%를 돌파하며 방화벽이 보호 모드(Conserve Mode)에 진입했거나 세션 한도에 도달함

# 2. 현재 활성 세션 요약 및 세션 테이블 가득 참(clash / drop) 통계 확인
$ diagnose sys session stat
# misc info:       session_count=998420 setup_rate=4520 exp_count=120
#         clash=15420 memory_tension_drop=8940 ephemeral=0/262144 removeable=0
# delete=4120, flush=0, dev_down=0/0
# TCP sessions:
#          120450 in ESTABLISHED state
#          820150 in TIME_WAIT state
#          45120 in SYN_RECV state
# -> TIME_WAIT 및 SYN_RECV 세션이 86만 개 이상 쌓여 세션 테이블(100만 개)을 고갈시킴 확인

# 3. 방화벽 보호 모드(Conserve Mode) 활성화 여부 직접 확인
$ diagnose hardware sysinfo conserve
# memory conserve mode:                        on
# total RAM:                                   8192 MB
# memory used:                                 7250 MB   88% of total RAM
# memory used + threshold red:                 7208 MB   88% of total RAM
# -> memory conserve mode가 'on' 상태이면 신규 세션 생성이 전면 차단(Fail-Close)됨

# 4. 세션을 가장 많이 점유하고 있는 악성/누수 출발지 IP Top 리스트 추출
$ diagnose sys session filter clear
$ diagnose sys session list | grep -E "hook=pre|state=" | head -n 20
```

&nbsp;
&nbsp;

## 스크립트

리눅스 클라이언트/서버 또는 관리 배스천 호스트에서 SSH를 통해 FortiGate 방화벽의 세션 통계와 컨저브 모드 상태를 원격으로 수집/파싱하고, 비정상적인 세션 급증(SYN Flood 또는 대량 유휴 세션 누적) 시 긴급 세션 초기화(Flush) 및 TTL 단축 명령어를 생성해 주는 진단 쉘 스크립트입니다.

```bash
#!/bin/bash
# check_fortigate_sessions.sh - Remote diagnostic script for FortiGate Session Exhaustion

FG_HOST=${1:-"192.168.1.254"}
FG_USER=${2:-"admin"}

echo "=========================================="
echo " [FortiGate 방화벽 세션 고갈 및 보호모드 진단]"
echo " 대상 방화벽: ${FG_HOST}"
echo "=========================================="

if ! command -v ssh &>/dev/null; then
    echo "  [오류] ssh 클라이언트가 설치되어 있지 않습니다."
    exit 1
fi

echo "  방화벽 CLI에서 세션 통계 수집 중..."

# SSH를 통한 원격 진단 명령 일괄 실행 (키 인증 또는 패스워드 프롬프트)
DIAG_OUTPUT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${FG_USER}@${FG_HOST}" << 'EOF'
get system performance status
diagnose sys session stat
diagnose hardware sysinfo conserve
EOF
)

if [ -z "$DIAG_OUTPUT" ]; then
    echo "  [오류] 방화벽 CLI 접속에 실패했습니다. SSH 접근 권한 및 네트워크를 확인하십시오."
    exit 1
fi

echo -e "\n[1] 세션 및 메모리 상태 분석 결과:"
SESS_COUNT=$(echo "$DIAG_OUTPUT" | grep -oE "session_count=[0-9]+" | cut -d'=' -f2)
MEM_DROP=$(echo "$DIAG_OUTPUT" | grep -oE "memory_tension_drop=[0-9]+" | cut -d'=' -f2)
CONSERVE_STATE=$(echo "$DIAG_OUTPUT" | grep -i "memory conserve mode:" | awk -F':' '{print $2}' | tr -d ' ')

echo "  - 현재 총 활성 세션 수     : ${SESS_COUNT:-"파싱실패"} 개"
echo "  - 메모리 부족 드롭 패킷 수 : ${MEM_DROP:-0} 건"
echo "  - 메모리 컨저브 모드 상태  : ${CONSERVE_STATE:-"알 수 없음"}"

echo -e "\n[2] TCP 상태별 세션 분포:"
echo "$DIAG_OUTPUT" | grep -E "in (ESTABLISHED|SYN_RECV|TIME_WAIT|FIN_WAIT) state" | sed 's/^/  /'

echo -e "\n[3] 진단 판정 및 긴급 복구 가이드:"
if [ "$CONSERVE_STATE" = "on" ]; then
    echo "  [치명적 위험] 방화벽이 Memory Conserve Mode에 진입했습니다!"
    echo "  -> 원인: 세션 테이블 폭증으로 RAM 점유율이 Red 임계치(88%)를 초과했습니다."
    echo "  -> 긴급 조치 1: 불필요한 세션 일괄 초기화"
    echo "     diagnose sys session clear"
    echo "  -> 긴급 조치 2: 기본 세션 만료 시간(TTL) 단축 (3600초 -> 300초)"
    echo "     config system session-ttl"
    echo "         set default 300"
    echo "     end"
else
    echo "  [정상] 현재 방화벽은 정상 작동 모드(Conserve Mode OFF)입니다."
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

방화벽(FortiGate 등)은 통과하는 모든 네트워크 연결(TCP, UDP, ICMP)의 출발지/목적지 IP, 포트, 상태 정보를 메모리의 **세션 테이블(Session Table)**에 기록하는 상태 기반(Stateful) 장비입니다. 장비의 하드웨어 모델마다 허용 가능한 최대 세션 수와 RAM 한계가 정해져 있으며, 이 한계를 초과하면 서비스 전체가 마비됩니다.

### 1. 세션 테이블 고갈의 3대 핵심 원인

1. **과도하게 긴 기본 세션 TTL (Time-To-Live)**:
   * FortiGate의 기본 TCP 세션 만료 시간(`session-ttl`)은 **3,600초(1시간)**입니다.
   * 웹 크롤러, 헬스체크, API 게이트웨이 등에서 수만 건의 연결을 맺은 뒤 정상 종료 패킷(`FIN`) 없이 소켓만 닫아버리면, 방화벽은 1시간 동안 죽은 세션을 메모리에 붙잡고 있게 되어 테이블이 폭발합니다.
2. **DDoS / SYN Flood 및 대량 포트 스캐닝 공격**:
   * 외부 공격자가 불완전한 TCP 핸드셰이크(`SYN`)를 초당 수만 건씩 쏟아부어 `SYN_RECV` 상태의 반열림(Half-Open) 세션이 세션 테이블을 100% 점유하는 경우입니다.
3. **내부 애플리케이션의 커넥션 풀(Connection Pool) 무한 재시도 버그**:
   * 내부 WAS나 배치 서버가 외부 API나 DB 접속이 막혔을 때 백오프(Backoff) 지연 없이 초당 수천 번씩 무한 재접속을 때려 방화벽 세션을 고갈시키는 경우입니다.

### 2. Conserve Mode(보호 모드) 동작 메커니즘

세션 수가 폭증하여 방화벽 RAM 사용률이 임계치에 도달하면 장비는 커널 패닉을 막기 위해 보호 모드에 들어갑니다.
* **Green 임계치 (82% 미만)**: 정상 동작.
* **Red 임계치 (88% 도달)**: **Conserve Mode 진입**. 장비가 새로운 세션을 전혀 생성하지 않고 패킷을 버리며(`Fail-Close`), 관리자 콘솔 접속마저 극도로 느려집니다.
* **Extreme 임계치 (95% 도달)**: 새로운 세션뿐만 아니라 기존 세션까지 강제 파기하기 시작합니다.

### 3. 단계별 긴급 복구 및 예방 튜닝

#### 1) 악성 IP 특정 후 해당 IP 세션만 선별 삭제
전체 세션을 지우면 정상적인 DB/SSH 연결까지 끊기므로, 트래픽을 유발하는 특정 IP 필터를 걸어 제거합니다.

```text
diagnose sys session filter clear
diagnose sys session filter src 203.0.113.55
diagnose sys session clear
```

#### 2) 전역 세션 만료 시간(TTL) 현실화
웹 트래픽 위주의 구간에서는 유휴 세션을 빠르게 회수하도록 기본 TTL을 3,600초에서 300~600초로 줄입니다.

```text
config system session-ttl
    set default 600
    config port
        edit 1
            set protocol 6
            set timeout 300
            set start-port 80
            set end-port 443
        next
    end
end
```

#### 3) DoS 정책(DoS Policy) 활성화를 통한 SYN Flood 방어
물리 인터페이스 인입 단에서 출발지 IP당 초당 허용 가능한 `tcp_syn_flood` 임계치를 걸어 세션 테이블 진입 전 하드웨어(NP6/NP7) 레벨에서 차단합니다.

&nbsp;
&nbsp;

## 주의사항

1. **`diagnose sys session clear` (전체 초기화) 실행 시 주의**:
   * 필터를 걸지 않고 전체 세션을 초기화하면 방화벽을 통과 중인 모든 장시간 TCP 세션(데이터베이스 풀, SSH 원격 관리 세션, 파일 전송)이 즉시 끊어집니다. 최후의 비상 상황에서만 사용해야 합니다.

2. **장시간 유휴 연결이 필요한 ERP/DB 정책은 별도 TTL 예외 처리**:
   * 전역 `session-ttl`을 300초로 줄이면, 쿼리 없이 5분 이상 대기하는 ERP 클라이언트나 DB 커넥션 풀의 연결이 방화벽에 의해 중간에 잘려나갈 수 있습니다. 해당 서비스 포트(예: TCP 1521, 1433, 3306)는 방화벽 정책(Firewall Policy) 개별 항목에서 `set session-ttl 7200`으로 길게 예외 설정해야 합니다.

3. **컨저브 모드 진입 임계치 임의 상향 금지**:
   * 경고를 피하려고 Red 임계치를 95% 이상으로 억지로 높여두면, 트래픽 폭증 시 방화벽 OS 자체가 OOM(Out of Memory)으로 리부팅되어 네트워크 전체가 수 분간 완전 블랙아웃(Blackout)되는 더 큰 사고가 발생합니다.