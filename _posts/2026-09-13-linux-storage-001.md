---
layout: article
title: 시스템 관리_01 디스크 여유 공간이 있는데도 'No space left on device' 발생 시 해결하기 (Inode 고갈)
tags: [Linux, Inode, Disk, Troubleshooting, ShellScript]
keys: 260913-linux-storage-001
---

- 출처 / 참고: 리눅스 시스템 엔지니어링 & 파일 시스템 트러블슈팅 가이드
> 명령어: `df`, `find`, `xargs`, `rm`, `wc`  
> 키워드: `Inode`, `디스크 공간`, `No space left on device`, `파일 시스템`, `가용 공간`  
> 사용처: `df -h`로 디스크 용량을 확인했을 때는 여유 공간이 충분하지만, 신규 파일 생성이나 서비스 기동 시 `No space left on device` 에러가 발생할 때  

---

> 실행예제

파일을 생성하려고 할 때 장치에 남은 공간이 없다는 에러가 발생하지만, `df -h`로 확인하면 디스크 사용량은 30%대에 불과한 상황입니다.

```bash
$ touch test.txt
touch: cannot touch 'test.txt': No space left on device

$ df -h /
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        50G   16G   32G  34% /

$ df -i /
Filesystem       Inodes   IUsed   IFree IUse% Mounted on
/dev/sda1       3276800 3276800       0  100% /
```

## 스크립트

어느 디렉토리에서 비정상적으로 많은 파일(Inode)을 점유하고 있는지 하위 디렉토리별로 파일 수를 집계하여 상위 10개를 출력하는 셸 스크립트입니다.

```bash
Bash#!/bin/bash
# TARGET_DIR 하위 디렉토리별 파일 개수를 계산하여 상위 10개 출력
TARGET_DIR="${1:-/var}"

echo "[*] Scanning Inode usage in: $TARGET_DIR"
echo "--------------------------------------------------"

for dir in "$TARGET_DIR"/*/; do
    if [ -d "$dir" ]; then
        count=$(find "$dir" -maxdepth 2 2>/dev/null | wc -l)
        printf "%10d  %s\n" "$count" "$dir"
    fi
done | sort -rn | head -n 10
```

&nbsp;
&nbsp;

## **해설**

리눅스 파일 시스템에서 파일을 생성하려면 다음 두 가지 자원이 모두 필요합니다.

1. 데이터 블록(Data Block): 파일의 실제 내용(데이터)이 저장되는 물리적 용량(Bytes)
2. 아이노드(Inode, Index Node): 파일의 메타데이터(소유자, 권한, 생성일자, 데이터 블록 위치 등)를 보관하는 고유 번호표
   
디스크 용량(df -h)이 수십 GB 이상 넉넉하게 남아있더라도, 생성 가능한 파일의 총개수 한도인 Inode(df -i)가 100% 소진되면 파일 시스템은 더 이상 새 파일을 만들 수 없으므로 No space left on device 에러를 반환합니다.

크기가 0바이트이거나 수십 바이트에 불과한 소용량 파일이 수백만 개 이상 무분별하게 생성되는 환경(예: 웹 세션 파일, 메일 큐, 캐시 파일 등)에서 흔히 발생합니다.

### 1. Inode 사용량 확인 (df -i)

  디스크 용량 대신 Inode 잔여량을 점검합니다.

  ```bash
  Bash$ df -i
  ```

  `IUse%`가 100%이거나 `IFree`가 0인 파티션이 문제의 대상입니다.

### 2. Inode 점유 디렉토리 추적가장 많은 파일이 쌓여 있는 상위 디렉토리를 단계적으로 좁혀나갑니다. 통상 `/var` 또는 `/tmp` 파티션에서 많이 발생합니다.

  ```bash
  # 현재 디렉토리 기준 하위 폴더별 파일/디렉토리 수 집계
  $ sudo find /var -xdev -printf '%h\n' | sort | uniq -c | sort -k1 -n | tail -n 15
  ```

  출력 결과에서 좌측 숫자가 해당 디렉토리에 존재하는 항목 수입니다. 숫자가 비정상적으로 큰 디렉토리(예: 수십만~수백만 개)가 원인 지점입니다.

### 3. 대표적인 Inode 고갈 원인 지점

  |디렉토리 경로 | 주된 원인 | 조치 방안 |
  |/var/spool/clientmqueue 또는 /var/spool/postfix | cron 작업 결과 통보 메일이 전송 실패하여 누적 | 큐 디렉토리 내 오래된 스풀 파일 일괄 정리 |
  |/var/lib/php/sessions 또는 /tmp | PHP 세션 가비지 컬렉션(GC) 미작동으로 세션 파일 방치 | 생성된 지 일정 기간 지난 세션 파일 자동 삭제 cron 등록 | 
  |/var/log | 로그 로테이션(logrotate) 미적용 또는 작은 로그 분할 누적 | logrotate 설정 점검 및 불필요한 아카이브 압축본 제거 | 
  |애플리케이션 임시 디렉토리 (uploads/tmp, cache) | 파일 업로드 임시본 또는 썸네일 캐시 미삭제 | 애플리케이션 캐시 퍼지(Purge) 및 정리 스크립트 실행 |

&nbsp;
&nbsp;

## **주의사항**

### 1. `rm *` 실행 시 `"Argument list too long"` 에러 대처

한 디렉토리 안에 파일이 수십만 개 이상 들어있는 상태에서 rm * 명령어를 사용하면 셸의 인자 버퍼 크기 제한을 초과하여 Argument list too long 에러가 발생하며 삭제되지 않습니다.

이때는 셸의 와일드카드 확장 대신 find 명령어의 -delete 옵션이나 xargs 파이프라인을 사용해야 합니다.

```bash
# 권장 방식 1: find 자체 삭제 옵션 (가장 빠르고 안전)
$ find /path/to/target_dir -type f -name "sess_*" -delete

# 권장 방식 2: xargs를 통한 분할 삭제
$ find /path/to/target_dir -type f -mtime +7 -print0 | xargs -0 rm -f
```

### 2. 파일 시스템 포맷(mkfs) 시점의 Inode 고정

  - Ext4: 파일 시스템 포맷(mkfs.ext4) 시점에 Inode 총개수가 정적으로 결정되며, 운영 중 동적으로 Inode 개수만 늘리는 것은 불가능합니다. 작은 파일이 대량으로 생성되는 특수 목적 서버라면 포맷 시 -i(bytes-per-inode) 옵션이나 -N(inode 수 직접 지정)을 조정해야 합니다.  

  - XFS: Inode가 동적으로 할당되므로 상대적으로 자유로우나, 전체 디스크 용량 대비 Inode가 사용할 수 있는 최대 비율(maxpct)이 제한되어 있을 수 있습니다(xfs_growfs -m).