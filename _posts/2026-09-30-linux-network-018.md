---
layout: article
title: 시스템 관리_18 TCP 소켓 누적 문제 해결 TIME_WAIT 및 CLOSE_WAIT 원인 분석과 완벽 대응 가이드
tags: [Linux, Network, TCP, Socket, TIME_WAIT, CLOSE_WAIT, Sysctl, Troubleshooting]
keys: 260930-linux-network-018
---

- 출처 / 참고: Linux Kernel Documentation (ip-sysctl.rst), RFC 793 (Transmission Control Protocol)

> 명령어: `ss`, `netstat`, `lsof`, `sysctl`, `gdb`, `pstack`  
> 키워드: TCP 4-Way Handshake, TIME_WAIT, CLOSE_WAIT, tcp_tw_reuse, File Descriptor Leak, Socket Exhaustion  
> 사용처: 대용량 트래픽 웹 서버의 로컬 포트 고갈 방지, 애플리케이션 연결 누수(Connection Leak) 디버깅 및 커널 튜닝

---

> 실행예제

현재 시스템 전체의 TCP 소켓 상태별 개수를 파악하고, `TIME_WAIT` 또는 `CLOSE_WAIT` 상태로 장시간 점유 중인 프로세스와 포트를 추적합니다.

```bash
# 1. 시스템 전체의 TCP 소켓 상태 요약 확인
$ ss -s
Total: 1425
TCP:   12530 (estab 420, closed 11800, orphaned 0, timewait 11500)
# -> timewait 수치가 비정상적으로 높거나 closed 상태가 과도한지 확인

# 2. 상태별(TIME-WAIT, CLOSE-WAIT 등) 소켓 수 카운트
$ ss -tan | awk '{print $1}' | sort | uniq -c | sort -nr
  11520 TIME-WAIT
   1240 CLOSE-WAIT
    420 ESTAB
     32 LISTEN

# 3. CLOSE_WAIT 상태를 유지하고 있는 특정 프로세스(PID) 및 포트 식별
$ sudo ss -tonp state close-wait
Recv-Q  Send-Q   Local Address:Port     Peer Address:Port   Process
1       0        192.168.1.100:8080     192.168.1.50:45120  users:(("java",pid=3456,fd=215))
# -> Recv-Q에 읽지 않은 버퍼가 남아있는지, 어떤 PID와 파일 디스크립터(FD)인지 확인

# 4. 시스템의 사용 가능한 로컬 포트(Ephemeral Port) 범위 및 현재 커널 파라미터 확인
$ sysctl net.ipv4.ip_local_port_range
net.ipv4.ip_local_port_range = 32768    60999
$ sysctl net.ipv4.tcp_tw_reuse
net.ipv4.tcp_tw_reuse = 2
```

&nbsp;
&nbsp;

## 스크립트

현재 시스템의 TCP 상태를 전수 조사하여 임계치를 초과한 `TIME_WAIT`와 애플리케이션 버그로 인한 `CLOSE_WAIT` 유발 프로세스를 즉시 식별하는 점검 쉘 스크립트입니다.

```bash
#!/bin/bash
# check_tcp_sockets.sh - Monitor TIME_WAIT and CLOSE_WAIT socket states

TW_THRESHOLD=${1:-5000}
CW_THRESHOLD=${2:-50}

echo "=========================================="
echo " [TCP 소켓 상태 진단 시작]"
echo " TIME_WAIT 경고 기준: ${TW_THRESHOLD}개"
echo " CLOSE_WAIT 경고 기준: ${CW_THRESHOLD}개"
echo "=========================================="

# 1. 소켓 상태별 집계
echo -e "\n[1] 상태별 TCP 소켓 개수:"
SOCKET_STATS=$(ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -nr)
echo "$SOCKET_STATS"

TW_COUNT=$(echo "$SOCKET_STATS" | awk '$2=="TIME-WAIT" {print $1}')
CW_COUNT=$(echo "$SOCKET_STATS" | awk '$2=="CLOSE-WAIT" {print $1}')

TW_COUNT=${TW_COUNT:-0}
CW_COUNT=${CW_COUNT:-0}

# 2. TIME_WAIT 상태 분석
echo -e "\n[2] TIME_WAIT 상태 점검 (현재: ${TW_COUNT}개):"
if [ "$TW_COUNT" -gt "$TW_THRESHOLD" ]; then
    echo "  [경고] TIME_WAIT 소켓이 과도하게 누적되어 로컬 포트 고갈 위험이 있습니다."
    
    # 커널 파라미터 점검
    REUSE_STATUS=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null)
    echo "  - net.ipv4.tcp_tw_reuse 설정값: ${REUSE_STATUS}"
    if [ "$REUSE_STATUS" -eq 0 ]; then
        echo "  -> tcp_tw_reuse가 비활성화(0)되어 있습니다. 활성화(1 또는 2) 검토가 필요합니다."
    fi
else
    echo "  [정상] TIME_WAIT 개수가 임계치 이하로 유지되고 있습니다."
fi

# 3. CLOSE_WAIT 상태 및 원인 프로세스 추적
echo -e "\n[3] CLOSE_WAIT 상태 점검 (현재: ${CW_COUNT}개):"
if [ "$CW_COUNT" -gt "$CW_THRESHOLD" ]; then
    echo "  [위험] CLOSE_WAIT 누적이 감지되었습니다! (애플리케이션 소켓 미종료 버그 가능성)"
    echo "  -> 누적을 유발하는 상위 프로세스 목록:"
    
    sudo ss -tanp state close-wait | awk 'NR>1 {print $6}' | cut -d',' -f1 | sort | uniq -c | sort -nr | head -n 5 | sed 's/^/     /'
    
    echo -e "\n  -> Recv-Q 버퍼가 비워지지 않은 연결 확인:"
    sudo ss -tanp state close-wait | awk '$2 > 0 {printf "     PID/Process: %-20s Recv-Q: %s\n", $6, $2}' | head -n 5
else
    echo "  [정상] CLOSE_WAIT 상태가 정상 범위입니다."
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

`TIME_WAIT`와 `CLOSE_WAIT`는 TCP 연결 종료 과정(4-Way Handshake) 중 서로 다른 주체에서 발생하는 정상적인 상태 머신이지만, 비정상적으로 누적될 경우 파일 디스크립터(FD) 고갈이나 로컬 포트 고갈(Port Exhaustion)을 초래합니다.

### 1. TIME_WAIT와 CLOSE_WAIT의 핵심 차이

| 구분 | 발생 주체 | 머무르는 이유 | 주된 해결 영역 |
| :--- | :--- | :--- | :--- |
| **`TIME_WAIT`** | **Active Closer** (먼저 `FIN`을 보낸 쪽) | 지연 패킷 수신 및 상대방의 마지막 `ACK` 유실 대비 | **커널 파라미터 튜닝** 및 Keep-Alive 설정 |
| **`CLOSE_WAIT`** | **Passive Closer** (상대의 `FIN`을 받은 쪽) | 로컬 애플리케이션이 `close()`를 호출할 때까지 대기 | **애플리케이션 코드 수정** (소켓 누수 버그) |

### 2. TIME_WAIT 누적 원인 및 해결

* **발생 원인**:
  * HTTP 단발성 연결(Keep-Alive 미사용) 또는 마이크로서비스 간 빈번한 짧은 커넥션 연결/해제 시, 연결을 먼저 끊는 서버(예: Reverse Proxy인 Nginx 또는 외부 API를 호출하는 백엔드) 측에 대량 생성됩니다.
  * 리눅스 기본 `2MSL`(Maximum Segment Lifetime)은 60초이므로, 초당 연결 종료량이 많으면 소켓이 60초간 쌓여 사용 가능한 클라이언트 포트를 소진합니다.
* **해결 방법**:
  1. **HTTP Keep-Alive 활성화**: 매 요청마다 연결을 맺고 끊지 않도록 커넥션 풀(Connection Pool)을 유지합니다.
  2. **커널 파라미터 조정**:
     * `net.ipv4.tcp_tw_reuse = 1` (또는 Linux 5.x+ 기본값 `2`): 발신용 아웃바운드 소켓에 한해 안전하게 `TIME_WAIT` 소켓을 재사용하도록 설정합니다.
     * `net.ipv4.ip_local_port_range = 10240 65535`: 가용 로컬 포트 대역을 확장합니다.

### 3. CLOSE_WAIT 누적 원인 및 해결

* **발생 원인**:
  * 상대방은 이미 `FIN`을 보내 연결 종료를 선언했으나, 내 서버의 애플리케이션 프로세스(Java, Node.js, Python 등)가 `read() == -1` (EOF) 신호를 감지하고도 대응하는 `close()` 시스템 콜을 호출하지 않고 방치할 때 발생합니다.
  * DB 커넥션 풀 타임아웃 미설정, 서드파티 HTTP Client 예외 처리 누락, 데드락(Deadlock)에 빠진 스레드 등이 원인입니다.
* **해결 방법**:
  * **커널 파라미터로는 해결 불가능**: 운영체제는 애플리케이션이 스스로 소켓을 닫지 않는 한 강제로 회수할 수 없습니다.
  * 해당 PID 프로세스의 스레드 덤프(`jstack`, `pstack`)를 분석하여 소켓 I/O 대기 상태인 스레드를 찾고 소스 코드 상에서 `try-with-resources` 또는 명시적인 `socket.close()` 처리를 구현해야 합니다.
  * 임시 응급 조치는 문제가 되는 프로세스를 재기동하는 방법뿐입니다.

&nbsp;
&nbsp;

## 주의사항

1. **`tcp_tw_recycle` 옵션 절대 사용 금지**:
   * 구형 블로그 등에서 `net.ipv4.tcp_tw_recycle = 1` 설정을 권장하는 경우가 있으나, 이는 NAT(공유기, 로드밸런서) 환경 뒤에 있는 정상 사용자의 접속을 차단하는 심각한 사이드 이펙트가 있어 Linux 4.12부터 제거(Deprecated)되었습니다.
2. **`tcp_max_tw_buckets` 강제 축소 주의**:
   * 이 값을 너무 낮추면 시스템이 `TIME_WAIT` 소켓을 강제로 제거하면서 커널 로그에 `TCP: time wait bucket table overflow` 경고를 출력하고, 패킷 순서가 꼬이는 TCP 이상 현상을 유발할 수 있습니다.
3. **CLOSE_WAIT 방치 시 `Too many open files` 장애 유발**:
   * `CLOSE_WAIT` 소켓 하나당 1개의 파일 디스크립터(FD)를 점유하므로, 누적될 경우 프로세스의 `ulimit -n` 한도에 도달하여 신규 접속과 파일 I/O가 전면 마비됩니다.