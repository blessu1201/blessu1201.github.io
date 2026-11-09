---
layout: article
title: 시스템 관리_55 FC SAN 스위치 HBA 포트 CRC 에러 및 ALUA 멀티패스 경로 장애 원인 분석과 해결 가이드
tags: [Linux, Storage, Fibre-Channel, SAN, HBA, CRC-Error, ALUA, multipath, Brocade, Troubleshooting]
keys: 261107-linux-storage-055
---

- 출처 / 참고: Brocade Fabric OS Troubleshooting and Diagnostics Guide, Linux Kernel Documentation (SCSI Target ALUA Mode), VMware Broadcom Knowledge Base (Interpreting SCSI sense codes - KB 2899)

> 명령어: `systool`, `multipath`, `dmesg`, `cat`, `grep`, `lspci`  
> 키워드: Fibre Channel, SAN Switch, HBA, CRC error, ALUA, Active-Optimized, Active-Non-Optimized, SFP degradation, Link Flapping  
> 사용처: SAN 스토리지 FC LUN 접근 시 I/O 응답 지연, HBA 포트 링크 끊김(Flapping), LUN 최적 경로가 비최적 경로로 강제 전환되는 장애 해결

---

> 실행예제

FC(Fibre Channel) 스토리지 연결 환경에서 광케이블 감쇄나 SFP 모듈 불량으로 인해 HBA 포트의 CRC 에러 카운터가 증가하고, 스토리지 ALUA 경로가 비최적 상태로 전락하는 현상을 진단합니다.

```bash
# 1. 호스트의 물리 FC HBA 포트 링크 상태 및 속도 확인
$ systool -c fc_host -v
# Class = "fc_host"
#   Class Device = "host1"
#     port_name           = "0x5001438012345678"
#     port_state          = "Online"
#     speed               = "16 Gbit"
#     symbolic_name       = "QLE2692 FW:v8.08.231 DVR:v10.02.00.04-k"

# 2. HBA 물리 수신단(RX)의 CRC 에러 및 링크 장애 카운터 확인
$ cat /sys/class/fc_host/host1/statistics/crc_error_count
# 14502
$ cat /sys/class/fc_host/host1/statistics/invalid_tx_words
# 89204
$ cat /sys/class/fc_host/host1/statistics/loss_of_sync_count
# 312
# -> CRC 에러 및 비정상 워드(invalid_tx_words) 카운터가 급증 중이면 광케이블/SFP 물리 계층 이상 확정

# 3. 현재 ALUA 멀티패스 토폴로지 및 LUN 경로 상태 확인 (multipath -ll)
$ sudo multipath -ll mpatha
# mpatha (360050768028085a12000000000000101) dm-0 NETAPP,INF-01-00
# size=1.0T features='1 queue_if_no_path' hwhandler='1 alua' wp=rw
# |-+- policy='service-time 0' prio=50 status=active
# | `- 1:0:0:1 sda 8:0  active ready running (Active/Optimized)
# `-+- policy='service-time 0' prio=10 status=enabled
#   `- 2:0:0:1 sdb 8:16 active ready running (Active/Non-Optimized)
# -> 정상일 때는 prio 50 경로로 I/O가 가야 하나, CRC 에러 발생 시 비최적 경로(prio 10)로 우회되어 지연 급증

# 4. 커널 로그에서 SCSI Check Condition 및 패브릭 단절 로그 확인
$ sudo dmesg -T | grep -iE "qla2xxx|lpfc|rport|scsi:.*check condition"
# [Sat Nov  7 11:20:15 2026] qla2xxx [0000:03:00.0]-500b:1: Loop down; waiting for recovery
# [Sat Nov  7 11:20:18 2026] rport-1:0-2: blocked FC remote port time out: removing target
```

&nbsp;
&nbsp;

## 스크립트

리눅스 시스템에 장착된 모든 FC HBA 어댑터의 통계 파일(`/sys/class/fc_host`)을 전수 조사하여 CRC 에러, 동기 유실(Loss of Sync), 원격 포트 재접속 이벤트를 탐색하고 ALUA 경로 상태를 요약해 주는 진단 쉘 스크립트입니다.

```bash
#!/bin/bash
# check_fc_hba_crc_errors.sh - Diagnose Fibre Channel HBA physical health, CRC errors, and ALUA path status

echo "=========================================="
echo " [FC HBA 물리 계층 CRC 에러 및 ALUA 상태 진단]"
echo "=========================================="

if [ ! -d /sys/class/fc_host ]; then
    echo "  [안내] 시스템에 장착된 FC HBA 장치가 없습니다."
    exit 0
fi

HOSTS=$(ls -d /sys/class/fc_host/host* 2>/dev/null)

if [ -z "$HOSTS" ]; then
    echo "  [오류] fc_host 디렉터리가 비어 있습니다."
    exit 1
fi

echo -e "\n[1] HBA 포트 사양 및 물리 카운터 점검:"
CRC_ALERT=0

for H in $HOSTS; do
    H_NAME=$(basename "$H")
    P_NAME=$(cat "$H/port_name" 2>/dev/null)
    P_STATE=$(cat "$H/port_state" 2>/dev/null)
    SPEED=$(cat "$H/speed" 2>/dev/null)
    
    CRC_CNT=$(cat "$H/statistics/crc_error_count" 2>/dev/null || echo 0)
    TX_WORDS=$(cat "$H/statistics/invalid_tx_words" 2>/dev/null || echo 0)
    SYNC_LOSS=$(cat "$H/statistics/loss_of_sync_count" 2>/dev/null || echo 0)
    LINK_FAIL=$(cat "$H/statistics/link_failure_count" 2>/dev/null || echo 0)
    
    printf "  >> [%s] 포트 WWPN: %s | 상태: %s | 속도: %s\n" "$H_NAME" "$P_NAME" "$P_STATE" "$SPEED"
    printf "     - CRC 에러 수     : %-8s | 비정상 워드 수: %s\n" "$CRC_CNT" "$TX_WORDS"
    printf "     - 동기 유실(Sync) : %-8s | 링크 장애 수  : %s\n" "$SYNC_LOSS" "$LINK_FAIL"
    
    if [ "$CRC_CNT" -gt 0 ] || [ "$TX_WORDS" -gt 100 ]; then
        echo "     [!] 경고: 물리 계층 신호 왜곡 및 패킷 변조가 감지되었습니다!"
        CRC_ALERT=1
    fi
    echo ""
done

echo -e "[2] 멀티패스 ALUA 상태 점검:"
if command -v multipath &>/dev/null; then
    MP_STATUS=$(multipath -ll 2>/dev/null)
    if [ -n "$MP_STATUS" ]; then
        echo "$MP_STATUS" | grep -E "^[a-zA-Z0-9_]+ \(|prio=|status=" | head -n 12 | sed 's/^/    /'
    else
        echo "  - 활성화된 멀티패스 디바이스가 없습니다."
    fi
else
    echo "  - multipath 유틸리티가 설치되어 있지 않습니다."
fi

echo -e "\n=========================================="
echo " [진단 요약]"
if [ "$CRC_ALERT" -eq 1 ]; then
    echo "  ★ 물리 계층 점검 시급 (광패치 케이블 청소/교체, SAN SFP 모듈 교체 권장)"
else
    echo "  ★ 물리 FC 링크 상태가 깨끗합니다."
fi
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

엔터프라이즈 SAN 환경에서 가장 까다로운 장애는 완전한 포트 단절이 아니라, 광케이블 손상이나 SFP 광트랜시버의 노후화로 인해 발생하는 **간헐적 링크 플래핑(Link Flapping)** 및 **CRC 비트 에러**입니다.

### 1. ALUA (Asymmetric Logical Unit Access) 경로 원리

현대 스토리지 어레이(NetApp, EMC, PureStorage 등)는 Active-Active 컨트롤러를 채택하되 성능을 위해 LUN의 소유권을 특정 컨트롤러에 귀속시키는 ALUA 아키텍처를 사용합니다.

1. **Active/Optimized (AO) 경로**:
   * LUN을 직접 소유한 스토리지 컨트롤러와 직결된 최단 경로로, 데이터가 내부 인터커넥트를 거치지 않아 지연 시간이 가장 낮습니다 (통상 우선순위 prio=50).
2. **Active/Non-Optimized (ANO) 경로**:
   * 대기 컨트롤러를 경유하는 경로입니다. 이 경로로 들어온 I/O는 스토리지 내부 버스를 통해 소유 컨트롤러로 우회 전송되므로 지연 시간이 2~5배 이상 길어집니다 (prio=10).
3. **경로 왜곡 문제**:
   * AO 경로의 광케이블에서 CRC 에러가 급증하면 호스트의 `dm-multipath`는 해당 경로를 일시적 실패(`failed`)로 판단하고 차단한 뒤, ANO 경로로 I/O를 우회시킵니다. 이로 인해 스토리지 내부 버스 부하가 폭증하고 전체 데이터베이스 I/O 대기열이 치솟게 됩니다.

### 2. CRC 에러 및 물리 계층 장애 원인

1. **광패치코드 오염 및 꺾임 (Fiber Micro-bending)**:
   * 랙 내부 케이블 정리 과정에서 곡률 반경(Bend Radius) 기준을 벗어나 심하게 꺾이거나 페룰 단면에 먼지가 끼면 광 신호 감쇄(dBm 저하)가 발생하여 비트가 왜곡됩니다.
2. **SAN 스위치 포트 SFP 레이저 열화**:
   * 브로케이드(Brocade)나 시스코(Cisco MDS) 스위치 포트의 SFP 광모듈이 노후화되면 송신 출력이 약해져 수신단에서 `invalid_crc_count`가 누적됩니다.
3. **HBA 카드 펌웨어와 스위치 FOS 간 속도 오토네고(Auto-negotiation) 실패**:
   * 16Gbps / 32Gbps 고속 통신 시 자동 속도 협상이 원활하지 않아 패킷 유실을 동반하는 경우입니다.

### 3. 단계별 복구 및 해결 방법

#### 1) HBA 통계 카운터 리셋 및 누적치 재검증
과거에 발생한 에러인지 현재 진행형인지 구분하기 위해 카운터를 리셋하고 관찰합니다.
```bash
# sysfs를 통한 에러 카운터 초기화
echo 1 | sudo tee /sys/class/fc_host/host1/statistics/reset_statistics
```

#### 2) SAN 스위치 포트 DDM (Digital Diagnostic Monitoring) 검사
스위치 콘솔에서 해당 포트의 광수신 레벨(Rx Power)을 측정하여 규격(-10 dBm ~ -2 dBm) 내에 있는지 확인합니다.
* Brocade 스위치 명령: `sfpshow <slot/port>`
* Cisco MDS 스위치 명령: `show interface fc<slot/port> transceiver details`

#### 3) 광케이블 교체 및 멀티패스 경로 수동 재평가
케이블/SFP 교체 완료 후 멀티패스가 정상적인 AO 경로를 다시 최우선으로 잡도록 갱신합니다.
```bash
sudo multipathd reconfigure
sudo multipath -r
```

&nbsp;
&nbsp;

## 주의사항

1. **SAN 스위치 조닝(Zoning) 수정 시 활성 영역(Effective Configuration) 백업**:
   * 포트 문제 해결을 위해 조닝을 변경할 때는 반드시 기존 조닝 구성을 사전에 백업해야 합니다. 활성 조닝 커밋(`cfgEnable`) 실수 시 동일 패브릭에 묶인 수십 대의 서버 연결이 일시에 단절될 수 있습니다.

2. **`multipath.conf`의 ALUA 하드웨어 핸들러 강제 변경 금지**:
   * 스토리지 벤더가 권장하는 기본 ALUA 설정(`hwhandler "1 alua"`)을 임의로 제거하거나 고정 우선순위로 강제 전환하면 컨트롤러 간 LUN 소유권 핑퐁(LUN Trespass) 현상이 발생하여 스토리지 CPU가 100% 포화됩니다.

3. **케이블 탈착 전 HBA 포트 오프라인화 권장**:
   * 가동 중인 시스템에서 광케이블을 예고 없이 뽑으면 다량의 SCSI 타임아웃 이벤트가 발생합니다. 사전 작업 시 `/sys/class/fc_host/hostX/issue_lip` 또는 스위치 포트 비활성화(`portdisable`)를 거친 후 케이블을 교체하는 것이 안전합니다.