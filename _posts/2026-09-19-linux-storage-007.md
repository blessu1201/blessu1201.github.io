---
layout: article
title: 시스템 관리_07 RHEL/CentOS에서 손상되거나 잠긴 RPM 데이터베이스(/var/lib/rpm) 복구 및 정리 방법
tags: [Linux, RHEL, CentOS, RPM, DNF, YUM, Troubleshooting]
keys: 260919-linux-storage-007
---

- 출처 / 참고: 리눅스 패키지 관리 및 RPM 데이터베이스 복구 가이드
> 명령어: `rpm --rebuilddb`, `rm -f /var/lib/rpm/__db*`, `yum clean all` / `dnf clean all`, `lsof /var/lib/rpm/Packages`  
> 키워드: RPM Database Corruption, BDB Lock, sqlite, Stale Lock, Packages, rebuilddb  
> 사용처: yum/dnf 실행 시 응답 없음(무한 대기), `rpmdb open failed` 오류 발생 시, 비정상 종료로 인한 BDB 락 파일 정리 및 데이터베이스 재구축  

---

> 실행예제

```bash
# 1. yum/dnf 또는 rpm 명령 실행 시 락 또는 손상 에러 확인
$ sudo yum check-update
Loaded plugins: fastestmirror
error: db5 error(-30973) from dbenv->open: BDB0087 DB_RUNRECOVERY: Fatal error, run database recovery
error: cannot open Packages index using db5 -  (-30973)
error: cannot open Packages database in /var/lib/rpm
CRITICAL:yum.main:

Error: rpmdb open failed

# 2. RPM 데이터베이스 디렉터리 내 점유 프로세스 확인 (Stale Process 점검)
$ sudo lsof /var/lib/rpm/*
COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF   NODE NAME
yum     14521 root    6uW  REG  253,0  2129920 131201 /var/lib/rpm/Packages

# 3. RPM 데이터베이스 잠금 파일(__db.*) 및 손상 징후 확인
$ ls -la /var/lib/rpm/__db*
-rw-r--r--. 1 root root   24576 Sep 22 13:10 /var/lib/rpm/__db.001
-rw-r--r--. 1 root root  229376 Sep 22 13:10 /var/lib/rpm/__db.002
-rw-r--r--. 1 root root 1318912 Sep 22 13:10 /var/lib/rpm/__db.003
```

&nbsp;
&nbsp;

## 스크립트

```bash
#!/usr/bin/env bash
#
# RHEL/CentOS RPM Database 손상 복구 및 잠금 해제 스크립트
#

set -euo pipefail

echo "=== [1] 실행 중인 중복 yum/dnf/rpm 프로세스 강제 종료 ==="
pkill -9 -f "yum" || true
pkill -9 -f "dnf" || true
pkill -9 -f "rpm" || true

BACKUP_DIR="/var/lib/rpm_backup_$(date +%Y%m%d_%H%M%S)"
echo "=== [2] 기존 RPM 데이터베이스 안전 백업 생성: ${BACKUP_DIR} ==="
mkdir -p "${BACKUP_DIR}"
cp -a /var/lib/rpm/ "${BACKUP_DIR}/"

echo "=== [3] 잠금 파일 및 임시 환경 파일(__db.*) 제거 ==="
# RHEL 6/7/8(BDB 환경) 잠금 파일 정리
rm -f /var/lib/rpm/__db*
# sqlite 기반(RHEL 8/9 일부 환경) 임시 락 및 저널 파일 정리
rm -f /var/lib/rpm/.rpm.lock /var/lib/rpm/rpmdb.sqlite-wal /var/lib/rpm/rpmdb.sqlite-shm 2>/dev/null || true

echo "=== [4] RPM 데이터베이스 재구축 (rebuilddb) ==="
rpm --rebuilddb -v

echo "=== [5] 패키지 매니저 캐시 정리 및 인덱스 갱신 ==="
if command -v dnf >/dev/null 2>&1; then
    dnf clean all
    dnf makecache
elif command -v yum >/dev/null 2>&1; then
    yum clean all
    yum makecache
fi

echo "=== [6] RPM 데이터베이스 정합성 검증 ==="
rpm -qa | wc -l >/dev/null
echo "=== [완료] RPM 데이터베이스가 정상적으로 복구되었습니다. ==="
```

&nbsp;
&nbsp;

## 해설

1. **에러 원인 분석:**
   * 패키지 설치(`yum install` / `dnf update`) 도중 강제 재부팅, 프로세스 비정상 종료(SIGKILL), 혹은 디스크 I/O 병목이 발생하면 Berkeley DB(BDB) 트랜잭션 락(`__db.*`)이 해제되지 못하고 고아 파일(Stale Locks)로 남게 됩니다.
   * 이로 인해 후속 명령어가 데이터베이스 잠금을 획득하지 못해 무한 대기 상태에 빠지거나, 인덱스 불일치로 `DB_RUNRECOVERY` 또는 `rpmdb open failed` 오류가 발생합니다.

2. **복구 절차 및 핵심 로직:**
   * **프로세스 정리 및 백업:** 아직 백그라운드에 물려 있는 좀비 패키지 프로세스를 정리한 뒤, 원본 `/var/lib/rpm/` 디렉터리를 백업하여 복구 실패 시 롤백이 가능하도록 보장합니다.
   * **락 파일 제거 (`rm -f /var/lib/rpm/__db*`):** 패키지 메타데이터 본체(`Packages` 파일 등)는 건드리지 않고 공유 메모리 및 동기화용 락 파일만 제거하여 점유 상태를 해제합니다.
   * **인덱스 재구축 (`rpm --rebuilddb`):** 기존 `Packages` 파일에 기록된 정보를 바탕으로 손상된 BDB/SQLite 헤더와 인덱스 테이블을 완전히 새로 생성합니다.
   * **캐시 갱신 (`clean all`):** 손상된 기존 메타데이터 캐시를 완전히 비우고 저장소 리포지토리 정보를 새로 동기화합니다.

&nbsp;
&nbsp;

## 주의사항

1. **`Packages` 원본 파일 보호:**
   * `/var/lib/rpm/Packages`(또는 RHEL 9/Fedora의 `rpmdb.sqlite`) 파일 자체가 물리적으로 손상(0 byte 등)된 경우 `rpm --rebuilddb`로도 복구가 불가능할 수 있으므로, 반드시 사전 백업을 확인해야 합니다.
2. **배포판 버전별 데이터베이스 구조 차이:**
   * RHEL 7/CentOS 7까지는 Berkeley DB(`__db.*`, `Packages`)를 기본 사용하지만, RHEL 8 후반 및 RHEL 9부터는 SQLite 백엔드(`rpmdb.sqlite`)를 기본으로 사용합니다. 스크립트 작성 시 해당 버전 환경을 감안해야 합니다.
3. **디스크 여유 공간 점검:**
   * 디스크 풀(`No space left on device`)로 인해 DB 쓰기가 중단되어 손상되는 경우가 흔하므로, 복구 전 반드시 `df -h /var` 명령으로 디스크 용량이 충분한지 점검해야 합니다.