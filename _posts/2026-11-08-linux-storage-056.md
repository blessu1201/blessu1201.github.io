---
layout: article
title: 시스템 관리_56 Linux Device Mapper Multipath DM-Multipath IO Hang 원인 분석 및 장애 복구 가이드
tags: [Linux, Storage, Multipath, DM-Multipath, IO-Hang, no_path_retry, queue_if_no_path, multipath.conf, Troubleshooting]
keys: 261108-linux-storage-056
---

- 출처 / 참고: Red Hat Enterprise Linux 8/9 DM Multipath Configuration and Administration, Linux man-pages (multipath.conf(5), multipathd(8))

> 명령어: `multipath`, `multipathd`, `iostat`, `dmsetup`, `cat`, `systemctl`  
> 키워드: DM-Multipath, I/O Hang, queue_if_no_path, no_path_retry, dev_loss_tmo, fast_io_fail_tmo, path_checker, D-state  
> 사용처: SAN/iSCSI 스토리지의 모든 경로가 일시 단절되었을 때 서버 전체가 멈추거나, 경로 복구 후에도 I/O 큐가 풀리지 않는 장애 해결

---

> 실행예제

스토리지 점검 또는 네트워크 일시 장애로 인해 다중 경로 중 일부(또는 전체)가 끊겼을 때, `dm-multipath` 레이어가 I/O를 무한정 큐에 쌓아두면서 애플리케이션 및 시스템 콜이 `D(Uninterruptible Sleep)` 상태로 멈추는 현상을 진단합니다.

```bash
# 1. 멀티패스 디바이스 상태 및 큐잉(Queueing) 정체 여부 확인
$ sudo multipath -ll
# mpathb (36001405a12b450123000000000000001) dm-1 OPEN-E,SAN
# size=2.0T features='1 queue_if_no_path' hwhandler='0' wp=rw
# `-+- policy='service-time 0' prio=0 status=active
#   |- 3:0:0:1 sdc 8:32  failed faulty running
#   `- 4:0:0:1 sdd 8:48  failed faulty running
# -> 모든 물리 경로(sdc, sdd)가 failed 상태인데 'queue_if_no_path' 기능으로 인해 I/O 에러를 리턴하지 않고 영구 대기열에 가둠

# 2. multipathd 데몬 상태 및 큐 모드 실시간 확인
$ sudo multipathd show maps
# name   sysfs uuid
# mpathb dm-1  36001405a12b450123000000000000001
$ sudo multipathd show map mpathb status
# map mpathb: 1 queue_if_no_path (queueing enabled)
# -> queueing enabled 상태로 인해 상위 파일시스템/DB로 에러가 전달되지 않고 프로세스가 정지됨

# 3. I/O 대기(await) 및 D 상태 프로세스 점검
$ iostat -xz 1 2
# Device            r/s     w/s     rkB/s     wkB/s   r_await  w_await   aqu-sz  %util
# dm-1             0.00    0.00      0.00      0.00      0.00     0.00   845.00  100.00
# -> 입출력 처리량은 0인데 대기 큐 크기(aqu-sz)가 수백 개 이상 적체된 상태 확인

# 4. multipathd 대화형 콘솔(CLI)을 통한 즉각적인 큐 플러시 테스트
$ sudo multipathd disablequeueing map mpathb
# ok
# -> 대기 중이던 I/O를 즉시 에러로 반환하여 프로세스 락을 강제 해제
```

&nbsp;
&nbsp;

## 스크립트

시스템 내 모든 멀티패스 디바이스(`dm-*`)를 점검하여, 가용 경로가 전혀 없음에도 무한 큐잉(`queue_if_no_path`) 상태로 멈춰 있는 고아 디바이스를 감지하고 강제 큐 비우기(`disablequeueing`)를 수행하여 서버 행을 해소하는 복구 쉘 스크립트입니다.

```bash
#!/bin/bash
# fix_multipath_io_hang.sh - Detect and resolve DM-Multipath I/O Hang and infinite queueing

echo "=========================================="
echo " [Linux DM-Multipath I/O Hang 진단 및 복구]"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] 멀티패스 관리를 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

if ! systemctl is-active --quiet multipathd; then
    echo "  [치명적] multipathd 서비스가 정지되어 있습니다!"
    echo "  -> 서비스 시작 시도: systemctl start multipathd"
    systemctl start multipathd
fi

# 1. multipath 전체 맵 이름 추출
MAP_NAMES=$(multipath -ll | grep -E "^[a-zA-Z0-9_]+ \(" | awk '{print $1}')

if [ -z "$MAP_NAMES" ]; then
    echo "  [안내] 구성된 멀티패스 디바이스가 없습니다."
    exit 0
fi

echo -e "\n[1] 멀티패스 디바이스 경로 헬스체크:"
HANG_DETECTED=0

for MAP in $MAP_NAMES; do
    MAP_INFO=$(multipath -ll "$MAP")
    ACTIVE_PATHS=$(echo "$MAP_INFO" | grep -c "status=active")
    READY_PATHS=$(echo "$MAP_INFO" | grep -c "ready running")
    IS_QUEUEING=$(echo "$MAP_INFO" | grep -c "queue_if_no_path")
    
    printf "  - 디바이스: %-15s | 활성경로: %s개 | 큐잉기능: %s\n" "$MAP" "$READY_PATHS" "$([ $IS_QUEUEING -gt 0 ] && echo 'ON' || echo 'OFF')"
    
    # 가용 경로가 0개인데 큐잉이 켜져 있는 경우 -> 영구 I/O Hang 상태
    if [ "$READY_PATHS" -eq 0 ] && [ "$IS_QUEUEING" -gt 0 ]; then
        echo "    [!] 치명적 감지: [${MAP}] 모든 물리 경로 단절 및 무한 큐잉 적체 중!"
        HANG_DETECTED=1
        
        echo "    -> 긴급 조치: multipathd disablequeueing map ${MAP} 실행 중..."
        multipathd disablequeueing map "$MAP" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "    -> [완료] 대기열 강제 반환 성공. 상위 프로세스 행(Hang)이 해제되었습니다."
        fi
    fi
done

# 2. multipath.conf 최적화 권장안 검사
echo -e "\n[2] /etc/multipath.conf 핵심 타임아웃 파라미터 점검:"
CONF_FILE="/etc/multipath.conf"
if [ -f "$CONF_FILE" ]; then
    grep -vE "^#|^$" "$CONF_FILE" | grep -E "no_path_retry|fast_io_fail_tmo|dev_loss_tmo" | sed 's/^/    /'
    
    if grep -q "queue_if_no_path" "$CONF_FILE"; then
        echo "  [주의] /etc/multipath.conf에 레거시 'queue_if_no_path'가 하드코딩되어 있습니다."
        echo "  -> 'no_path_retry fail' 또는 특정 횟수(예: no_path_retry 12)로 교체를 권장합니다."
    fi
else
    echo "  [안내] 사용자 설정 파일(/etc/multipath.conf)이 존재하지 않아 커널 기본값이 적용 중입니다."
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

Linux Device Mapper Multipath(`dm-multipath`)는 서버와 스토리지 사이의 다중 경로 장애에 대비한 고가용성 드라이버입니다. 그러나 설정 파라미터 중 경로 유실 시의 동작 모드가 잘못 설계되어 있으면, 장애 발생 시 유연하게 페일오버되거나 빠른 에러를 반환하는 대신 **시스템 전체 I/O를 영구적으로 멈추게(Hang)** 만드는 치명적 상태에 빠집니다.

### 1. `queue_if_no_path`의 함정과 무한 I/O 블로킹

* **동작 원리**:
  * 스토리지와의 연결 경로가 일시적으로 끊겼을 때 상위 파일시스템이나 애플리케이션으로 I/O 에러(`EIO`)를 리턴하면 DB나 파일시스템이 읽기 전용(Read-Only)으로 마운트되거나 크래시됩니다.
  * 이를 막기 위해 도입된 기능이 `queue_if_no_path`입니다. 연결이 복구될 때까지 들어오는 모든 I/O 요청을 메모리 큐에 대기(Queueing)시킵니다.
* **발생 문제**:
  * 만약 스토리지 스위치 전원 차단, 광케이블 절단 등 물리적 장애로 인해 경로가 장시간 복구되지 않으면, 커널은 들어오는 I/O를 무한정 큐에 쌓아둡니다.
  * 결국 메모리가 고갈되거나 I/O를 요청한 모든 스레드(Java, C, Oracle 프로세스)가 커널의 D 상태에 갇혀 명령 입력조차 먹통이 되는 **시스템 동결(System Freeze)**로 번집니다.

### 2. 현대 멀티패스의 표준: `no_path_retry` 아키텍처

현대 리눅스 커널은 무한정 큐잉을 지양하고, **일정 횟수/시간 동안만 큐잉을 유지한 뒤 경로가 복원되지 않으면 I/O 실패(fail)를 리턴**하는 방식을 표준으로 채택합니다.

* `no_path_retry <number>`:
  * 경로 점검 주기(`polling_interval`, 보통 5초)마다 재시도 횟수를 차감합니다.
  * 예: `no_path_retry 12` $\rightarrow$ $12 \times 5\text{초} = 60\text{초}$ 동안만 큐잉을 유지하고, 60초 후에도 경로가 없으면 에러를 리턴하여 프로세스 행을 차단합니다.
* `no_path_retry fail`:
  * 경로가 0개가 되는 즉시 에러를 리턴합니다 (HA 클러스터 환경 권장).

### 3. 안정적인 `/etc/multipath.conf` 권장 구성

```ini
# /etc/multipath.conf
defaults {
    user_friendly_names yes
    find_multipaths yes
    
    # 무한 큐잉 방지: 60초(12회 x 5초) 후 실패 반환
    no_path_retry 12
    
    # 장애 경로 빠른 감지 (초 단위)
    fast_io_fail_tmo 5
    
    # 원격 포트 최종 정리 타임아웃
    dev_loss_tmo 30
    
    # 검사 도구
    path_checker tur
    path_grouping_policy group_by_prio
}
```
* 변경 후 데몬 리로드:
  ```bash
  sudo systemctl reload multipathd
  ```

&nbsp;
&nbsp;

## 주의사항

1. **클러스터 환경(Pacemaker / Oracle RAC)의 펜싱(Fencing) 충돌**:
   * 클러스터 환경에서 `no_path_retry` 값을 너무 길게(수 분 이상) 주면 스토리지 하트비트가 멈췄을 때 클러스터 소프트웨어가 노드를 비정상으로 오인하여 노드를 강제 재부팅(Reboot fencing)시키는 연쇄 장애가 발생합니다. 클러스터 환경은 `no_path_retry fail` 또는 짧은 초(5~10초)를 주어야 합니다.

2. **`multipath -F` (Flush All) 실행 시 서비스 중단 주의**:
   * 멀티패스 맵을 재구성하겠다고 마운트가 물려있는 상태에서 `multipath -F`를 내리면 마운트된 디바이스 매퍼 테이블이 손상되어 시스템이 패닉에 빠질 수 있습니다. 반드시 상위 마운트 및 LVM 활성화를 해제한 후 플러시해야 합니다.

3. **SCSI 드라이버 타임아웃과의 연계**:
   * SCSI 계층의 `fast_io_fail_tmo` 값이 FC HBA의 링크 다운 타임아웃보다 길게 설정되면 HBA 수준에서 I/O를 먼저 버려 멀티패스가 페일오버 결정을 제때 내리지 못하므로 값을 스토리지 권장 가이드와 일치시켜야 합니다.