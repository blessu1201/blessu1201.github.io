---
title: SoftEtherVPN + freeradius + OpenLAP 연동
date: 2020-08-13
categories: [Linux, Server보안]
tags: [Linux]
comments: true
seo:
  date_modified: 2020-08-15 16:59:05 +0900
---

## Freeradius + SoftetherVPN + OpenLDAP 연동하기

---

> SoftEtherVPN과 OpenLAP 을 사용 중인 전제하에 작성된 글입니다.

참고 : (https://www.tldp.org/HOWTO/archived/LDAP-Implementation-HOWTO/index.html)  

<br>

#### 1 freeradius  설치

```
$ yum install -y freeradius freeradius-ldap freeradius-config freeradius-utils freeradius-krb5
```

<br>

#### 2. ldap 설정

<pre>하기 파일은 LDAP서버의 접속설정입니다.</pre>

```
$ vi /etc/raddb/modules/ldap
...
ldap {
#
#  Note that this needs to match the name in the LDAP
#  server certificate, if you're using ldaps.
server = "192.168.1.XXX"                      # ldap 서버 IP를 입력합니다.
identity = "cn=manager,dc=mycompany,dc=co,dc=kr"
password = ldap manager password              # ldap manager password 를 입력합니다.
basedn = "dc=mycompany,dc=co,dc=kr"
filter = "(uid=%{%{Stripped-User-Name}:-%{User-Name}})"
#base_filter = "(objectclass=radiusprofile)"

        #  How many connections to keep open to the LDAP server.
        #  This saves time over opening a new LDAP socket for
        #  every authentication request.
        ldap_connections_number = 50          # 알맞게 설정합니다.
```

<br>

#### 3.ldap 연동

```
$ vi /etc/raddb/sites-available/default
...
        #  The ldap module will set Auth-Type to LDAP if it has not
        #  already been set
        ldap                         # 주석을 해제합니다.
...
```

<br>

#### 4. radius  비밀번호 변경

<pre>line 101에 secret 암호를 설정합니다.</pre>

```
$ vi /etc/raddb/clients.conf
...
#  And is at LEAST 8 characters long, preferably 16 characters in
#  length.  The secret MUST be random, and should not be words,
#  phrase, or anything else that is recognizable.
#
#  The default secret below is only for testing, and should
#  not be used in any real environment.
#
secret          = mypassword   # vpn server manager에 Authentication Server Setting 에 입력될 패스워드
...
```

<br>

#### 5.nas ip 와 hostname 매핑

<pre>
clients.conf 에서 nas ip 확인 후 /etc/hosts에 매핑
vpn 서버와 radius가 동일한 서버에 설치되어 아래와 같이 설정하였습니다.
</pre>

```
$ vi /etc/hosts
127.0.0.1   VPN-server localhost localhost.localdomain localhost4 localhost4.localdomain4
```

<br>

#### 6. radius 시작

```
$ /etc/init.d/radiusd start
```

<br>

#### 7. 로컬에서 테스트

```
$ radtest LdapID 'LdapID pw' 127.0.0.1 1812 'mypassword'        #radius password
Sending Access-Request of id 116 to 127.0.0.1 port 1812
User-Name = "user"
User-Password = "userpassword"
NAS-IP-Address = 127.0.0.1
NAS-Port = 1812
Message-Authenticator = 0x00000000000000000000000000000000
rad_recv: Access-Accept packet from host 127.0.0.1 port 1812, id=116, length=20
```

<br>

#### 8. softether vpn 설정

###### (8-1) 서버 radius 설정

<pre>
서버 매니저 실행 -> manage virtual hub -> Authentication Server Setting ->  
radius server ip  :  nas ip를 적어주도록 합니다.
port : 1812
shared secret :  clients.conf 에서 수정한 비번을 적어주도록 합니다.</pre>

![ServerManager](http://drive.google.com/uc?export=view&id=1JkSrweput616_dcIZNxf4_uWtdIkXbfE)

<br>

###### (8-2) 유저 생성 (기존 유저는 전부 삭제)

<pre>서버 매니저 실행 -> Manager users ->  New
user Name : *
Auth type : RADIUS Authentication </pre>

![User](http://drive.google.com/uc?export=view&id=1OlBfH7EqbNLX9zaOPiO3L-0Mxz7GASLe)

<pre>Authentication Server Setting -> Use RADIUS Authentication 체크
IP : 127.0.0.1 (radius 설치한 서버 IP)
port :1812
Shared Secret : mypassword
confirm Shared Secret : mypassword</pre>

<br>

###### (8-3) vpn client 설정  : User Authentication Setting

<pre>
Auth Type : RADIUS or NT Domain Authentication
User Name :  openldap 계정
password : openldap 계정 패스워드</pre>

![client](http://drive.google.com/uc?export=view&id=11SPGCjTJep4ewGMU25pDALNc22VbRIjM)

<br>

#### 9. 트러블슈팅

https://github.com/SoftEtherVPN/SoftEtherVPN/issues/112  

> 운영 중인 VPN서버의 적용전 테스트 서버를 만들어 몇가지 테스트를 해보았는데,<br>
> 아래와 같은 이슈가 있었습니다. 추후 VPN 설정하실 때 참고하새요.

<br>

###### (9-1) securenatenable 한 후 계정으로 접속하면 udp broadcast storm 발생

<pre>하기 log 폴더에 log가 과하게 쌓이고 속도가 느려짐
securenatdisable 하면 dhcp ip를 받아오지 못함.</pre>

- /usr/local/src/vpnserver/security_log
- /usr/local/src/vpnserver/server_log

<br>

<pre>vpncmd 로 접속하여 하기 명령어를 입력하여 gateway ip 와 물리 ip가 동일한지 확인합니다.</pre>

```
$ VPN-server> dhcpget
```

- 원인) 물리 인터페이스와 gateway ip 가 동일하여 발생하는 문제
- 해결) eth의 ip 와 gateway ip 를 서로 다르게 설정

<br>

###### (9-2) server manager 에서  user에 * 가 설정되어있고, 기존계정이 남아있다면 authtype 상관없이(radius,standard) 기존암호(standard)로 접속이 가능함.

<pre>
- 1차로 standard 계정접속정보를 확인 후, radius 접속정보(ldap계정)를 확인하는게 아닌가 싶습니다.(추측)
- ServerManager 에서 user 를 * 로 설정하게 되면 모든 계정이 LDAP계정을 사용하게 됩니다.
- user별 개별설정을 하려면 동일한 계정을 만들고 radius 로 설정 후 개별설정을 해줄 수 있습니다.</pre>
