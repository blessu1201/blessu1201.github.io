---
layout: article
title: Zabbix Disk Monitoring 설정하기
tags: [Linux, Zabbix]
key: 20200826_zabbix_disk_monitoring
---

{% include googlead.html %}

---
> zabbix에서 disk-performence를 모니터링 하는 방법입니다.

- 참고사이트 : <https://github.com/grundic/zabbix-disk-performance>

## 1. diskstats user parameters config

> `/etc/zabbix/zabbix_agent.d/`위치로 이동하여 해당 설정 파일을 다운받습니다.

``` bash
$ cd /etc/zabbix/zabbix_agentd.d/
$ wget https://raw.githubusercontent.com/grundic/zabbix-disk-performance/master/userparameter_diskstats.conf -O /etc/zabbix/zabbix_agentd.d/userparameter_diskstats.conf
```
> 다운받은 `userparameter_diskstats.conf`의 내용은 아래와 같습니다.

{% highlight bash linenos %}
UserParameter=custom.vfs.discover_disks,/usr/local/bin/lld-disks.py

UserParameter=custom.vfs.dev.read.ops[*],awk '{print $$1}' /sys/class/block/$1/stat
UserParameter=custom.vfs.dev.read.merged[*],awk '{print $$2}' /sys/class/block/$1/stat
UserParameter=custom.vfs.dev.read.sectors[*],awk '{print $$3}' /sys/class/block/$1/stat
UserParameter=custom.vfs.dev.read.ms[*],awk '{print $$4}' /sys/class/block/$1/stat
UserParameter=custom.vfs.dev.write.ops[*],awk '{print $$5}' /sys/class/block/$1/stat
UserParameter=custom.vfs.dev.write.merged[*],awk '{print $$6}' /sys/class/block/$1/stat
UserParameter=custom.vfs.dev.write.sectors[*],awk '{print $$7}' /sys/class/block/$1/stat
UserParameter=custom.vfs.dev.write.ms[*],awk '{print $$8}' /sys/class/block/$1/stat
UserParameter=custom.vfs.dev.io.active[*],awk '{print $$9}' /sys/class/block/$1/stat
UserParameter=custom.vfs.dev.io.ms[*],awk '{print $$10}' /sys/class/block/$1/stat
UserParameter=custom.vfs.dev.weight.io.ms[*],awk '{print $$11}' /sys/class/block/$1/stat
{% endhighlight %}

<br>

## 2. low level discovery script

> `lld-disks.py` 파일을 다운받은 후 실행권한을 부여해줍니다. 이 파일은 disk를 탐색하는데 사용됩니다.

```bash
$ wget https://raw.githubusercontent.com/grundic/zabbix-disk-performance/master/lld-disks.py -O /usr/local/bin/lld-disks.py
$ chmod +x /usr/local/bin/lld-disks.py
```

> 다운받은 `lld-disks.py`의 내용은 아래와 같습니다.

{% highlight python linenos %}
#!/usr/bin/python
import os
import json

if __name__ == "__main__":
    # Iterate over all block devices, but ignore them if they are in the
    # skippable set
    skippable = ("sr", "loop", "ram")
    devices = (device for device in os.listdir("/sys/class/block")
               if not any(ignore in device for ignore in skippable))
    data = [{"{#DEVICENAME}": device} for device in devices]
    print(json.dumps({"data": data}, indent=4))
{% endhighlight %}  

<br>

## 3. zabbix-agent restart

> agent를 재시작 합니다.

```bash
$ /bin/systemctl restart zabbix-agent.service
```

<br>

## 4. Disk performence Template Download

> Zabbix Server에서 아래의 Template를 download 한 후 Import 한 후 Template 등록을 해주면 끝.

- TemplateDownload : <https://share.zabbix.com/storage-devices/linux-disk-performance-monitoring>
