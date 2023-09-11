---
layout: article
title: 리눅스 서버 및 윈도우 내 아이피(IP) 확인방법 / Linux, windows public ip check
tags: [Linux, Windows, Public ip check]
key: 20230817-linux_windows_public_ip_check 
---

# 리눅스, 윈도우에서 현재 사용 중인 외부공인 IP 확인 방법

> 리눅스 서버를 사용하거나, 또는 내가 지금 사용하고 있는 컴퓨터의 외부 공인 IP를 확인해야할 상황이 종종 발생합니다.
>> 가장 간단하고 쉬운 command 명령어 입니다. 리눅스에서만 사용가능한 줄 알았으나, 윈도우에서도 사용이 가능합니다.
>>> 숙지하고 계시면, 간단한 명령어로 현재 장비가 사용중인 공인 IP를 확인하실 수 있습니다.
 

## 1. 내아이피 확인(외부 공인)

> 리눅스, 윈도우(cmd실행 후) 내 컴퓨터의 외부 공인 IP 확인

```bash
$ curl ifconfig.me
```

## 2. 리눅스 내부 IP 확인 

```bash
$ ifconfig
```
```bash
$ ip addr
```

## 3. 윈도우 내부 IP 확인

> cmd 창에서 하기 명령어 입력 

```bash
$ ipconfig
```




