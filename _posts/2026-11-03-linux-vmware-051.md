---
layout: article
title: 시스템 관리_51 Linux NFS 마운트 Stale File Handle ESTALE 오류 원인 분석 및 D 상태 프로세스 안전 복구 가이드
tags: [Linux, Storage, NFS, ESTALE, Stale-File-Handle, umount, fuser, rpcdebug, autofs, Troubleshooting]
keys: 261103-linux-storage-051
---

- 출처 / 참고: Linux man-pages (nfs(5), mount(8), umount(8)), IETF RFC 7530 (Network File System (NFS) Version 4 Protocol - Section 8.4.4.1 Filehandle Inspection)

> 명령어: `umount`, `fuser`, `lsof`, `mount`, `showmount`, `rpcdebug`, `cat`  
> 키워드: NFS, ESTALE, Stale file handle, Error 116, D state, umount -l, umount -f, nfsstat, fsid, exportfs  
> 사용처: NAS/NFS 공유 디렉터리 접근 시 'Stale file handle' 오류로 서비스 장애 발생 및 프로세스가 Uninterruptible Sleep(D)에 빠졌을 때 긴급 복구

---

> 실행예제

NFS 클라이언트에서 마운트된 공유 디렉터리에 접근하거나 파일을 조회할 때 `Stale file handle (errno 116)` 오류가 발생하고 명령어가 즉시 반환되지 않거나 멈출 때, 파일시스템 상태와 해당 마운트 지점을 물고 있는 프로세스를 점검합니다.

```bash
# 1. 클라이언트 관점: 마운트 디렉터리 접근 시 ESTALE 오류 발생 확인
$ cd /mnt/nas_share
$ ls -la
# ls: cannot open directory '.': Stale file handle
$ df -h /mnt/nas_share
# df: /mnt/nas_share: Stale file handle
# -> 파일시스템 호출 시 커널이 ESTALE(116) 에러를 반환함을 확인

# 2. 마운트 옵션 및 프로토콜 버전 확인 (NFSv3 vs NFSv4)
$ mount | grep -i nfs
# 192.168.1.200:/data/share on /mnt/nas_share type nfs4 (rw,relatime,vers=4.2,rsize=1048576,wsize=1048576,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=192.168.1.100,local_lock=none,addr=192.168.1.200)

# 3. 해당 마운트 경로를 열고 있어 정체를 유발하는 프로세스 점검 (fuser)
# 일반 lsof나 fuser는 마운트가 멈추었을 때 행(Hang)에 걸릴 수 있으므로 타임아웃 옵션 고려
$ fuser -vm /mnt/nas_share
#                      USER        PID ACCESS COMMAND
# /mnt/nas_share:      appuser    4812 ..c..  java
#                      root       5102 ..c..  bash
# -> PID 4812, 5102가 현재 stale 디렉터리를 current directory(c)로 물고 있음 확인

# 4. 물려있는 프로세스의 상태(STAT) 확인 (D 상태 여부)
$ ps -eo pid,stat,time,wchan:20,comm | grep -E "4812|5102"
#   PID STAT     TIME WCHAN                COMMAND
#  4812 D        0:15 nfs_wait_on_request  java
#  5102 S        0:00 do_wait              bash
# -> java 프로세스가 D(Uninterruptible Sleep) 상태로 커널 I/O를 기다리며 멈춰 있음

# 5. NFS 서버(NAS) 단 통신 상태 점검 (RPC 포트 매퍼 및 익스포트 목록)
$ showmount -e 192.168.1.200
# Export list for 192.168.1.200:
# /data/share 192.168.1.0/24
# -> 서버의 익스포트 권한 설정은 살아있는지 확인
```

&nbsp;
&nbsp;

## 스크립트

클라이언트 시스템에서 모든 NFS 마운트 지점을 순회하며 `ESTALE` 상태를 자동으로 감지하고, 해당 마운트를 점유하여 언마운트를 방해하는 프로세스를 추출한 뒤 지연 언마운트(`umount -l`)를 통해 시스템 재부팅 없이 마운트를 안전하게 재설정하는 복구 쉘 스크립트입니다.

```bash
#!/bin/bash
# fix_nfs_estale.sh - Detect and safely recover Stale NFS mount points on Linux

echo "=========================================="
echo " [Linux NFS Stale File Handle (ESTALE) 진단기]"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] 파일시스템 마운트 관리를 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

# 1. /proc/mounts 에서 모든 NFS 마운트 지점 파싱
NFS_MOUNTS=$(awk '$3 ~ /^nfs/ {print $2}' /proc/mounts)

if [ -z "$NFS_MOUNTS" ]; then
    echo "  [안내] 시스템에 마운트된 NFS 디렉터리가 없습니다."
    exit 0
fi

STALE_FOUND=0

echo -e "\n[1] 마운트 지점 헬스체크 진행 중..."
for MNT in $NFS_MOUNTS; do
    # stat 또는 readlink로 비동기 검사 (서버 무응답 시 무한정 멈추는 것을 방지하기 위해 timeout 2초 지정)
    timeout 2 stat "$MNT" >/dev/null 2>&1
    RET=$?
    
    if [ $RET -eq 124 ]; then
        echo "  [타임아웃] 마운트 경로: ${MNT} (서버 무응답 또는 완전 행 상태)"
        STALE_FOUND=1
    elif [ $RET -ne 0 ]; then
        # errno 116 확인을 위한 상세 문자열 검증
        ERR_MSG=$(ls -d "$MNT" 2>&1)
        if echo "$ERR_MSG" | grep -qi "stale"; then
            echo "  [경고] ESTALE 감지됨: ${MNT}"
            STALE_FOUND=1
            TARGET_MNT="$MNT"
            
            # 2. 마운트 지점을 물고 있는 프로세스 탐색
            echo -e "\n[2] ${TARGET_MNT} 점유 프로세스 추적:"
            BLOCKING_PIDS=$(fuser -m "$TARGET_MNT" 2>/dev/null)
            
            if [ -n "$BLOCKING_PIDS" ]; then
                echo "  - 점유 중인 PID: ${BLOCKING_PIDS}"
                ps -fp ${BLOCKING_PIDS} 2>/dev/null | awk '{printf "    -> PID: %-6s | STAT: %-4s | CMD: %s\n", $2, $8, $8}'
            else
                echo "  - 직접적인 프로세스 점유 없음."
            fi
            
            # 3. 안전한 Lazy Unmount 실행
            echo -e "\n[3] 지연 언마운트(Lazy Unmount) 조치 실행:"
            echo "  -> 실행 명령어: umount -l ${TARGET_MNT}"
            umount -l "$TARGET_MNT"
            
            if [ $? -eq 0 ]; then
                echo "  [성공] ${TARGET_MNT} 지연 언마운트 완료."
                echo "  -> 마운트 테이블에서 즉시 분리되었으며, 잔여 파일 핸들이 닫히는 대로 시스템 자원이 정리됩니다."
            else
                echo "  [강제 시도] 일반/지연 실패로 강제 언마운트 시도: umount -f -l ${TARGET_MNT}"
                umount -f -l "$TARGET_MNT"
            fi
            
            # 4. fstab 기반 자동 재마운트 시도
            echo -e "\n[4] fstab 기준 마운트 복구 시도:"
            if grep -qs "$TARGET_MNT" /etc/fstab; then
                mount "$TARGET_MNT" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo "  [복구 완료] ${TARGET_MNT} 정상 재마운트 성공."
                else
                    echo "  [주의] 재마운트 실패. 스토리지 서버(NAS)의 exportfs 상태를 점검하십시오."
                fi
            else
                echo "  [알림] /etc/fstab에 설정이 없어 수동 mount 명령이 필요합니다."
            fi
        fi
    else
        echo "  - 정상: ${MNT}"
    fi
done

if [ "$STALE_FOUND" -eq 0 ]; then
    echo "  [정상] 점검된 모든 NFS 마운트가 정상 접근 가능합니다."
fi

echo -e "\n=========================================="
echo " [점검 및 조치 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

`Stale file handle (오류 코드: 116 / ESTALE)`은 클라이언트 커널이 캐시하고 있는 특정 파일이나 디렉터리의 **NFS 파일 핸들(File Handle)**이 서버(NAS 또는 NFS 서버) 측에서 더 이상 유효하지 않거나 일치하지 않을 때 반환되는 표준 POSIX 에러입니다.

### 1. NFS 파일 핸들과 ESTALE 발생 원리

NFS 프로토콜은 로컬 파일시스템과 달리 경로명(Pathname)이 아니라 서버가 발행한 불투명한 고유 식별자인 **파일 핸들(File Handle: 파일시스템 ID, inode 번호, 세대 번호/Generation Number의 조합)**을 통해 객체를 식별합니다.

1. **서버 측 파일/디렉터리 삭제 또는 재생성 (가장 흔함)**:
   * 클라이언트의 어떤 프로세스가 `/mnt/nas/data.log` 파일을 열어두거나 해당 디렉터리를 `cd`로 참조하고 있는 도중에, 서버 측에서 해당 파일/디렉터리를 삭제하거나 동일한 이름으로 다시 생성한 경우입니다.
   * 이름은 같더라도 서버 내부의 inode 번호나 generation number가 변경되었기 때문에, 클라이언트가 보내는 기존 파일 핸들은 서버에서 "존재하지 않는 오래된 핸들(Stale)"로 판정되어 즉시 거부됩니다.
2. **NFS 서버(NAS) 재부팅 또는 파일시스템 재익스포트(`exportfs -r`)**:
   * 서버 측의 볼륨 마운트 구조가 변경되었거나, NFSv3 환경에서 `fsid` 파라미터가 명시되지 않아 재부팅 후 파일시스템 UUID 기반 핸들이 어긋난 경우 발생합니다.
3. **스토리지 페일오버(Failover) 시 볼륨 ID 불일치**:
   * Active-Standby NAS 이중화 환경에서 컨트롤러 절체 시 대기 장비의 볼륨 생성 파라미터(fsid)가 원본 장비와 일치하지 않을 때 모든 연결 클라이언트에 동시다발적인 ESTALE 장애가 터집니다.

### 2. 일반 `umount`{:.info}가 실패하고 프로세스가 멈추는 이유

* 마운트가 Stale 상태에 빠졌을 때 일반적인 `umount /mnt/nas`를 내리면 OS는 "파일시스템이 아직 사용 중(Device or resource busy)"이라며 명령을 거절합니다.
* 더 큰 문제는 클라이언트의 애플리케이션(Java, Python, C)이 해당 디렉터리에 파일 I/O를 호출하면 커널 스케줄러가 응답을 무한정 기다리는 **D 상태(Uninterruptible Sleep)**로 프로세스를 전환시킨다는 점입니다. D 상태 프로세스는 `kill -9` 시그널조차 수신하지 못합니다.

### 3. 단계별 해결 방법

#### 1) 지연 언마운트 (Lazy Unmount: `umount -l`{:.info}) 적용
단순 강제 언마운트(`umount -f`)는 서버와의 통신이 끊겼을 때 여전히 행(Hang)에 걸릴 위험이 큽니다. 반면 **지연 언마운트(`umount -l`)**는 가장 안전하고 확실한 방법입니다.

```bash
# 마운트 네임스페이스에서 즉시 분리하고, 열려있는 파일 핸들이 닫히는 대로 백그라운드 정리
sudo umount -l /mnt/nas_share
```
* `umount -l`을 실행하면 즉시 마운트 지점이 깨끗하게 떨어져 나가므로, 동일한 마운트 포인트에 신규 마운트를 즉각 맺을 수 있습니다.

#### 2) `fuser`{:.info}를 이용한 점유 세션 강제 종료
Stale 디렉터리에 갇혀 있는 셸(Bash)이나 프로세스를 정리합니다.

```bash
# 마운트 지점에 물려있는 모든 프로세스에 SIGKILL 전달
sudo fuser -k -9 -m /mnt/nas_share
```

#### 3) 올바른 마운트 옵션으로 재연결
재마운트 시 네트워크 지연으로 인한 영구 행을 방지할 수 있는 옵션을 적용합니다.

```bash
sudo mount -t nfs -o rw,bg,hard,nointr,rsize=1048576,wsize=1048576,timeo=600,retrans=2 192.168.1.200:/data/share /mnt/nas_share
```

#### 4) 서버 측 영구 fsid 설정 (서버 관리자)
서버의 `/etc/exports` 설정 시 고정된 `fsid`를 부여하면 NAS 컨트롤러 절체나 데몬 재시작 후에도 파일 핸들 일관성을 유지할 수 있습니다.

```text
/data/share 192.168.1.0/24(rw,sync,no_root_squash,fsid=101)
```

&nbsp;
&nbsp;

## 주의사항

1. **D 상태 프로세스에 대한 `kill -9`{:.info} 남발 주의**:
   * ESTALE로 인해 커널 I/O 대기열에 걸려 `D` 상태로 굳어버린 프로세스는 `kill -9`를 보내도 종료되지 않으며 프로세스 테이블에 좀비처럼 남게 됩니다. 이 경우 마운트를 `umount -l`로 먼저 끊어주어야 커널이 I/O 실패 에러(EIO)를 프로세스로 리턴하면서 프로세스가 자연스럽게 깨어나 종료됩니다.

2. **`soft`{:.info} 마운트 옵션 사용 시 데이터 손상(Silent Data Corruption) 위험**:
   * ESTALE이나 무응답 시 빠른 타임아웃 처리를 위해 `soft` 옵션을 주는 경우가 있으나, 이는 쓰기 I/O 실패 시 커널이 데이터를 조용히 폐기하여 심각한 데이터 손상을 유발할 수 있습니다. 엔터프라이즈 환경에서는 항상 `hard` 옵션을 사용하고 `timeo`와 `retrans`를 적절히 조절해야 합니다.

3. **자동 마운트 도구(Autofs) 도입 검토**:
   * 상시 마운트된 디렉터리는 서버 재부팅 시 ESTALE에 취약합니다. 접근 시에만 동적으로 마운트하고 일정 시간 유휴 시 자동 언마운트해 주는 `autofs` 서비스를 구성하면 ESTALE 발생 빈도를 90% 이상 예방할 수 있습니다.