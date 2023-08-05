---
layout: article
title: 리눅스 보안 배너 경고문구 (banner) / Linux banner
tags: [linux, linux banner]
key: 20230805-linux_banner
---

## 1.배너문구 설정하기

> 리눅스 보안 사항 중 경고(warning)메세지를 설정해야 하는 사항이 있습니다.
> 아래 문구를 `/etc/motd`{:.error}, `/etc/issue`{:.error}, `/etc/issue.net`{:.error} 에 등록하여 사용하시면 됩니다.
> 문구를 알맞게 수정하여 사용하셔도 됩니다.

```bash
vi /etc/motd

===============================================================================
본시스템은 허가된 사용자만 이용하실수 있습니다.
부당한 방법 또는 무단으로 전산망에 접속하거나 정보를 삭제,변경,유출하는 사용자는
관련법령에 따라 처벌 받게 됩니다

This is a private system.
Access for any reason must be specifically authorized by the manager.
Unless you are so authorized, your continued access and any other use may
expose you to criminal.
===============================================================================
```

```bash
vi /etc/issue
vi /etc/issue.net

=============================================================================
본 시스템은 법적으로 보호 받고 있으며 허가 받은 사용자만 접속할 수 있습니다.
모든 접속시도는 기록되고 있으며 불법적인 접근은 법적제재를 받을 수 있습니다.
비인가 접속인 경우 즉시 접속을 해지하시기 바랍니다.

WARNING !!
You are entering a secured area.
This system is restricted to authorized access only.
If you are not authorized to access or use this system, disconnect now.
All activities on this system are recored and logged.
Unauthorized access will be fully investigated and reported to the appopriate
law enforcement agencies.
=============================================================================
```

## 2.motd 자동변경 disable 설정

> 아래 명령어는 AWS EC2에서 배너를 수정해도 원복(default 값으로)되는 상황이 발생하게 되는데,
> 하기 명령어를 수행하시면 수정된 내용이 변경되지 않습니다.

```bash
sudo update-motd --disable
```

## 3.sshd_config 수정하기

> sshd_config 의 Banner 주석을 해제해 줍니다.

```bash
/etc/ssh/sshd_config
# no default banner path
#Banner none
Banner /etc/issue.net # 주석해제
```

---

{% include googlead.html %}

---
