---
layout: article
title: Linux-journal log 크기 변경하기
tags: [Linux, journal]
key: 20240105-linux-journal-log
---


> 명령어: systemctl  
> 키워드: journal log   
> 사용처: 리눅스의 journal log size limit  

리눅스를 오래 사용하다 보면 로그가 많이 쌓여 용량 관리가 필요합니다.  
시스템의 특성을 파악하여 적정한 수준으로 변경하시면 됩니다.


## 저널 네임스페이스에 따른 단위당 크기 제한

하기 경로의 `journald.conf` 파일을 수정하여 영구적으로 변경 할 수 있습니다.

```
/etc/systemd/journald.conf
SystemMaxUse=1000M
```

```
재시작
systemctl restart systemd-journald
```

## 저널 파일을 수동으로 정리

수동으로 기간을 정해서 정리하려면 하기와 같이 command를 입력하면 됩니다.

```
journalctl --vacuum-time=2d
```

```
journalctl --vacuum-time=2weeks
```

```
journalctl --vacuum-size=100M
```

`참고사이트` <https://wiki.archlinux.org/title/Systemd/Journal#Journal_size_limit>


우아한형제들 기술 블로그
주소: https://techblog.woowahan.com/

스마일서브 기술 블로그
주소: http://idchowto.com/