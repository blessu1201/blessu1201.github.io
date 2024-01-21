---
layout: article
title: 파일처리_10 로그 파일이 엄청 많은 디렉터리에서 파일들에 명령어를 일괄 실행하기
tags: [Linux, ShellScript, find, xargs, grep]
key: 20240120-Linux-find-xargs-grep
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: find, xargs, grep  
> 키워드: 인수, 명령행 인수, 대량 파일  
> 사용처: 파일이 너무 많아 단순히 *로 파일을 지정하면 에러가 발생하는 상황에서 grep 명령어 등을 실행하고 싶을 때
  
---

> 실행 예제  

```
$ ./xargs-grep.sh
/var/log/myapp/49294.log:2012-12-24 00:04:59 [ERROR] File Not Found.
/var/log/myapp/23100.log:2013-06-10 03:54:21 [ERROR] I/O Error.
/var/log/myapp/14322.log:2013-10-12 13:21:03 [ERROR] File Not Found.
/var/log/myapp/21322.log:2013-10-12 13:21:04 [ERROR] File Not Found.
```

> 스크립트

```bash
#!/bin/sh
 
logdir="/var/log/myapp"
 
# 확장자 .log 파일에서 "ERROR" 문자열 검색
find $logdir -name "*.log" -print | xargs grep "ERROR" /dev/null  # --- 1
```

&nbsp;
&nbsp;

## **해설** 

이 스크립트는 수 많은 파일이 존재하는 디렉터리 /var/log/myapp에 대해 "ERROR" 라는 문자열을 포함한 파일을 grep 명령어로 검색합니다. 여기서 디렉터리 /var/log/myapp에는 단순히 grep 명령어를 실행하면 에러가 발생할 만큼 많은 로그 파일이 존재한다고 가정합니다.

- 파일이 너무 많으면 에러 발생

```
$ grep 'ERROR' *.log
-bash: /bin/grep: Argument list too long
```

여기서 "Argument list too long"(OS에 따라 메시지는 다소 다릅니다)이라는 에러가 발생한 원인은 *(애스터리스크)가 셸에 따라 확장될 때 무척 긴 문자열이 되므로 명령행 인수가 시스템이 다룰 수 있는 한계를 넘었기 때문입니다.
 
유닉스에서는 명령행 인수 상한값이 **ARG_MAX** 상수로 정해져 있습니다. 따라서 많은 파일이 있을 때 *로 파일 목록을 넘기면 ARG_MAX 이상의 문자열 길이가 되어서 에러가 발생합니다. ARG_MAX 값은 리눅스라면 **getconf** 명령어로 확인할 수 있습니다.

- 명령행 인수의 상한값 확인

```
$ getconf ARG_MAX
2621440
```

man execve 로 execve(2)설명서를 읽어보기 바랍니다. execve는 프로그램을 실행하는 시스템 콜로 리눅스라면 ARG_MAX값이 <limit.h> 에 정의되어 있다는 등의 설명이 적혀있습니다.
참조: <https://man7.org/linux/man-pages/man2/execve.2.html>

이 제한을 회피하려면 예제처럼 **find 명령어**로 우선 파일 목록을 출력해서 그것을 **xargs 명령어**로 받아서 **grep**을 실행합니다.

xargs 명령어는 ARG_MAX 값을 넘지 않도록 인수를 적당히 나눠서 지정한 명령어를 실행합니다. 따라서 명령행 인수가 얼마나 길든지 상관없이 ARG_MAX 제한에 걸리지 않도록 제대로 처리할 수 있습니다.
 
한편, 이 스크립트에서는 특별한 처리를 위해 대상 파일에 /dev/null을 추가합니다. 이것은 grep 명령어 출력에 반드시 파일명을 포함하기 위한 처리입니다. grep 명령어에서는 여러 파일을 대상으로 할 때 다음처럼 앞부분에 파일명을 출력해 일치한 줄을 출력합니다.

```
$ grep "ERROR" *
<파일명>:<일치한 줄>
<파일명>:<일치한 줄>
<파일명>:<일치한 줄>
...
```

예제에서는 /var/log/myapp에 수많은 파일이 있다고 가정합니다. 하지만 만약 대상 파일이 하나뿐이라면 grep 명령어는 결과에 파일명을 출력하지 않습니다.

- *라고 지정했지만 실제로는 파일이 하나뿐이면

```
$ grep "ERROR" *
<일치한 줄>
```

이러면 대상 파일 수에 따라 결과 출력이 달라지므로 처리를 할 때 불편합니다. 따라서 이 예제에서는 대상 파일에 정해진 /dev/null도 추가해서 grep 명령어가 늘 복수 개의 파일을 대상으로 실행되도록 해서 결과에 파일명이 표시되도록 합니다.

/dev/null은 어떤 문자열도 포함되어 있지 않으므로 grep되지 않고 검색 결과에는 영향이 없습니다.

&nbsp;
&nbsp;

## **주의사항**

이 예제에서는 파일에 공백문자(스페이스)가 포함되면 에러가 발생합니다. 공백문자를 다루려면 find 명령어에서 -print0 옵션을 이용해야 합니다.
