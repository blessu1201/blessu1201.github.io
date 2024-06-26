---
layout: article
title: 파일처리_11 파일을 백업할 때 파일명에 날짜 넣기
tags: [Linux, ShellScript, date, cp]
key: 20240121-Linux-file-date
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: date, cp  
> 키워드: 백업, 현재 시각, 날짜  
> 사용처: 어떤 파일을 백업할 때 현재 날짜를 넣어서 간단히 복사해두고 싶을 때
  
---

> 실행 예제  

```
$ ls  # ---------------------------- 파일 확인
datename.sh		myapp.conf

$ ./datename.sh  # ---------------------- 실행
myapp.conf -> myapp.conf.20210318

$ ./datename.sh  # ---------------------- 실행
myapp.conf -> myapp.conf.202103182210.20

$ ls  # ----------------------------- 파일 확인
datename.sh	myaapp.conf	myapp.conf.20131202	myapp.conf.201312022255.20

```

> 스크립트

```bash
#!/bin/sh
 
config="myapp.conf"
 
bak_filename="${config}.$(date '+%y%m%d')"  # ----------------------- 1
 
# 이미 myapp.conf.20131202 파일 등이 있으면 초까지 넣어서 백업 파일 작성
if [ -e $bak_filename ]; then  # ------------------------------------ 2
    bak_filename="${config}.$(date '+%Y%m%d%H%M.%S')"  # ------------ 2
fi  # --------------------------------------------------------------- 2                      

cp -v "$config" "$bak_filename"  # ---------------------------------- 3
```

&nbsp;
&nbsp;

## **해설** 

이 스크립트는 현재 디렉터리에 있는 myapp.conf라는 설정 파일을 백업합니다. 실행하면 현재 날짜를 이용해서 파일명을 조합해 myapp.conf.20131202, 즉 "원래 파일명 + 날짜" 형식으로 복사본을 작성합니다.  

같은 날에 여러 번 스크립트를 실행하면 백업 파일을 덮어쓰지 않도록 시분초까지 포함해서 myapp.conf.201312022255.20 라는 파일명으로 백업을 만듭니다.  

이 스크립트에서는 현재 시각을 취득하기 위해 **date 명령어**를 사용합니다. date 명령어는 인수가 +로 시작할 때는 현재 시각(날짜)을 지정한 형식으로 표시합니다. 시각 표시 형식은 인수에 필드명을 써서 제어할 수 있으므로 년월일이나 시분초를 자유롭게 조합해서 문자열을 만들 수 있습니다.  

date 명령어에서 자주 사용하는 필드명을 표로 정리했습니다. 이런 필드는 라이브러리 함수 strftime으로 정의되어 있으므로 man strftime을 참조하기 바랍니다.  

- date 명령어 필드

    |필드명|설명|
    |:----|:---|
    |%Y|년(1970~)|
    |%y|년도 아래 두 글자(00~99)|
    |%m|월(01~12)|
    |%d|일(01~31)|
    |%H|시(00~23)|
    |%M|분(00~59)|
    |%S|초(00~59)|

`1`{:.info}에서는 **$()**라는 **명령어 치환**을 써서 파일명을 조합합니다. 이때 date 명령어 표시 형식으로 %Y%m%d, 즉 YYYYMMDD(년월일)를 사용합니다. 오늘이 2013년 12월 2일이라면 20131202가 됩니다. 따라서 현재 날짜를 뒤에 붙여서 백업 파일명을 조합할 수 있습니다.

이대로라면 같은 날에 두 번 이상 스크립트를 실행하면 앞서 만든 파일을 덮어쓰게 되므로 `2`{:,info}에서 덮어쓰기 확인 처리를 합니다. 만약 현재 날짜가 끝에 딸린 파일이 이미 존재하면 덮어쓰지 않도록 시분초까지 포함한 파일명으로 복사합니다. 시분초를 지정하려면 필드로 %H%M%S를 사용합니다.  여기서 보기 편하도록 초 앞에 점을 찍습니다. 따라서 2013년 12월 2일 22시 55분 22초에 스크립트를 실행하면 myapp.conf.201312022255.22 이라는 파일명이 조합됩니다.

`3`{:.info}에서 백업을 위해 파일을 복사하는데 **cp 명령어**에 **-v 옵션**(verbose)을 사용해서 어떤 파일을 어떤 파일명으로 복사하는지 표시합니다. 파일을 조작하는 셸 스크립트에서는 화면으로 봐서(또는 로그 파일을 봐서) 확인 가능하도록 이런 -v 옵션을 지정하는 것이 좋습니다.

&nbsp;
&nbsp;

## **주의사항**

- 이 스크립트에서는 초까지 파일명에 사용하므로 1초 이내 두 번 이상 실행되면 파일을 덮어쓰게  됩니다. 파일명 뒤에 1, 2, 3, ... 식으로 연변을 붙이는 방법도 있지만 이 방법은 언제 변경되었는지 한번에 알아보기 어렵고, 게다가 설정 파일 백업용이라서 1초 이내 갱신될 일도 없으므로 이 예제에서는 이미 파일이 존재하면 시분초를 붙이는 방법을 사용합니다.

- 날짜로 백업 파일을 만드는 것은 간단해서 자주 쓰이는 방법이지만 임기응변이기도 합니다. 제대로 하려면 Git이나 서브버전(Subversion) 같은 버전 관리 시스템으로 관리를 하는 것이 옳습니다.

- 서브 버전은 svn 명령어, Git은 git 명령어를 사용합니다. 예를 들어 다음은 서브 버전으로 버전 관리를 하는 파일 이력입니다. 언제 누가 어떤 편집을 했는지 한 눈에 보이고, 과거 버전으로 간단히 되돌릴 수 있습니다. 이런 버전 관리 프로그램은 각 전문서를 참조하기 바랍니다.

    ```
    $ svn log myapp.conf
    -----------------------------------------------------------------
    r194 | kim | 2014-01-19 18:49:21 +0900 (Sun, 19 Jan 2014) | 2 lines

    server1에서 고장 발생, 접속 IP 주소를 sserver3으로 변경
    -----------------------------------------------------------------
    r182 | Mola | 2014-01-07 10:17:14 +0900 (Tue, 07 Jan 2014) | 2 lines

    로그 출력 디렉터리를 /var/log/myapp에서 /var/log/newapp로 변경
    -----------------------------------------------------------------
    ```