---
layout: article
title: 서버관리_01 서버 네트워크 인터페이스와 IP 주소 목록 얻기
tags: [Linux, ifconfig, awk, ShellScript]
key: 20230822-linux_server_manage_01 
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

# 서버 네트워크 인터페이스와 IP 주소 목록 얻기

> 명령어: ifconfig, awk  
> 키워드: NIC, IP주소, 네트워크 인터페이스  
> 사용처: 서버 NIC와 IP 주소 목록을 표시하고 싶을때  


> 실행예제

```
$ ./nic-ipaddr.sh
[eth0]
10.211.55.18
[eth1]
[lo]
127.0.0.1
```

> 스크립트

 ```bash
#!/bin/bash

# ifconfig 명령어로 유효한 인터페이스 표시
# awk 명령어로 인터페이스명과  IP 주소 추출

LANG=C /usr/sbin/ifconfig |\             # ---- 1
awk '/^[a-z]/ {print "[" $1 "]"}         # ---- 2
/inet / {split($2,arr,":");} {print $2}' # ---- 3
```

## **해설**

이 스크립트는 서버 네트워크 인터페이스와 거기에 할당된 IP 주소를 표시합니다. IP 주소 취득은 **ifconfig 명령어**로 하고 그 출력을 awk 명령어로 가공합니다. 이때 이 서버에는 네트워크 인터페이스로 eth0와 eth1이 있고 인터페이스는 둘 다 유효(UP)하지만 IP 주소는 eth0에만 설정되어 있다고 가정합니다.

예제에서 사용한 ifconfig 명령어는 서버 네트워크 설정이나 정보를 취득하는 명령어입니다. 다음처럼 인수 없이 실행하면 서버에서 현재 유효한 네트워크 인터페이스 정보(링크상태, MAC주소, IP주소, 전송 패킷 수 등)를 표시합니다. 그리고 ifconfig 명령어는 리눅스, Mac, FreeBSD에서 서로 조금씩 출력이 다릅니다. 따라서 리눅스 외에서는 예제를 그대로 사용할 수 없으므로 주의사항을 참조하기 바랍니다.

- ifconfig 명령어를 인수 없이 실행하기

```
eth0: flags=4099<UP,BROADCAST,MULTICAST>  mtu 1500
        inet 10.211.55.18  netmask 255.255.0.0  broadcast 172.17.255.255
        ether 02:42:ef:e8:25:45  txqueuelen 0  (Ethernet)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

eth1: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
      :(생략)

lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
      :(생략)
```

ifconfig 명령어는 서버 관리에 자주 사용하는 명령어인데 출력하는 내용이 많아서 다루기가 조금 번거롭습니다. 네트워크 설정 확인이라면 예제처럼 간단히 서버 네트워크 인터페이스와 IP 주소만 표시하고 싶을 때도 있을 것입니다.

[1](#){:.button.button--primary.button--rounded.button--xs}에서 ifconfig 명령어를 실행합니다. 이때 영어로 표기하도록 LANG=C를 지정합니다. 그리고 리눅스에서 /sbin을 경로에 포함하지 않는 경우도 있으므로 ifconfig 명령어를 완전 경로로 지정해서 실행합니다. 출력 결과를 파이프로 awk 명령어에 보내는데 한 줄이 길어지므로 줄 끝에 \를 써서 줄바꿈 합니다.

[2](#){:.button.button--primary.button--rounded.button--xs}의 **awk 명령어**는 우선 /^[a-z]/ 패턴을 사용합니다. 이것은 인터페이스명을 출력하기 위한 패턴입니다. ifconfig 명령어는 줄 처음에 인터페이스명을 표시하고 그다음부터는 들여쓰기(indent)해서 링크 상태 등 각종 정보를 표시합니다. 따라서 줄 처음에 소문자 알파벳이 있는 줄을 찾아서 그 첫 번째 컬럼을 표시하면 인터페이스명을 얻을 수 있습니다. 여기서는 인터페이스명을 보기 쉽도록 awk 명령어로 표시할 때 []로 둘러 쌉니다.

```
{print "[" $1 "]"}
```
awk 명령어는 스페이스를 때고 표시하므로 [eth0]처럼 인터페이스명이 표시됩니다.

[3](#){:.button.button--primary.button--rounded.button--xs} 에서 IP 주소를 취득합니다. 여기서 취득하고 싶은 것은 inet addr: 뒤에 오는 부분 즉, 10.211.55.18 입니다.

```
inet 10.211.55.18  netmask 255.255.0.0  broadcast 172.17.255.255
```

[3](#){:.button.button--primary.button--rounded.button--xs}은 우선 awk 명령어로 두 번째 컬럼을 $2로 추출합니다. awk 명령어 구분자는 스페이스이므로 $2에는 addr:10.211.55.18이 들어 있습니다.

이 $2에서 IP 주소를 추출하려면 : 를 구분자로 하여 두 번째 컬럼을 추출하면 됩니다. 따라서 "3"은 awk 명령어의 split 함수를 써서 : 으로 문자열을 분할해서 arr[2]로 두 번째 컬럼을 추출합니다. 이 예제처럼 우선 스페이스 구분자로 추출하고 다시 다른 구분자로 취득하는 데는 awk 명령어의 **split 함수**를 사용하면 편리합니다.

예제에서는 네트워크 인터페이스명과 IP 주소를 출력하는데 출력 결과를 다른 스크립트에 넘기면서 네트워크 인터페이스명은 빼고 IP 주소만 쓰고 싶을 때 있습니다. 이때 /^[a-z]/ 필터 부분을 삭제해서 다음처럼 스크립트를 작성합니다.

```bash
LANG=C /sbin/ifconfig | awk '/inet / {split($2,arr,":"); print arr[2]}'
```

## **주의사항**

- 이 스크립트는 IPv4 주소만 대응하고 IPv6 주소는 무시합니다.
- Mac/FreeBSD의 ifconfig 명령어는 조금 다릅니다. IP 주소 표시 부분이 inet 10.211.55.21로 리눅스와 달리 addr:문자열이 없습니다.

- Mac/FreeBSD ifconfig 명령어
```
$ ifconfig
em0: flags=8843<UP,BROADCAT,RUNNING,SIMPLEX,MULTICAST> metric 0 mtu 1500
        options=9b<RXCSUM,TXCSUM,VLAN_MTU,VLAN_HWTAGGING,VLAN_HWCSUM>
        ether 00:1c:42:5e:c3:b1
        inet 10.211.55.21 netmask 0xffffff00 broadcast 10.211.55.255
              :(생략)
```
따라서 Mac이나 FreeBSD에서는 : 구분자로 추출하지 않아도 되므로 다음처럼 조금 더 간결한 스크립트가 됩니다.
```bash
LANG=C /usr/sbin/ifconfig |\ awk '/^[a-z]/ {print "[" $1 "]"} /inet / {print $2}'
```