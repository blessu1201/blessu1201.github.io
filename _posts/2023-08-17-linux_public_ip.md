---
layout: article
title: 리눅스 서버 및 윈도우 외부 공인IP 확인방법 / Linux, windows public ip check
tags: [linux, windows, public ip check]
key: 20230817-linux_windows_public_ip_check 
---

{% include googlead.html %}

---

## 리눅스, 윈도우에서 현재 사용 중인 외부공인 IP 확인 방법

> 리눅스 서버를 사용하거나, 또는 내가 지금 사용하고 있는 컴퓨터의 외부 공인 IP를 확인해야할 상황이 종종 발생합니다.
>> 가장 간단하고 쉬운 command 명령어 입니다. 리눅스에서만 사용가능한 줄 알았으나, 윈도우에서도 사용이 가능합니다.
>>> 숙지하고 계시면, 간단한 명령어로 현재 장비가 사용중인 공인 IP를 확인하실 수 있습니다.
 
```bash
$ curl ifconfig.me
```