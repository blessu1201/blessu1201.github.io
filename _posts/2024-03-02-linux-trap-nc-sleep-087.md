---
layout: article
title: 쉘기능을 자유자재로 다루기_02 스크립트 실행할 때 시그널을 받아서 현재 실행 상태 출력하기
tags: [Linux, ShellScript, trap, nc, sleep]
key: 20240302-linux-
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: trap, nc, sleep  
> 키워드: 시그널, 끼어들기, 트랩  
> 사용처: 처리 시간이 긴 셸 스크립트를 실행하는데 프로세스를 정지하지 않고 내부 실행 상태를 표시하고 싶을 때

--- 

> 실행예제

```
$ ./sig-usr1.sh
Connection to 192.168.2.105 80 port [tcp/http] succeeded!
Connection to 192.168.2.105 80 port [tcp/http] succeeded!
Connection to 192.168.2.105 80 port [tcp/http] succeeded!
Try Count: 3  <----- 다른 터미널에서 시그널을 보내면 현재 Try Count를 표시 가능
Connection to 192.168.2.105 80 port [tcp/http] succeeded!
(생략)
```

> 스크립트

```bash
#!/bin/sh

# 실행 횟수
count=0  #------------------------------------ 1

# 통신 대상 서버
server="192.168.2.105"  #--------------------- 2

# 시그널 USR1 트랩설정. 현재 $count 표시
trap 'echo "Try Count: $count"' USR1  #------- 3

# nc 명령어로 연속 통신 확인 반복
while [ "$count" - le 1000 ]  #--------------- 4
do
  # 카운터 1 늘리고 nc 명령어 실행
  # 마지막에 1초 대기
  count=$(expr $count + 1)  #----------------- 5
  nc -zv "$server" 80  #---------------------- 5
  sleep 1  #---------------------------------- 5
done
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 반복 처리를 하여 통신 시간이 긴 스크립트가 실행 중일 때 해당 프로세스에 **kill 명령어**로 **USR1 시그널**을 보내서 지금까지 반복한 실행 횟수를 표시합니다. 여기서는 **nc 명령어**를 사용해 TCP 포트 80(http)으로 보내는데 지금까지 반복한 횟수를 "Try Count:"로 표시합니다. 에제에서 사용하는 nc 명령어는 서버와의 통신을 확인하는데 유용합니다.

실행 중인 프로세스 상태를 알려면 프로세스에 시그널을 보내고 그때의 내부 상태를 표시하는 방법이 있습니다. 셸 스크립트에서 이런 시그널 처리를 하려면 trap 명령어를 사용합니다.

예제에서 사용하는 USR1 시그널은 애플리케이션마다 원하는 대로 기능을 지정하는 시그널입니다. 예를 들어 웹 서버로 자주 쓰는 아파치 httpd에 USR1 시그널이 오면 graceful 모드로 '자연스럽게 재기동'을 하고 리눅스 dd 명령어에 USR1 시그널을 보내면 명령어를 계속 실행하면서 '지금까지 처리한 블록 수'를 표시합니다.

이런 구조를 셸 스크립트에서도 구현하면 처리 시간이 오래 걸리는 스크립트라도 현재 실행 중인 상태를 볼 수 있어서 편리합니다. 예제에서는 nc 명령어 반복 횟수를 표시하고 있습니다.

우선 `1`{:.info}과 `2`{:.info}에서 확인 횟수 카운터를 초기화하고 대상 서버를 정의합니다. 셸 변수 count가 실행 반복 횟수가 됩니다.

`3`{:.info}은 시그널을 수신했을 때 어떤 처리를 할지 작성한 부분입니다. trap 명령어로 USR1 시그널을 받으면 "Try Count: $count"를 echo 명령어로 표시해서 지금까지 처리한 반복 횟수를 표시합니다. `3`{:.info}부분은 스크립트를 위에서부터 순서대로 실행할 때는 아무것도 표시하지 않습니다. 실행 중에 실제로 USR1 시그널이 왔을 때 이 처리를 하도록 정의한 문장이라고 이해하기 바랍니다. 이렇게 셸 스크립트에서는 trap 명령어를 사용해서 끼어들기 처리를 작성할 수 있습니다.

`4`{:.info}에서 while 문으로 통신 확인(실행 시간이 긴 처리)을 합니다. 카운터를 1 늘려가며 1000번 실행합니다.

`5`{:.info}에서 nc 명령어로 대상 서버 80번(http)로 통신 확인을 하고 sleep 명령어로 1초씩 기다린 다음 expr 명령어로 셸 변수 count 값을 1 늘립니다.

실제로 이 프로세스에 USR1 시그널을 보내려면 스크립트를 실행시킨 채 다른 터미널에서 실행 중인 프로세스 목록을 표시하는 **ps 명령어**를 실행합니다.

```
$ ps x
PID   TT	  STAT	  TIME	COMMAND
264   ??    S     0:19.49	/usr/libexe/UserEventAgent (Aqua)
266	  ??	  S	    33:12.42 /usr/sbin/distnoted agent
267	  ??	  S	    0:11.10	/usr/sbin/universalaccessd launchd -s
268   ??    S     8:45:31 /usr/sbin/cfprefsd agent
29658	pts/1	S+	  0:00.00	/bin/sh ./sig-usr1.sh
```

PID 열을 보면 sig-usr1.sh를 실행하는 프로세스 ID가 29658입니다. 이 프로세스 ID에 kill 명령어로 USR1 시그널을 보냅니다.

```
$ kill -s USR1 29658
```

이렇게 명령어를 실행하면 스크립트에서 USR1 시그널을 수신해서 실행 예제(sig-usr1.sh)에서 본 것 처럼 "Try Count: 3"같이 nc 명령어 실행 횟수를 표시합니다.

&nbsp;
&nbsp;

## **주의사항**

- OS에 따라서 사용 가능한 시그널은 조금씩 다릅니다. 사용 가능한 시그널은 kill -l로 확인할 수 있습니다. 이때 표시되는 시그널은 모두 SIG로 시작합니다. 예를 들어 HUP 시그널은 SIGHUP으로 표시됩니다.
