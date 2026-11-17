---
layout: article
title: 시스템 관리_60 VMware CBT Changed Block Tracking 손상으로 인한 증분 백업 실패 및 풀 백업 전환 복구 가이드
tags: [VMware, ESXi, vSphere, CBT, Changed-Block-Tracking, Backup-Failure, CTK, vmdk, Virtualization, Troubleshooting]
keys: 261112-linux-storage-060
---

- 출처 / 참고: VMware Broadcom Knowledge Base (Resetting Changed Block Tracking for VMware vSphere virtual machines - KB 1031873, QueryChangedDiskAreas API returns incorrect sectors - KB 2136854)

> 명령어: `vim-cmd`, `grep`, `ls`, `rm`, `sed`  
> 키워드: CBT, Changed Block Tracking, ctkEnabled, *-ctk.vmdk, Incremental Backup Failure, QueryChangedDiskAreas, Reset CBT  
> 사용처: 가상 머신 디스크 크기 증설(Extend) 또는 ESXi 강제 리부팅 후 증분 백업 실패 및 강제 전체 백업(Full Backup) 전환 장애 복구

---

> 실행예제

가상 머신의 디스크 용량을 확장하거나 호스트가 비정상 재부팅된 후 백업 솔루션에서 `Error: Failed to call QueryChangedDiskAreas` 또는 `CBT data is corrupted` 오류를 내며 증분 백업이 실패할 때, ESXi 셸에서 CTK(Change Tracking) 파일 상태를 진단합니다.

```bash
# 1. 가상 머신의 VMX 설정에서 CBT(ctkEnabled) 활성화 여부 확인
$ grep -iE "ctkEnabled|ctkDisallowed" /vmfs/volumes/datastore1/Mail-Server/Mail-Server.vmx
# ctkEnabled = "TRUE"
# scsi0:0.ctkEnabled = "TRUE"

# 2. 데이터스토어 디렉터리에서 변경 블록 추적 파일(*-ctk.vmdk) 존재 및 타임스탬프 확인
$ ls -lh /vmfs/volumes/datastore1/Mail-Server/*-ctk.vmdk
# -rw------- 1 root root 1.2M Nov 12 01:00 Mail-Server-ctk.vmdk
# -rw------- 1 root root 2.4M Oct 20 02:00 Mail-Server_1-ctk.vmdk
# -> 두 번째 디스크의 ctk 파일 날짜가 오래되어 메인 디스크 크기 확장 후 동기화가 깨진 상태 확인

# 3. vmware.log에서 CBT 인덱스 불일치 및 읽기 실패 로그 검색
$ grep -iE "ctk|changed block|QueryChangedDiskAreas" /vmfs/volumes/datastore1/Mail-Server/vmware.log | tail -n 15
# [출력 예시]
# DISKLIB-CTK   : Could not open change tracking file "/vmfs/volumes/datastore1/Mail-Server/Mail-Server_1-ctk.vmdk": Change tracking invalid.
# DISKLIB-CTK   : Disabling change tracking on disk "Mail-Server_1.vmdk".
```

&nbsp;
&nbsp;

## 스크립트

ESXi 호스트에서 특정 가상 머신의 손상된 CBT(Changed Block Tracking) 상태를 무중단(가상 머신 전원 끄기 없이)으로 리셋하고 재활성화하기 위해 스냅샷 생성/삭제 사이클을 트리거하여 깨끗한 `*-ctk.vmdk` 맵을 재생성하는 자동화 쉘 스크립트입니다.

```bash
#!/bin/sh
# reset_vmware_cbt.sh - Non-disruptive CBT (Changed Block Tracking) reset on ESXi

VM_NAME=${1:-""}

echo "=========================================="
echo " [VMware CBT(변경 블록 추적) 무중단 리셋 도구]"
echo "=========================================="

if [ -z "$VM_NAME" ]; then
    echo "  [오류] 대상 가상 머신 이름을 입력하십시오."
    echo "  사용법: $0 <VM_Display_Name>"
    exit 1
fi

# 1. VMID 및 디렉터리 확인
VM_LINE=$(vim-cmd vmsvc/getallvms 2>/dev/null | grep -F "$VM_NAME" | head -n 1)
if [ -z "$VM_LINE" ]; then
    echo "  [오류] 가상 머신 '${VM_NAME}'을(를) 찾을 수 없습니다."
    exit 1
fi

VMID=$(echo "$VM_LINE" | awk '{print $1}')
VMX_PATH=$(vim-cmd vmsvc/get.summary "$VMID" | grep "vmPathName =" | awk -F'"' '{print $2}')
VM_DIR=$(dirname "$VMX_PATH")

echo "  - 대상 VM명 : ${VM_NAME} (VMID: ${VMID})"
echo "  - VMX 경로  : ${VMX_PATH}"

# 2. 기존 스냅샷 존재 여부 사전 검증 (스냅샷이 있으면 CBT 리셋 불가)
SNAP_COUNT=$(vim-cmd vmsvc/snapshot.get "$VMID" 2>/dev/null | grep -c "Snapshot Name")
if [ "$SNAP_COUNT" -gt 0 ]; then
    echo "  [치명적 경고] 현재 가상 머신에 ${SNAP_COUNT}개의 스냅샷이 존재합니다!"
    echo "  -> 기존 스냅샷이 있는 상태에서는 CBT를 안전하게 리셋할 수 없습니다. 먼저 스냅샷을 삭제/통합하십시오."
    exit 1
fi

# 3. VMX 파일 백업 및 ctkEnabled 설정 비활성화
echo -e "\n[1] VMX 설정 백업 및 CBT 임시 비활성화:"
cp -p "$VMX_PATH" "${VMX_PATH}.cbt_bak"

sed -i 's/ctkEnabled = "TRUE"/ctkEnabled = "FALSE"/gi' "$VMX_PATH"
vim-cmd vmsvc/reload "$VMID"
echo "  - ctkEnabled = FALSE 적용 및 VMX 리로드 완료."

# 4. 무중단 스냅샷 생성 및 즉시 삭제를 통한 기존 ctk 파일 잠금 해제 트리거
echo -e "\n[2] 헬퍼 스냅샷 생성 및 삭제를 통한 변경 추적 캐시 플러시:"
vim-cmd vmsvc/snapshot.create "$VMID" "CBT_Reset_Temp" "Temporary snapshot for CBT reset" 0 0 >/dev/null 2>&1
sleep 3
vim-cmd vmsvc/snapshot.removeall "$VMID" >/dev/null 2>&1
sleep 3

# 5. 잔여 손상된 *-ctk.vmdk 파일 정리
echo -e "\n[3] 손상된 기존 *-ctk.vmdk 파일 제거:"
rm -f "${VM_DIR}"/*-ctk.vmdk
echo "  - 이전 CTK 파일 삭제 완료."

# 6. CBT 재활성화 및 헬퍼 스냅샷 사이클로 새 CTK 맵 생성
echo -e "\n[4] CBT 재활성화(TRUE) 및 신규 추적 맵 초기화:"
sed -i 's/ctkEnabled = "FALSE"/ctkEnabled = "TRUE"/gi' "$VMX_PATH"
vim-cmd vmsvc/reload "$VMID"

vim-cmd vmsvc/snapshot.create "$VMID" "CBT_Init_Temp" "Initialize fresh CBT map" 0 0 >/dev/null 2>&1
sleep 3
vim-cmd vmsvc/snapshot.removeall "$VMID" >/dev/null 2>&1

# 7. 신규 CTK 파일 생성 검증
echo -e "\n[5] 최종 검증:"
NEW_CTK=$(ls -lh "${VM_DIR}"/*-ctk.vmdk 2>/dev/null)
if [ -n "$NEW_CTK" ]; then
    echo "  [성공] 깨끗한 신규 CTK 추적 파일이 생성되었습니다:"
    echo "$NEW_CTK" | sed 's/^/    /'
    echo "  -> 다음 백업 실행 시 1회 풀 백업(Active Full) 후 정상적인 증분 백업이 수행됩니다."
else
    echo "  [주의] 신규 CTK 파일이 아직 보이지 않습니다. 다음 백업 소프트웨어가 스냅샷을 생성할 때 자동 초기화됩니다."
fi

echo -e "\n=========================================="
echo " [CBT 리셋 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

VMware의 **CBT(Changed Block Tracking)**는 가상 머신이 켜진 상태에서 마지막 백업 이후 변경된 디스크 섹터 블록의 주소만을 기록하는 핵심 백업 가속 기능입니다. 이 정보가 담기는 파일이 바로 가상 머신 디렉터리의 `*-ctk.vmdk` 파일입니다.

### 1. CBT가 손상되는 주요 원인

1. **가상 디스크(VMDK) 용량 증설 (Disk Extend)**:
   * 디스크 용량을 100GB에서 200GB로 늘렸으나 CBT 비트맵 테이블의 섹터 인덱스가 새 디스크 기하 구조와 맞지 않아 `QueryChangedDiskAreas` API 호출 시 `Invalid parameter` 또는 섹터 계산 오류를 일으키는 경우.
2. **ESXi 호스트 비정상 전원 차단 및 스토리지 단절**:
   * 메모리에 캐싱된 CBT 변경 비트맵이 디스크의 `*-ctk.vmdk` 파일에 플러시되기 전에 호스트가 다운되어 비트맵 정합성이 깨진 경우.
3. **스토리지 마이그레이션(Storage vMotion) 도중 네트워크 순단**:
   * 디스크 이동 중 원본과 대상 스토리지 간 CTK 동기화 체인이 어긋난 경우.

### 2. 왜 단순 VMX 수정만으로는 안 되고 스냅샷 사이클이 필요한가

가상 머신이 전원이 켜진(Powered On) 상태에서는 하이퍼바이저 커널(`vmx`)이 기존 손상된 `*-ctk.vmdk` 파일에 배타적 락(Lock)을 걸고 메모리에 상태를 유지합니다.
* VM을 끄지 않고 무중단으로 리셋하려면, `ctkEnabled = "FALSE"`로 바꾼 뒤 **임시 스냅샷 생성 및 삭제(Create & Delete Snapshot)**를 한 번 돌려야 ESXi가 디스크 핸들을 재오픈하면서 기존 잠금을 풀고 새로운 상태를 반영하게 됩니다.

&nbsp;
&nbsp;

## 주의사항

1. **CBT 리셋 직후 첫 번째 백업은 반드시 전체(Full) 데이터 스캔 발생**:
   * CBT를 초기화하면 "어떤 블록이 바뀌었는지"에 대한 과거 이력이 모두 비워지므로, 리셋 후 처음 실행되는 백업 작업은 전체 디스크 블록을 모두 읽어 들이는 **Active Full(또는 대용량 초기 동기화)**로 동작합니다. 스토리지 I/O 부하와 네트워크 대역폭을 고려하여 주간 피크 타임을 피해 리셋해야 합니다.

2. **기존 스냅샷이 있는 VM에서는 CBT 리셋 절대 금지**:
   * 스냅샷이 1개 이상 걸려 있는 상태에서 CBT 설정을 변경하거나 `*-ctk.vmdk` 파일을 수동으로 지우면 스냅샷 체인과 추적 파일이 꼬여 가상 머신 디스크 인식 불능 상태가 될 수 있습니다. 반드시 스냅샷이 0개인 상태에서 진행해야 합니다.

3. **vSphere 하드웨어 버전 7 이상 필수**:
   * CBT는 VM Hardware Version 7 이상에서만 지원되는 기능이므로 레거시 구형 VM의 경우 하드웨어 호환성 업그레이드가 선행되어야 합니다.