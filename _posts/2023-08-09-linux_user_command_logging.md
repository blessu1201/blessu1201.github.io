---
layout: article
title: 리눅스 user command logging / Linux user command logging
tags: [Linux, User command]
key: 20230809-linux_user_command
---

## 1. user command history 로깅 설정

> 각 계정의 사용자가 어떤 명령어를 실행했는지 이력을 남기는 방법입니다.
> 아래와 같이 userhistory.sh 를 생성합니다.

```bash
vi /etc/profile.d/userhistory.sh

function history_to_ceelog {
 declare command
 remoteadd="`who am i`"
 command=$(fc -ln -0)
 if [ "$command" != "$old_command" ]; then
  logger -p local0.notice -t bash[$$] "remoteip=$remoteadd" : "user=$USER" : "uid=$UID" : "pid=$$" : "pwd=$PWD" : "cmd=$command"
 fi
 old_command=$command
 }
 trap history_to_ceelog DEBUG
```

## 2. rsyslog.conf 수정

```bash
vi /etc/rsyslog.conf

local0.notice                                           /var/log/userhistory.log
```

## 3. rsyslog 재시작 및 로그 확인.

> 리눅스의 config를 수정 후 재기동하는걸 잊지마세요.

```bash
ssytemctl restart rsyslog

```