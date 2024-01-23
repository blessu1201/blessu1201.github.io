---
layout: article
title: 파일처리_13 로컬 디렉터리에 파일을 만들지 않고 직접 원격 호스트에 아카이브하기
tags: [Linux, Shellscript, tar, ssh, cat]
key: 20240123-linux-tar
---


> 명령어: tar, ssh, cat  
> 키워드: tar 아카이브, 원격 호스트, 중간 파일   
> 사용처: tar 아카이브를 작성해서 원격 호스트에 복사하면서 중간 파일을 만들지 않고 직접 복사하고 싶을 때

--- 

> 실행예제

```
$ ./tar-ssh.sh
myapp/log
myapp/log/20131201.log
myapp/log/20131202.log
```

> 스크립트

```bash
#!/bin/sh

username="user1"
server="192.168.1.5"

tar cvf - myapp/log | ssh ${username}@${server} "cat > /backup/myapplog.tar" # --- 1
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 로그 파일이 저장된 myapp/log 디렉터리를 아카이브한 tar 파일을 192.168.1.5라는 다른 서버의 /bakcup 디렉터리에 복사합니다. 이때 작업하는 로컬 서버에서 중간 파일을 만들지 않고 직접 원격 호스트에 tar 파일을 작성하는 것이 포인트입니다. 이런 처리는 매일 또는 매주 정기적으로 실행하는 경우가 많습니다. 

이때 백업을 저장하는 서버 IP 주소나 파일 저장 경로 등 많은 인수가 있어서 이걸 매번 직접 입력하는 것은 문제가 있습니다. 그러므로 셸 스크립트를 만들어두면 필요할 때마다 실행할 수 있어 편리하며 인수 지정에서 실수할 일도 없어집니다.

- 원격 호스트에 직접  tar 파일 작성  
<img src='http://drive.google.com/thumbnail?id=15__h81KsVxffHFHGMiuCKO-tKq8xVUtv&sz=w1000' /><br>

`1`{:.info}에서 **tar 명령어**로 아카이브를 만들 때 표준 출력에 tar 아카이브를 출력하는 **-(하이픈) 옵션**을 사용합니다. `1`{:.info}에서 ssh 접속하는 코드를 삭제하면 다음과 같습니다.

```
tar cvf - myapplog | cat > /backup/myapplog.tar
```

여기서 tar 명령어 옵션으로 **c**(아카이브 작성), **v**(처리 파일 표시), **f**(아카이브 파일 사용)를 쓰며 그 앞에 -(하이픈)을 지정해서 표준 출력에 표시합니다. 이대로는 tar 파일 내용 자체가 화면에 표시되어서 읽을 수 없으므로 이걸 파이프로 받아서 **cat 명령어**로 리다이렉트하여 tar 파일로 출력하면 /backup/myalpplog.tar 이라는 tar 아카이브를 작성하게 됩니다.

즉, 우선 tar 아카이브를 표준 출력으로 표시하고 이걸 파이프로 받습니다. 셸 변수 backup_server로 지정한 원격 호스트에서 이 파이프 내용을 cat 하면 원격 호스트에서 이런 파일을 직접 tar 파일로 아카이브하게 됩니다

&nbsp;
&nbsp;

## **주의사항**

- 이 예제와는 반대로 현재 호스트에서 원격 호스트에 맞는 tar 파일의 아카이브를 직접 해제하려면 다음처럼 tar 명령어로 -(하이픈)을 서서 표준 입력에서 해제하면 됩니다.

```
ssh ${username}@${server} "cat /backup/myapplog.tar" | tar xvf -
```

- tar 아카이브는 파일을 하나로 묶을 뿐 압축 처리는 하지 않습니다. gzip 압축도 같이 하고 싶다면 tar 명령어에 z 옵션(gzip)을 추가합니다.