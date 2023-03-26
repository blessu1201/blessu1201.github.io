---
layout: article
title: 리눅스 계정 보안(패스워드 복잡성 설정하기) / Linux password complexity
tags: [linux, linux password complexity]
key: 20230324-linux_password_complexity
---

{% include googlead.html %}

---

<img src='http://drive.google.com/uc?export=view&id=1ApCe1lsvgZpOFGSMyLqAe0qd6xp3d0_g' /><br>

> CentOS 6 이상 버전에서는 system-auth 설정을 통해 복잡성 설정이 가능합니다.
> 하기 내용을 참고하셔서 각 파일의 설정으로 계정을 보호하시기 바랍니다.

> In CentOS 6 and higher, complexity can be set via the system-auth setting. 
> Please refer to the following to protect your account with the settings of each file.


**system-auth**

- deny=5 unlock_time=300 : 계정로그인시 5회 실패할 경우 300초에 lock 타임 발생
- type=minlen=10 : 패스워드 최소 길이 10자
- retry=5 : 패스워드 입력실패시 재시도 횟수
- lcredit=-1 : 영어소문자 최소 갯수
- ucredit=-1 : 영어대문자 최소 갯수
- dcredit=-1 : 숫자 최소 갯수
- ocredit=-1 : 특수문자 최소 갯수

```bash
cat /etc/pam.d/system-auth
#%PAM-1.0
# This file is auto-generated.
# User changes will be destroyed the next time authconfig is run.
auth        required      pam_tally2.so deny=5 unlock_time=300
auth        required      pam_env.so
auth        sufficient    pam_unix.so try_first_pass nullok
auth        required      pam_deny.so

account     required      pam_tally2.so
account     required      pam_unix.so

password    requisite     pam_pwquality.so try_first_pass retry=5 type=minlen=10 lcredit=-1 ucredit=-1 dcredit=-1 ocredit=-1
password    sufficient    pam_unix.so try_first_pass use_authtok nullok sha512 shadow try_first_pass use_authtok remember=1
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
-session     optional      pam_systemd.so
session     [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session     required      pam_unix.so
```
