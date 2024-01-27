---
layout: article
title: 파일처리_16 tar 아카이브할 때 일부 파일이나 디렉터리 제외하기
tags: [Linux, Shellscript, tar]
key: 20240126-linux-tar
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: tar  
> 키워드: tar 아카이브, 제외, 예외   
> 사용처: tar 명령어로 아카이브 파일을 만들면서 Subversion의 [.svn] 디렉터리 등 특정 파일이나 디렉터리를 제외하고 싶을 때 

--- 

> 실행예제

```
$ ls -aF myapp
./	../	.svn/	bin/	etc/	log/

$ ./tar-exclude.sh
myapp/
myapp/etc/
myapp/etc/app.conf
myapp/etc/disk.conf
myapp/log/
myapp/bin/
myapp/bin/start
myapp/bin/stop
```

> 스크립트

```bash
#!/bin/sh
 
tar cvf archive.tar --exclude ".svn" myapp
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 tar 명령어로 현재 디렉터리 아래에 있는 myapp 디렉터리를 아카이브하면서 [.svn] 이라는 서브디렉터리를 제외합니다. 이런 처리는 백업 용도 등에 자주 사용되어서 정기적으로 실행됩니다. 따라서 명령어 한 줄로 끝난다고 하더라도 입력 실수 등을 방지하기 위해 매번 수동으로 실행하는 수고를 덜고자 이런 스크립트는 사용하는 것이 좋습니다.
 
여기서 myapp 디렉터리에는 다음처럼 4개의 디렉터리가 있다고 가정합니다.
그냥 tar 명령어를 실행하면 myapp 디렉터리에 있는 전 서브디렉터리가 대상이 되지만 여기서는 [.svn] 디렉터리를 아카이브 대상에서 제외합니다. 따라서 실행 예제의 tar 명령어 출력에 [.svn] 디렉터리가 들어 있지 않다는데 주의하기 바랍니다.

- 실행 예제의 디렉터리 구성

```
myapp/
├── .svn
├── bin
├── etc
└── log
```
 
이런 경우에는 **tar 명령어**의 **--exclude 옵션**을 이용해서 지정한 디렉터리를 제외하고 아카이브할 수 있습니다. --exclude 옵션은 다음처럼 --exclude 뒤에 파일명(디렉터리명)을 지정합니다.

```
tar cvf archive.tar --exclude ".svn" myapp
```
 
exclude를 지정하면 해당하는 이름의 파일과 디렉터리 전부를 제외 대상으로 삼습니다. 예를 들어 myapp/log/디렉터리를 아카이브하고 myapp/backup/log/ 디렉터리를 제외하고 싶을 때 단순히 log를 지정하면 둘 다 제외됩니다. 이럴 때는 디렉터리 경로를 exclude 지정하면 제외 대상을 설정할 수 있습니다.

```
tar cvf archive.tar --exclude "myapp/backup/log" myapp
```

&nbsp;
&nbsp;

## **주의사항**

아카이브 제외하고 싶은 파일이 많다면 -X 옵션으로 외부 파일로 제외 목록을 적용할 수 있습니다. 예를 들어 제외하고 싶은 디렉터리를 적은 텍스트 파일이 exclude.lst 라면 다음처럼 작성합니다.

```
tar cvf archive.tar -X exclude.lst myapp
```