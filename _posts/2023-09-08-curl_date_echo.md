---
layout: article
title: 서버관리_12 / 웹 접근 감시하기
tags: [Linux, curl, date, echo, ShellScript]
key: 20230908-linux_server_manage_12
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

## 웹 접근 감시하기

> 명령어: curl, date, echo  
> 키워드: 웹 감시, 서비스 감시, HTTP 스테이터스 코드   
> 사용처: 운용하는 웹 서비스에서 접근 확인을 정기적으로 실행해서 이상 발생 시 경고 통지를 하고 싶을 때  

> 실행 예제  

```bash
$ ./web-curlcheck.sh
[2023/09/07 12:05:01] HTTP 스테이터스 이상:HTTP status[503]
ALERT...
```

> 스크립트

```bash
#!/bin/sh

# 감시 대상 URL 지정
url="http://www.example.org/webapps/check" # -------------------------------- 1

# 현재 시각을 [2013/02/01 13:15:44] 형식으로 조합
date_str=$(date '+%Y/%m/%d %H:%M:%S') # ------------------------------------- 2

# 감시 URL에 curl 명령어로 접속해서 종료 스테이터스를 변수 curlresult에 대입
httpstatus=$(curl -s "$url" -o /dev/null -w "%{http_code}") # --------------- 3
curlresult=$?

# curl 명령어에 실패하면 HTTP 접속 자체에 문제가 있다고 판단
if [ "$curlresult" -ne 0 ]; then # ------------------------------------------ 4
  echo "[$date_str] HTTP 접속이상: curl exit status[$curlresult]"
  /home/user1/bin/alert.sh

# 400번대, 500번대 HTTP 스테이터스 코드라면 에러로 보고 경고
elif [ "$httpstatus" -ge 400 ]; then # -------------------------------------- 5
  echo "[$date_str] HTTP 스테이터스 이상: HTTP status[$httpstatus]"
  /home/user1/bin/alert.sh
fi

```

### **해설**

이 스크립트는 웹 서버 접근을 감시해서 이상 발생 시 경고합니다. 이때 이상 발생 시 alert.sh 스크립트를 실행해서 이걸로 알림을 보낸다고 가정합니다.

예제에서는 **curl 명령어**로 **HTTP 스테이터스** 코드를 확인합니다. 따라서 단순히 웹 서버가 움직이고 있는지 확인하는 것이 아니라 그 위에 동작하는 애플리케이션 상태까지 감시하는 것이 핵심입니다.

웹 서비스를 제공하려면 wget 명령어 등으로 HTTP 접속이 되는지만 확인하는 걸로는 부족합니다. 다음처럼 백엔드 데이터베이스에 장애가 발생했을 경우를 살펴봅니다.

 - 백엔드 서버에서 발생한 장애도 포함해서 확인하고 싶음
 
<img src='http://drive.google.com/uc?export=view&id=1E9iI8CniZRsHicixDE3Dy8rxg4t7jPsZ' /><br>

만약 포트 감시만 하면 웹 서버는 정상적으로 TCP 포트 80번으로 접속할 수 있어 데이터베이스 장애 발생을 놓치게 됩니다. HTTP 스테이터스 코드까지 감시하면 웹 서버는 HTTP 스테이터스 코드 500(Internal Server Error) 등을 돌려주므로 애플리케이션이 제대로 동작하지 않는다는 걸 알 수 있습니다.

따라서 웹 애플리케이션 감시는 HTTP 스테이터스 코드까지 확인해야 합니다.

우선 [1](#){:.button.button--primary.button--rounded.button--xs}은 감시 대상 URL을 셸 변수 url에 정의합니다. 여기서 대상 URL은 앞에서 본 백엔드 서버까지 접속하는 애플리케이션 경로를 지정하는 것이 좋습니다.

[2](#){:.button.button--primary.button--rounded.button--xs}는 **date 명령어**를 사용해서 현재 시각을 2023/09/07 15:11:18 형식으로 조합해서 경고 표시 시각으로 사용합니다.

[3](#){:.button.button--primary.button--rounded.button--xs}은 curl 명령어로 HTTP 스테이터스 코드를 취득해서 셸 변수 httpstatus에 대입합니다. curl 명령어는 다양한 옵션이 있지만 여기에서는 다음 세 종류의 옵션을 이용합니다.

- 스크립트에서 사용하는 curl 명령어 옵션

|명령어|설명|
|:----|:---|
|-s|slient 모드(침묵 모드). 처리 중 내용을 표시하지 않음|
|-o|취득한 파일 저장 경로 지정|
|-w|명령어 완료 후 출력할 표시 형식 지정|

[3](#){:.button.button--primary.button--rounded.button--xs}은 curl 명령어 자체의 종료 스테이터스 $?도 셸 변수 curlresult에 대입합니다. 이것은 어떤 네트워크 장애나 URL 지정 실수로 curl 명령어가 실패했을 때 확인하기 위함입니다. curl 명령어 종료 스테이터스는 [4](#){:.button.button--primary.button--rounded.button--xs}의 if문에서 확인해서 curl 명령어에 실패했으면 HTTP 접속 에러라고 에러 메시지를 표시하고 alert.sh를 실행합니다.

[5](#){:.button.button--primary.button--rounded.button--xs}는 HTTP 스테이터스 코드로 정상인지 비정상인지 판별합니다. 일반적으로 HTTP 스테이터스 코드는 400번대 및 500번대가 비정상 코드입니다.

- 확인해야 할 비정상 HTTP 스테이터스 코드

|코드|일반적표시|설명|
|:---|:--------|:---|
|400|Bad Request|리퀘스트 문제 발생. 존재하지 않늠 메소드 등|
|403|Forbidden|접근 거부. 서버 설정에 따른 접속 거부 등|
|404|Not Found|파일이 존재하지 않을 때|
|500|Internal Server Error|서버 내부 에러. CGI 에러 등|
|502|Bad Gateway|프록시 서버 등 상위 서버에서 잘못된 응답이 왔을 때|
|503|Service Unavailable|서버가 바쁘거나 처리를 받을 수 없을 때|

예를 들어 503(Service Unavailable)은 서버가 고부하 상태일 때 자주 보게 도비니다. 500(Internal Server Error)은 프로그램에 어떤 버그가 있어서 정상적으로 응답할 수 없을 때도 발생합니다.

이런 400번대나 500번대 HTTP 스테이터스 코드가 돌아오면 문제가 발생했다고 봐야하므로 [5](#){:.button.button--primary.button--rounded.button--xs}에서 **test 명령어 -ge 연산자**로 HTTP 스테이터스 코드가 400 이상인지로 판별합니다. 400 이상이면 문제가 있다고 보고 메시지를 출력하고 경고하는 alert.sh를 실행합니다. 이렇듯 HTTP 스테이터스 코드로 비정상인지 판단하는 방법으로 코드값이 400 또는 500 이상인지 확인하는 방법이 일반적입니다.

이렇게 하면 웹 서비스 감시가 가능합니다. cron에 등록해서 정기적으로 실행하게 하는 등 상황에 맞춰 사용하기 바랍니다.

### **주의사항**

- FreeBSD는 curl 명령어가 기본 설치되지 않습니다. FreeBSD 표준 fetch 명령어로는 HTTP 스테이터스 코드를 취득할 수 없으므로 ports로 curl 명령어를 설치하기 발랍니다.

```
# cd /usr/ports/ftp/curl
# make install
```

- 웹 서버를 운용하다보면 웹 크롤러나 어떤 악의를 가진 공격자가 이곳 저곳으로 접속해오는 것이 보통입니다. 따라서 접속 로그 파일에서 다수의 404(Not Found)가 발견될 것입니다. 그다지 신경 쓰지 않아도 되지만 공격의 징조를 발견하거나 페이지 링크가 끊긴 걸 확인할 수도 있으므로 접속 로그 파일도 정기적으로 확인하는 것이 좋습니다.