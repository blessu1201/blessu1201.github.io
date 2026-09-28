---
layout: article
title: 시스템 관리_16 "리눅스 SSH 'Connection closed by remote host / port 22' 권한 및 소유권 오류 완벽 해결 가이드"
tags: [Linux, SSH, OpenSSH, Permissions, Security, StrictModes, Troubleshooting]
keys: 260928-linux-network-016
---

- 출처 / 참고: OpenSSH Documentation (sshd_config(5), ssh-keygen(1)), RFC 4252 (SSH Authentication Protocol)

> 명령어: `ssh`, `sshd`, `chmod`, `chown`, `journalctl`, `namei`, `ls`  
> 키워드: Connection closed by remote host, port 22, StrictModes, authorized_keys, permissions, sshd  
> 사용처: SSH 키 등록 직후 접속 종료 현상 분석, 홈 디렉터리 권한 오설정에 따른 SSH 차단 복구, 원격 서버 접근 통제 디버깅  

> 실행예제

클라이언트에서 SSH 접속을 시도했으나 인증 직후 혹은 핸드셰이크 단계에서 `Connection closed by remote host` 메시지와 함께 즉시 튕기는 경우, 상세 디버깅 옵션과 서버 로그를 확인하여 원인을 파악합니다.

```bash
# 1. 클라이언트 관점: 최고 수준의 상세 로그(-vvv)로 종료 지점 추적
$ ssh -vvv user@192.168.1.100
# ... (디버그 로그 출력)
# debug1: Authentications that can continue: publickey
# debug3: start over, passed a different list publickey
# debug3: send packet: type 50
# debug3: receive packet: type 51
# Connection closed by 192.168.1.100 port 22

# 2. 서버 관점: sshd 인증 로그 실시간 추적 (권한 거부 이유 확인)
$ sudo journalctl -u ssh -u sshd -f
# 또는 레거시 배포판의 경우
$ sudo tail -f /var/log/auth.log   # Debian/Ubuntu
$ sudo tail -f /var/log/secure     # RHEL/Rocky Linux

# [주요 오류 로그 패턴 예시]
# "Authentication refused: bad ownership or modes for directory /home/user"
# "Authentication refused: bad ownership or modes for file /home/user/.ssh/authorized_keys"

# 3. 서버 관점: 디렉터리 및 키 파일의 현재 퍼미션(권한)과 소유권 확인
$ namei -m /home/user/.ssh/authorized_keys
# f: /home/user/.ssh/authorized_keys
#  drwxr-xr-x /
#  drwxr-xr-x home
#  drwxrwxrwx user           <-- 홈 디렉터리가 777로 열려 있어 sshd가 거부함!
#  drwxrwxr-x .ssh           <-- 디렉터리 쓰기 권한이 그룹에 열려 있음
#  -rw-rw-r-- authorized_keys <-- 파일 쓰기 권한이 과도함

```

## 스크립트

OpenSSH의 보안 검증 기준(`StrictModes`)에 맞추어 홈 디렉터리, `.ssh` 디렉터리, `authorized_keys` 및 호스트 키 파일들의 권한과 소유권을 자동으로 진단하고 표준 보안 퍼미션(700, 600)으로 일괄 복구하는 쉘 스크립트입니다.

```bash
#!/bin/bash
# fix_ssh_permissions.sh - Diagnose and fix SSH key & directory permissions

TARGET_USER=${1:-"$USER"}

if [ "$EUID" -ne 0 ]; then
    echo "오류: 권한 조정을 위해 루트(root) 권한으로 실행해야 합니다."
    echo "사용법: sudo $0 [사용자명]"
    exit 1
fi

USER_HOME=$(eval echo "~$TARGET_USER" 2>/dev/null)

if [ ! -d "$USER_HOME" ]; then
    echo "오류: 사용자 '${TARGET_USER}'의 홈 디렉터리(${USER_HOME})를 찾을 수 없습니다."
    exit 1
fi

echo "=========================================="
echo " [SSH 권한 진단 및 복구] 대상 계정: ${TARGET_USER}"
echo " 홈 디렉터리 경로: ${USER_HOME}"
echo "=========================================="

USER_GROUP=$(id -gn "$TARGET_USER")
SSH_DIR="${USER_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

# 1. 홈 디렉터리 점검 및 복구 (Group/Other 쓰기 권한 제거 필수: 최대 755)
HOME_PERM=$(stat -c "%a" "$USER_HOME")
echo -e "\n[1] 홈 디렉터리 권한 확인: ${HOME_PERM}"
if [ "$HOME_PERM" -gt 755 ]; then
    echo "  [주의] 홈 디렉터리에 타인 쓰기 권한이 있어 StrictModes에 걸립니다."
    echo "  -> chmod 755 ${USER_HOME} 적용 중..."
    chmod 755 "$USER_HOME"
else
    echo "  [정상] 홈 디렉터리 권한이 안전합니다."
fi

# 2. .ssh 디렉터리 점검 및 복구 (700 권장)
if [ -d "$SSH_DIR" ]; then
    echo -e "\n[2] .ssh 디렉터리 권한 및 소유권 복구:"
    chown "${TARGET_USER}:${USER_GROUP}" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    echo "  -> chown ${TARGET_USER}:${USER_GROUP} ${SSH_DIR} 완료"
    echo "  -> chmod 700 ${SSH_DIR} 완료"
else
    echo -e "\n[2] .ssh 디렉터리가 존재하지 않아 새로 생성합니다."
    mkdir -p "$SSH_DIR"
    chown "${TARGET_USER}:${USER_GROUP}" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
fi

# 3. authorized_keys 파일 점검 및 복구 (600 권장)
if [ -f "$AUTH_KEYS" ]; then
    echo -e "\n[3] authorized_keys 권한 및 소유권 복구:"
    chown "${TARGET_USER}:${USER_GROUP}" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    echo "  -> chown ${TARGET_USER}:${USER_GROUP} ${AUTH_KEYS} 완료"
    echo "  -> chmod 600 ${AUTH_KEYS} 완료"
else
    echo -e "\n[3] authorized_keys 파일이 없습니다."
fi

# 4. SSH 개인키(id_rsa, id_ed25519 등) 권한 보호 (600 적용)
echo -e "\n[4] .ssh 내부 개인키 파일 권한 점검:"
find "$SSH_DIR" -type f \( -name "id_*" ! -name "*.pub" \) -exec chmod 600 {} + 2>/dev/null
find "$SSH_DIR" -type f -name "*.pub" -exec chmod 644 {} + 2>/dev/null
echo "  -> 개인키 600, 공개키 644 적용 완료."

# 5. sshd 설정 문법 검사
echo -e "\n[5] sshd 데몬 설정 검사:"
if sshd -t; then
    echo "  [정상] /etc/ssh/sshd_config 문법 정상"
else
    echo "  [오류] sshd_config 파일에 문법적 문제가 있습니다. 확인이 필요합니다."
fi

echo -e "\n=========================================="
echo " [조치 완료] 권한이 성공적으로 재설정되었습니다."
echo "=========================================="
```

## 해설

SSH 연결 시 패스워드나 키 인증 단계에서 갑자기 원격 서버에 의해 연결이 종료(`Connection closed by remote host`)되는 현상은 네트워크 문제라기보다는 **서버 측 OpenSSH 데몬(`sshd`)이 보안상의 이유로 연결을 강제 차단**하는 경우가 대부분입니다.

### 1. 주요 발생 원인

1. **OpenSSH의 `StrictModes` 보안 검증 실패 (가장 빈번함)**:
   * `sshd`는 기본값으로 `StrictModes yes`가 활성화되어 있습니다.
   * 사용자의 홈 디렉터리(`~`), `.ssh` 디렉터리, 또는 `authorized_keys` 파일에 다른 사용자나 그룹(`group`, `others`)이 **쓰기(write) 권한**을 가지고 있는 경우, 악의적인 사용자가 공개키를 조작할 수 있다고 판단하여 인증 자체를 거부하고 연결을 끊어버립니다.

2. **파일 및 디렉터리 소유권(Ownership) 불일치**:
   * `root` 권한으로 파일을 복사하거나 생성하여 `/home/user/.ssh` 또는 `authorized_keys`의 소유자가 `root`로 남아 있는 경우 일반 계정(`user`)으로 로그인할 수 없습니다.

3. **서버 호스트 키(Host Key) 권한 문제**:
   * 서버 측의 `/etc/ssh/ssh_host_*_key` 파일의 권한이 풀려 있거나(반드시 `600` 및 `root` 소유여야 함) 손상된 경우 핸드셰이크 단계에서 즉시 접속이 종료됩니다.

4. **셸(Shell) 설정 오류 또는 nologin 상태**:
   * `/etc/passwd` 상에 해당 계정의 로그인 셸이 `/usr/sbin/nologin` 또는 존재하지 않는 셸 경로로 지정되어 있으면 키 인증에 성공하더라도 셸을 할당하지 못해 바로 세션이 닫힙니다.

### 2. 표준 권한 가이드라인 (StrictModes 기준)

| 대상 경로 | 권장 권한 (Octal) | 설명 |
| :--- | :--- | :--- |
| **`/home/user`** | `755` (`drwxr-xr-x`) 또는 `750` | 그룹 및 타인에게 쓰기(`w`) 권한이 없어야 함 |
| **`~/.ssh`** | `700` (`drwx------`) | 소유자만 읽기/쓰기/실행 가능해야 함 |
| **`~/.ssh/authorized_keys`** | `600` (`-rw-------`) | 소유자만 읽기/쓰기 가능해야 함 |
| **`~/.ssh/id_*` (개인키)** | `600` (`-rw-------`) | 개인키는 반드시 소유자 전용 권한 |
| **`~/.ssh/*.pub` (공개키)** | `644` (`-rw-r--r--`) | 공개키는 읽기 허용 가능 |

## 주의사항

1. **`chmod 777` 사용 절대 금지**:
   * 퍼미션 오류가 발생했을 때 해결을 위해 디렉터리에 `chmod -R 777 /home/user`를 부여하는 경우가 많습니다. 이는 `sshd`의 `StrictModes` 보안 검증을 무조건 실패하게 만들어 영구적인 SSH 접근 차단을 유발합니다.

2. **임시 조치로 `StrictModes no` 설정 지양**:
   * `/etc/ssh/sshd_config`에서 `StrictModes no`로 변경하면 권한 검사를 우회하여 접속할 수는 있으나, 서버의 보안 체계가 크게 취약해지므로 권한을 올바르게 맞추는 방식으로 해결해야 합니다.

3. **SELinux 활성화 환경(RHEL/CentOS/Rocky Linux)**:
   * 파일 권한(chmod)이 정상이더라도 SELinux 컨텍스트가 올바르지 않으면 접근이 거부됩니다. 비표준 경로를 사용했거나 키 파일을 수동 이동한 경우 아래 명령어로 컨텍스트를 복원해야 합니다.
     ```bash
     restorecon -R -v ~/.ssh
     ```