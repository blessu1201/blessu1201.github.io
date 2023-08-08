---
layout: article
title: 리눅스 jar 파일 시스템에 등록하기 / Linux jar file systemctl register
tags: [linux, linux jar systemctl]
key: 20230808-linux_jar_systemctl
---

{% include googlead.html %}

---

## 1. Vi 에디터를 사용하여 어플리케이션 등록파일 생성

> 하기 myapp 은 예시 입니다. 상황에 맞게 이름을 변경하여 등록합니다.
> 파일 생성시 jar파일의 경로와 파일명을 확인합니다.
> StandardOutput=null 옵션을 주지 않을 경우 시스템에 등록된 프로세스의 log가 /var/log/messsage 에 기록됩니다.
> 프로세스의 경우 별도의 log를 설정하는 경우가 많으니 필요하지 않다면 해당 옵션을 주어 불필요한 log를 남기지 않도록 합니다.

```bash
vi /etc/systemd/system/myapp.service

[Unit]
Description=Kisa scheduler Service
After=network.target

[Service]
ExecStart=/bin/bash -c "exec java -jar /동작시킬 jar파일 위치/파일명.jar"
StandardOutput=null
User=root

[Install]
WantedBy=multi-user.target
```

## 2. 데몬 리로드

> 데몬을 리로드하지 않으면 등록이 되지 않습니다.

```bash
$ systemctl daemon-reload
```

## 3. 등록하기

> 하기 명령어를 실행해 1 에서 생성한 이름으로 서비스를 등록합니다.

```bash
$ systemctl enable myapp.service
```