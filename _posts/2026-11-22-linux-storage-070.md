---
layout: article
title: 시스템 관리_70 SAN 스토리지 볼륨 확장 후 Linux 파티션 및 파일시스템 온라인 리사이징 가이드
tags: [Linux, Storage, SAN, LUN-Resize, LVM, growpart, pvresize, lvextend, xfs_growfs, resize2fs, Troubleshooting]
keys: 261122-linux-storage-070
---

- 출처 / 참고: Red Hat Enterprise Linux Storage Administration Guide (Online Storage Reconfiguration and Resizing), Linux man-pages (growpart(1), pvresize(8), xfs_growfs(8), resize2fs(8))

> 명령어: `rescan-scsi-bus.sh`, `multipathd`, `growpart`, `pvresize`, `lvextend`, `xfs_growfs`, `resize2fs`  
> 키워드: LUN Resize, Online Resizing, SCSI Rescan, Multipath Resize, growpart, pvresize, lvextend, xfs_growfs, GPT Secondary Header  
> 사용처: 외장 SAN 스토리지 또는 클라우드 블록 볼륨 증설 후 서비스 중단(언마운트/재부팅) 없이 리눅스 파일시스템 용량을 실시간 확장

---

> 실행예제

스토리지 관리자가 SAN 어레이에서 기존 500GB LUN을 1TB(1000GB)로 증설했으나, 리눅스 OS의 `df -h` 및 `lsblk`에서는 여전히 500GB로 표시될 때 하위 SCSI 계층부터 상위 파일시스템 계층까지 용량 인식 상태를 점검합니다.

```bash
# 1. 현재 블록 디바이스 및 파일시스템 인식 크기 확인 (여전히 500G로 보임)
$ lsblk /dev/sdb
# NAME              MAJ:MIN RM  SIZE RO TYPE  MOUNTPOINT
# sdb                 8:16   0  500G  0 disk
# └─mpatha          253:0    0  500G  0 mpath
#   └─mpatha1       253:1    0  500G  0 part
#     └─vg_data-lv1 253:2    0  500G  0 lvm   /data

# 2. SCSI 디바이스 재스캔(Rescan) 실행하여 커널이 스토리지 새 용량(1TB)을 인지하도록 유도
$ for host in /sys/class/scsi_host/host*; do echo "- - -" | sudo tee $host/scan; done
$ for dev in /sys/class/scsi_disk/*/device/rescan; do echo 1 | sudo tee $dev; done

# 3. 물리 디스크(sdb)는 1TB로 바뀌었으나 멀티패스(mpatha)와 파티션(mpatha1)이 500G에 머물러 있는지 확인
$ lsblk /dev/sdb
# NAME              MAJ:MIN RM  SIZE RO TYPE  MOUNTPOINT
# sdb                 8:16   0    1T  0 disk   <-- 1T 인식 성공
# └─mpatha          253:0    0  500G  0 mpath  <-- 아직 500G
#   └─mpatha1       253:1    0  500G  0 part   <-- 아직 500G
#     └─vg_data-lv1 253:2    0  500G  0 lvm   /data

# 4. 멀티패스 맵 리사이즈 명령 실행
$ sudo multipathd resize map mpatha
# ok
```

&nbsp;
&nbsp;

## 스크립트

SAN 볼륨 또는 가상 디스크 증설 이후 **1) SCSI 버스 재스캔 $\rightarrow$ 2) 멀티패스 맵 리사이즈 $\rightarrow$ 3) GPT 백업 헤더 복구 및 파티션 확장(`growpart`) $\rightarrow$ 4) LVM 물리 볼륨(`pvresize`) 및 논리 볼륨(`lvextend`) 확장 $\rightarrow$ 5) XFS/Ext4 파일시스템 온라인 확장**의 5단계 파이프라인을 무중단으로 일괄 수행하는 자동화 쉘 스크립트입니다.

```bash
#!/bin/bash
# online_extend_storage.sh - End-to-end online resizing for SCSI, Multipath, Partition, LVM, and Filesystem

MOUNT_POINT=${1:-"/data"}

echo "=========================================="
echo " [스토리지 볼륨 무중단 온라인 확장 자동화]"
echo " 대상 마운트 경로: ${MOUNT_POINT}"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] 블록 디바이스 및 파티션 조작을 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

if ! grep -qs "\s${MOUNT_POINT}\s" /proc/mounts; then
    echo "  [오류] 지정한 경로(${MOUNT_POINT})가 마운트되어 있지 않습니다."
    exit 1
fi

# 1. 마운트 경로에서 디바이스 매퍼/블록 경로와 파일시스템 타입 추출
LV_DEV=$(findmnt -n -o SOURCE "$MOUNT_POINT")
FS_TYPE=$(findmnt -n -o FSTYPE "$MOUNT_POINT")

echo "  - 논리/블록 디바이스 : ${LV_DEV}"
echo "  - 파일시스템 유형    : ${FS_TYPE}"

# 2. 전체 SCSI 버스 및 개별 블록 디바이스 재스캔
echo -e "\n[1] 커널 SCSI 디스크 용량 재스캔(Rescan) 실행 중..."
for HOST in /sys/class/scsi_host/host*; do
    echo "- - -" > "$HOST/scan" 2>/dev/null
done
for DEV in /sys/class/scsi_disk/*/device/rescan; do
    echo 1 > "$DEV" 2>/dev/null
done
sleep 2

# 3. 멀티패스(DM-Multipath) 사용 시 맵 리사이즈
if command -v multipathd &>/dev/null && systemctl is-active --quiet multipathd; then
    echo -e "\n[2] 멀티패스(Multipath) 디바이스 맵 용량 동기화:"
    MAPS=$(multipath -ll | grep -E "^[a-zA-Z0-9_]+ \(" | awk '{print $1}')
    for M in $MAPS; do
        multipathd resize map "$M" >/dev/null 2>&1
        echo "  - 멀티패스 맵 리사이즈 완료: ${M}"
    done
fi

# 4. LVM 구성인 경우 하위 PV 및 파티션 추적 확장
if lvs "$LV_DEV" >/dev/null 2>&1; then
    VG_NAME=$(lvs --noheadings -o vg_name "$LV_DEV" | tr -d ' ')
    PV_DEV=$(pvs --noheadings -o pv_name -S vg_name="$VG_NAME" | tr -d ' ' | head -n 1)
    
    echo -e "\n[3] LVM 하부 물리 볼륨(${PV_DEV}) 및 파티션 확장:"
    
    # 파티션 번호 분리 (예: /dev/sdb1 -> 디스크 /dev/sdb, 파티션 1 / 또는 /dev/mapper/mpatha1)
    if echo "$PV_DEV" | grep -qE "[0-9]+$"; then
        PART_NUM=$(echo "$PV_DEV" | grep -oE "[0-9]+$")
        BASE_DISK=$(echo "$PV_DEV" | sed -E "s/${PART_NUM}$//")
        
        if command -v growpart &>/dev/null; then
            echo "  - 파티션 확장 실행: growpart ${BASE_DISK} ${PART_NUM}"
            growpart "$BASE_DISK" "$PART_NUM" 2>/dev/null
            partprobe "$BASE_DISK" 2>/dev/null
        else
            echo "  [주의] growpart(cloud-utils-growpart)가 없어 파티션 자동 확장을 건너뜁니다."
        fi
    fi
    
    # PV 리사이즈
    echo "  - 물리 볼륨 확장: pvresize ${PV_DEV}"
    pvresize "$PV_DEV"
    
    # LV 100% 가용 공간 확장
    echo "  - 논리 볼륨 100% 확장: lvextend -l +100%FREE ${LV_DEV}"
    lvextend -l +100%FREE "$LV_DEV"
fi

# 5. 상위 파일시스템 온라인 확장 (XFS / Ext4)
echo -e "\n[4] 파일시스템 온라인 확장 실행 (${FS_TYPE}):"
case "$FS_TYPE" in
    xfs)
        xfs_growfs "$MOUNT_POINT"
        ;;
    ext4|ext3)
        resize2fs "$LV_DEV"
        ;;
    *)
        echo "  [경고] 지원하지 않는 파일시스템 유형입니다: ${FS_TYPE}"
        exit 1
        ;;
esac

echo -e "\n[5] 최종 확장 결과 검증 (df -h):"
df -h "$MOUNT_POINT"

echo -e "\n=========================================="
echo " [온라인 확장 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

리눅스 스토리지 스택은 물리 디스크부터 애플리케이션이 보는 마운트 디렉터리까지 **5개의 계층(Layer)**이 수직으로 쌓여 있습니다. 하위 스토리지 어레이에서 용량을 늘렸더라도 위 5개 계층을 순서대로 하나씩 넓혀주지 않으면 OS는 늘어난 공간을 전혀 사용하지 못합니다.

### 1. 스토리지 확장 5단계 계층 파이프라인

```
[5단계] 파일시스템 (Filesystem)       --> xfs_growfs /data  또는  resize2fs /dev/vg/lv
   ▲
[4단계] 논리 볼륨 (LVM LV)            --> lvextend -l +100%FREE /dev/vg/lv
   ▲
[3단계] 물리 볼륨 (LVM PV)            --> pvresize /dev/mapper/mpatha1
   ▲
[2단계] 파티션 테이블 (GPT/MBR)       --> growpart /dev/mapper/mpatha 1
   ▲
[1단계] 물리/멀티패스 디스크          --> echo 1 > /sys/class/block/sdb/device/rescan
                                          multipathd resize map mpatha
```

### 2. 단계별 핵심 포인트 및 트러블슈팅

1. **GPT 보조 헤더(Secondary GPT Header) 위치 불일치**:
   * GPT 파티션 테이블은 디스크 맨 앞과 **디스크 맨 끝 섹터**에 백업 헤더를 저장합니다. 디스크 용량을 늘리면 기존 백업 헤더가 디스크 중간에 위치하게 되어 `parted`나 `fdisk` 실행 시 `The backup GPT table is not at the end of the disk` 경고가 발생합니다.
   * `cloud-utils-growpart` 패키지의 `growpart` 명령어를 사용하면 GPT 백업 헤더를 새 디스크 끝으로 안전하게 옮기면서 파티션을 한 번에 확장해 줍니다.
2. **멀티패스(Multipath) 환경의 순서 주의**:
   * 물리 경로(`/dev/sdb`, `/dev/sdc`)를 모두 리스캔한 직후 `multipathd resize map <맵이름>`을 반드시 먼저 호출해야 상위 디바이스 매퍼(`/dev/mapper/mpatha`)의 크기가 갱신됩니다.

&nbsp;
&nbsp;

## 주의사항

1. **XFS 파일시스템은 확장(Grow)만 가능하며 축소(Shrink) 절대 불가**:
   * XFS는 아키텍처 설계상 온라인 확장은 1초 만에 처리되지만, 한 번 늘린 파일시스템 크기를 다시 줄이는 기능은 존재하지 않습니다. 용량 할당 전 반드시 정확한 증설 사이즈를 확인해야 합니다.

2. **멀티패스 경로 중 일부만 리스캔된 상태에서 확장 금지**:
   * 4개의 SAN 경로 중 3개만 1TB로 인식되고 1개가 기존 500GB로 남아있는 상태에서 `multipathd resize`나 `pvresize`를 강행하면 경로 간 블록 크기 불일치로 I/O 에러가 발생합니다. `lsblk`로 모든 하위 경로의 크기가 동일하게 갱신되었는지 먼저 검증해야 합니다.

3. **MBR(MS-DOS) 파티션의 2TB 단일 볼륨 한계**:
   * 디스크가 구형 MBR 파티션 테이블로 구성되어 있다면 2TB 이상으로 확장할 수 없습니다. 2TB 초과 증설이 필요하다면 파티션 없는 통디스크(Whole-disk PV)로 구성하거나 백업 후 GPT로 마이그레이션해야 합니다.