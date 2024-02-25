---
layout: article
title: 텍스트처리_14 오른쪽 정렬로 숫자를 표시하는 텍스트 표 만들기
tags: [Linux, ShellScript, grep, printf]
key: 20240225-linux-grep-printf
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: grep, printf  
> 키워드: 서식 출력, 텍스트 변형, 포맷  
> 사용처: 숫자를 카운트하는 명령어에서 세로 위치를 정리해서 리포트하고 싶을 때

--- 

> 실행예제

```
$ ./printf.sh
    1 (app20210409.log)
   73 (app20210410.log)
  146 (app20210412.log)
   11 (info.log)
    5 (system.log)
```

> 스크립트

```bash
#!/bin/sh

# 검색할 문자열 정의
search_text="ERROR 19:"

# 현재 디렉터리에서 확장자가 .log인 파일을 순서대로 처리
for filename in *.log  #----------------------------- 1
do
  # 일치하는 줄 수를 -c 옵션으로 취득
  count=$(grep -c "$search_text" "$filename")  #----- 2

  # printf 명령어로 오른쪽 정렬 6칸으로 변형해서 출력
  printf "%6s(%s)\n" "$count" "$filename"  #--------- 3
done
```

&nbsp;
&nbsp;
                                                
## **해설**

이 스크립트는 현재 디렉터리의 로그 파일(확장자 .log)에서 셸 변수 search_text로 정의한 문자열(여기에서는 "ERROR 19:")을 검색해서 일치한 줄 수를 파일마다 표시합니다. 예를 들어 어떤 애플리케이션 로그 파일 무리에서 로그 파일마다 에러가 발생한 줄을 세고 싶을 때 사용하면 되겠지요.

이 예제에서는 일치한 줄 수를 출력할 때 **printf 명령어**로 포맷에 맞춘 리포트를 만드는 것이 포인트입니다. 파일에서 패턴과 일치한 줄 수를 세서 표시하는 방법으로는 **grep 명령어**에 **-c 옵션**을 사용하는 방법이 있습니다.

- grep 명령어 -c 옵션으로 일치한 줄 수를 표시
```
$ grep -c "ERROR 19:" *.log
app20210409.log:1
app20210410.log:73
app20210412.log:146
info.log:11
system.log;5
```

하지만 이런 형태로는 깔끔하지 않으므로 리포트용으로 손보는 것이 좋습니다.

우선 `1`{:.info}에서는 for문 in에 *.log를 지정해서 현재 디렉터리에 있는 확장자 .log 파일은 순서대로 셸 변수 filename으로 처리합니다.

`2`{:.info}는 일치한 줄 수만 표시하는 grep 명령어에 -c 옵션을 써서 검색 문자 출현 줄 수를 셉니다. 이 결과는 명령어 치환 $()을 사용해서 셸 변수 count에 대입합니다.

`3`{:.info}은 결과를 정리해서 표시하는 처리입니다. 여기서 서식을 써서 문자열을 출력하는 printf 명령어를 사용합니다. printf는 펄이나 C 언어에서 자주 사용하는 함수인데 셸에서도 직접 사용 가능하도록 명령어화한 것이 printf 명령어입니다.

printf 명령어는 **서식 지정자**라고 부르는 문자열을 지정해서 다양한 포맷을 지정할 수 있고 그 뒤에 지정한 인수(`3`{:.info}의 $count, $filename)를 대입할 수도 있습니다. 여기서 $count에는 일치한 줄 수가 $filename에는 파일명이 들어 있습니다.

print 명령어에서 자주 사용하는 서식 지정은 다음과 같습니다.

- printf에서 자주 쓰는 서식 지정

|서식 지정 예|의미|출력 예|
|:----------|:---|:-----|
|"[%s]"|문자열을 그대로 출력|[ABC]|
|"[%5s]"|오른쪽 정렬로 5칸짜리 문자열|[  ABC]|
|"[%-5s]"|왼쪽 정렬로 5칸짜리 문자열|[ABC  ]|
|"[%-.2s]"|왼쪽 정렬로 왼쪽에서두글자만|[AB]|
|"[%5d]"|오른쪽 정렬로 5칸짜리 정수|[  123]|
|"[%05d]"|오른쪽 정렬로 5칸짜리 정수(빈자리는 0을 채움)|[00123]|
|"[%-5d]"|왼쪽 정렬로 5칸짜리 정수|[123  ]|

서식에서 지정하는 **%s**는 문자열을, **%d**는 정수를 의미합니다. %5s처럼 숫자가 있으면 그 칸만큼 출력할 공간을 확보합니다. 이때 오른쪽 정렬이 되는데 %-라고 지정하면 왼쪽 정렬로 표시합니다. printf는 그 외에도 많은 서식 지정자가 있습니다.

"man 1 printf"를 실행해서 자세한 내용을 살펴보기 바랍니다.

`3`{:.info}은 서식 지정자로 "%06s (%s)\n"을 지정합니다. 따라서 첫 번째 인수(일치한 줄 수)를 6칸 오른쪽 정렬로, 두 번째 인수(파일명)를 괄호로 둘러싸서 표시합니다. 그리고 printf 명령어는 줄바꿈을 출력하지 않으므로 줄을 바꾸고 싶으면 \n이 필요합니다.

이렇게 리포트를 구며서 표시하고 싶다면 printf 명령어가 편리합니다. 상황에 맞춰 서식 지정자를 잘 설정해보기 바랍니다.

&nbsp;
&nbsp;

## **주의사항**

- man으로 매뉴얼을 표시할 때 printf는 함수명과 명령어로서의 두 가지 의미가 있어서 각각 매뉴얼이 존재합니다. 함수 printf 매뉴얼은 man 3 printf이고 명령어 printf 매뉴얼은 man 1 printf입니다.

- C언어의 sprintf 함수처럼 포맷 문자열을 표시하지 않고 변수에 직접 대입하고 싶을 때가 있습니다. 그럴 때는 다음처럼 단순히 printf 명령어 출력을 명령어 치환을 써서 변수에 대입하면 됩니다.
```
format_string=$(printf "%6s (%s)\n" "$count" "$filename")
```