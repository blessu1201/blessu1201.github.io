---
layout: article
title: 파일처리_14 중요한 파일을 암호 걸어서 zip으로 아카이브하기
tags: [Linux, ShellScript, tar, ssh, cat]
key: 20240124-linux-zip
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: zip  
> 키워드: 암호, 암호화, zip 파일   
> 사용처: 중요한 정보를 담은 로그 파일 등을 암호가 있는 zip으로 아카이브 할 때

--- 

> 실행예제

```
$ ./passzip.sh
Enter password:      <--------------------------- 암호를 입력함
Verity password:     <--------------------------- 암호를 입력함
  adding: log/ (stored 0%)
  adding: log/access.log-20210322 (deflated 43%)
  adding: log/error.log (deflated 21%)
  adding: log/error.log-20210322 (deflated 66%)
  adding: log/error.log-20210323 (deflated 19%)
  adding: log/access.log-2021-0324 (feflated 60%)
  adding: log/access.log (deflated 39%)
```

> 스크립트

```bash
#!/bin/sh
 
logdir="/home/user1/myapp"
 
cd "$logdir"
 
# /home/user1/myapp/log 디렉터리에 있는 로그 파일을 암호 걸린 zip으로 아카이브
zip -e -r log.zip log
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 /home/user1/myapp/log 라는 디렉터리에 저장된 로그 파일을 zip 파일로 아카이브 합니다. 이 로그 파일에 중요한 정보가 포함되어 있다고 가정해서 암호가 걸린 zip 파일로 저장합니다. 이 예제에서는 이용하는 **zip 명령어** 사용법은 다음과 같습니다.

```
zip [옵션] <zip 파일> <대상 파일>
```

**-r 옵션**은 디렉터리를 재귀적으로 처리합니다. 즉, 지정한 경로에 서브디렉터리가 있으면 그 내부도 대상에 포함됩니다. 대부분의 경우 이 옵션이 필요합니다. 또한, 하나의 파일을 아카이브할 때 -r 옵션을 지정해도 별 문제가 없으므로 -r 옵션은 늘 지정해서 사용하는 일이 많습니다. 암호 걸린 zip 파일을 만들려면 **-e(Encrypt) 옵션**을 이용합니다. 예제에서는 -e -r로 따로 지정하고 있지만 -er처럼 붙여서 사용해도 됩니다.

```
zip -er log.zip myapp
```

-e 옵션이 있는 zip 파일을 작성하면 "Enter password: "라고 암호를 물어보며 키보드로 암호를 입력합니다. 다시 "Verify password: "라고 확인하므로 다시 같은 암호를 입력합니다. 이걸로 암호 걸린 zip 파일을 작성할 수 있습니다.
 
유닉스에서 자주 사용하는 tar + gz 형식은 아카이브 파일에 암호를 설정할 수 없습니다. 그러나 zip 파일은 암호 설정이 가능하며 윈도우 등에서 많이 사용되므로 PC와 파일을 주고 받을 때 자주 사용합니다. 이 예제에서 만든 암호 걸린  zip 파일은 윈도우에서도 문제없이 열 수 있습니다.

&nbsp;
&nbsp;

## **주의사항**

- FreeBSD에서 암호 걸린 zip 파일을 열면 퍼미션에 따라서 zip 패키지에 있는 /usr/bin/unzip 명령어로 에러가 발생해서 열 수 없습니다. Ports의 archivers/unzip 으로 설치 가능한 /usr/local/bin/unzip 명령어를 이용하기 바랍니다.
