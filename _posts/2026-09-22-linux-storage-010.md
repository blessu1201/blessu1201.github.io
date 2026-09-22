---
layout: article
title: "부팅 실패를 유발하는 손상된 /etc/fstab 파일 복구 가이드"
tags: [Linux, Storage, Troubleshooting, Boot, Filesystem, systemd]
keys: 260922-linux-storage-010
---

- 출처 / 참고: 리눅스 파일시스템 마운트 관리 및 스토리지 복구 가이드
> 명령어: `mount -o remount,rw /`, `blkid`, `findmnt --verify`, `mount -a`, `journalctl -xb`  
> 키워드: fstab Corruption, Emergency Mode, Maintenance Shell, Read-Only Filesystem, UUID Mismatch  
> 사용처: 부팅 중 `Give root password for maintenance` 또는 Emergency Mode 진입 시, 잘못된 UUID/오타로 인한 마운트 실패 복구  

---

> 실행예제

```bash
# 1. 부팅 중 긴급 모드(Emergency/Maintenance Shell) 진입 화면 확인
# You are in emergency mode. After logging in, type "journalctl -xb" to view
# system logs, "systemctl reboot" to reboot, or "exit" to continue bootup.
# Give root password for maintenance
# (or press Control-D to continue): 

# 2. 부팅 실패 원인 로그 확인 (fstab 관련 마운트 실패 추적)
# journalctl -xb | grep -E "Timed out waiting for device|Failed to mount"
# Sep 22 14:10:05 srv-node01 systemd[1]: Timed out waiting for device /dev/disk/by-uuid/a1b2c3d4-xxxx.
# Sep 22 14:10:05 srv-node01 systemd[1]: Dependency failed for /data.
# Sep 22 14:10:05 srv-node01 systemd[1]: Failed to mount /data.

# 3. 루트 파일시스템의 쓰기 잠금(Read-Only) 상태 확인
# mount | grep " / "
/dev/mapper/vg_system-lv_root on / type ext4 (ro,relatime)

# 4. 블록 디바이스의 실제 UUID 및 fstab의 등록 내용 대조
# blkid
/dev/sda2: UUID="f3a1c840-7e82-491a-b6d3-2e061805aa11" BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="98765432-01"
/dev/mapper/vg_system-lv_root: UUID="11223344-5566-7788-99aa-bbccddeeff00" BLOCK_SIZE="4096" TYPE="ext4"
/dev/mapper/vg_data-lv_data: UUID="99887766-5544-3322-1100-ffeeddccbbaa" BLOCK_SIZE="4096" TYPE="xfs"

# cat /etc/fstab
# /dev/mapper/vg_data-lv_data 마운트 구문에 오타 또는 잘못된 UUID가 지정되어 타임아웃 발생 확인
UUID=99887766-5544-3322-1100-ffeeddccbbaX /data xfs defaults 0 2
```

&nbsp;
&nbsp;

## 스크립트

```bash
#!/usr/bin/env bash
#
# 긴급/복구 모드 환경에서 실행하는 /etc/fstab 점검 및 복구 자동화 스크립트
#

set -euo pipefail

echo "=== [1] 루트(/) 파일시스템을 읽기/쓰기(RW) 모드로 재마운트 ==="
mount -o remount,rw /

echo "=== [2] 손상 전 원본 /etc/fstab 백업 생성 ==="
BACKUP_PATH="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
cp -p /etc/fstab "${BACKUP_PATH}"
echo "백업 완료: ${BACKUP_PATH}"

echo "=== [3] 누락/오류 유발 비필수 마운트 포인트 임시 주석 처리 (부팅 보장) ==="
# 루트(/), 부트(/boot, /boot/efi), 스왑(swap)을 제외한 나머지 외부 볼륨에 부팅 타임아웃 방지 옵션 점검
# 문제가 발생한 파티션을 즉시 파악하기 위해 findmnt 검증 수행
if command -v findmnt >/dev/null 2>&1; then
    echo "--- fstab 문법 및 UUID 매핑 사전 검증 ---"
    findmnt --verify || true
fi

echo "=== [4] /etc/fstab 내 부팅 실패 방지 옵션(nofail) 권장 적용 가이드 ==="
# 부팅 시 필수적이지 않은 데이터/로그 디렉터리는 옵션에 'nofail,x-systemd.device-timeout=10s' 추가 권장
echo "알림: 시스템 구동과 무관한 볼륨(/data, /backup 등)은 마운트 옵션에 'nofail'을 명시하면 디스크 누락 시에도 정상 부팅됩니다."

echo "=== [5] 수정된 fstab 반영 및 마운트 테스트 (오류 발견 시 즉시 중단) ==="
# -a: /etc/fstab 전체 마운트 시도, -v: 상세 로그 출력
mount -a -v

echo "=== [완료] /etc/fstab 문법 검증 완료. 시스템을 정상 리부팅할 수 있습니다. ==="
echo "명령어: systemctl reboot"
```

&nbsp;
&nbsp;

## 해설

1. **에러 원인 분석:**
   * **하드 블로킹(Hard Blocking):** systemd는 기본적으로 `/etc/fstab`에 선언된 모든 파일시스템을 부팅 완료(`local-fs.target`)를 위한 필수 종속성으로 간주합니다.
   * **타임아웃(Timeout):** 스토리지 디바이스의 UUID 오타, 디스크 제거, LVM 볼륨 비활성화, 파일시스템 파일 형식(ext4, xfs) 불일치 등이 발생하면 90초간 장치를 탐색하다 타임아웃이 발생하고, 시스템은 부팅을 중단한 채 `Emergency Mode`로 떨어집니다.

2. **복구 절차 및 핵심 로직:**
   * **`mount -o remount,rw /`:** 긴급 모드로 진입하면 파일시스템 손상을 막기 위해 루트 디렉터리가 **읽기 전용(Read-Only, `ro`)**으로 마운트됩니다. 이 상태에서는 `/etc/fstab` 수정이 불가능하므로 반드시 읽기/쓰기(`rw`) 모드로 재마운트해야 합니다.
   * **`blkid` 대조:** 실제 연결된 블록 장치의 UUID 및 파티션 레이블을 확인하여 `/etc/fstab`에 기록된 값과 글자 단위로 비교 검증합니다.
   * **`mount -a` 검증:** 재부팅 전에 반드시 `mount -a`를 실행해야 합니다. 오류가 있는 상태에서 재부팅하면 다시 긴급 모드로 튕기지만, 셸 상태에서 `mount -a`를 치면 오타가 있는 줄 번호와 실패 원인이 화면에 즉시 출력됩니다.

## 주의사항

1. **외장/데이터 파티션에 `nofail` 옵션 사용:**
   * `/` 또는 `/boot`와 같은 필수 영역이 아닌 데이터 볼륨(`/data`, 외장 NAS/SAN 마운트 등)은 옵션에 `nofail`을 반드시 추가해야 합니다.
   * 예: `UUID=... /data ext4 defaults,nofail,x-systemd.device-timeout=10s 0 2` 형태로 작성하면 스토리지가 끊기더라도 부팅이 중단되지 않습니다.

2. **GRUB 복구 파라미터 활용 (루트 암호 분실 시):**
   * 긴급 모드 진입 시 root 비밀번호를 묻는데 암호를 모르거나 계정이 잠겨있다면, 부팅 시 GRUB 메뉴에서 `e`를 누르고 커널 라인 끝에 `systemd.unit=emergency.target` 또는 `init=/bin/sh`를 추가해 단일 사용자 셸로 진입한 후 위 스크립트 과정을 수행해야 합니다.

3. **덤프(dump) 및 fsck 패스(pass) 순서 번호 점검:**
   * `/etc/fstab`의 마지막 두 숫자(예: `0 2`) 중 마지막 숫자는 `fsck` 검사 순서입니다. 루트 파일시스템은 반드시 `1`, 일반 파티션은 `2`, 네트워크 드라이브나 스왑은 `0`이어야 하며, 이 값이 잘못 지정되면 검사 실패가 유발될 수 있습니다.