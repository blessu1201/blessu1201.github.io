---
title: 리눅스 GeoIP 설치(CentOS 7)
date: 2020-07-17
categories: [Linux, Server보안]
tags: [Linux, geoip]
comments: true
seo:
  date_modified: 2020-08-15 16:59:05 +0900
---


## CentOs 7 에서 GeoIP 설치
---

CentOs7 에서 GeoIP를 활용하여 국가IP차단 하는 방법. 서버 보안설정시 참고하세요.
<br>
참고 : <http://sata.kr/entry/IPTables-12-IPTables%EC%97%90-GeoIP%EB%A5%BC-%EC%84%A4%EC%B9%98%ED%95%B4%EB%B3%B4%EC%9E%90-GeoIP-CentOS-6CentOS-7>



<br>

#### 1. 패키지 설치

```
$ yum install gcc gcc-c++ make automake unzip zip xz kernel-devel-`uname -r` iptables-devel
$ yum install perl-Text-CSV_XS
$ wget https://jaist.dl.sourceforge.net/project/xtables-addons/Xtables-addons/xtables-addons-2.14.tar.xz
$ tar xvf xtables-addons-2.14.tar.xz
$ cd xtables-addons-2.14.tar.xz
$ ./configure
$ make &&  make install
```

<br>

컴파일시 에러날 경우

```
$ vi mconfig
#build_TARPIT=m  // 주석처리 해주세요.
```

<br>

#### 2.모듈셋팅

```
$ cd geoip/
$ ./xt_geoip_dl
$ ./xt_geoip_build GeoIPCountryWhois.csv
$ mkdir -p /usr/share/xt_geoip/
$ cp -r {BE,LE} /usr/share/xt_geoip/
```

<br>

#### 3. 설정하기

```
$ iptables -I INPUT -m geoip --src-cc CN -j DROP
```

또는

```
/etc/sysconfig/iptables (iptable 설정파일에 추가 )
-A INPUT -m geoip  --source-country CN -j DROP
```
