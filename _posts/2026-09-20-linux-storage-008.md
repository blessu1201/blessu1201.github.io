---
layout: article
title: 시스템 관리_08 "/etc/sudoers 파일 권한 오류(world writable) 및 구문 에러 복구 방법"
tags: [Linux, Sudo, Security, Troubleshooting, Permissions]
keys: 260920-linux-storage-008
---

- 출처 / 참고: 리눅스 시스템 보안 및 계정 권한 복구 가이드
> 명령어: `pkexec chmod 0440 /etc/sudoers`, `visudo -c`, `chmod 440`, `su -`  
> 키워드: Sudoers World Writable, Syntax Error, Visudo Check, File Permissions, Emergency Recovery  
> 사용처: 잘못된 chmod 명령으로 sudo 실행 불가 시, /etc/sudoers 문법 오류로 일반 사용자의 root 권한 승격이 차단되었을 때 복구  

---

> 실행예제

```bash
# 1. sudo 실행 시 world writable 권한 오류 발생 확인
$ sudo ls -l /root
sudo: /etc/sudoers is world writable
sudo: no valid sudoers sources found, quitting
sudo: unable to initialize policy plugin

# 2. 현재 /etc/sudoers 및 /etc/sudoers.d 디렉터리의 권한 상태 확인
$ ls -l /etc/sudoers /etc/sudoers.d
-rwxrwxrwx 1 root root 3181 Sep 22 13:45 /etc/sudoers

/etc/sudoers.d:
total 4
-rwxrwxrwx 1 root root  958 Sep 22 13:45 90-cloud-init-users

# 3. sudoers 파일 구문(Syntax) 오류 상태 점검 (root 세션 또는 문법 검사 시)
# 오류 메시지 예시:
# >>> /etc/sudoers: syntax error near line 28 <<<
# sudo: parse error in /etc/sudoers near line 28
# sudo: no valid sudoers sources found, quitting
```

&nbsp;
&nbsp;

## 스크립트

```bash
#!/usr/bin/env bash
#
# /etc/sudoers 권한 복구 및 문법 오류 검증 스크립트 (root 세션 또는 pkexec 환경에서 실행)
#

set -euo pipefail

echo "=== [1] 실행 권한 확인 (Root 권한 필수) ==="
if [ "$(id -u)" -ne 0 ]; then
    echo "오류: 이 스크립트는 root 권한으로 실행되어야 합니다."
    echo "sudo가 작동하지 않는 경우 'su -' 또는 'pkexec bash <스크립트>'를 사용하십시오."
    exit 1
fi

echo "=== [2] /etc/sudoers 및 /etc/sudoers.d 권한 및 소유권 원복 ==="
# 소유자를 root:root로 복원
chown -R root:root /etc/sudoers /etc/sudoers.d

# sudoers 메인 파일 권한을 0440 (r--r-----)으로 제한
chmod 0440 /etc/sudoers

# sudoers.d 디렉터리 권한을 0750, 하위 설정 파일들을 0440으로 제한
if [ -d /etc/sudoers.d ]; then
    chmod 0750 /etc/sudoers.d
    find /etc/sudoers.d -type f -exec chmod 0440 {} +
fi

echo "=== [3] sudoers 파일 문법 검증 (visudo -c) ==="
if visudo -c; then
    echo "=== [4] 문법 검사 통과: sudoers 파일이 유효합니다. ==="
else
    echo "경고: 문법 검사에 실패했습니다. 즉시 'visudo'를 실행하여 오류 라인을 수정하십시오."
    exit 2
fi

echo "=== [5] sudo 명령 테스트 ==="
sudo -k
sudo -l -U root

echo "=== [완료] /etc/sudoers 권한 및 구문 복구가 성공적으로 완료되었습니다. ==="
```

&nbsp;
&nbsp;

## 해설

1. **에러 원인 분석:**
   * **보안 메커니즘 차단:** `sudo` 유틸리티는 보안상 매우 엄격한 권한 검사를 수행합니다. `/etc/sudoers` 파일이나 `/etc/sudoers.d/` 디렉터리가 소유자 외에 수정 가능한 상태(`world writable`, 예: `777` 또는 `666`)가 되면, 악의적인 사용자의 변조를 방지하기 위해 즉시 모든 sudo 명령 실행을 거부합니다.
   * **구문(Syntax) 오류:** 일반 텍스트 편집기(`vi`, `nano` 등)로 `/etc/sudoers`를 직접 수정하다가 오타나 포맷 실수가 발생하면 파싱 에러가 발생하여 권한 승격 플러그인 초기화가 실패합니다.

2. **복구 절차 및 핵심 로직:**
   * **권한 제한 (`chmod 0440`):** `/etc/sudoers`의 표준 권한은 소유자(root)와 그룹(root)만 읽기 가능하고 쓰기가 불가능한 `0440` (`-r--r-----`)이어야 합니다.
   * **sudo가 막혔을 때의 우회 진입:**
     1. **`su -`:** root 비밀번호가 설정되어 있다면 root 셸로 직접 전환하여 권한을 수정합니다.
     2. **`pkexec` 활용:** GUI/Polkit이 설치된 배포판(Ubuntu 데스크톱/일부 서버)에서는 `pkexec chmod 0440 /etc/sudoers`를 통해 PolicyKit 인증으로 권한을 원복할 수 있습니다.
     3. **단일 사용자 모드 / 복구 모드:** root 암호가 없거나 잠겨있는 경우 재부팅 후 GRUB 메뉴에서 `init=/bin/bash` 또는 복구 모드(Recovery Mode)로 부팅하여 권한을 복구합니다.
   * **`visudo -c` 문법 검사:** 파일을 직접 덮어쓰기 전에 구문 오류를 사전에 감지하여 시스템 잠금 상태를 방지합니다.

&nbsp;
&nbsp;

## 주의사항

1. **직접 편집 금지 (`visudo` 사용 필수):**
   * `/etc/sudoers`를 편집할 때는 절대로 `nano`나 일반 `vim`으로 열지 말고 반드시 `visudo` 명령어를 사용해야 합니다. `visudo`는 저장 시점에 문법 오류를 자동으로 감지하여 오류가 있을 경우 저장을 차단해 줍니다.

2. **`/etc/sudoers.d/` 디렉터리 파일 주의:**
   * `/etc/sudoers.d/` 내에 생성하는 추가 설정 파일 역시 반드시 소유권 `root:root`, 권한 `0440`을 유지해야 합니다. 또한 파일명에 마침표(`.`)나 물결표(`~`)가 포함되면 `sudo`가 해당 설정을 무시하므로 네이밍 규칙에 주의해야 합니다.

3. **작업 시 셸 세션 유지:**
   * sudo 관련 설정을 변경하거나 복구할 때는 현재 열려 있는 root 터미널 세션을 닫지 말고, 다른 터미널 창을 열어 `sudo -v` 또는 일반 명령어가 정상 작동하는지 완전히 검증한 후 기존 세션을 종료해야 잠김 현상을 방지할 수 있습니다.