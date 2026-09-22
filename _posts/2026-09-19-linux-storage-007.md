---
layout: article
title: 시스템 관리_07 LVM 이벤트 감시 시작 실패(Failed to start LVM event inspection)&quot; 또는 LVM 볼륨 활성화 문제 해결
tags: [Linux, LVM, Storage, Troubleshooting, Systemd]
keys: 260919-linux-storage-007
---

- 출처 / 참고: 리눅스 파일시스템 마운트 관리 및 스토리지 복구 가이드
> 명령어: `systemctl status lvm2-monitor`, `vgscan`, `vgchange -ay`, `lvscan`, `lsblk`  
> 키워드: LVM Event Inspection, Volume Group, Logical Volume, Active, Inactive, Emergency Mode  
> 사용처: 부팅 중 LVM 모니터링 데몬 실패 시, 긴급 모드(Emergency Shell) 진입 시, 비활성화된 LVM 볼륨 강제 활성화 및 복구 작업  

---

> 실행예제

```bash
# 1. 시스템 부팅/서비스 실패 상태 확인 (systemd 실패 서비스 조회)
$ sudo systemctl status lvm2-monitor.service
● lvm2-monitor.service - Monitoring of LVM2 mirrors, snapshots etc. using dmeventd or progress polling
     Loaded: loaded (/lib/systemd/system/lvm2-monitor.service; enabled; vendor preset: enabled)
     Active: failed (Result: exit-code) since Mon 2026-09-21 10:14:22 KST; 2min ago
       Docs: man:dmeventd(8)
             man:lvcreate(8)
             man:lvchange(8)
             man:vgchange(8)
   Process: 612 ExecStart=/sbin/lvm vgchange --monitor y (code=exited, status=5)
   Main PID: 612 (code=exited, status=5)

Sep 21 10:14:22 srv-node01 systemd[1]: Starting Monitoring of LVM2 mirrors, snapshots etc. using dmeventd or progress polling...
Sep 21 10:14:22 srv-node01 lvm[612]:   Failed to find device mapper event daemon.
Sep 21 10:14:22 srv-node01 lvm[612]:   Volume group "vg_data" not found or not active
Sep 21 10:14:22 srv-node01 systemd[1]: lvm2-monitor.service: Main process exited, code=exited, status=5/NOTINSTALLED
Sep 21 10:14:22 srv-node01 systemd[1]: Failed to start Monitoring of LVM2 mirrors, snapshots etc. using dmeventd or progress polling.

# 2. 현재 논리 볼륨(LV) 활성화 여부 확인 ('inactive' 상태 확인)
$ sudo lvscan
  inactive          '/dev/vg_system/lv_root' [50.00 GiB] inherit
  inactive          '/dev/vg_system/lv_var' [30.00 GiB] inherit
  inactive          '/dev/vg_data/lv_storage' [500.00 GiB] inherit

# 3. 블록 디바이스 구조 및 마운트 연결 실패 상태 확인
$ lsblk -f
NAME        FSTYPE      FSVER LABEL UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
sda                                                                                     
├─sda1      vfat        FAT32       A1B2-C3D4                             505.2M     1% /boot/efi
├─sda2      ext4        1.0         e4f5g6h7-1234-5678-90ab-cdef12345678  1.2G    20% /boot
└─sda3      LVM2_member             Wxyz01-abcd-efgh-ijkl-mnop-qrst-uvwxyz              
sdb                                                                                     
└─sdb1      LVM2_member             123456-7890-abcd-efgh-ijkl-mnop-qrstuv              
```

&nbsp;
&nbsp;

## 스크립트

```bash
#!/usr/bin/env bash
#
# LVM Volume Group / Logical Volume 복구 및 재활성화 자동화 스크립트
#

set -euo pipefail

echo "=== [1] 물리 볼륨(PV) 및 볼륨 그룹(VG) 검색 ==="
lvm pvscan --cache
lvm vgscan --mknodes

echo "=== [2] 비활성화된 모든 볼륨 그룹 활성화 (vgchange -ay) ==="
lvm vgchange -ay

echo "=== [3] dmeventd (Device Mapper Event Daemon) 상태 점검 및 재시작 ==="
if systemctl is-enabled dmeventd.socket >/dev/null 2>&1; then
    systemctl restart dmeventd.socket dmeventd.service || true
fi

echo "=== [4] lvm2-monitor 서비스 재기동 ==="
systemctl restart lvm2-monitor.service

echo "=== [5] LVM 논리 볼륨 활성화 상태 및 디바이스 매핑 검증 ==="
lvm lvscan

echo "=== [6] 파일시스템 마운트 점검 (/etc/fstab 기준) ==="
mount -a

echo "=== [완료] LVM 복구 및 마운트 프로세스가 정상적으로 처리되었습니다. ==="
```

&nbsp;
&nbsp;

## 해설

1. **에러 원인 분석:**
   - `Failed to start LVM event inspection` 또는 `lvm2-monitor.service` 실패는 부팅 과정에서 Device Mapper 이벤트 데몬(`dmeventd`)과의 통신이 실패하거나, 스토리지 디바이스 인식 지연 등으로 볼륨 그룹(VG)이 비활성화(`inactive`) 상태로 남아 있을 때 발생합니다.
   - 주로 다중 디스크 구성 환경, 커널 업데이트 후 드라이버 지연 로딩, 스냅샷/미러링 볼륨 모니터링 실패, 혹은 디스크 UUID 변동으로 인해 긴급 모드(Emergency Mode)로 떨어질 때 동반됩니다.

2. **복구 절차 및 핵심 로직:**
   - **`pvscan --cache` & `vgscan --mknodes`:** LVM 메타데이터 캐시를 갱신하고 누락된 `/dev/mapper` 노드를 다시 생성합니다.
   - **`vgchange -ay` (Activate Yes):** 시스템에 존재하는 모든 볼륨 그룹과 하위 논리 볼륨을 즉시 활성(`active`) 상태로 전환하여 커널 디바이스 매핑에 등록합니다.
   - **`systemctl restart dmeventd` & `lvm2-monitor`:** LVM의 상태 감시 데몬을 재구동하여 실패한 systemd 유닛 상태를 정상(`active (running)`)으로 복원합니다.
   - **`mount -a`:** 활성화된 볼륨들을 `/etc/fstab` 정의에 맞추어 마운트 포인트를 복원합니다.

&nbsp;
&nbsp;

## 주의사항

1. **UUID 불일치 확인 (`/etc/fstab`):**
   - LVM 볼륨이 정상 활성화되었음에도 부팅 시 여전히 긴급 모드로 진입한다면, `/etc/fstab`에 명시된 볼륨의 UUID나 디바이스 경로(`/dev/mapper/...`)가 실제 `blkid` 결과와 일치하는지 반드시 검토해야 합니다.
2. **다중 경로(Multipath) 및 iSCSI/SAN 스토리지 지연:**
   - 네트워크 기반 스토리지나 SAN 환경의 경우 네트워크 데몬 활성화 이전에 LVM 검사가 먼저 실행되어 실패할 수 있습니다. 이 경우 `_netdev` 마운트 옵션을 추가하거나 systemd 종속성 순서를 확인해야 합니다.
3. **볼륨 필터링 설정 (`/etc/lvm/lvm.conf`):**
   - `lvm.conf` 내의 `filter` 또는 `global_filter` 지시어로 인해 특정 물리 디스크(PV)가 제외 처리되어 있지 않은지 점검해야 합니다. 필터 설정이 잘못되면 시스템 재부팅 시 볼륨 그룹을 찾지 못합니다.
4. **Initramfs 재생성 권장:**
   - LVM 설정이나 디스크 구성을 수정한 후에는 드라이버 및 lvm 모듈이 부트 이미지에 정확히 반영되도록 `update-initramfs -u` (Ubuntu/Debian) 또는 `dracut -f` (RHEL/CentOS/Rocky)를 실행해야 합니다.