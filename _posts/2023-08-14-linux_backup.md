---
layout: article
title: 리눅스 부팅전 상태 백업 명령어 / Linux info backup before reboot
tags: [Linux, Linux_info]
key: 20230814-linux_info_backup 
---

{% include googlead.html %}

---

## 리눅스 부팅전 서버 정보 백업 스크립트.

> 리눅스서버를 부팅하기전 서버의 정보를 백업하는 스크립트 입니다.
>> 추가로 필요한 정보는 덧붙여 수정하여 사용하면 됩니다.
>>> root 계정으로 하셔야 합니다.
 
```bash
#!/bin/bash

DATE=$(date +%Y-%m-%d_%H:%M)

mkdir $DATE

df -Th > /root/info/$DATE/df.info
ifconfig -a > /root/info/$DATE/ifconfig.info
netstat -rn > /root/info/$DATE/netstat.info
ps -ef > /root/info/$DATE/ps.info
tail /var/log/messages > /root/info/$DATE/messages.info
cat /var/log/messages > /root/info/$DATE/messages_full.info
lsblk > /root/info/$DATE/lsblk.info
blkid > /root/info/$DATE/blkid.info
fdisk -l > /root/info/$DATE/fdisk.info
cat /proc/net/bonding/bond0 > /root/info/$DATE/bond0.info
cat /proc/net/bonding/bond1 > /root/info/$DATE/bond1.info
cat /etc/fstab > /root/info/$DATE/fstab.info
dmidecode > /root/info/$DATE/dmidecode.info

```