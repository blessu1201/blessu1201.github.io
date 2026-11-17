---
layout: article
title: 시스템 관리_59 VM 백업 솔루션 연동 후 발생하는 고아 스냅샷 Orphaned Snapshot 자동 탐지 및 제거 가이드
tags: [VMware, ESXi, vSphere, Backup, Veeam, Orphaned-Snapshot, VMDK, Datastore-Cleanup, Virtualization, Troubleshooting]
keys: 261111-linux-storage-059
---

- 출처 / 참고: VMware Broadcom Knowledge Base (Identifying and removing orphaned virtual machine files - KB 1005049), Veeam Backup & Replication Troubleshooting Guide

> 명령어: `find`, `vim-cmd`, `vmkfstools`, `grep`, `awk`, `du`  
> 키워드: Orphaned Snapshot, VM Backup, Veeam, delta.vmdk, sesparse.vmdk, vmx descriptor, Datastore Bloat, Consolidation  
> 사용처: 백업 솔루션 작업 실패 후 vSphere Client UI에는 보이지 않으나 스토리지 용량을 수백 GB씩 잠식하는 고아 스냅샷 파일 식별 및 안전한 회수

---

> 실행예제

vSphere Client의 스냅샷 관리자(Snapshot Manager)에는 스냅샷이 0개로 표시되지만, 데이터스토어 실제 사용량이 비정상적으로 크고 디렉터리 내부에 과거 백업 시점의 델타 디스크 파일들이 방치되어 있는 상태를 진단합니다.

```bash
# 1. 데이터스토어 전체에서 스냅샷 델타(-delta.vmdk, -sesparse.vmdk) 및 디스크립터 일괄 스캔
$ find /vmfs/volumes/datastore1 -type f \( -name "*-00000[0-9]*.vmdk" -o -name "*-delta.vmdk" \) -exec ls -lh {} \;
# -rw------- 1 root root  16.0M Oct 15 02:10 /vmfs/volumes/datastore1/ERP-DB/ERP-DB-000001.vmdk
# -rw------- 1 root root 185.4G Oct 15 03:45 /vmfs/volumes/datastore1/ERP-DB/ERP-DB-000001-sesparse.vmdk
# -> 10월 15일자 백업 작업 중 생성된 185GB 크기의 스냅샷 파일이 남아있음 확인

# 2. 해당 가상 머신의 활성 VMX 설정 파일이 현재 참조(마운트)하고 있는 실제 디스크 경로 확인
$ grep -i "fileName" /vmfs/volumes/datastore1/ERP-DB/ERP-DB.vmx | grep -i "\.vmdk"
# scsi0:0.fileName = "ERP-DB.vmdk"
# -> VMX 설정 파일은 최상위 베이스 디스크(ERP-DB.vmdk)만 정상 참조하고 있음!
# -> 즉, ERP-DB-000001-sesparse.vmdk는 현재 VM이 전혀 쓰지 않는 완벽한 '고아(Orphaned) 파일'임이 판명됨

# 3. ESXi 스냅샷 메타데이터 파일(.vmsd) 내용 확인
$ cat /vmfs/volumes/datastore1/ERP-DB/ERP-DB.vmsd
# .encoding = "UTF-8"
# snapshot.lastUID = "1"
# snapshot.numSnapshots = "0"
# -> .vmsd 메타데이터상 스냅샷 개수는 0개이나, 실제 스토리지 블록은 정리되지 않은 상태
```

&nbsp;
&nbsp;

## 스크립트

ESXi 호스트에 연결된 모든 데이터스토어를 탐색하여 델타 스냅샷 파일을 찾아낸 뒤, 각 디렉터리의 `.vmx` 활성 설정 및 현재 실행 중인 파일 잠금(`lsof`)과 대조하여 **실제로 사용 중인 체인인지, 안전하게 삭제 가능한 고아(Orphaned) 파일인지** 정확히 분류해 주는 감사(Audit) 쉘 스크립트입니다.

```bash
#!/bin/sh
# audit_orphaned_snapshots.sh - Safely identify orphaned VMDK snapshot files on ESXi datastores

echo "=========================================="
echo " [ESXi 고아 스냅샷(Orphaned Snapshot) 감사기]"
echo "=========================================="

DATASTORES=$(ls -d /vmfs/volumes/* 2>/dev/null)

if [ -z "$DATASTORES" ]; then
    echo "  [오류] 데이터스토어 경로를 찾을 수 없습니다."
    exit 1
fi

ORPHAN_COUNT=0
TOTAL_RECLAIMABLE_KB=0

# 1. 모든 VMFS 볼륨에서 델타 디스크 검색
for DS in $DATASTORES; do
    # 심볼릭 링크가 아닌 실제 마운트 경로만 처리하여 중복 스캔 방지
    [ -L "$DS" ] && continue
    
    DELTA_FILES=$(find "$DS" -maxdepth 3 -type f \( -name "*-00000[0-9]-sesparse.vmdk" -o -name "*-00000[0-9]-delta.vmdk" \) 2>/dev/null)
    
    for DFILE in $DELTA_FILES; do
        VM_DIR=$(dirname "$DFILE")
        F_NAME=$(basename "$DFILE")
        # 대응하는 디스크립터 이름 (예: vm-000001.vmdk)
        DESC_NAME=$(echo "$F_NAME" | sed -e 's/-sesparse\.vmdk/\.vmdk/' -e 's/-delta\.vmdk/\.vmdk/')
        VMX_FILE=$(ls "${VM_DIR}"/*.vmx 2>/dev/null | head -n 1)
        
        F_SIZE_KB=$(du -k "$DFILE" | awk '{print $1}')
        F_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $F_SIZE_KB / 1024 / 1024}")
        
        echo "------------------------------------------------------------------"
        echo "  발견된 델타 디스크 : ${DFILE}"
        echo "  점유 스토리지 용량 : ${F_SIZE_GB} GB"
        
        # 2. 해당 VMX가 이 델타 디스크를 활성 체인으로 참조하는지 검증
        IS_REFERENCED=0
        if [ -f "$VMX_FILE" ]; then
            if grep -q "$DESC_NAME" "$VMX_FILE"; then
                IS_REFERENCED=1
            fi
        fi
        
        # 3. 다른 델타 디스크의 부모(parentFileNameHint)로 체인 연결되어 있는지 검증
        IS_PARENT_CHAIN=0
        if grep -q "$DESC_NAME" "${VM_DIR}"/*-00000[0-9].vmdk 2>/dev/null; then
            IS_PARENT_CHAIN=1
        fi
        
        # 4. 현재 프로세스에 의해 열려있는지(Lock) 검증
        IS_OPENED=$(lsof 2>/dev/null | grep -c "$F_NAME")
        
        if [ "$IS_REFERENCED" -eq 0 ] && [ "$IS_PARENT_CHAIN" -eq 0 ] && [ "$IS_OPENED" -eq 0 ]; then
            echo "  [판정] ★ 확실한 고아 스냅샷(Orphaned)입니다! (활성 체인 미연결 및 잠금 없음)"
            echo "  -> 안전 삭제 명령: vmkfstools -U \"${VM_DIR}/${DESC_NAME}\""
            ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
            TOTAL_RECLAIMABLE_KB=$((TOTAL_RECLAIMABLE_KB + F_SIZE_KB))
        else
            echo "  [판정] 활성 스냅샷 체인에 연결되어 있거나 백업 프로세스가 사용 중입니다. (삭제 금지)"
        fi
    done
done

TOTAL_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_RECLAIMABLE_KB / 1024 / 1024}")

echo -e "\n=========================================="
echo " [감사 요약]"
echo "  - 탐지된 고아 스냅샷 개수 : ${ORPHAN_COUNT}개"
echo "  - 즉시 회수 가능한 용량   : ${TOTAL_GB} GB"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

Veeam, Commvault, Veritas 같은 엔터프라이즈 백업 솔루션은 가상 머신 백업 시 vCenter API를 호출하여 임시 스냅샷을 생성한 뒤 데이터를 추출하고, 백업이 완료되면 스냅샷 삭제(Delete) 명령을 내립니다. 그러나 네트워크 타임아웃이나 vCenter 세션 만료로 후처리 작업이 실패하면 **vSphere UI에는 보이지 않지만 스토리지 블록만 수백 GB씩 차지하는 고아 스냅샷(Orphaned Snapshot)**이 누적됩니다.

### 1. 고아 스냅샷의 위험성

1. **스토리지 용량 고갈 (Datastore Capacity Exhaustion)**:
   * 백업 실패가 누적되면 수백 GB 단위의 `-sesparse.vmdk` 파일들이 데이터스토어 여유 용량을 잠식하여 다른 운영 VM들의 디스크 확장을 차단합니다.
2. **가상 머신 성능 저하 (Read I/O Amplification)**:
   * 만약 고아 파일이 활성 디스크 체인 중간에 끼어있는 상태라면, ESXi가 블록을 읽을 때마다 여러 단계의 델타 파일을 순회해야 하므로 디스크 읽기 응답 지연(DAVG)이 급증합니다.

### 2. 안전한 제거 절차

#### 1단계: 활성 VMX 참조 체인 확인
가상 머신 디렉터리의 `.vmx` 파일을 열어 `scsiX:Y.fileName` 항목이 베이스 디스크(`vm.vmdk`)를 가리키고 있는지, 아니면 델타 디스크(`vm-000001.vmdk`)를 가리키고 있는지 확인합니다.
* **베이스 디스크를 가리키고 있다면**: 남아있는 `-000001` 파일은 VM이 전혀 사용하지 않는 고아 파일이므로 안전하게 삭제 가능합니다.
* **델타 디스크를 가리키고 있다면**: 고아 파일이 아니라 실제 운영 데이터가 기록 중인 활성 체인이므로 절대로 직접 삭제하면 안 되며, vSphere의 **"통합(Consolidate)"** 메뉴를 통해 병합해야 합니다.

#### 2단계: `vmkfstools -U`를 이용한 정식 삭제
`rm` 명령 대신 VMware 전용 VMDK 삭제 명령어를 사용하면 디스크립터(`.vmdk`)와 데이터 파일(`-sesparse.vmdk`) 한 쌍을 깔끔하게 동시에 지워줍니다.

```bash
vmkfstools -U /vmfs/volumes/datastore1/ERP-DB/ERP-DB-000001.vmdk
```

&nbsp;
&nbsp;

## 주의사항

1. **활성 체인에 연결된 델타 파일 삭제 절대 금지**:
   * `.vmx` 파일이 `ERP-DB-000002.vmdk`를 가리키고 있고 `000002`의 부모가 `000001.vmdk`인 상태에서 `000001`을 지워버리면, 중간 고리가 끊어져 가상 머신 부팅 불가 및 최신 데이터 영구 유실이 발생합니다. 반드시 모든 자식/부모 링크 관계를 확인한 후 제거해야 합니다.

2. **백업 스케줄 중 실행 중인 임시 스냅샷 오인 주의**:
   * 새벽 백업이 진행 중인 시간대에 스캔을 돌리면 현재 백업 솔루션이 정상적으로 생성해서 쓰고 있는 스냅샷이 탐지될 수 있습니다. 반드시 `lsof`로 파일 잠금(Lock)이 없는지 검증하고 백업 작업이 종료된 주간 시간대에 정리해야 합니다.

3. **백업 솔루션의 "Snapshot Hunter" 자동 정리 기능 활성화**:
   * Veeam 등 주요 백업 솔루션의 설정에서 '백업 작업 완료 후 잔여 스냅샷 자동 통합/제거(Snapshot Hunter)' 기능을 활성화해 두면 고아 스냅샷 누적을 원천 방지할 수 있습니다.