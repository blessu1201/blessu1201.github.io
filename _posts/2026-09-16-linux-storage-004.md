---
layout: article
title: 시스템 관리_04 리눅스 D 상태(Uninterruptible Sleep) 무응답 프로세스 진단 및 트러블슈팅
tags: linux, troubleshooting, process, uninterruptible-sleep, d-state
keys: 260916-linux-storage-004
---

- 출처 / 참고: 리눅스 파일시스템 마운트 관리 및 스토리지 복구 가이드
> 명령어: `ps`, `cat /proc/<PID>/stack`, `cat /proc/<PID>/wchan`, `dmesg`  
> 키워드: D State, Disk Sleep, Uninterruptible, I/O Wait, Kernel Wait Channel  
> 사용처: `kill -9`로도 종료되지 않는 프로세스 분석, 스토리지 I/O 행(Hang) 및 NFS 마운트 지연 장애 조치  

---

> 실행예제

응답이 없는 프로세스에 강제 종료 시그널(kill -9)을 전달했음에도 프로세스가 종료되지 않고, 시스템 부하(Load Average) 및 I/O 대기 큐(procs b)가 치솟으며 커널 레벨에서 특정 I/O 함수에 멈춰있는 상황입니다.

```bash
$ kill -9 18420

$ uptime
 10:15:32 up 45 days,  3:20,  2 users,  load average: 15.12, 14.80, 10.05

$ vmstat 1 2
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 0  4      0 1048576 131072 2097152    0    0     0     0  120  240  0  1 74 25  0
 0  4      0 1048576 131072 2097152    0    0     0     0  115  235  0  1 75 24  0

$ ps -eo pid,stat,wchan:20,comm | grep -E 'STAT| 18420'
  PID STAT WCHAN                COMMAND
18420 D    nfs_wait_client      backup_sync.sh

$ cat /proc/18420/stack
[<0>] nfs_wait_client+0x9c/0x140 [nfs]
[<0>] nfs4_proc_lookup+0x148/0x290 [nfsv4]
[<0>] lookup_slow+0xb2/0x170
[<0>] walk_component+0x1bf/0x200
[<0>] path_lookupat+0x72/0x1b0
[<0>] filename_lookup+0xb8/0x180
[<0>] do_faccessat+0x7c/0x220
[<0>] __x64_sys_access+0x1a/0x20
[<0>] do_syscall_64+0x5b/0x1b0
[<0>] entry_SYSCALL_64_after_hwframe+0x65/0xca

$ dmesg -T | grep -E -i 'blocked|hung_task|nfs' | tail -n 3
[Wed Sep 16 10:12:15 2026] nfs: server 192.168.10.200 not responding, still trying
[Wed Sep 16 10:14:18 2026] echo 0 > /proc/sys/kernel/hung_task_timeout_secs disables this message.
[Wed Sep 16 10:14:18 2026] INFO: task backup_sync.sh:18420 blocked for more than 120 seconds.
```

&nbsp;
&nbsp;

## 스크립트

현재 시스템에서 D 상태인 프로세스 목록을 추출하고, 각각의 커널 대기 함수(`wchan`)와 호출 스택(`stack`)을 즉시 수집하는 진단 스크립트입니다.

```bash
#!/bin/bash
echo "=== [1] D 상태(Uninterruptible Sleep) 프로세스 목록 ==="
D_PIDS=$(ps -eo pid,stat,user,comm | awk '$2 ~ /D/ {print $1}')

if [ -z "$D_PIDS" ]; then
    echo "현재 D 상태인 프로세스가 없습니다."
    exit 0
fi

ps -eo pid,ppid,user,stat,comm | awk 'NR==1 || $4 ~ /D/'

echo ""
echo "=== [2] 프로세스별 커널 대기 함수 및 콜스택 분석 ==="
for PID in $D_PIDS; do
    echo "----------------------------------------"
    echo "PID: $PID ($(cat /proc/$PID/comm 2>/dev/null))"
    echo "Wait Channel: $(cat /proc/$PID/wchan 2>/dev/null)"
    echo "Kernel Stack:"
    cat /proc/$PID/stack 2>/dev/null
done

echo "----------------------------------------"
echo "=== [3] 스토리지 I/O 응답 지연 의심 로그 (최근 15줄) ==="
dmesg -T | grep -iE 'hung_task|blocked|call trace|nfs' | tail -n 15
```

&nbsp;
&nbsp;

## 해설

D 상태(Uninterruptible Sleep)는 프로세스가 디바이스 드라이버나 커널 I/O 작업(디스크 읽기/쓰기, NFS 네트워크 응답 등)의 완료 신호를 기다리는 상태입니다. 커널 데이터 일관성을 보호하기 위해 **모든 시그널(`SIGKILL`, `kill -9` 포함) 수신이 차단**되므로 일반적인 명령어로는 종료되지 않습니다.

| 진단 항목 | 점검 파일 / 명령어 | 설명 |
|---|---|---|
| **상태 확인** | `ps -eo stat,pid,comm` | STAT 열에 `D` 또는 `D+` 표시 여부 확인 |
| **대기 함수** | `/proc/<PID>/wchan` | 프로세스가 커널에서 슬립에 들어간 함수 이름 확인 |
| **커널 스택** | `/proc/<PID>/stack` | I/O 드라이버, 파일시스템 모듈 등 블로킹 지점 상세 추적 |
| **I/O 병목** | `vmstat 1` / `iostat -xz 1` | `b`(Blocked) 수치 증가 및 `%util` 100% 지속 여부 확인 |

**대표적인 발생 원인 및 조치 방법:**

* **원격 스토리지(NFS/SMB) 응답 중단**: 네트워크 단절이나 스토리지 장애로 서버가 응답하지 않을 때 발생합니다. 네트워크 연결을 복구하거나 강제 언마운트(`umount -f -l <마운트포인트>`)를 시도하여 시스템 콜을 빠져나오게 해야 합니다.
* **물리 디스크 I/O 오류**: 배드 섹터, 컨트롤러 장애 등으로 디스크 응답이 무한 지연될 때 발생합니다. `dmesg`에서 I/O 에러를 확인하고 하드웨어 교체 또는 케이블 점검이 필요합니다.
* **디바이스 드라이버 데드락**: 커널 내부 뮤텍스 락 경합으로 멈춘 경우로, 대기 중인 원인 자원이 해제되지 않으면 해당 프로세스는 스스로 복구되지 않습니다.

&nbsp;
&nbsp;

## 주의사항

* **`kill -9` 남발 금지**: D 상태의 프로세스는 시그널을 처리할 수 없으므로 `kill -9`를 반복 실행해도 메모리에서 제거되지 않으며 불필요한 시스템 부하만 가중시킵니다.
* **부모 프로세스 주의**: 부모 프로세스를 강제 종료할 경우 D 상태 프로세스가 좀비(Zombie) 혹은 고아 프로세스로 전환되어 `init`(PID 1)으로 넘어가 시스템 리소스를 계속 점유할 수 있습니다.
* **시스템 재부팅 검토**: 원인이 되는 I/O 자원(NFS, 하드웨어) 복구가 불가능한 상태에서 다수의 프로세스가 D 상태로 누적되면 Load Average가 급증합니다. 이 경우 안전한 캐시 플러시(`sync`) 후 시스템 재부팅(`reboot`)을 진행하는 것이 최선의 복구 방법입니다.
