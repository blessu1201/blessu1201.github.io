---
layout: article
title: Linux GeoIP 설치(CentOS 7)
tags: [Linux]
key: 202007176_geoip_centos7
---

{% include googlead.html %}

## CentOs 7 에서 GeoIP 설치

---

> CentOs7 에서 GeoIP를 활용하여 국가IP차단 하는 방법. 서버 보안설정시 참고하세요.

<br>

- [참조사이트](http://sata.kr/entry/IPTables-12-IPTables%EC%97%90-GeoIP%EB%A5%BC-%EC%84%A4%EC%B9%98%ED%95%B4%EB%B3%B4%EC%9E%90-GeoIP-CentOS-6CentOS-7)

<br>

### 1. 패키지 설치

```bash
$ yum install gcc gcc-c++ make automake unzip zip xz kernel-devel-`uname -r` iptables-devel
$ yum install perl-Text-CSV_XS
$ wget https://jaist.dl.sourceforge.net/project/xtables-addons/Xtables-addons/xtables-addons-2.14.tar.xz
$ tar xvf xtables-addons-2.14.tar.xz
$ cd xtables-addons-2.14.tar.xz
$ ./configure
$ make &&  make install
```

<br>

> 컴파일시 에러날 경우

```bash
$ vi mconfig
#build_TARPIT=m  // 주석처리 해주세요.
```

<br>

### 2.모듈셋팅

```bash
$ cd geoip/
$ ./xt_geoip_dl
$ ./xt_geoip_build GeoIPCountryWhois.csv
$ mkdir -p /usr/share/xt_geoip/
$ cp -r {BE,LE} /usr/share/xt_geoip/
```

<br>

### 3. 설정하기

```bash
$ iptables -I INPUT -m geoip --src-cc CN -j DROP
```

또는

```bash
/etc/sysconfig/iptables (iptable 설정파일에 추가 )
-A INPUT -m geoip  --source-country CN -j DROP
```
