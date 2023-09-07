---
layout: article
title: 리눅스 rsyslog를 활용하여 message 로그 수집 / Linux rsyslog collect log
tags: [Linux, Rsyslog]
key: 20230809-linux_rsyslog
---

## 1. 로그를 수집하는 서버

> 로그서버 한개를 대표로 놓고 다른서버의 로그를 수집하는 설정방법 입니다. 
> Amazon linux 2 기준으로 작성되었습니다.
> 원격지 서버의 message log를 수집하는 설정입니다.

```bash
[root@ip-10-10-20-1 log]#  cat /etc/rsyslog.conf | grep -Ev "^$|#"

$ModLoad imudp # 주석제거
$UDPServerRun 514 #주석제거

$WorkDirectory /var/lib/rsyslog
$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat
$IncludeConfig /etc/rsyslog.d/*.conf
$OmitLocalLogging on
$IMJournalStateFile imjournal.state

$template FILENAME,"/var/log/%fromhost-ip%_messages_%$YEAR%-%$MONTH%-%$DAY%.log" #추가
*.* ?FILENAME #추가

*.info;mail.none;authpriv.none;cron.none                /var/log/messages
authpriv.*                                              /var/log/secure
mail.*                                                  -/var/log/maillog  
cron.*                                                  /var/log/cron
*.emerg                                                 :omusrmsg:*
uucp,news.crit                                          /var/log/spooler
local7.*                                                /var/log/boot.log
```

## 2. 클라이언트의 rsyslog.conf 설정

> 하기 명령어를 실행해 등록할 이름을 정한 후 서비스를 등록합니다.

```bash
cat /etc/rsyslog.conf | grep -Ev "^$|#"

$WorkDirectory /var/lib/rsyslog
$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat
$IncludeConfig /etc/rsyslog.d/*.conf
$OmitLocalLogging on
$IMJournalStateFile imjournal.state
*.info;mail.none;authpriv.none;cron.none                /var/log/messages
authpriv.*                                              /var/log/secure
mail.*                                                  -/var/log/maillog
cron.*                                                  /var/log/cron
*.emerg                                                 :omusrmsg:*
uucp,news.crit                                          /var/log/spooler
local7.*                                                /var/log/boot.log

*.* @10.10.20.1 # 로그 수집하는 서버의 IP 추가
```

## 3. rsyslog 재시작 및 로그 확인.

> 리눅스의 config를 수정 후 재기동하는걸 잊지마세요.

```bash
ssytemctl restart rsyslog

```