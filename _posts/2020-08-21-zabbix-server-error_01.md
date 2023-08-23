---
layout: article
title: Zabbix error Too many connections
tags: [Linux, Zabbix]
key: 20200821_zabbix_server_error_01
---

{% include googlead.html %}

---

> zabbix 운영 중에 server가 갑자기 멈췄다.(하루동안 아무도 몰랐다는게 함정. ㄷㄷ)  
> 프로세스는 살아있었지만 정상적인 일을 하지못하여 아무런 값을 받아오지 못하고 있었다.

<br>

## 1. LOG 확인

> log를 확인해보니, DB connection 오류가 많이 보인다.  
> process를 죽이고 다시 시작을 해도 다시 stop 되는 상황이 발생했다.

```bash
$ cat /var/log/zabbix/zabbix_server.log
...
...
14622:20200820:090347.272 [Z3001] connection to database 'zabbixdb' failed: [1040] Too many connections
14622:20200820:090347.272 Cannot connect to the database. Exiting...
14689:20200820:090347.273 server #194 started [trapper #9]
14623:20200820:090347.273 [Z3001] connection to database 'zabbixdb' failed: [1040] Too many connections
14623:20200820:090347.273 Cannot connect to the database. Exiting...
14690:20200820:090347.275 server #195 started [trapper #10]
14327:20200820:090347.275 One child process died (PID:14617,exitcode/signal:1). Exiting ...
14700:20200820:090347.360 server #204 started [trapper #19]
14327:20200820:090349.277 syncing history data...
14327:20200820:090349.277 syncing history data done
14327:20200820:090349.277 syncing trend data...
14327:20200820:090349.277 syncing trend data done
14327:20200820:090349.278 Zabbix Server stopped. Zabbix 4.0.0alpha2 (revision 76689).
zabbix_server [14700]: [file:'log.c',line:245] lock failed: [22] Invalid argument
```

<br>

## 2. database max_connections 확인

> 구글링으로 검색해보니, max_connections을 500으로 설정을 하라고 한다.  
> 변경에 앞서 설정을 확인해보니 값이 151로 설정이 되어있다.

```bash
$ mysql -u root -p

MariaDB [(none)]>  show variables like "max_connections";
+-----------------+-------+
| Variable_name   | Value |
+-----------------+-------+
| max_connections | 151   |
+-----------------+-------+
```

<br>

## 3. max_connections 값 변경

> 권장값에 따라 `151`{:.info} ==> `500`{:.info} 으로 변경하였다.  
> 일시적으로 늘리려면 아래와 같이 설정 해주면 된다.

```
MariaDB [(none)]>  SET GLOBAL max_connections = 500;
```
<br>

> 영구적으로 변경하려면 `/etc/my.cnf` 파일을 수정하면 된다.  
> 재발방지를 위해 `my.cnf` 를 수정했다.

```bash
$ vi /etc/my.cnf

[mysqld]
max_connections = 500
```

<br>

## 4. 서비스 재시작

> 설정 적용을 위해 DB를 재시작 한후, zabbix-server 를 다시 올려주었다.  
> 정상적으로 작동하는 것을 확인 할 수 있었다.

```bash
$ /bin/systemctl restart mariadb
$ systemctl start zabbix-server
```
