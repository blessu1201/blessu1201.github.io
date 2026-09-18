---
layout: article
title: 시스템 관리_06 LVM 이벤트 감시 실패(Failed to start LVM event inspection) 및 볼륨 비활성화 문제 해결 가이드
tags: linux, lvm, systemd, storage, troubleshooting
keys: 260918-linux-storage-006
---

- 출처 / 참고: 리눅스 파일시스템 마운트 관리 및 스토리지 복구 가이드
> 명령어: systemctl status lvm2-monitor, vgchange -ay, lvm dumpconfig, journalctl -u lvm2-monitor  
> 키워드: lvm2-monitor, dmeventd, thin-provisioning, vgchange, volume activation, systemd  
> 사용처: 부팅 중 또는 스토리지 장애/증설 시 lvm2-monitor 서비스 실패 및 LVM 볼륨 그룹/논리 볼륨 비활성화(Not active) 문제 해결  

---

> 실행예제

시스템 부팅 과정 또는 OS 업데이트/스토리지 이벤트 후 `lvm2-monitor.service`가 실패(`failed`) 상태로 빠지거나, 논리 볼륨(LV)이 비활성화(`inactive`)되어 마운트 실패 및 서비스 기동 장애가 발생하는 현상을 진단하는 화면입니다.

```bash
# 1. systemd 서비스 상태 확인 (lvm2-monitor 실패 감지)
$ systemctl status lvm2-monitor.service
● lvm2-monitor.service - Monitoring of LVM2 mirrors, snapshots etc. using dmeventd or progress polling
     Loaded: loaded (/usr/lib/systemd/system/lvm2-monitor.service; enabled; vendor preset: enabled)
     Active: failed (Result: exit-code) since Fri 2026-09-18 08:30:12 KST; 5min ago
       Docs: man:dmeventd(8)
             man:lvcreate(8)
             man:lvm.conf(5)
    Process: 852 ExecStart=/usr/sbin/lvm vgchange --monitor y (code=exited, status=5)
   Main PID: 852 (code=exited, status=5)

Sep 18 08:30:12 node01 systemd[1]: Starting Monitoring of LVM2 mirrors, snapshots etc....
Sep 18 08:30:12 node01 lvm[852]:   Failed to connect to dmeventd.
Sep 18 08:30:12 node01 lvm[852]:   Failed to start LVM event inspection.
Sep 18 08:30:12 node01 systemd[1]: lvm2-monitor.service: Main process exited, code=exited, status=5/NOTINSTALLED
Sep 18 08:30:12 node01 systemd[1]: lvm2-monitor.service: Failed with result 'exit-code'.
Sep 18 08:30:12 node01 systemd[1]: Failed to start Monitoring of LVM2 mirrors, snapshots etc. using dmeventd or progress polling.

# 2. LVM 볼륨 상태 점검 (LV 활성화 여부 확인)
$ lvs -a -o lv_name,vg_name,lv_attr,size
  LV       VG        Attr       LSize
  root     vg_system -wi-ao---- 50.00g
  swap     vg_system -wi-ao----  8.00g
  lv_data  vg_data   -wi------- 200.00g

# [분석] Attr의 5번째 플래그가 'a'(active)가 아닌 '-'로 표시되어 lv_data 볼륨이 비활성화 상태임.

# 3. dmeventd 관련 소켓 및 데몬 상태 점검
$ systemctl status dm-event.socket dm-event.service
● dm-event.socket - Device-mapper event daemon FIFO
     Loaded: loaded (/usr/lib/systemd/system/dm-event.socket; enabled; vendor preset: enabled)
     Active: inactive (dead)
```

&nbsp;
&nbsp;

## 스크립트

`dmeventd` 소켓/서비스 상태를 점검하고 필요시 복구하며, 비활성화된 LVM 볼륨 그룹을 일괄 활성화(`vgchange -ay`) 및 모니터링을 재등록하는 복구 스크립트입니다.

```bash
#!/bin/bash
# ==============================================================================
# Script: fix_lvm_activation_and_monitor.sh
# Purpose: dmeventd 및 lvm2-monitor 복구와 비활성 LVM 볼륨 강제 활성화
# ==============================================================================

set -euo pipefail

echo "=========================================================="
echo "          [1] LVM 데몬 및 소켓 상태 확인"
echo "=========================================================="

# dm-event 소켓/데몬 정상화
if ! systemctl is-active --quiet dm-event.socket; then
    echo "[조치] dm-event.socket 활성화 및 기동..."
    systemctl restart dm-event.socket
fi

if ! systemctl is-active --quiet dm-event.service; then
    echo "[조치] dm-event.service 기동..."
    systemctl restart dm-event.service || true
fi

echo ""
echo "=========================================================="
echo "          [2] LVM 볼륨 그룹(VG) 및 논리 볼륨(LV) 활성화"
echo "=========================================================="

echo "[작업] 비활성화된 LVM 볼륨 일괄 활성화 수행 (vgchange -ay)..."
vgchange -ay

echo ""
echo "[상태 확인] 현재 LV 활성화 상태:"
lvs -a -o lv_name,vg_name,lv_attr,size,pool_lv

echo ""
echo "=========================================================="
echo "          [3] lvm2-monitor 서비스 복구 및 재시작"
echo "=========================================================="

echo "[작업] lvm2-monitor 재시작 및 모니터링 활성화..."
systemctl reset-failed lvm2-monitor.service 2>/dev/null || true
if systemctl restart lvm2-monitor.service; then
    echo "[성공] lvm2-monitor.service가 정상적으로 시작되었습니다."
else
    echo "(!) 경고: lvm2-monitor 기동 실패. lvm.conf 모니터링 설정 점검 필요."
    echo "(!) 임시 우회: lvm.conf의 monitoring = 0 설정을 고려하십시오."
fi

systemctl status lvm2-monitor.service --no-pager

echo ""
echo "=========================================================="
echo "          [4] 마운트 실패된 파일시스템 확인"
echo "=========================================================="
echo "[작업] mount -a 실행을 통한 누락 마운트 일괄 복구..."
mount -a
df -h -x tmpfs -x devtmpfs
```

&nbsp;
&nbsp;

## 해설

1. **`Failed to start LVM event inspection` 오류 발생 원인**
   - **`dmeventd` 미기동 또는 소켓 통신 실패:** `lvm2-monitor` 서비스는 `vgchange --monitor y` 명령을 통해 미러(Mirror), 스냅샷(Snapshot), 씬 프로비저닝(Thin-pool) 볼륨의 임계치 초과 및 장애 이벤트를 감시합니다. 이때 이벤트 감시 백엔드 데몬인 `dmeventd` 소켓(`/run/dmeventd-server` 또는 `/var/run/dmeventd-server`)과 통신하지 못하면 해당 오류(Exit status 5)가 발생합니다.
   - **패키지 누락/불일치:** RHEL/CentOS 또는 Ubuntu에서 LVM 패키지 업데이트 중 `device-mapper-event` 패키지가 누락되거나 데몬 의존성이 깨졌을 때 발생합니다.
   - **스토리지 인식 지연:** 부팅 시점에 물리 디스크(SAN/iSCSI/멀티패스 디바이스)가 늦게 로드되어 LVM 메타데이터를 즉시 읽지 못해 발생할 수 있습니다.

2. **LVM 볼륨 비활성화(`inactive`) 해결 원리**
   - 비활성화된 LV는 커널 디바이스 매퍼(`/dev/mapper/` 및 `/dev/vg_name/lv_name`) 블록 디바이스 노드를 생성하지 않으므로 마운트(`mount`) 단계에서 디바이스를 찾지 못하는 오류(`No such file or directory`)로 이어집니다.
   - `vgchange -ay` (또는 `lvchange -ay <LV_PATH>`) 명령을 통해 모든 VG/LV를 Active 상태로 전환하면 디바이스 매퍼에 매핑 테이블이 즉시 로드되고 마운트 가능한 상태가 됩니다.

3. **모니터링 비활성화(우회 해결책)**
   - 미러링이나 Thin-pool/스냅샷을 사용하지 않는 단순 Linear 볼륨 환경이고 `dmeventd` 문제로 부팅 지연이 발생한다면, `/etc/lvm/lvm.conf` 파일의 `activation { monitoring = 0 }`으로 변경하여 모니터링 감시를 비활성화할 수 있습니다.

&nbsp;
&nbsp;

## 주의사항

1. **Thin Pool 및 Snapshot 볼륨 운영 시 모니터링 비활성화 주의**
   - Thin-provisioned 풀이나 자동 확장 스냅샷을 운영 중인 환경에서 `dmeventd` 모니터링을 무작정 끄면(`monitoring = 0`), 풀 용량이 100%에 도달했을 때 자동 확장 스크립트가 호출되지 않아 I/O Fail 또는 파일시스템 크래시가 발생할 수 있습니다.

2. **클러스터 볼륨(cLVM / lvmlockd) 환경 주의**
   - 공유 스토리지 기반 클러스터 환경(Pacemaker 등)에서는 무분별하게 `vgchange -ay`를 로컬에서 직접 실행할 경우 스플릿 브레인 또는 데이터 손상이 발생할 수 있으므로, 클러스터 리소스 매니저 상태와 락 매니저(`lvmlockd`) 상태를 먼저 확인해야 합니다.

3. **부팅 단계 반복 오류 발생 시 initramfs 재생성 필요**
   - OS 커널 또는 LVM 라이브러리 업데이트 후 부팅 시점마다 해당 에러가 반복된다면, initramfs 이미지 내부의 LVM 바이너리/설정 불일치일 수 있으므로 `dracut -f` (RHEL 계열) 또는 `update-initramfs -u` (Debian 계열)를 실행하여 램디스크 이미지를 갱신해야 합니다.