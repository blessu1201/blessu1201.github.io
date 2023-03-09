---
layout: article
title: Linux GeoIP 설치(CentOS 6)
tags: [Linux, GeoIP]
key: 20200716_geoip_centos6
---

{% include googlead.html %}

---

> 서버 운영시 중국등에서 잦은 해킹시도로 인해, 보안을 강화하고자 GeoIP를  
> 서버에 설치 및 설정한 내용을 정리하였습니다.

<br>

- [참조사이트](https://www.enteroa.com/2014/09/26/xtables-addons-%EC%84%A4%EC%B9%98/)

<br>

## 1. 기본 라이브러리 설치

```bash
$ yum install gcc gcc-c++ make automake unzip zip xz kernel-devel-`uname -r` iptables-devel
```

<br>

## 2. Perl-Text 설치

> 정상적으로 컴파일이 되면 /lib64/xtables/libxt_geoip.so 파일이 생성됩니다.   
> 미생성시 재 컴파일해주세요)

```bash
$ wget https://nchc.dl.sourceforge.net/project/xtables-addons/Xtables-addons/xtables-addons-1.47.tar.xz
$ tar xvf xtables-addons-1.47
$ cd xtables-addons-1.47
$ ./configure --with-xtables
$ make && make install
```
```bash
$ vi /usr/src/kernels/`uname -r`/include/linux/autoconf.h
LINE 1574 -->  /* define CONFIG_IP6_NF_IPTABLES_MODULE 1 */
```

<br>

## 3. xtables-addons 설치 및 컴파일

```bash
$ cd geoip
$ ./xt_geoip_dl
$ ./xt_geoip_build GeoIPCountryCSV.zip
```

<br>

## 4. geoip 모듈 세팅

```bash
$ cd geoip
$ ./xt_geoip_dl
$ ./xt_geoip_build GeoIPCountryCSV.zip
```
<br>

## 5. geoip DB를 위한 디렉토리 생성

> BE,LE 디렉토리 복사 경우에 따라 4,5 순서가 바뀌어야 진행되는 경우가 있습니다.

```bash
$ mkdir -p /usr/share/xt_geoip
$ cp -r {BE,LE} /usr/share/xt_geoip/
```

<br>

## 6. 중국,러시아 ip 차단

```bash
$ iptables -I INPUT -m geoip --src-cc CN,RU -j DROP
```

<br>

## 7.확인

```bash
$ iptables --version
iptables v1.4.7

$ iptables -L
Chain INPUT (policy ACCEPT)
target     prot opt source               destination        
DROP       all  --  anywhere             anywhere             Source countries: CN,RU
ACCEPT     all  --  anywhere             anywhere            state RELATED,ESTABLISHED
ACCEPT     all  --  anywhere             anywhere
...
```
<br>

## 8. 트러블슈팅

[참고사이트](http://vividrigh.tistory.com/296)

> 만약 iptables를 소스 컴파일 하였다면 설치된 경로를 `--with-xtables` 옵션에 적어주고   
> compile 패키지 설치 한 경우에는 `iptables-devel`을 install 해준다.

<br>

> yum install perl-Text-CSV_XS 설치 안될 경우

```bash
$ yum install epel-release-6-8.noarch
$ ./xt_geoip_build GeoIPCountryWhois.csv
```
