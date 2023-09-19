---
layout: article
title: 네트워크_02 ping으로 특정 호스트 응답 평균 시간을 취득하기
tags: [Linux, ping, sed, awk, ShellScript]
key: 20230919-linux_network_02
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: ping, sed, awk  
> 키워드: ICMP, 응답 속도, 평균값   
> 사용처: 특정 서버와 통신 상태를 조사하고 싶을 때  

> 실행 예제  

```
$ ./pingavg.sh
Ping to: 192.168.2.1
Ping count: 10
Ping average[ms]:
38.79
```

> 스크립트

```bash
#!/bin/sh

ipaddr="192.168.2.1" # ipaddr, count 변수 --------- 1
count=10

echo "Ping to: $ipaddr" # echo 항목 --------------- 2
echo "Ping count: $count"
echo "Ping average[ms]:"

# ping 명령어 실행 결과를 임시 파일에 출력
ping -c $count $ipaddr > ping.$$ # ---------------- 3

# "time=4.32" 부분을 sed로 추출, awk로 평균값 계산
sed -n "s/^.*time=\(.*\) ms/\1/p" ping.$$ |\  # --- 4
awk '{sum+=$1} END{print sum/NR}'  # -------------- 5

# 임시파일 삭제
rm -f ping.$$
```

&nbsp;
&nbsp;

## **해설** 

이 스크립트는 지정한 IP 주소에 여러 번 ping을 실행해서 응답 시간 평균을 계산해서 표시합니다.

**ping 명령어**는 **ICMP 패킷**을 보내는 명령어입니다. 실행하면 ICMP echo request 패킷을 상대방에게 보내고 응답으로 ICMP echo reply가 돌아옵니다.

- ping 명령어와 ICMP 패킷
<img src='http://drive.google.com/uc?export=view&id=1178Ndkhs7AFfa2g8U2u7Qli2SQEM7q31' /><br>

ICMP 패킷 응답 시간을 측정해서 네트워크 상태를 조사할 수 있습니다. 예를 들어 정기적으로 ping 명령어를 실행하다가 갑자기 응답 시간이 길어지면 해당 호스트 대상으로 네트워크가 혼잡하거나 도중에 네트워크 기기가 어떤 이상이 생겼을 수도 있습니다.

ping 명령어 출력은 OS에 따라 다소 다르지만 다음과 같습니다. 표시괸 icmp_seq가 실행 횟수, ttl이 패킷 TTL값(라우터를 몇 번 넘었는가), time이 응답 시간(밀리초)입니다.

- ping 명령어 출력 예

```
$ ping -c 4 192.168.2.1
PING 192.168.2.1 (192.168.2.1) 56(84) bytes of data.
64 bytes from 192.168.2.1: icmp_seq=1 ttl=64 time=0.374 ms
64 bytes from 192.168.2.1: icmp_seq=2 ttl=64 time=0.405 ms
64 bytes from 192.168.2.1: icmp_seq=3 ttl=64 time=0.345 ms
64 bytes from 192.168.2.1: icmp_seq=4 ttl=64 time=0.469 ms

--- 192.168.2.1 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3000ms
rtt min/avg/max/mdev = 0.345/0.398/0.469/0.048 ms
```

마지막 줄을 보면 rtt(round trip time, 패킷 왕복에 걸린 시간)의 avg가 ping 명령어 자체의 평균 응답 시간입니다. 이제부터 명령어 출력에서 평균값을 구하는 예로 스크립트에서 값을 계산해 봅시다.

`1`{:.info}은 대상 IP 주소와 ping 명령어 실행 횟수를 지정합니다. 이걸로 `2`{:.info}에서 측정할 대상 IP주소, 횟수 등을 표시합니다.

`3`{:.info}은 ping 명령어를 실행합니다. ping 명령어는 옵션을 지정하지 않으면 계속 반복 실행하므로 **-c 옵션**으로 실행 횟수를 지정합니다. 표시 결과를 나중에 계산하기 위해 표준 출력을 임시 파일 ping.`$$`{:.warning}에 리다이렉트 합니다. 여기서 **$$**는 셸 특수 변수로 프로세스 ID가 들어가므로 이런 임시 파일을 만들 때 파일명에 자주 사용합니다.

`4`{:.info}는 ping 명령어 출력 결과에서 응답 속도를 취득합니다. ping 명령어 응답 속도는 time=0.374 ms의 숫자 부분입니다. ms는 밀리세컨드(밀리초)를 의미합니다.

sed 명령어의 **-n 옵션**은 처리 후에 패턴 스페이스 내용을 출력하지 않도록 하는 옵션입니다. 그대로는 아무것도 출력되지 않아서 의미가 없으므로 마지막에 p플래그를 붙여서 일치했을 때만 패턴 스페이스를 출력하도록 지정합니다.

이런 -n 옵션과 p플래그를 조합해서 sed 명령어로 치환하면 치환이 발생한 줄만 출력 할 수 있습니다. sed 명령어에서 자주 쓰는 방식이므로 기억해두기 바랍니다.

**sed 명령어 -n 옵션**과 **p 플래그**로 time=0.374 ms 부분에서 숫자 부분만 출력해서 응답 시간을 추출합니다. sed 명령어로 패턴이 일치한 부분만 출력하고, 파이프로 awk 명령어에 접속하는데 한 줄이 길어지므로 끝에 \로 줄바꿈을 넣습니다.

sed 명령어로 숫자만 뽑았으므로 `4`{:.info}에서 awk에 넘길 때 입력은 다음과 같습니다. 이것이 ping 명령어 응답 시간(밀리초)이 됩니다.

```
0.374
0.405
0.345
0.469
```

이런 숫자 나열에서 평균값을 구하려면 예제에서는 **awk 명령어**를 사용합니다. `5`{:.info}처럼 awk 액션에서는 sum 변수에 $1(1열)값을 더해서 전체 합을 구합니다. 마지막에 END 패턴에서 sum 값을 처리한 줄 수(NR)로 나눠서 평균값을 출력할 수 있습니다. NR은 awk 내장 변수로 입력한 레코드 수를 나타냅니다.

&nbsp;
&nbsp;

## **주의사항**

- 보안을 이유로 최근에는 ping 명령어(ICMP 패킷)에 응답하지 않는 서버가 많습니다. 따라서 예제를 사용하기 전에 대상 서버가 ping에 응답하는지 확인해보기 바랍니다.
