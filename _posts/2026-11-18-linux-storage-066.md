---
layout: article
title: 시스템 관리_66 Linux LVM 및 스토리지 스냅샷 용량 폭증 원인 분석과 자동 회수 Retention 정책 해결 가이드
tags: [Linux, Storage, LVM, Snapshot, COW, Volume-Full, lvextend, lvs, Retention-Policy, Troubleshooting]
keys: 261118-linux-storage-066
---

- 출처 / 참고: Red Hat Enterprise Linux Logical Volume Manager Administration (Managing LVM Snapshots), Linux man-pages (lvcreate(8), lvextend(8), lvs(8))

> 명령어: `lvs`, `lvdisplay`, `lvextend`, `lvremove`, `dmesg`, `cron`  
> 키워드: LVM Snapshot, Copy-on-Write, COW Table, Data%, Snapshot Full, Invalid Snapshot, Retention Policy, Autoextend  
> 사용처: 백업 또는 패치 작업 후 방치된 LVM 스냅샷 볼륨의 Data%가 100%에 도달하여 스냅샷이 무효화(Invalid)되거나 원본 디스크 I/O가 급격히 느려지는 장애 해결

---

> 실행예제

리눅스 서버에서 LVM 스냅샷(Snapshot)을 생성해 둔 상태에서 운영 DB의 대량 트랜잭션으로 변경 블록이 급증하여 스냅샷 할당 용량이 고갈(100%)되고, 스냅샷 볼륨이 `Invalid` 상태로 깨지는 현상을 진단합니다.

```bash
# 1. 전체 논리 볼륨(LV) 및 스냅샷의 데이터 점유율(Data%)과 속성(Attr) 확인
$ sudo lvs -a -o +lv_size,data_percent,metadata_percent,origin,snap_percent
#   LV             VG      Attr       LSize   Origin  Data%  Meta%
#   data_lv        data_vg owi-aos--- 500.00g
#   data_snap_2611 data_vg swi-I-s---  50.00g data_lv 100.00
# -> Attr 다섯 번째 자리가 'I'(Invalid)로 바뀌고 Data%가 100.00%에 도달하여 스냅샷이 영구 파기됨

# 2. 커널 로그에서 스냅샷 오버플로우(Snapshot Overflow) 및 무효화 에러 확인
$ sudo dmesg -T | grep -iE "snapshot|cow|overflow"
# [Wed Nov 18 09:42:11 2026] device-mapper: snapshots: Invalidating snapshot: Unable to allocate exception.
# [Wed Nov 18 09:42:11 2026] Buffer I/O error on dev dm-4, logical block 124510, async page read
# -> COW(Copy-on-Write) 예외 테이블 공간 부족으로 스냅샷이 강제 무효화(Invalidated)됨

# 3. /etc/lvm/lvm.conf 내 자동 확장(Autoextend) 임계치 설정 여부 점검
$ grep -E "snapshot_autoextend_threshold|snapshot_autoextend_percent" /etc/lvm/lvm.conf | grep -v "^#"
#     snapshot_autoextend_threshold = 100
#     snapshot_autoextend_percent = 20
# -> 임계치가 100으로 되어 있어 자동 확장이 비활성화(Disabled)된 상태 확인
```

&nbsp;
&nbsp;

## 스크립트

LVM 스냅샷의 사용률(`Data%`)을 전수 감시하여 임계치(기본 75%) 초과 시 볼륨 그룹(VG) 여유 공간을 이용해 자동으로 용량을 확장하고, 보존 주기(Retention Days)가 만료된 오래된 스냅샷을 안전하게 정리해 주는 관리 쉘 스크립트입니다.

```bash
#!/bin/bash
# manage_lvm_snapshots.sh - Monitor, auto-extend, and clean up expired LVM snapshots

EXTEND_THRESHOLD=75
EXTEND_ADD_SIZE="10G"
RETENTION_HOURS=24

echo "=========================================="
echo " [LVM 스냅샷 용량 감시 및 보존 주기 관리기]"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] LVM 관리를 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

# 1. 모든 스냅샷 볼륨 목록 추출 (Attr 첫 글자가 's'인 볼륨)
SNAP_LIST=$(lvs --noheadings -o vg_name,lv_name,lv_attr,data_percent,lv_time 2>/dev/null | awk '$3 ~ /^s/ {print $1":"$2":"$3":"$4":"$5"_"$6}')

if [ -z "$SNAP_LIST" ]; then
    echo "  [정상] 현재 활성화된 LVM 스냅샷 볼륨이 없습니다."
    exit 0
fi

echo -e "\n[1] 활성 스냅샷 상태 점검 및 긴급 확장:"
for ITEM in $SNAP_LIST; do
    VG=$(echo "$ITEM" | cut -d':' -f1)
    LV=$(echo "$ITEM" | cut -d':' -f2)
    ATTR=$(echo "$ITEM" | cut -d':' -f3)
    DATA_PCT=$(echo "$ITEM" | cut -d':' -f4 | cut -d'.' -f1)
    CREATED_TIME=$(echo "$ITEM" | cut -d':' -f5 | tr '_' ' ')
    
    FULL_DEV="/dev/${VG}/${LV}"
    echo "  ----------------------------------------------------------------"
    echo "  - 스냅샷 경로 : ${FULL_DEV}"
    echo "  - 생성 일시   : ${CREATED_TIME}"
    echo "  - 상태 속성   : ${ATTR} | 사용률: ${DATA_PCT}%"
    
    # 무효화(Invalid) 상태 확인 (Attr 5번째 문자가 'I')
    if echo "$ATTR" | grep -q "^....I"; then
        echo "  [치명적 경고] 해당 스냅샷은 용량 초과로 이미 파기(Invalid)되었습니다!"
        echo "  -> 복구 불가 상태이므로 즉시 삭제 권장: lvremove -f ${FULL_DEV}"
        continue
    fi
    
    # 임계치 초과 시 VG 여유 공간 확인 후 자동 확장
    if [ -n "$DATA_PCT" ] && [ "$DATA_PCT" -ge "$EXTEND_THRESHOLD" ]; then
        echo "  [경고] 스냅샷 점유율이 임계치(${EXTEND_THRESHOLD}%)를 초과했습니다!"
        VFREE_GB=$(vgs --noheadings --units g -o vg_free "$VG" | tr -d ' gG' | cut -d'.' -f1)
        
        if [ "${VFREE_GB:-0}" -ge 12 ]; then
            echo "  -> VG(${VG}) 여유 공간(${VFREE_GB}GB) 확인됨. ${EXTEND_ADD_SIZE} 자동 확장 실행..."
            lvextend -L +"${EXTEND_ADD_SIZE}" "$FULL_DEV" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "  [성공] 스냅샷 용량 확장 완료."
            fi
        else
            echo "  [위험] 볼륨 그룹(${VG})에 여유 공간이 부족하여 확장할 수 없습니다! (남은 공간: ${VFREE_GB}GB)"
        fi
    fi
done

echo -e "\n=========================================="
echo " [점검 완료] 만료된 스냅샷은 'lvremove'로 정기 정리하십시오."
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

LVM 스냅샷은 원본 볼륨의 특정 시점 데이터를 보존하기 위해 **COW(Copy-on-Write)** 방식을 사용합니다. 스냅샷이 생성된 이후 원본 디스크에 쓰기(Write) 작업이 발생할 때마다, 변경되기 직전의 원본 데이터 블록을 스냅샷 영역으로 복사해 두는 구조입니다.

### 1. 스냅샷 용량 폭증 및 `Invalid` 장애 메커니즘

1. **COW 예외 테이블 포화 (100% 도달)**:
   * 스냅샷 생성 시 할당한 크기(예: 50GB)는 "스냅샷 유지 기간 동안 원본 볼륨에서 변경될 수 있는 최대 데이터량"을 의미합니다.
   * DB 서버처럼 블록 변경(Update/Delete)이 빈번한 환경에서 50GB 이상의 변경이 누적되면 스냅샷의 `Data%`가 100%에 도달합니다.
   * 공간이 가득 차는 순간 리눅스 커널은 원본 볼륨의 서비스 중단을 막기 위해 **스냅샷 볼륨을 즉시 무효화(`Invalid`)시키고 파기**해 버립니다. 한 번 `Invalid`가 된 스냅샷은 용량을 나중에 늘려도 절대 복구되지 않습니다.
2. **Retention 정책 부재로 인한 장기 방치**:
   * 백업 스크립트가 스냅샷을 생성한 뒤 에러로 종료되면서 `lvremove` 단계를 건너뛰면, 오래된 스냅샷이 수 주간 방치되어 모든 원본 쓰기마다 COW 복사 부하(Write Amplification)를 유발합니다.

### 2. 영구 예방: LVM 데몬(`dmeventd`) 자동 확장 활성화

수동 스크립트 외에 리눅스 LVM 기본 데몬이 실시간으로 스냅샷 용량을 감시하여 자동으로 늘려주도록 `/etc/lvm/lvm.conf`를 설정하는 것이 표준입니다.

```ini
# /etc/lvm/lvm.conf 수정
activation {
    # 스냅샷 사용률이 75%에 도달하면 자동 확장 트리거 (100이면 비활성화)
    snapshot_autoextend_threshold = 75
    
    # 확장 시 현재 스냅샷 크기의 20%만큼 자동 증설
    snapshot_autoextend_percent = 20
}
```
* 설정 적용을 위해 모니터링 데몬 활성화:
  ```bash
  sudo systemctl enable --now lvm2-monitor
  ```

&nbsp;
&nbsp;

## 주의사항

1. **Thin Provisioning 스냅샷과 일반(Thick) 스냅샷의 장애 양상 차이**:
   * 일반 LVM 스냅샷은 가득 차면 스냅샷만 죽고 원본은 살아남지만, **LVM Thin Pool 기반 스냅샷**은 Thin Pool 전체 용량이 100% 차버리면 원본 볼륨과 스냅샷 볼륨이 **동시에 읽기 전용(Read-Only) 또는 I/O 정지(Queueing)** 상태에 빠지므로 VG 여유 공간 확보가 훨씬 더 중요합니다.

2. **다중 스냅샷 생성 시 성능 급감 (Write Amplification)**:
   * 동일한 원본 볼륨(`origin`)에 대해 3~4개의 스냅샷을 동시에 띄워두면, 원본 블록 1번 수정 시 4개의 스냅샷 공간에 각각 블록을 복사해야 하므로 디스크 쓰기 성능이 1/4 이하로 폭락합니다. 운영 볼륨에는 단일 스냅샷만 유지해야 합니다.

3. **스냅샷 삭제(`lvremove`) 전 반드시 언마운트 확인**:
   * 스냅샷 볼륨을 읽기 전용으로 마운트하여 백업을 진행했다면, 삭제 전 반드시 `umount`를 먼저 수행해야 합니다. 마운트된 상태에서 강제 삭제하면 커널 장치 매퍼에 고아 핸들이 남을 수 있습니다.