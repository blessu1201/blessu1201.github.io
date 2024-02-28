---
layout: article
title: 날짜처리_03 한 달 전에 만든 로그 파일을 일괄 아카이브 하기
tags: [Linux, ShellScript, date, tar]
key: 20240210-linux-date-tar
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: date, tar  
> 키워드: 전월, 월말   
> 사용처: 오늘 날짜에서 지난달 년월표기(YYYYMM)를 조합해서 해당 날짜가 파일명에 있는 로그 파일을 아카이브하고 싶을 때

--- 

> 실행예제

```
$ ./lastmonth.sh
/var/log/myapp/access.log-20130201
/var/log/myapp/access.log-20130218
/var/log/myapp/access.log-20130222
/var/log/myapp/access.log-20130228
```

> 스크립트

```bash
#!/bin/sh

logdir="/var/log/myapp"

# 이번달 15일 날짜 취득
thismonth=$(date '+%Y/%m/15 00:00:00')  #----------------------------- 1

# 지난달 날자를 YYYYMM으로 취득
# 1 month ago는 지난달의 같은 '날(일)'이 되므로 말일을 피하도록
# 변수 thismonth에 15일을 지정함
last_YYYYMM=$(date -d "$thismonth -1 month ago" '+%Y%m')  #----------- 2

# 지난달 로그 파일을 아카이브
tar cvf ${last_YYYYMM}.tar ${logdir}/access.log-${last_YYYYMM}*  #---- 3
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 오늘 날짜를 기준으로 해서 지난달 년월표기(YYYYMM)를 조합해서 로그 파일에서 지난달 분량을 아카이브합니다. 오늘이 2021년 3월 29일이라고 하고, /var/log/myapp 디렉터리에는 파일명에 날짜가 포함된 "access.log-년월일" 파일이 존재한다고 가정합니다.

- 로그 파일 확인

    ```
    /var/log/myapp/access.log-20210224
    /var/log/myapp/access.log-20210225
    /var/log/myapp/access.log-20210226
    /var/log/myapp/access.log-20210227
    /var/log/myapp/access.log-20210228
    (생략)
    ```

    지난달 날짜 표기를 얻고 싶다면 리눅스에서는 **date 명령어 -d 옵션**으로 한 달 전을 뜻하는 "1 month ago"를 지정하면 편리합니다. 하지만 이 옵션을 사용할 때는 주의해야 할 사항이 있습니다.

- date 명령어 "1 month ago" 실패 예

    ```
    $ date "+%Y/%m/%d %H:%M:%S"
    2013/03/30 00:00:05  #---------- 오늘 날짜

    $ date "+%Y/%m/%d %H:%M:%S" -d "1 month ago"
    2013/03/02 00:00:06  #---------- 2월 28일이 아님
    ```

    이 결과처럼 3월 30일에는 date -d "1 month ago"를 실행해도 2월 말인 2월 28일이 되지 않습니다. 이것은 리눅스 date 명령어로 "1 month ago"를 지정하면 "지난달의 같은 날"을 취득하기 때문입니다.

- 결과가 3월 2일이 되는 구조

    <img src='http://drive.google.com/thumbnail?id=1lw8XSVWw-YmTwkqD5LMaSbh_J0eGrQb-&sz=w1000' /><br>

이 예제에서는 오늘이 3월 30일이므로 "2월 30일"을 취득하려고 하지만 그런 날은 존재하지 않으므로 2월 28일에서 계산하면 2일 뒤 즉, 3월 2일이 됩니다.

이런 상황이 발생하지 않도록 모든 달에 존재하는 날짜를 지정해서 "1 month ago"를 사용합니다. 즉 1일~28일 중 하루를 지정합니다. `1`{:.info} 에서는 중간 쯤인 15일을 선택했습니다.

이런 월말 처리는 리눅스 date 명령어의 특징입니다. FreeBSD나 Mac의 date 명령어에서는 다르게 동작하므로 주의사항을 참조하기 바랍니다.

`2`{:.info}에서 앞서 15일로 지정한 이번달 날짜에서 지난달을 얻기 위해 date 명령어로 "1 month ago" 날자를 얻습니다. '+%Y%m'을 지정해서 지난달 년월표기(YYYYMM)를 얻습니다.
 
`3`{:.info}에서 지난달 날짜로 로그 파일을 아카이브합니다. 오늘이 3월 30일이면 2013년 2월 로그 파일을 아카이브 합니다.

```
tar cvf 201302.tar /var/log/myapp/access.log-201302*
```

&nbsp;
&nbsp;

## **주의사항**

- FreeBSD나 Mac에서 지난달을 취득하려면 스크립트 `2`{:.info}에서 -d '1 month ago' 대신에 -v 옵션을 사용합니다.

    ```
    last_YYYYMM=$(date -v-1m "+%Y/%m")
    ```

    -v-1m은 '-v 옵션에 -1m 지정'을 의미합니다.

- FreeBSD나 Mac에서 -v-1m으로 지정한 "1개월 전"은 리눅스 "1 month ago"와는 달리 지난달 말일이 됩니다. 따라서 15일로 날짜를 바꿀 필요가 없습니다.

