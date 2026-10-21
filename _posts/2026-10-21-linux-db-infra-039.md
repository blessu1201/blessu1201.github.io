---
layout: article
title: 시스템 관리_39 파일시스템 블록 한계로 인한 데이터베이스 데이터파일 자동확장 실패 오류 원인 분석 및 해결 가이드
tags: [Linux, Database, Filesystem, Block-Limits, ext4, xfs, Datafile, AUTOEXTEND, ORA-01119, Smallfile, Bigfile, DBA, Troubleshooting]
keys: 261021-linux-db-infra-039
---

- 출처 / 참고: Linux man-pages (tune2fs(8), xfs_info(8), statvfs(3)), Oracle Database Administrator's Guide (Physical Database Structures), PostgreSQL Documentation (Database File Layout)

> 명령어: `df`, `tune2fs`, `xfs_info`, `dumpe2fs`, `stat`, `blockdev`, `sqlplus`  
> 키워드: Filesystem Block Limit, Block Size, 4KB block, Datafile Auto-Extend Failure, ext4 max file size, Smallfile 32GB limit, Bigfile Tablespace, ORA-01119  
> 사용처: 디스크 용량이 남아있음에도 불구하고 데이터파일 확장 실패, DB 테이블스페이스 추가/크기 조정 거부 장애 해결

---

> 실행예제

OS 디스크 여유 공간(`df -h`)은 충분함에도 데이터베이스(Oracle, PostgreSQL, MySQL 등)에서 데이터파일 크기를 확장(`AUTOEXTEND` 또는 `RESIZE`)하려 할 때 파일시스템 블록 구조적 제한이나 OS 파일 크기 제한으로 인해 실패하는 현상을 진단합니다.

```bash
# 1. OS 관점: 파티션의 전체 용량과 블록 여유 공간 확인
$ df -h /u01/app/oracle/oradata
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/sdb1       2.0T  1.2T  800G  60% /u01/app/oracle/oradata
# -> 디스크 가용 용량은 800GB로 넉넉한 상태 확인

# 2. 파일시스템 타입 및 블록 크기(Block Size) 확인
# ext4 파일시스템인 경우:
$ sudo tune2fs -l /dev/sdb1 | grep -i "block size"
# Block size:               4096
# XFS 파일시스템인 경우:
$ sudo xfs_info /u01/app/oracle/oradata | grep -i "bsize"
# data     =                       bsize=4096   blocks=524288000, imaxpct=25

# 3. 현재 문제의 데이터파일 실제 크기(바이트) 및 할당 블록 수 확인
$ ls -lh /u01/app/oracle/oradata/users01.dbf
# -rw-r----- 1 oracle dba 32G Oct 21 09:30 /u01/app/oracle/oradata/users01.dbf
$ stat /u01/app/oracle/oradata/users01.dbf
#  File: /u01/app/oracle/oradata/users01.dbf
#  Size: 34359721984     Blocks: 67108840   IO Block: 4096   regular file
# -> 정확히 32GB (34,359,721,984 bytes) 경계에 도달해 있는지 확인

# 4. 데이터베이스 에러 로그 확인 (오라클 예시)
$ tail -n 20 $ORACLE_BASE/diag/rdbms/$ORACLE_SID/$ORACLE_SID/trace/alert_$ORACLE_SID.log
# [출력 예시]
# ORA-01119: error in creating database file '/u01/app/oracle/oradata/users01.dbf'
# ORA-27059: could not resize file
# Linux-x86_64 Error: 27: File too large
# Additional information: 2
# -> OS 에러로 "File too large" (EFBIG, 27)가 전달되었거나 DB 내부 블록 제한 도달 확인

# 5. 오라클 내부 테이블스페이스가 Smallfile인지 Bigfile인지 조회
$ sqlplus -s / as sysdba << 'EOF'
SELECT tablespace_name, bigfile, block_size 
FROM dba_tablespaces 
WHERE tablespace_name = 'USERS';
EXIT;
EOF
# TABLESPACE_NAME BIGFILE BLOCK_SIZE
# --------------- ------- ----------
# USERS           NO            8192
# -> Smallfile(BIGFILE=NO)이고 8KB 블록인 경우 최대 단일 파일 한도는 32GB(4194303 * 8KB)에 고정됨
```

&nbsp;
&nbsp;

## 스크립트

데이터베이스 마운트 포인트의 파일시스템 종류(ext4/xfs) 및 블록 크기, OS 수준의 단일 파일 최대 허용 크기를 진단하고, 데이터파일들이 32GB(Smallfile 한계) 또는 OS 한계에 도달하여 자동확장이 멈출 위험이 있는지 점검하는 쉘 스크립트입니다.

```bash
#!/bin/bash
# check_fs_block_limits.sh - Diagnose Filesystem block size and DB datafile size boundary

DATAFILE_DIR=${1:-"/u01/app/oracle/oradata"}

echo "=========================================="
echo " [파일시스템 블록 및 데이터파일 한계 진단]"
echo " 대상 경로: ${DATAFILE_DIR}"
echo "=========================================="

if [ ! -d "$DATAFILE_DIR" ]; then
    echo "  [오류] 대상 디렉터리를 찾을 수 없습니다: ${DATAFILE_DIR}"
    echo "  사용법: sudo $0 [데이터파일_디렉터리_경로]"
    exit 1
fi

# 1. 대상 경로의 마운트 장치 및 파일시스템 확인
MOUNT_INFO=$(df -PT "$DATAFILE_DIR" | tail -n 1)
DEV_NAME=$(echo "$MOUNT_INFO" | awk '{print $1}')
FS_TYPE=$(echo "$MOUNT_INFO" | awk '{print $2}')
AVAIL_SPACE=$(echo "$MOUNT_INFO" | awk '{print $5}')
MOUNT_POINT=$(echo "$MOUNT_INFO" | awk '{print $7}')

echo -e "\n[1] 스토리지 및 파일시스템 사양:"
echo "  - 마운트 장치     : ${DEV_NAME}"
echo "  - 파일시스템 타입 : ${FS_TYPE}"
echo "  - 마운트 지점     : ${MOUNT_POINT}"
echo "  - 가용 디스크 용량: ${AVAIL_SPACE} (1K-blocks)"

# 2. 블록 크기(Block Size) 및 파일시스템별 파일 크기 상한 산출
echo -e "\n[2] 파일시스템 블록 크기 및 구조적 파일 한계:"
BLOCK_SIZE=4096
if [ "$FS_TYPE" == "ext4" ] || [ "$FS_TYPE" == "ext3" ]; then
    if command -v tune2fs &>/dev/null; then
        BLOCK_SIZE=$(sudo tune2fs -l "$DEV_NAME" 2>/dev/null | grep -i "Block size" | awk '{print $3}')
    fi
    echo "  - ext4 파일시스템 블록 크기: ${BLOCK_SIZE} Bytes"
    if [ "$BLOCK_SIZE" -eq 4096 ]; then
        echo "  - OS 수준 최대 단일 파일 허용 크기: 16 TB (ext4 4KB 블록 기준)"
    elif [ "$BLOCK_SIZE" -eq 1024 ]; then
        echo "  - OS 수준 최대 단일 파일 허용 크기: 16 GB (ext4 1KB 블록 기준 - 주의!)"
    fi
elif [ "$FS_TYPE" == "xfs" ]; then
    if command -v xfs_info &>/dev/null; then
        BLOCK_SIZE=$(sudo xfs_info "$MOUNT_POINT" 2>/dev/null | grep -oE "bsize=[0-9]+" | head -n 1 | cut -d'=' -f2)
    fi
    echo "  - XFS 파일시스템 블록 크기: ${BLOCK_SIZE:-4096} Bytes"
    echo "  - OS 수준 최대 단일 파일 허용 크기: 8 EB (XFS 구조상 사실상 무제한)"
fi

# 3. 32GB(Smallfile Tablespace 한계치: 34359721984 바이트) 근접 파일 점검
echo -e "\n[3] 데이터파일 크기 임계치 점검 (Smallfile 32GB 경계):"
LIMIT_BYTES=34359721984  # 32GB (8KB DB 블록 * 4,194,303)
WARN_BYTES=32212254720   # 30GB

NEAR_LIMIT_FILES=$(find "$DATAFILE_DIR" -type f \( -name "*.dbf" -o -name "*.ibd" -o -name "*.dat" \) -size +30G 2>/dev/null)

if [ -z "$NEAR_LIMIT_FILES" ]; then
    echo "  [정상] 30GB를 초과하여 한계에 근접한 대형 데이터파일이 없습니다."
else
    echo "  [주의] 한계치(32GB)에 도달했거나 근접한 데이터파일 목록:"
    for DFILE in $NEAR_LIMIT_FILES; do
        F_SIZE=$(stat -c "%s" "$DFILE")
        F_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $F_SIZE / 1024 / 1024 / 1024}")
        echo "  -> 파일: $(basename "$DFILE") | 크기: ${F_SIZE_GB} GB (${F_SIZE} Bytes)"
        
        if [ "$F_SIZE" -ge "$LIMIT_BYTES" ]; then
            echo "     [!] 경고: 해당 파일은 오라클 Smallfile 최대 한도(32GB)에 도달했습니다."
            echo "     -> AUTOEXTEND가 켜져 있어도 파일시스템 레벨에서 더 이상 확장 불가능함."
        fi
    done
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

디스크 여유 공간이 수백 GB 이상 남아있는데도 `AUTOEXTEND` 또는 `RESIZE` 수행 시 `File too large`나 `unable to extend` 오류가 발생하는 원인은 리눅스 **파일시스템의 블록 포맷 한계**와 데이터베이스 엔진 내부의 **블록 주소 체계 한계**가 결합되어 나타납니다.

### 1. 주요 발생 원인

1. **오라클 Smallfile Tablespace의 32GB 포맷 한계 (가장 흔함)**:
   * 오라클의 기본 테이블스페이스는 Smallfile 방식입니다.
   * Smallfile은 22비트 블록 포인터를 사용하므로, 데이터파일 1개당 최대 가질 수 있는 블록 수가 **$2^{22} - 1 = 4,194,303$ 블록**으로 고정되어 있습니다.
   * 표준 DB 블록 크기가 `8KB (8,192 Bytes)`라면:
     $$4,194,303 \times 8,192 \text{ Bytes} \approx 32\text{GB} \ (34,359,721,984 \text{ Bytes})$$
   * 데이터파일이 32GB에 도달하는 순간 디스크가 10TB 비어있어도 더 이상 1바이트조차 확장되지 못합니다.
2. **파일시스템 생성 시 블록 크기 오설정 (ext4 1KB/2KB 블록)**:
   * Linux `ext4` 파일시스템은 포맷 시 블록 크기(`-b`)에 따라 단일 파일 최대 크기가 달라집니다.
     * 1KB 블록: 최대 단일 파일 크기 **16GB**
     * 2KB 블록: 최대 단일 파일 크기 **256GB**
     * 4KB 블록(기본): 최대 단일 파일 크기 **16TB**
   * 만약 파티션 생성 시 블록 크기가 1KB로 잡혔다면 파일이 16GB를 넘는 순간 OS 커널이 `EFBIG (Error 27: File too large)`를 발생시킵니다.
3. **OS 레벨 파일 크기 제한 (ulimit `fsize`)**:
   * 데이터베이스 프로세스 계정(`oracle`, `postgres`)의 셸 리소스 제한에서 `ulimit -f`(Maximum file size)가 특정 블록 수로 제한되어 있을 경우 확장이 차단됩니다.

### 2. 단계별 복구 및 해결 방법

#### 1) 신규 데이터파일 추가 (Smallfile Tablespace 조치)
이미 32GB에 도달한 데이터파일은 물리적으로 늘릴 수 없으므로, 해당 테이블스페이스에 새로운 데이터파일을 추가하여 확장을 분산시킵니다.

```sql
-- 테이블스페이스에 두 번째 데이터파일 추가
ALTER TABLESPACE USERS 
ADD DATAFILE '/u01/app/oracle/oradata/users02.dbf' 
SIZE 10G AUTOEXTEND ON NEXT 100M MAXSIZE 31G;
```

#### 2) Bigfile Tablespace로 전환 설계
대용량 데이터(수 TB)를 단일 데이터파일로 관리해야 한다면 Bigfile 테이블스페이스를 생성하여 사용합니다.
* Bigfile은 32비트(40억 개) 블록 포인터를 사용하여 단일 파일로 최대 **32TB ~ 128TB**까지 확장 가능합니다.

```sql
-- 신규 Bigfile 테이블스페이스 생성
CREATE BIGFILE TABLESPACE BIG_DATA 
DATAFILE '/u01/app/oracle/oradata/big_data01.dbf' 
SIZE 50G AUTOEXTEND ON NEXT 1G MAXSIZE UNLIMITED;
```

#### 3) 계정의 ulimit 파일 크기 제한 무제한 설정
`/etc/security/limits.conf`에서 DB 실행 계정의 `fsize`가 `unlimited`인지 확인합니다.

```ini
# /etc/security/limits.conf
oracle   soft   fsize   unlimited
oracle   hard   fsize   unlimited
```

&nbsp;
&nbsp;

## 주의사항

1. **Smallfile에서 `MAXSIZE UNLIMITED`의 착시**:
   * `ALTER DATABASE DATAFILE '...' AUTOEXTEND ON MAXSIZE UNLIMITED;`를 주더라도 이는 오라클 엔진이 허용하는 구조적 한계(32GB)를 넘어설 수 없습니다. 무제한으로 적어두었어도 32GB에 도달하면 확장에 실패하므로 모니터링 임계치를 30GB로 잡아 사전 알림을 걸어야 합니다.

2. **XFS 파일시스템 권장**:
   * 대규모 데이터베이스 환경에서는 `ext4`보다 확장성과 대형 파일 할당(Extent allocation) 속도가 뛰어난 `xfs` 파일시스템을 데이터 영역 마운트 포인트로 채택하는 것이 안정적입니다.

3. **기존 Smallfile을 Bigfile로 직접 변환 불가**:
   * 오라클에서 기존 Smallfile 테이블스페이스를 `ALTER TABLESPACE` 구문으로 Bigfile로 직접 바꿀 수는 없습니다. 신규 Bigfile 테이블스페이스를 생성한 후 테이블/인덱스 세그먼트를 이동(`ALTER TABLE ... MOVE TABLESPACE ...`)시키는 방식으로 이관해야 합니다.