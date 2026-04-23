---
layout: article
title: 우분투 본딩 Ubuntu Netplan을 이용한 네트워크 본딩(Active-Backup) 설정 및 트러블슈팅
tags: [Linux, Ubuntu, Netplan, Bonding, Network]
key: 20260423-linux-netplan-bonding
---

- 출처 : 직접 경험 기반 (Ubuntu 22.04 LTS 환경)

> 명령어: netplan, ip link, cat /proc/net/bonding/bond0  
> 키워드: 본딩(Bonding), Active-Backup, Netplan, 가용성, 장애 조치  
> 사용처: 서버의 네트워크 이중화를 통해 물리적인 랜 카드나 케이블 장애 시에도 서비스 중단을 방지하고 싶을 때  

--- 

> 실행예제  

```bash
$ ip link show bond0
4: bond0: <BROADCAST,MULTICAST,MASTER,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default qlen 1000
    link/ether 00:0c:29:xx:xx:xx brd ff:ff:ff:ff:ff:ff
```

```
# /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s8:
      dhcp4: no
    enp0s9:
      dhcp4: no  #---------------------------------------------- 1
  bonds:
    bond0:
      interfaces:
        - enp0s8
        - enp0s9
      parameters:
        mode: active-backup
        mii-monitor-interval: 100  #---------------------------- 2
        primary: enp0s8            #---------------------------- 3
      addresses:
        - 192.168.1.100/24
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
      routes:
        - to: default
          via: 192.168.1.1
```

&nbsp;
&nbsp;

## **해설**

이 설정은 두 개의 물리 인터페이스(enp0s8, enp0s9)를 하나로 묶어 bond0라는 가상 인터페이스를 생성하는 과정입니다. 특히 Active-Backup 모드를 사용하여 고가용성을 확보하는 데 중점을 두었습니다.  

`1`{:.info} 물리 랜 카드 인터페이스 설정입니다. 본딩의 멤버가 될 인터페이스에는 별도의 IP 설정을 하지 않도록 dhcp4: no를 지정하여 초기화합니다.  

`2`{:.info} mii-monitor-interval 설정입니다. 기존에 1로 설정되어 있던 값을 100으로 수정하였습니다. 이 수치는 밀리초(ms) 단위이며, 너무 짧은 간격(1ms)은 시스템 리소스를 과하게 소모하거나 미세한 링크 흔들림에도 불필요한 페일오버를 일으킬 수 있습니다. 이를 100ms(0.1초)로 조정하여 안정적인 감시 환경을 구축했습니다.  

`3`{:.info} primary 인터페이스 지정입니다. 본딩 구성 시 특정 랜 카드가 우선적으로 데이터를 처리하도록 강제하는 설정입니다. 이 설정이 누락되거나 잘못 지정될 경우, 어떤 인터페이스가 활성 상태인지 불분명해져 통신 패킷이 정상적으로 응답하지 않는 문제가 발생할 수 있습니다. enp0s8을 명시하여 통신의 주 통로를 확실히 정의했습니다.   

&nbsp;
&nbsp;

## **트러블슈팅 및 주의사항**

본딩 설정 후 네트워크 통신이 되지 않는다면 다음 항목을 점검해야 합니다.  

가상화 환경(VMware/ESXi) 정책: 가상 머신에서 본딩을 테스트할 경우, 가상 스위치의 보안 정책(Mac Address Changes, Forged Transmits)이 Accept로 되어 있어야 합니다.  

불필요한 IP 설정 제거: 물리 인터페이스(enp0s8 등)에 기존에 설정된 IP나 게이트웨이 정보가 남아있으면 본딩 인터페이스와 충돌하여 통신이 단절됩니다.  

상태 확인 명령:  
설정 적용 후에는 반드시 cat /proc/net/bonding/bond0를 실행하여 Currently Active Slave가 지정한 primary 인터페이스와 일치하는지 확인해야 합니다.