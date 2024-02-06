---
layout: article
title: 파일처리_23 디렉터리에 있는 서브 디렉터리들의 디스크 사용량 조사하기
tags: [Linux, ShellScript, du, sort]
key: 20240203-linux-umask
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: umask  
> 키워드: 보안, 권한, umask   
> 사용처: 디스크립트에서 권한을 지정해서 파일을 작성하고 싶을 때

--- 

> 실행예제

```
$ ./umask.sh
$ ls -l
total 8
-rw------- 1 user1 48 Dec 11 23:24 idinfo.tmp
-rwxr-xr-x 1 user1 39 Dec 11 23:17 umask.sh
```

> 스크립트

```bash
#!/bin/sh

umask 077 # ------------------------------------ 1

#echo  명령어 출력을 권한 600인 임시 파일로 생성
echo "ID: abcd123456" > idinfo.tmp  # ---------- 2
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 umask 명령어로 임시 파일 권한을 설정합니다. 이러면 다른 사람이 파일 내용을 보는 걸 막아서 보안을 고려한 파일을 작성할 수 있습니다.

예제에서는 "ID: abcd123456" 이라는 문자열을 임시 파일에 출력합니다.

스크립트 실행 중에 임시 파일을 자주 만들지만 ID 정보처럼 다른 사람이 보면 안 되는 정보를 기록하는 경우도 있습니다. 그럴 때는 **umask 명령어**로 마스크 값을 설정해서 파일을 만들면 임시 파일 권한을 적절하게 설정할 수 있습니다.

umask 사용 방법은 아래와 같습니다.

umask <마스크 값>
{:.info}

마스크 값(umask 값)은 세 자리 8진수로 지정합니다. umask 명령어 실행 후 만들어질 파일 권한은 umask로 지정한 비트가 0이 되도록 작성됩니다. 또한 파일 권한 값은 셸 스크립트에서 만들어지면 666(디렉터리는 777)을 umask 값으로 마스크한 값이 됩니다.

즉, 666과 umask값 각각을 2진수로 표기해서 umask 값이 1인 곳을 0으로 바꾼 값이 스크립트에서 작성한 파일 권한이 됩니다. 

예를 들어 umask 022로 지정했을 때 만들어지는 파일 권한은 644입니다.

```
666 --2진수 표시 -> 1 1 0 1 1 0 1 1 0
022 --2진수 표시 -> 0 0 0 0 1 0 0 1 0
    마스크 결과     1 1 0 1 0 0 1 0 0   -> 8진수(644)
```

이 스크립트는 스크립트 앞 부분 `1`{:.info}에서 umask 077을 설정합니다. 따라서 스크립트에서 만들어진 파일 권한은 600(파일 소유자만 읽고쓰기 가능)이 됩니다. `2`{:.info}에서 echo 명령어 출력을 파일에 리다이렉트하는데 이 임시 파일 권한도 600 이므로 다른 사람은 읽을 수 없습니다. 이렇게 하면 셸 스크립트 안에서 안전한 임시 파일을 작성할 수 있습니다.