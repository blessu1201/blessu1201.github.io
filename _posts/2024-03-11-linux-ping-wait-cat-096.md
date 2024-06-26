---
layout: article
title: 쉘기능을 자유자재로 다루기_11 여러 호스트에 병렬로 ping을 날려서 대기 시간 줄이기
tags: [Linux, ShellScript, ping, wait, cat]
key: 20240311-linux-ping-wait-cat
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: ping, wait, cat  
> 키워드: 병렬 처리, 동기, 종료  
> 사용처: 여러 호스트에 ping 명령어를 실행하는 대기 시간을 줄이고자 병렬로 백그라운드 실행시키고 명령어 종료를 동기화해서 결과를 순서대로 출력하고 싶을 때

--- 

> 실행예제

```
$ ./background-wait.sh
PING 192.168.2.1 (192.168.2.1): 56 data bytes
64 bytes from 192.168.2.1: icmp_seq=0 ttl=255 time=3.554 ms
64 bytes from 192.168.2.1: icmp_seq=0 ttl=255 time=3.435 ms
64 bytes from 192.168.2.1: icmp_seq=0 ttl=255 time=3.469 ms
(생략. 두 번째, 세 번째 ping 결과가 출력됨)
```

> 스크립트

```bash
#!/bin/sh

# 호스트 세 개를 병렬로 ping 실행, 6번 반복해서
# 각각 5초 대기

ping -c 6 192.168.2.1 > host1.log &  #---------- 1
ping -c 6 192.168.2.2 > host2.log &  #---------- 1
ping -c 6 192.168.2.3 > host3.log &  #---------- 1

# 모든 ping 명령어가 종료할 때까지 대기, 동기화
wait  #----------------------------------------- 2

# ping 명령어 결과 출력
cat host1.log host2.log host3.log  #------------ 3
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 여러 서버에 ping 명령어를 실행해서 네트워크 개통을 확인하고 그 결과를 표시합니다. ping 명령어는 백그라운드로 병렬 실행하지만 마지막 결과를 표시하기 전에 **wait 명령어로 동기화한다**는 것이 중요합니다.

`1`{:.info}은 192.168.2.1, 192.168.2.2, 192.168.2.3이라는 세 호스트에 **ping 명령어**로 ICMP 패킷을 보냅니다. 이때 결과를 각 로그 파일(host1.log, host2.log, host3.log)에 출력합니다. ICMP 패킷을 보내는 횟수는 -c 옵션으로 6번을 지정합니다.

ping 명령어로 ICMP 패킷을 여러 번 보내며 자동으로 1초간 대기합니다. 즉, 6번 ping을 실행하면 중간에 5번 대기가 있어서 적어도 5초는 걸리게 됩니다. 예제에서는 3대에 ping을 실행하므로 전체적으로 5초 x 3 = 15초가 걸리게 됩니다. 수를 늘릴수록 대기 시간도 늘어나게 됩니다. 그리고 `1`{:.info}은 시간 단축을 위해 ping 마지막에 **&**를 각각 붙여서 백그라운드로 실행합니다. 이렇게 백그라운드로 병렬 실행하면 (응답 시간을 무시한다면) 3개의 ping은 5초 정도에 끝납니다.

`2`{:.info}는 wait 명령어로 백그라운드로 실행한 ping 명령어를 동기화합니다. 단순히 명령어를 병렬로 처리하고 백그라운드로 실행시킨다면 &만 붙이면 됩니다. 하지만 각각 명령어의 종료를 알 수 없어서 스크립트 마지막에 결과를 표시할 수 없습니다. 이 예제처럼 종료 결과를 표시하고 싶으면 wait 명령어로 동기화해야 합니다.

wait 명령어를 인수 없이 실행하면 스크립트에서 실행된 백그라운드 실행 명령어 종료를 기다립니다. 예제에서는 마지막 ping 결과를 순서대로 표시하기 위해 모든 ping 명령어의 종료를 기다립니다. 따라서 wait 명령어를 사용하면 각각 백그라운드로 실행한 ping 명령어가 끝나길 기다렸다가 다음 줄을 실행합니다.

`3`{:.info}은 모든 ping 명령어 출력 결과를 cat 명령어로 표시합니다. `2`{:.info}에서 wait 명령어를 사용했으므로 이 cat 명령어를 실행하면 세 ping 명령어가 종료되어 결과가 제대로 표시됩니다.

&nbsp;
&nbsp;

## **주의사항**

- 너무 많은 백그라운드 처리를 병렬로 실행하면 네트워크가 혼잡해져서 이런 네트워크 진단 툴이 제대로 동작하지 못할 수 있습니다. 따라서 결과를 보면서 동시 실행하는 명령어 수를 적당히 조절해야 합니다.
