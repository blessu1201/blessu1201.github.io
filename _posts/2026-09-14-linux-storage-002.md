---
layout: article
title: 시스템 관리_02 리눅스 High I/O Wait(wa) 원인 분석 및 디스크 병목 프로세스 추적하기
tags: [Linux, Disk, IO, Troubleshooting, Performance, ShellScript]
keys: 260914-linux-storage-002
---

- 출처 / 참고: 리눅스 성능 분석 및 I/O 서브시스템 트러블슈팅 가이드
> 명령어: `top`, `iostat`, `iotop`, `pidstat`, `lsof`  
> 키워드: `I/O Wait`, `wa`, `디스크 병목`, `iostat`, `%util`, `D 상태 프로세스`  
> 사용처: CPU 사용률 중 `wa` 수치가 비정상적으로 치솟고 시스템 응답이 현저히 느려질 때, 병목을 유발하는 디스크 장치 및 범인 프로세스를 추적할 때  

---

> 실행예제

`top` 실행 시 CPU 사용률 항목에서 `%wa`(I/O Wait)가 높게 치솟고, 로드 애버리지(load average)가 급격히 상승하며 콘솔 입력 및 서비스 응답이 지연되는 상황입니다.

```bash
$ top -b -n 1 | head -n 5
top - 14:20:15 up 45 days,  3:12,  2 users,  load average: 8.42, 6.15, 3.20
Tasks: 215 total,   2 running, 212 sleeping,   0 stopped,   1 zombie
%Cpu(s):  2.5 us,  3.1 sy,  0.0 ni, 28.4 id, 65.8 wa,  0.0 hi,  0.2 si,  0.0 st
MiB Mem :  16024.5 total,   1250.2 free,  12140.0 used,   2634.3 buff/cache
MiB Swap:   4096.0 total,   3820.0 free,    276.0 used.   3520.1 avail Mem

$ iostat -xz 1 2
Linux 5.15.0-105-generic (srv-core) 	09/14/2026 	_x86_64_	(4 CPU)

Device            r/s     w/s     rkB/s     wkB/s   rrqm/s   wrqm/s  %rrqm  %wrqm  r_await w_await aqu-sz rareq-sz wareq-sz  svctm  %util
sda              2.50  350.20     12.00  48200.00     0.00    12.00   0.00   3.31     1.20   28.50   9.80     4.80   137.64   2.78  99.80
```

## 스크립트
I/O Wait를 유발하는 주원인인 D 상태(Uninterruptible Sleep, 디스크 I/O 대기 중인 상태) 프로세스를 실시간으로 집계하고, 누적 I/O 요청량이 가장 높은 상위 프로세스를 추적하는 셸 스크립트입니다.

```bash
#!/bin/bash
# High I/O Wait 발생 시 D 상태 프로세스 및 디스크 쓰기 상위 프로세스 추출

echo "[*] Checking D-state (Uninterruptible Sleep) Processes..."
echo "--------------------------------------------------"
ps -eo pid,user,state,wchan:20,cmd | awk '$3 ~ /D/'

echo ""
echo "[*] Top 10 Disk Writing Processes (via /proc/[pid]/io)..."
echo "--------------------------------------------------"
printf "%-8s %-10s %-15s %s\n" "PID" "USER" "WRITE_BYTES" "COMMAND"

for pid in /proc/[0-9]*/; do
    pid_num=$(basename "$pid")
    if [ -f "$pid/io" ] && [ -r "$pid/io" ]; then
        write_bytes=$(awk '/write_bytes:/ {print $2}' "$pid/io" 2>/dev/null)
        if [ -n "$write_bytes" ] && [ "$write_bytes" -gt 0 ]; then
            user=$(ps -o user= -p "$pid_num" 2>/dev/null)
            cmd=$(ps -o comm= -p "$pid_num" 2>/dev/null)
            printf "%-8s %-10s %-15s %s\n" "$pid_num" "$user" "$write_bytes" "$cmd"
        fi
    fi
done | sort -k3 -nr | head -n 10
```

## 해설
I/O Wait(%wa)는 CPU 코어가 작업을 처리하지 않고 디스크(스토리지)로부터 데이터 읽기/쓰기가 완료되기를 대기하며 idle 상태로 머문 시간의 비율을 의미합니다.

CPU 자체의 연산 부하가 아니라 디스크 처리 한계 또는 특정 프로세스의 과도한 디스크 작업으로 인해 시스템 전체가 병목에 걸렸음을 알리는 지표입니다.

### 1. 디스크 장치별 포화도 확인 (iostat -xz 1)
어느 블록 디바이스(HDD/SSD/SAN)에서 지연이 발생하는지 점검합니다.

```bash
$ sudo iostat -xz 1
```

- `%util`: 해당 디스크가 I/O 요청을 처리 중인 시간의 백분율입니다. 90~100%에 근접하면 디스크 장치가 포화 상태임을 의미합니다.
- `await` (또는 `r_await`, `w_await`): I/O 요청이 큐에서 대기한 시간부터 실제 처리가 끝날 때까지 걸린 평균 시간(ms)입니다. SSD 기준 수 ms 이내가 정상이며, 수십~수백 ms 이상 지속된다면 심각한 지연입니다.
- `aqu-sz` (Average Queue Size): 디스크 드라이버 큐에 쌓여 대기 중인 요청 수입니다. 이 수치가 높을수록 디스크가 요청을 소화하지 못하고 밀려 있음을 나타냅니다.

### 2. 병목 유발 프로세스 추적 (iotop / pidstat)
과도한 디스크 I/O를 일으키는 프로세스를 찾습니다.

```bash
# 실시간 I/O 발생 프로세스만 필터링 출력
$ sudo iotop -oP

# 프로세스별 I/O 통계 1초 간격 모니터링
$ sudo pidstat -d 1 5
```

- iotop의 DISK WRITE 및 IO> 컬럼이 높은 프로세스를 확인합니다.
- pidstat -d 결과의 kB_rd/s(초당 읽기 KB), kB_wr/s(초당 쓰기 KB), iodelay(I/O 지연으로 소모된 클록 틱)를 확인합니다.

### 3. 디스크 작업을 일으키는 대상 파일 확인 (lsof)
확인된 프로세스가 어떤 대용량 파일 또는 디렉토리에 I/O를 집중시키고 있는지 파악합니다.

```bash
$ sudo lsof -p <PID> | grep -E 'REG|DIR'
```

### 4. 주요 원인 및 조치 방안

|원인 유형|세부 상황|조치 방안|
|메모리 부족으로 인한 Swap 발생|RAM 고갈로 빈번한 메모리 페이징(Swap In/Out) 디스크 I/O 발생|`vmstat 1`의 `si`/`so` 수치 확인, 메모리 누수 프로세스 조치 및 RAM 증설|
|백업 및 배치 쿼리 집중|야간 백업, 대량 DB 덤프, 풀스캔 쿼리 동시 실행|I/O 우선순위 조정(ionice -c 3), 작업 시간대 분산|
|비동기 더티 페이지 플러시 지연|커널 메모리에 캐시된 데이터가 디스크로 일괄 동기화되며 스파이크 발생|커널 파라미터(`vm.dirty_background_ratio`, `vm.dirty_ratio`) 튜닝|
|로그 과다 기록|디버그 레벨 로그 또는 에러 루프로 인한 초당 수만 건 파일 쓰기|애플리케이션 로그 레벨 상향 조정, 로그 버퍼링 적용|

## 주의사항

### 1. D 상태(Uninterruptible Sleep) 프로세스는 kill -9로 종료되지 않음
I/O Wait가 극심할 때 ps 상태가 D로 표시되는 프로세스는 커널 스페이스에서 디스크 응답을 기다리는 인터럽트 불가 상태입니다.

이 상태의 프로세스는 시그널을 수신할 수 없으므로 kill -9를 내려도 종료되지 않고 프로세스 테이블에 남아있게 됩니다. 스토리지가 정상 응답을 재개하거나 디바이스 타임아웃이 발생해야 해제되며, 장치 응답 불가 상태가 지속되면 시스템 재부팅이 필요할 수 있습니다.

### 2. I/O 우선순위 격리 도구 ionice 활용
서버 운영 중 필수적으로 실행해야 하는 정기 백업(tar, rsync)이나 대용량 파일 복사 작업이 메인 서비스의 디스크 성능을 저하시키지 않도록 Idle 클래스로 우선순위를 강등하여 실행합니다.

```bash
# 다른 프로세스가 디스크를 쓰지 않는 유휴 시간에만 I/O 수행하도록 설정 (Class 3: Idle)
$ sudo ionice -c 3 rsync -avz /source/ /backup/
```