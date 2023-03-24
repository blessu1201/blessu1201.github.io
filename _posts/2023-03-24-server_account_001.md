---
layout: article
title: 리눅스 잠긴 계정 해제 / unlock linux locked account
tags: [linux, linux account unlock,]
key: 20230324-linux_account_unlock
---

{% include googlead.html %}

---

<img src='http://drive.google.com/uc?export=view&id=1ApCe1lsvgZpOFGSMyLqAe0qd6xp3d0_g' /><br>

> 리눅스 서버운영시 사용자의 계정이 비밀번호 입력 초과 또는 오랫동안 미사용으로 인해 잠겨있는 상태를 해제하는 명령어 입니다. 

> This command unlocks the locked state of a user's account due to excessive password entry or long-term inactivity when operating a Linux server.

**1. 계정상태 확인(Check account status)**

```bash
pam_tally2 -u account_name
```


**2. 계정 잠금 해제(unlock account)**

```bash
pam_tally2 -u account_name --reset
```


**3. 계정 expire 해제(Unexpired account)**

> 계정이 잠기는 것을 해제하는 명령어 입니다. 필요한 계정에 적용하여 사용할 수 있습니다.

> This is a command to unlock the account. You can use it by applying it to the account you need.

```bash
chage -E -1 -M 99999 account_name
chage -E -1 -M 99999 account_name
chage -E -1 -I 0 -m 0 -M 99999 account_name
```
