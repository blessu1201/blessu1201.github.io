---
layout: article
title: 사용자 인터페이스_02 키보드에서 Ctrl +c를 입력했을때 현재 상태를 출력하며 종료하기
tags: [Linux, ShellScript, trap, exit, curl, sleep]
key: 20240412-linux-trap-exit-curl-sleep
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: trap, exit, curl, sleep  
> 키워드: 시그널, 트랩, 종료  
> 사용처: 시간이 오래 걸리는 처리나 무한 반복 처리에서 사용자가 도중에 종료를 하기 위해서 Ctrl + C 키를 입력하더라도 종료하기 전에 어떤 처리를 했는지 확인하고 싶을 때

--- 

> 실행예제

```
$ ./sigint.sh http:/www.example.org/
%	Total	%	Received	%	Xferd	Average Dload	Speed Upload	Time Total	Time Spent	Time Left	Current Speed
100	1270	100	1270		0	0	2903		0		--:--:--		--:--:--		--:--:--	9921
%	Total	%	Received	%	Xferd	Average Dload	Speed Upload	Time Total	Time Spent	Time Left	Current Speed
100	1270	100	1270		0	0	5384		0		--:--:--		--:--:--		--:--:--	10948
^C ------------------------------------------------------------------------------Ctrl + C 누름
Try count : 2
```

> 스크립트

```bash
#!/bin/sh

count=0
trap ' echo
      echo "Try count: $count"
      exit ' INT  #-------------------------- 1(trap문)

while :  #----------------------------------- 2(while문)
do
  curl -o /dev/null $1
  count=$(expr $count + 1)
  sleep 1
done
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 명령행 인수로 지정한 URL에 1초에 한 번씩 curl 명령어로 접근합니다. 키보드에서 `Ctrl` + `C` 가 입력되면 동작을 멈추고 지금까지 접근한 횟수를 "Try count : 2" 처럼 표시합니다.

`Ctrl` + `C` 로 현재 터미널에서 포 그라운드로 동작하는 셸 스크립트를 강제 종료하는데 이때의 동작은 다음과 같습니다.

1. `Ctrl` + `C` 를 입력하면 셸 스크립트 프로세스에 **SIGINT**라는 시그널이 전달됩니다.
2. SIGINT를 받은 셸 스크립트 프로세스는 키보드에서 인터럽트가 발생했다고 알립니다.
3. 키보드 인터럽트의 기본 동작은 프로세스 종료이므로 셸 스크립트는 실행 종료됩니다.

여기서 **시그널**이란 실행 중 프로세스에 대해 다양한 동작을 지시하는 방식입니다. 시그널에는 여러 종류가 있는데 각각 기능도 다릅니다. 키보드에서 `Ctrl` + `C`를 입력하면 시그널 번호 2의 SIGINT가 발생합니다.

**kill 명령어**에 -l 옵션을 지정해서 실행하면 아래와 같이 시스템 시그널 목록을 표시합니다.

- 시그널 목록은 kill -l로 확인

  ```
  $ kill -l
   1) SIGHUP 	   2) SIGINT	   3) SIGQUIT	   4) SIGILL
   5) SIGTRAP 	   6) SIGABRT	   7) SIGEMT	   8) SIGFPE
   9) SIGKILL	  10) SIGBUS	  11) SIGSEGV	  12) SIGSYS
  13) SIGPIPE	  14) SIGALRM	  15) SIGTERM	  16) SIGURG
  17) SIGSTOP	  18) SIGTSTP	  19) SIGCONT	  20) SIGCHLD
  21) SIGTTIN	  22) SIGTTOU	  23) SIGIO 	  24) SIGXCPU
  25) SIGXFSZ	  26) SIGVTALRM   27) SIGPROF	  28) SIGWINCH
  29) SIGINFO	  30) SIGUSR1	  31) SIGUSR2
  ```

SIGINT를 받은 프로세스는 그대로 종료되는게 보통입니다. 하지말 셸 스크립트에서는 시그널을 받았을 때 동작을 **trap** 명령어로 제어할 수 있습니다. trap 명령어 서식은 ' ' 안에 하고 싶은 처리, 그 다음에 제어하고 싶은 시그널명을 씁니다. 이 예는 `Ctrl` + `C` 를 눌렀을 때 현재 시각을 표시하고 exit 명령어로 셸 스크립트를 종료합니다.

```
trap ' date; exit ' INT
      하고 싶은 처리   시그널
```

trap 명령어는 SIGINT 같은 종료 시그널을 받았을 때 로그를 출력하거나 현재 상태를 표시하고 종료하는 등 기본 동작을 덮어쓰는 경우에 자주 사용됩니다.

예제에서 `2`{:.info}는 **curl 명령어**로 1초마다 한 번씩 웹 사이트에서 내려받아서 통신이 정상적인지 확인하는 스크립트입니다. 이 프로그램은 무한 반복이므로 `Ctrl` + `C` 를 입력할 때까지 종료하지 않습니다. 그리고 SIGINT를 `1`{:.info}에서 trap하므로 `Ctrl` + `C` 를 입력하면 전부 몇 번 curl을 실행했는지를 변수 count로 출력하고 종료합니다.

&nbsp;
&nbsp;

## **주의사항**

- FreeBSD에서 curl은 기본 인스톨 대상이 아닙니다. 따라서 **fetch 명령어**로 대신합니다.

  ```
  fatch -o /dev/null $1
  ```

- 다음과 같이 실행하는 명령어를 비워두면 `Ctrl` + `C` 를 무시하는 키보드 입력으로 종료할 수 없는 프로세스를 만들 수 있습니다. 이때 다른 터미널에서 kill 명령어로 **TERM** 시그널(kill 명령어가 기본값으로 보내는 시그널)을 보내면 종료할 수 있습니다.

  ```
  trap '' INT
  ```

