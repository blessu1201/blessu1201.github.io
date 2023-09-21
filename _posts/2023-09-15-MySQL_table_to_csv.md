---
layout: article
title: 서버관리_19 MySQL 테이블을 CSV로 출력하기
tags: [Linux, mysql, date, tr, ShellScript]
key: 20230915-linux_server_manage_19
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어  

> 명령어: mysql, date, tr  
> 키워드: MySQL, 레플리케이션, 감시  
> 사용처: 정기적으로 데이터베이스에서 SELECT한 결과를 CSV 파일로 출력하고 싶을 때     

> 실행 예제  

```
$ ./mysql-csvout.sh
csv_outputdir로 지정한 디렉터리에 CSV 파일로 출력

```

> 스크립트

```bash
#!/bin/sh

# 데이터베이스 접속 설정
DBHOST="192.168.11.5" #------------------------------------------ 1
DBUSER="user1"
DBPASS="PASSWORD"
DBNAME="hamilton"

# mysql 명령어 경로
MYSQL="/usr/bin/mysql" # ---------------------------------------- 2

# CSV 파일 출력 경로와 리포트 작성용 SQL문 파일명 지정
csv_outputdir="/home/user1/output" # ---------------------------- 3
sqlfile="/home/user1/bin/select.sql"

# SQL 파일 확인
if [ ! -f "$sqlfile" ]; then # if문 ----------------------------- 4
  echo "SQL 파일이 존재하지 않습니다: $sqlfile" >&2
  exit 1
fi

# CSV 파일 출력용 디렉터리 확인
if [ ! -d "$csv_outputdir" ]; then # if문 ----------------------- 5
  echo "CSV 출력용 디렉터리가 존재하지 않습니다: $csv_outputdir" >&2
  exit 1
fi

# 오늘 날짜를 YYYYMMDD로 취득
today=$(date '+%Y%m%d') # --------------------------------------- 6

# CSV 출력. -N으로 컬럼명 생략
# tr 명령어로 탭을 쉼표로 변환
$MYSQL -h "${DBHOST}" -u "${DBUSER}" -p"${DBPASS}" -D "${DBNAME}" -N < "$sqlfile" | tr "\t" "," > "${csv_outputdir}"/data-${today}.csv # ---7
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 **MySQL** 서버에 select문을 실행해서 그 결과를 CSV 파일로 출력합니다. MySQL 서버가 원격 호스트에서 기동 중이더라도 이 스크립트를 실행한 머신에 직접 CSV 파일을 작성할 수 있습니다. 그리고 여기서 실행하는 SQL문은 셸 변수 sqlfile로 지정한 텍스트 파일에 작성되어 있다고 가정합니다.

데이터베이스 내용을 SELECT한 결과를 리포트해서 그걸 웹 서버에 배포하고 사용자 PC에서 보는 경우가 종종 있습니다. 이때 실시간으로 데이터베이스에 문의해서 결과를 조합해 최신 정보를 돌려줄 수도 있지만 웹 접속이 집중되면 데이터베이스 부하도 높아지게 되는 문제가 있습니다. 특히 웹 서버를 외부에 공개한다면 뉴스 사이트 등을 통해 퍼져서 접속이 갑자기 폭발적으로 늘어날 수도 있기 때문에 주의해야 합니다.

- 매번 데이터베이스에 접속하는 리포트 배포 방법

<img src='http://drive.google.com/uc?export=view&id=1Bx0n4fj37dgv80eTxxc_nymGyNflphPs' /><br>

일별 데이터로 하루에 한 번 배치 처리하여 CSV 파일을 만들고, 그 파일을 사용자가 내려받게 한다면 리포트를 내려받을 때 생기는 데이터베이스 서버 부하를 크게 줄일 수 있습니다. 예제에서는 그런 경우를 가정합니다.

- 매번 데이터베이스를 접속하지 않아도 되는 리포트 배포 방법

<img src='http://drive.google.com/uc?export=view&id=1fmyDF6WOe1c81dSXdYqxqsV2MrY_m3kH' /><br>

셸 변수 sqlfile로 지정한 예제에서 이용하는 SQL문은 다음과 같습니다. 이 SQL은 상황에 맞게 수정해서 사용하기 바랍니다.

```
SELECT id, score FROM userinfo ORDER BY id;
```

에제를 봅시다. `1`{:.info}에서 정의한 설정으로 데이터베이스에 정상적으로 접속 가능하고, `2`{:.info}처럼 **mysql 명령어**가 설치되어 있다고 가정합니다. `3`{:.info}은 CSV 파일 출력용 디렉터리(셸 변수 csv_outputdir)와 실행할 SQL문을 기록해둔 파일(셸 변수 sqlfile)을 정의합니다. 이어서 `4`{:.info}와 `5`{:.info}는 이것들이 존재하는지 확인합니다. 만약 존재하지 않으면 에러로 보고 스크립트를 종료합니다. `6`{:.info}은 date 명령어를 이용해서 오늘 날짜는 YYYYMMDD 포맷으로 조합합니다. 이 날짜는 CSV 파일명에서 사용합니다. `7`{:.info}에서 mysql 명령어를 이용해서 CSV 파일을 출력합니다. 명령행이 길어지므로 \로 줄바꿈을 합니다. mysql 명령어 옵션은 다음과 같습니다.

- 스크립트에서 사용하는 mysql 명령어 옵션

|옵션|설명|
|:---|:---|
|-h|MySQL 서버 호스트명|
|-u|MySQL 서버 접속 사용자명|
|-p|MySQL 서버 접속 암호|
|-D|접속할 데이터베이스명|
|-N|컬럼명을 표시하지 않음|

`7`{:.info}에서 mysql 명령어에 SQL문이 적힌 파일을 입력 리다이렉트로 넘깁니다. 이렇게 하면 출력 결과 컬럼의 구분자가 탭이 됩니다. 따라서 파이프로 연결한 **tr 명령어**로 탭을 ,(쉽표)로 변환합니다. tr "\t" "," 부분입니다. 이것으로 SELECT한 결과를 CSV 형식으로 얻게 되므로 리다이렉트해서 CSV 파일로 출력합니다.

MySQL의 SELECT 결과를 셸 스크립트에서 CSV 파일로 저장할 수 있습니다. cron에 등록해서 정기적으로 리포트를 작성하도록 합시다.

&nbsp;
&nbsp;

## **주의사항**

- MySQL에서 결과를 CSV 파일로 출력하는데 **INTO OUTFILE** 명령어를 이용하는 방법도 있습니다.
```
SELECT id, score FROM userinfo
	INTO OUTFILE '/home/park/output.csv'
  FIELDS TERMINATED BY ','
```

- 하지만 MySQL의 INTO OUTFILE은 mysql 명령어를 실행한 클라이언트 서버가 아니라 데이터베이스 서버에 출력 파일을 작성하므로 scp 명령어 등으로 데이터베이스 서버에서 네트워크를 통해 파일을 복사해야 합니다. 따라서 예제에서는 INTO OUTFILE을 사용하지 않고 SQL문 결과를 리다이렉트해서 사용 중인 머신에 직접 저장합니다.

- 데이터에 쉼표가 포함되면 구분자 문자와 데이터 문자를 구분할 수 없게 됩니다. 따라서 SQL문 CONCAT 함수를 이용해 각 컬럼을 "(큰따옴표)로 둘러싸면 엑셀 등에서 정상적으로 처리할 수 있게 됩니다. SQL문을 다음처럼 수정해서 각 컬럼값에 큰따옴표를 두릅니다.
```
SELECT CONCAT('"',id,'"'),CONCAT('"',score,'"') FROM userinfo
```
여기서 이용하는 CONCAT은 MySQL 문자열 함수의 인수로 지정한 문자열을 순서대로 연결해서 하나의 문자열로 돌려줍니다. 선택한 컬럼값 앞뒤로 **CONCAT 함수**를 사용해서 큰따옴표 기호를 연결하면 컬럼값을 큰따옴표로 둘러쌀 수 있습니다. 엑셀 등에서는 값을 큰따옴표로 싸면 그 안에 쉼표가 있더라도 바르게 구분자를 인식하게 됩니다.

