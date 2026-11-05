---
layout: article
title: 시스템 관리_53 Linux Samba CIFS 마운트 파일 Lock 경합 및 세션 타임아웃 원인 분석과 완벽 해결 가이드
tags: [Linux, Storage, Samba, CIFS, SMB, File-Locking, Oplocks, Lease, Session-Timeout, Troubleshooting]
keys: 261105-linux-storage-053
---

- 출처 / 참고: Linux man-pages (mount.cifs(8), smb.conf(5)), Microsoft Protocol Documentation (MS-SMB2 - Server Message Block Protocol Versions 2 and 3), Samba Documentation (Locking and Oplocks)

> 명령어: `smbstatus`, `mount.cifs`, `ss`, `dmesg`, `lsof`, `tcpdump`  
> 키워드: Samba, CIFS, SMB2, SMB3, Oplocks, Lease break, File Lock contention, echo_interval, nobrl, CIFS VFS timeout  
> 사용처: 리눅스-윈도우 이종 시스템 간 CIFS/SMB 공유 디렉터리 동시 접근 시 파일 열기 지연, 세션 단절(Reconnecting) 및 I/O 행(Hang) 긴급 복구

---

> 실행예제

리눅스 클라이언트에서 CIFS(SMB)로 마운트된 볼륨 내 파일에 다중 프로세스가 접근할 때 파일 잠금(Lock) 경합으로 I/O가 멈추거나 커널 로그에 `CIFS VFS: Server not responding` 메시지가 발생하며 세션이 끊기는 현상을 진단합니다.

```bash
# 1. 클라이언트 커널 로그에서 CIFS 세션 단절 및 재연결 타임아웃 확인
$ sudo dmesg -T | grep -iE "cifs|smb"
# [Thu Nov  5 10:15:21 2026] CIFS VFS: \\192.168.1.210 has not responded in 120 seconds. Reconnecting...
# [Thu Nov  5 10:15:23 2026] CIFS VFS: sends on sock 000000001245 stuck for 15 seconds
# [Thu Nov  5 10:15:25 2026] CIFS VFS: echo_interval 60 missed, initiating reconnect
# -> SMB 에코 핑(Keepalive) 실패로 클라이언트 커널이 세션을 강제 재수립하며 I/O 행 유발

# 2. 클라이언트 현재 CIFS 마운트 옵션 및 프로토콜 버전 확인
$ mount | grep -i cifs
# //192.168.1.210/shared on /mnt/cifs_share type cifs (rw,relatime,vers=3.0,cache=strict,username=appuser,uid=1000,forceuid,gid=1000,forcegid,addr=192.168.1.210,file_mode=0755,dir_mode=0755)
# -> 기본값인 cache=strict, brl(바이트 범위 락 활성화) 적용 상태 확인

# 3. Samba 서버 관점: 현재 물려있는 배타적 락(Oplocks / Lease / Deny Mode) 점검
$ sudo smbstatus -L
# Locked files:
# Pid          DataId             DenyMode   Access      R/W        Oplock           SharePath   Name   Time
# ------------------------------------------------------------------------------------------------------
# 14820        12:45120:0         DENY_NONE  0x120089    RDWR       LEASE(RWH)       /data/share log.db Thu Nov  5 10:10:02 2026
# 15210        12:45120:0         DENY_NONE  0x120089    RDWR       NONE             /data/share log.db Thu Nov  5 10:14:15 2026
# -> 14820 프로세스가 LEASE(RWH: Read/Write/Handle) 락을 쥐고 있어 다른 클라이언트의 접근이 대기열에 걸림

# 4. Samba 서버의 활성 SMB 클라이언트 세션 및 TCP 445 상태 확인
$ sudo smbstatus -S
$ ss -tan state established '( sport = :445 or dport = :445 )'
```

&nbsp;
&nbsp;

## 스크립트

CIFS 마운트 환경에서 발생한 파일 락 경합 및 응답 지연을 진단하고, 커널 수준의 세션 Keepalive 튜닝 및 바이트 범위 락(`nobrl`) 최적화 옵션으로 무중단 재마운트를 지원하는 점검 쉘 스크립트입니다.

```bash
#!/bin/bash
# diagnose_cifs_lock_timeout.sh - Diagnose CIFS/SMB locking contention and session timeout

MOUNT_POINT=${1:-"/mnt/cifs_share"}

echo "=========================================="
echo " [Samba/CIFS 파일 락 및 타임아웃 진단기]"
echo " 대상 마운트 경로: ${MOUNT_POINT}"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] 진단 및 마운트 분석을 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

# 1. 마운트 상태 확인
MNT_ENTRY=$(grep -E "\s${MOUNT_POINT}\scifs\s" /proc/mounts)

if [ -z "$MNT_ENTRY" ]; then
    echo "  [오류] 지정한 경로가 CIFS 파일시스템으로 마운트되어 있지 않습니다."
    exit 1
fi

echo -e "\n[1] 현재 CIFS 마운트 파라미터 분석:"
echo "  - $MNT_ENTRY"

SERVER_IP=$(echo "$MNT_ENTRY" | grep -oE "addr=[0-9\.]+" | cut -d'=' -f2)
SMB_VER=$(echo "$MNT_ENTRY" | grep -oE "vers=[0-9\.]+" | cut -d'=' -f2)
echo "  - 서버 IP: ${SERVER_IP}"
echo "  - SMB 프로토콜 버전: ${SMB_VER:-"기본값"}"

# 2. 바이트 범위 락(BRL) 및 캐시 옵션 검사
if echo "$MNT_ENTRY" | grep -q "nobrl"; then
    echo "  - 바이트 범위 락(nobrl): 비활성화됨 (로컬 락 처리, 경합 최소화 모드)"
else
    echo "  - 바이트 범위 락: 활성화됨 (서버 측 전송으로 인한 경합 발생 가능)"
fi

# 3. 최근 커널 CIFS 에러 로그 분석
echo -e "\n[2] 최근 1시간 내 CIFS VFS 에러 이벤트 점검:"
CIFS_ERRS=$(dmesg -T | grep -i "CIFS VFS" | tail -n 5)

if [ -n "$CIFS_ERRS" ]; then
    echo "  [경고] 커널 수준 CIFS 타임아웃/에러 감지:"
    echo "$CIFS_ERRS" | sed 's/^/    /'
    
    if echo "$CIFS_ERRS" | grep -qi "has not responded"; then
        echo "  -> 원인: SMB 서버 응답 지연으로 인한 세션 단절 (Echo 타임아웃)"
    fi
    if echo "$CIFS_ERRS" | grep -qi "stuck"; then
        echo "  -> 원인: TCP 소켓 송신 버퍼 블로킹 (네트워크 정체 또는 서버 락 지연)"
    fi
else
    echo "  [정상] 최근 감지된 커널 CIFS 에러가 없습니다."
fi

# 4. 점유 중인 로컬 프로세스 확인
echo -e "\n[3] 대상 마운트 접근 중인 프로세스:"
MNT_PIDS=$(lsof +D "$MOUNT_POINT" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u)

if [ -n "$MNT_PIDS" ]; then
    ps -fp $MNT_PIDS 2>/dev/null | awk '{printf "  -> PID: %-6s | 사용자: %-10s | 상태: %-4s | 명령: %s\n", $2, $1, $8, $8}'
else
    echo "  - 현재 열려있는 파일 핸들이 없습니다."
fi

# 5. 권장 최적화 마운트 옵션 제시
echo -e "\n[4] 성능 및 안정성 최적화 권장 옵션:"
echo "  - 세션 단절 방지 Keepalive: echo_interval=15 (기본 60초에서 단축)"
echo "  - 락 경합 완화: nobrl (다중 프로세스 공유 파일 I/O 충돌 회피)"
echo "  - 최신 다중화 프로토콜: vers=3.1.1"
echo "  [적용 예시]:"
echo "  mount -t cifs //${SERVER_IP}/share ${MOUNT_POINT} -o remount,vers=3.1.1,nobrl,echo_interval=15"

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

리눅스 클라이언트가 윈도우 서버나 리눅스 Samba 기반의 NAS 공유 볼륨을 `cifs`로 마운트하여 사용할 때, 일반 로컬 파일시스템과 달리 **네트워크 레벨의 파일 잠금 메커니즘(Oplocks, Lease, Byte-Range Lock)**과 **SMB 하트비트 세션 검사(Echo Interval)**로 인해 특유의 I/O 멈춤(Hang) 및 타임아웃 현상이 발생합니다.

### 1. Lock 경합의 핵심 원인 (Oplocks & Lease Break)

SMB 프로토콜은 성능 향상을 위해 클라이언트가 로컬 캐시를 적극 활용하도록 허용하는 **기회적 잠금(Oplocks: Opportunistic Locks)** 및 SMB2/3의 **Lease** 기능을 제공합니다.

1. **Lease Break 지연에 따른 I/O 정체**:
   * 클라이언트 A가 파일에 대해 `Read-Write-Handle (RWH)` Lease를 얻어 로컬 캐싱 중일 때, 클라이언트 B가 동일 파일에 쓰기/열기를 요청하면 Samba 서버는 클라이언트 A에게 Lease Break 통지를 보냅니다.
   * 클라이언트 A가 캐시를 서버로 플러시하고 락을 양보할 때까지 클라이언트 B의 시스템 콜(`open`, `write`)은 커널 단에서 수 초~수십 초간 대기(Blocked) 상태로 굳어집니다.
2. **Byte-Range Lock (BRL) 충돌**:
   * DB 파일(SQLite 등)이나 로그 파일처럼 파일의 특정 오프셋 범위를 잠그는 애플리케이션의 경우, 리눅스 CIFS 클라이언트가 모든 바이트 락 요청을 서버로 전달합니다. 서버 측의 엄격한 POSIX/Windows 락 변환 과정에서 오버헤드가 발생하고 데드락 성 경합이 유발됩니다.

### 2. 세션 타임아웃 (CIFS VFS: Server not responding) 원인

1. **과도하게 긴 기본 `echo_interval` (기본값: 60초)**:
   * 리눅스 CIFS 모듈은 SMB 서버와 연결을 유지하기 위해 주기적으로 SMB Echo 요청을 보냅니다.
   * 네트워크 패킷 지연이나 방화벽의 세션 정리로 응답이 제때 오지 않으면 커널은 약 120초(에코 2회 누락)를 기다린 후 세션을 끊고 재연결(Reconnect)을 시도합니다. 이 2분 동안 해당 볼륨에 걸려있는 모든 프로세스가 D 상태로 멈추게 됩니다.
2. **대용량 파일 전송 중 소켓 버퍼 포화**:
   * 대용량 I/O가 단일 TCP 스트림을 100% 점유하면 동일 소켓을 공유하는 Echo 패킷이 제시간에 나가지 못해 소켓 정체(`sends on sock stuck`) 에러와 함께 연결이 끊어지는 악순환이 발생합니다.

### 3. 단계별 최적화 및 해결 방법

#### 1) 락 경합 완화: `nobrl` 마운트 옵션 적용
애플리케이션 간 엄격한 네트워크 바이트 락이 필수적이지 않은 경우, 클라이언트 로컬 수준에서만 락을 처리하고 서버로 락 RPC를 보내지 않도록 설정합니다.
```bash
sudo mount -t cifs //server/share /mnt/share -o username=user,password=pass,nobrl
```

#### 2) 세션 하트비트 단축 (`echo_interval=15`)
네트워크 일시 단절을 빠르게 감지하고 세션을 복원하도록 에코 주기를 15초로 단축합니다.
```bash
sudo mount -t cifs //server/share /mnt/share -o remount,echo_interval=15
```

#### 3) Samba 서버 측 튜닝 (`smb.conf`)
Samba 서버가 리눅스인 경우, 다중 클라이언트 공유 디렉터리에 대해 락 완화 설정을 적용합니다.
```ini
[shared]
   path = /data/share
   read only = no
   # 락 경합이 심한 환경에서 Lease 지연 완화
   oplocks = yes
   kernel oplocks = no
   level2 oplocks = yes
   # 윈도우 스타일 바이트 락 완화
   blocking locks = no
```
* 수정 후 `sudo systemctl reload smbd` 실행.

&nbsp;
&nbsp;

## 주의사항

1. **`nobrl` 옵션 사용 시 SQLite 등 임베디드 DB 파일 다중 접근 주의**:
   * `nobrl` 옵션을 주면 서로 다른 클라이언트 서버가 동일한 SQLite DB 파일이나 단일 파일에 동시 쓰기를 할 때 데이터가 덮어씌워져 파일시스템 내부 레코드가 깨질 수 있습니다. 다중 서버가 동시에 직접 수정하는 공유 DB 파일에는 사용하지 말아야 합니다.

2. **SMB 버전 명시 필수 (`vers=3.1.1` 또는 `vers=3.0`)**:
   * 버전을 명시하지 않으면 배포판에 따라 구형 SMB 2.0이나 2.1로 협상될 수 있습니다. 대규모 세션 유지와 보안, 멀티채널 성능을 위해 항상 `vers=3.1.1`을 명시하는 것이 권장됩니다.

3. **윈도우 전원 절전 및 방화벽 TCP Keepalive 세션 타임아웃**:
   * 스토리지 서버가 윈도우 서버인 경우 전원 옵션에서 네트워크 어댑터 절전 기능이 켜져 있거나, 중간 L4/보안 방화벽에서 유휴 세션을 300초 만에 정리해 버리면 리눅스 커널의 CIFS 세션이 예고 없이 끊어집니다. 방화벽의 TCP 유휴 세션 타임아웃을 최소 1시간 이상으로 늘려야 합니다.