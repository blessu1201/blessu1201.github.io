---
layout: article
title: 시스템 관리_57 Linux LVM 메타데이터 손상 오류 원인 분석 및 vgcfgrestore 무손실 복구 가이드
tags: [Linux, Storage, LVM, vgcfgrestore, vgcfgbackup, Metadata-Corruption, PV, VG, LV, Troubleshooting]
keys: 261109-linux-storage-057
---

- 출처 / 참고: Linux man-pages (vgcfgrestore(8), vgcfgbackup(8), pvcreate(8)), Red Hat Enterprise Linux Logical Volume Manager Administration Guide

> 명령어: `vgcfgrestore`, `vgcfgbackup`, `pvs`, `vgs`, `lvs`, `pvcreate`, `vgchange`  
> 키워드: LVM, Volume Group, Metadata corrupted, vgcfgrestore, /etc/lvm/archive, UUID mismatch, Couldn't find device with uuid, PActive  
> 사용처: 디스크 재파티셔닝, 헤더 덮어쓰기, 스토리지 재할당 후 LVM 볼륨 그룹(VG) 비활성화 및 마운트 불가 장애 긴급 복구

---

> 실행예제

시스템 관리자의 실수로 파티션 테이블이 조작되었거나 스토리지 볼륨 헤더가 손상되어 `Couldn't find device with uuid` 경고가 뜨고 볼륨 그룹(VG)이 통째로 사라졌을 때, `/etc/lvm/archive` 백업 파일을 이용해 메타데이터를 진단하고 복구하는 과정입니다.

```bash
# 1. LVM 상태 조회 시 메타데이터 손상 및 누락 경고 확인
$ sudo vgs
#   WARNING: Couldn't find device with uuid '5f9a1b-4c2d-8812-99ab-cdef12345678'.
#   WARNING: VG data_vg is missing PV 5f9a1b-4c2d-8812-99ab-cdef12345678 (last written to /dev/sdb1).
#   VG      #PV #LV #SN Attr   VSize   VFree
#   data_vg   2   1   0 wz-pn- 100.00g    0
# -> 볼륨 그룹 속성에 'p'(partial) 플래그가 붙고 PV 하나가 유실된 상태 확인

# 2. 논리 볼륨(LV) 활성화 시도 시 실패 확인
$ sudo vgchange -ay data_vg
#   Refusing activation of partial LV data_vg/data_lv. Use '--activationmode partial' to override.
#   0 logical volume(s) in volume group "data_vg" now active

# 3. 디스크 블록 장치의 LVM 헤더 손상 여부 확인
$ sudo pvs /dev/sdb1
#   Device /dev/sdb1 not found (or ignored by filtering).
# -> /dev/sdb1 장치는 OS에 보이나 LVM PV 레이블 헤더가 날아가 인식되지 않음

# 4. /etc/lvm/archive/ 디렉터리에서 가장 최근의 정상 메타데이터 백업 파일 검색
$ ls -lt /etc/lvm/archive/data_vg_*.vg | head -n 3
# -rw------- 1 root root 4521 Nov  8 18:30 /etc/lvm/archive/data_vg_00015-1245102.vg
# -rw------- 1 root root 4480 Nov  5 10:12 /etc/lvm/archive/data_vg_00014-8851241.vg
# -> 변경 직전인 00015 백업 아카이브 확인
```

&nbsp;
&nbsp;

## 스크립트

LVM의 `/etc/lvm/archive/` 및 `/etc/lvm/backup/`을 스캔하여 손실된 볼륨 그룹의 정확한 복구 시점을 식별하고, 날아간 PV의 UUID를 복원하여 볼륨 그룹과 논리 볼륨을 무손실 활성화해 주는 자동 복구 쉘 스크립트입니다.

```bash
#!/bin/bash
# restore_lvm_metadata.sh - Restore corrupted LVM metadata and missing PV using vgcfgrestore

VG_NAME=${1:-"data_vg"}
FAILED_DEV=${2:-"/dev/sdb1"}

echo "=========================================="
echo " [Linux LVM 메타데이터 긴급 복구 도구]"
echo " 대상 볼륨 그룹(VG): ${VG_NAME}"
echo " 복구 대상 장치(PV) : ${FAILED_DEV}"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] LVM 메타데이터 복구를 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

# 1. 최신 아카이브 파일 검색
LATEST_ARCHIVE=$(ls -t /etc/lvm/archive/${VG_NAME}_*.vg 2>/dev/null | head -n 1)

if [ -z "$LATEST_ARCHIVE" ]; then
    echo "  [경고] /etc/lvm/archive에 해당 VG의 아카이브가 없습니다. /etc/lvm/backup 확인 중..."
    LATEST_ARCHIVE="/etc/lvm/backup/${VG_NAME}"
    if [ ! -f "$LATEST_ARCHIVE" ]; then
        echo "  [치명적 오류] 복구에 필요한 LVM 메타데이터 백업 파일이 존재하지 않습니다!"
        exit 1
    fi
fi

echo -e "\n[1] 복구 소스 메타데이터 파일:"
echo "  - 백업 파일 경로: ${LATEST_ARCHIVE}"

# 2. 백업 파일 내에서 대상 장치(또는 누락된 장치)의 UUID 추출
TARGET_UUID=$(grep -B 2 -A 5 "description = " "$LATEST_ARCHIVE" | grep -A 10 "physical_volumes {" | grep -B 1 "device = \"${FAILED_DEV}\"" | grep -oE "id = \"[a-zA-Z0-9\-]+\"" | cut -d'"' -f2)

if [ -z "$TARGET_UUID" ]; then
    echo "  [알림] 백업 파일 내 장치명 매핑 실패. 유실된 고아 UUID 탐색 시도..."
    TARGET_UUID=$(vgs --noheadings -o pv_uuid "$VG_NAME" 2>/dev/null | tr -d ' ' | head -n 1)
fi

echo "  - 복원할 PV 고유 UUID: ${TARGET_UUID}"

if [ -z "$TARGET_UUID" ]; then
    echo "  [오류] 유효한 UUID를 추출할 수 없습니다. 수동으로 아카이브 파일을 확인하십시오."
    exit 1
fi

# 3. PV 헤더 강제 재생성 (UUID 유지 옵션 적용)
echo -e "\n[2] 물리 볼륨(PV) 헤더 및 UUID 복원 중..."
echo "  -> 실행: pvcreate --uuid ${TARGET_UUID} --restorefile ${LATEST_ARCHIVE} ${FAILED_DEV}"
pvcreate --uuid "$TARGET_UUID" --restorefile "$LATEST_ARCHIVE" "$FAILED_DEV" -y

if [ $? -ne 0 ]; then
    echo "  [실패] PV 헤더 재생성 실패. 장치가 열려있거나 파티션이 없습니다."
    exit 1
fi
echo "  [성공] PV 헤더가 성공적으로 재기록되었습니다."

# 4. vgcfgrestore를 통한 볼륨 그룹 메타데이터 복원
echo -e "\n[3] 볼륨 그룹(VG) 메타데이터 복원 중..."
echo "  -> 실행: vgcfgrestore -f ${LATEST_ARCHIVE} ${VG_NAME}"
vgcfgrestore -f "$LATEST_ARCHIVE" "$VG_NAME"

if [ $? -ne 0 ]; then
    echo "  [실패] vgcfgrestore 복원 실패!"
    exit 1
fi
echo "  [성공] VG 메타데이터 복원 완료."

# 5. VG 및 LV 활성화
echo -e "\n[4] 논리 볼륨 활성화 시도:"
vgchange -ay "$VG_NAME"

echo -e "\n[5] 최종 LVM 상태 검증:"
lvs "$VG_NAME"
vgs "$VG_NAME"

echo -e "\n=========================================="
echo " [복구 완료] 정상적으로 LV가 활성화되었는지 확인하십시오."
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

LVM(Logical Volume Manager)의 구조는 매우 견고하지만, 디스크 앞부분(첫 1~2MB)에 기록되는 **LVM 메타데이터 영역(MDA: Metadata Area)**이 파티셔닝 툴(`fdisk`, `parted`), `dd` 오작동, 또는 볼륨 확장 실수로 덮어씌워지면 OS는 볼륨 그룹 전체를 인식하지 못하게 됩니다. 이때 실제 데이터 블록은 디스크 뒤쪽에 그대로 보존되어 있으므로 **메타데이터 헤더만 정확히 재구성하면 100% 무손실 복구**가 가능합니다.

### 1. LVM 메타데이터 백업 구조 (`/etc/lvm`)

LVM 데몬은 LVM 구성(PV 생성, VG 확장, LV 크기 조절 등)이 변경될 때마다 자동으로 텍스트 형식의 메타데이터 백업본을 로컬 파일시스템에 저장합니다.

* `/etc/lvm/archive/`: 변경 이력이 발생할 때마다 타임스탬프와 함께 보관되는 **과거 이력 아카이브** 디렉터리입니다.
* `/etc/lvm/backup/`: 가장 최신의 볼륨 그룹 구성 상태를 담고 있는 **현재 스냅샷 백업** 파일입니다.

이 파일들은 단순 텍스트로 되어 있어 열어보면 물리 볼륨의 고유 `UUID`, 물리 익스텐트(PE)의 시작 오프셋, 스트라이프 구조 및 논리 볼륨 매핑 정보가 완전하게 기록되어 있습니다.

### 2. 무손실 복구의 핵심 원리: `pvcreate --uuid` 와 `vgcfgrestore`

단순히 `pvcreate /dev/sdb1`을 다시 때리면 **새로운 랜덤 UUID**가 발급되어 기존 볼륨 그룹과의 연결 링크가 영구 단절됩니다. 반드시 백업 메타데이터에 기록되어 있던 이전 UUID를 그대로 주입해야 합니다.

1. **UUID 주입 PV 재생성**:
   ```bash
   pvcreate --uuid "5f9a1b-4c2d-..." --restorefile /etc/lvm/archive/data_vg_00015.vg /dev/sdb1
   ```
   * 이 명령은 데이터 영역은 건드리지 않고, 첫 섹터의 LVM 레이블 헤더만 이전 UUID로 다시 작성합니다.
2. **메타데이터 복원 (`vgcfgrestore`)**:
   ```bash
   vgcfgrestore -f /etc/lvm/archive/data_vg_00015.vg data_vg
   ```
   * 백업 파일에 들어있던 정확한 PE 매핑 및 LV 레이아웃을 PV의 메타데이터 영역에 밀어 넣습니다.
3. **볼륨 그룹 활성화**:
   ```bash
   vgchange -ay data_vg
   ```
   * 커널 장치 매퍼(`dm-mod`)가 새 테이블을 읽어 `/dev/data_vg/data_lv` 블록 장치를 즉시 생성합니다.

&nbsp;
&nbsp;

## 주의사항

1. **복구 전 디스크 전체에 `mkfs` 절대 실행 금지**:
   * 볼륨 그룹이 보이지 않는다고 해서 해당 디바이스(`/dev/sdb1`)에 새로 파일시스템(`mkfs.ext4`, `mkfs.xfs`)을 포맷하면 기존 데이터 블록과 슈퍼블록이 영구 파괴되어 복구가 불가능해집니다.

2. **`/etc/lvm/archive/` 파일의 타임스탬프 대조 필수**:
   * 아카이브 목록 중 가장 최신 버전이 아닐 경우, 최근에 확장했던 LV의 크기나 신규 생성된 PE 정보가 누락되어 파일시스템 정합성이 어긋날 수 있습니다. 반드시 텍스트 에디터로 아카이브 본문의 날짜와 크기를 확인한 후 복원해야 합니다.

3. **OS 디스크 재설치 시 메타데이터 유실 대비**:
   * `/etc/lvm/` 디렉터리는 OS 루트(`/`) 파티션에 위치합니다. OS 디스크 장애 시에도 복구할 수 있도록 외장 LUN의 LVM 메타데이터 텍스트 백업본(`vgcfgbackup -f ...`)을 외부 스토리지나 백업 서버에 정기적으로 보관해 두는 것이 권장됩니다.