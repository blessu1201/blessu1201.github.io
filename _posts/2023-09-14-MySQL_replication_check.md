---
layout: article
title: 서버관리_18 MySQL 레플리케이션 감시하기
tags: [Linux, mysql, awk, grep, date, ShellScript]
key: 20230914-linux_server_manage_18
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어  

> 명령어: mysql, awk, grep, date  
> 키워드: MySQL, 레플리케이션, 감시  
> 사용처: MySQL 레플리케이션 구성 상태를 정기적으로 감시하고 싶을 때     

> 실행 예제  

```
$ ./mysql-replcheck.sh
[2023/09/14 15:15:15] STATUS NG
Slave_IO_Running: No
Slave_SQL_Running: Yes
Last_IO_Error: Got fatal error 1236 from master when reading data from
binary log: 'Cloud not find first log file name in binary log index file'
Last_SQL_Error:
```

> 스크립트

```bash
#!/bin/sh

# 데이터베이스 접속 설정. 슬레이브 서버에 접속
DBHOST="192.168.11.5" # ----------------------------------------------------------------------- 1
DBUSER="operator"
DBPASS="PASSWORD"

# mysql 명령어 경로 지정과 임시파일 정의
MYSQL="/usr/bin/mysql" # ---------------------------------------------------------------------- 2
resulttmp="tmp.$$"

# SHOW SLAVE STATUS 실행 결과를 임시 파일에 출력
$MYSQL -h "${DBHOST}" -u "${DBUSER}" -p"${DBPASS}" -e "SHOW SLAVE STATUS \G" > $resulttmp # --- 3

# 레플리케이션 상태 관련 파라미터 추출
Slave_IO_Running=$(awk '/Slave_IO_Running:/ {print $2}' "$resulttmp") # ----------------------- 4
Slave_SQL_Running=$(awk '/Slave_SQL_Running;/ {print $2}' "$resulttmp")
Last_IO_Error=$(grep 'Last_IO_Error:' "$resulttmp" | sed 's/^ *//g')
Last_SQL_Error=$(grep 'Last_SQL_Error:' "$resulttmp" | sed 's/^ *//g')

# 현재 시각을 2023/09/14 15:15:15 형태로 조합
date_str=$(date +%Y/%m/%d %H:%M:%S) # --------------------------------------------------------- 5

# Slave_IO_Running과 Slave_SQL_Running이 둘 다 YES가 아니면 에러
if [ "SLAVE_IO_Running" = "YES" -a "$Slave_SQL_Running" = "YES" ]; then # if문 ---------------- 6
  echo "[$date_str] STATIS OK"
else
  echo "[$date_str] STATIS NG"
  echo "Slave_IO_Running: $Slave_IO_Running"
  echo "Slave_SQL_Running: $Slave_SQL_Running"
  echo "$Last_IO_Error"
  echo "$Last_SQL_Error"

  # 경고 메일 등 출력
  /home/user1/bin/alert.sh
fi

# 임시파일 삭제
rm -f "$resulttmp"
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 **MySQL 레플리케이션**(복제) 상태를 감시합니다. MySQL 슬레이브 서버에 접속해서 레플리케이션 이상이 있다면 경고 메시지를 표시합니다.

이 스크립트는 **mysql 명령어**로 SHOW SLAVE STATUS라는 명령어를 실행해서 레플리케이션 이상이라고 판별하면 경고 메시지를 표시하고, alert.sh라는 스크립트를 실행합니다. 예제에서 alert.sh는 어떤 경고를 표시하는 스크립트라고 가정합니다. 그리고 MySQL 레플리케이션이 이미 가동중이고 `1`{:.info}에서 정의한 설정으로 데이터베이스에 정상적으로 접속된다고 가정합니다.

`2`{:.info}에서 mysql 명령어의 완전 경로와 임시 파일명을 정의합니다. 임시 파일명에서 쓰는 **$$** 변수는 프로세스 ID입니다.

`3`{:.info}은 MySQL 서버에 mysql 명령어로 "SHOW SLAVE STATUS" 명령을 전달합니다. mysql 명령어에 지정하는 옵션은 다음과 같습니다.

- 스크립트에서 사용하는 mysql 명령어 옵션

|옵션|설명|
|:---|:---|
|-h|MySQL 서버 호스트명|
|-u|MySQL 서버 접속 사용자명|
|-p|MySQL 서버 접속 암호|
|-e|지정할 SQL 실행|

**-e 옵션**을 사용하면 셸 명령행에서 직접 MySQL 서버에 명령을 실행할 수 있습니다. -e 옵션을 이용해서 `3`{:.info}에서 실행할 **SHOW SLAVE STATUS**는 레플리케이션 구성 슬레이브 서버의 레플리케이션 상태를 표시하는 명령어입니다. 출력 예는 다음과 같습니다.

- SHOW SLAVE STATUS
```
Slave_IO_State: Waiting for master to send event
Master_Host: 192.168.11.5
:생략
Relay_Master_Log_File: mysql-bin.000151
Slave_IO_Running: YES          <- YES면 정상
Slave_SQL_Running: YES         <- YES면 정상
Last_IO_Errno: 0
Last_IO_Error:
:생략
Last_SQL_Errno: 0
Last_SQL_Error:
:생략
```

위 출력 결과는 많은 부분을 생략했습니다. 레플리케이션 상태를 확인하고 싶을 때 확인해야 하는 것은 **"Slave_IO_Running"**과 **"Slave_SQL_Running"**입니다. 이 두 값이 둘다 Yes가 아니면 레플리케이션에 어떤 문제가 생긴 것입니다. `3`{:.info}은 SHOW SLAVE STATUS 출력 결과를 임시 파일에 리다이렉트해서 저장합니다.

`4`{:.info}에서 임시 파일에 출력된 결과에서 필요한 값을 취득해서 셸 변수에 대입합니다. Slave_IO_Running은 **awk 명령어** 필터를 이용해서 두 번째 컬럼($2)으로 취득합니다. 또한 그 에러 메시지인 Last_IO_Error와 Last_SQL_Error는 **grep 명령어**로 임시 파일에서 추출합니다. 이때 필요 없는 공백문자를 삭제하기 위해 **sed 명령어**도 사용합니다.

`5`{:.info}에서 date 명령어로 현재 시각을 2023/09/11 15:15:15 포맷으로 조합합니다. 이 시간을 이용해서 `6`{:.info}에서 메시지 출력 시 날짜를 표시합니다.

`6`{:.info}은 레플리케이션 상태를 확인해서 경고를 출력할지 판단하는 if문입니다. 레플리케이션 상태가 정상인지는 Slave_IO_Running과  Slave_SQL_Running이 모두 Yes인가로 판단합니다. test 명령어 = 연산자로 각각 문자열을 비교해서 **-a 연산자**로 이어서 AND로 비교합니다. 만약 결과가 참이면 레플리케이션 상태는 이상이 없다고 보고 OK를 출력합니다.

`6`{:.info}의 결과가 거짓이면 레플리케이션 상태에 문제가 있다고 판단합니다. 예를 들어 마스터 서버의 바이너리 로그를 찾지 못했다면 Slave_IO_Running은 No가 되고 Last_IO_Error에는 아래와 같이 에러 메시지가 표시됩니다.

- 레플리케이션 이상 발생 시 SHOW STATUS
```
Slave_IO_running: No
Slave_SQL_Running: Yes
Last_IO_Error: Got fatal error 1236 from master when reading data from
binary log: 'Cloud not find log file name in binary log index file'
Last_SQL_Error:
```

`6`{:.info}의 else에서는 레플리케이션 이상이 있으면 NG와 함께 에러 메시지를 표시합니다. 또한 alert.sh를 실행하고 경고 메시지를 보냅니다. 마지막으로 `7`{:.info}에서 임시 파일을 삭제합니다.

이렇게 해서 레플리케이션 상태 감시가 가능합니다. 최근 MySQL 시스템은 레플리케이션 구성을 많이 하기 때문에 이런 시스템을 운용 관리하는 일이 많을 것입니다. 레플리케이션은 시스템 가용성을 높이지만 데이터 불일치 같은 문제를 만들기도 하므로 정기적으로 이렇게 레플리케이션 상태를 감시하는 것이 중요합니다.

&nbsp;
&nbsp;

## **데이터베이스와 레플리케이션**

<img src='http://drive.google.com/thumbnail?id=1AwR6TD2AXoSbDm2DOG8igELtGCpOTXHo&sz=w1000' /><br>

레플리케이션이란 데이터베이스 서버에서 이용하는 시스템 구성으로 그림처럼 마스터 서버에서 슬레이브 서버에 데이터를 복제합니다. 이러면 시스템 가용성이 높아지고 데이터베이스 서버 부하도 줄게 됩니다.

예를 들어 어떤 데이터베이스를 빈번히 참조하는 애플리케이션이 있을 때 여러 슬레이브 서버에 분산해서 참조하면 각각의 데이터베이스 서버의 접속 부하는 줄어들게 됩니다. 또한 어느 슬레이브 서버에 장애가 생겨서 접속하지 못하게 되어도 대상 슬레이브 서버를 시스템에서 제외하면 시스템 복구를 할 수 있습니다. 애플리케이션에서 에러가 발생했을 때 자동으로 다음 슬레이브 서버에 접속하도록 만들면 시스템 다운 시간을 0으로 만들 수 있습니다.

레플리케이션은 데이버테이스 데이터 복구에도 무척 도움이 됩니다. 그림의 마스터 서버에서 디스크 장애가 일어나더라도 슬레이브 서버 중 하나를 마스터 서버로 승격시키거나, 슬레이브 서버의 자료를 재구축해서 마스터 서버에 복사하면 장애가 발생하기 직전 상태로 데이터를 복구할 수 있습니다. 

하지만 레플리케이션은 백업과는 달리 늘 마스터와 함께 데이터를 갱신합니다. 따라서 잘못 삭제하거나 작업 실수로 데이터 파손이 일어난 것을 되돌릴 수 없습니다. 따라서 레플리케이션했다고 백업이 필요 없는 것은 아니므로 주의하기 바랍니다.

&nbsp;
&nbsp;

## **주의사항**

- 이 스크립트는 MySQL 서버에 접속하는 암호가 적혀 있으므로 파일 권한에 주의해서 다른 사용자가 볼 수 없도록 해야 합니다. 그리고 가능하면 접속 사용자는 최소한의 권한만 가진 감시 목적용 사용자를 별도로 만들어서 관리하기 바랍니다. 그래야 스크립트가 다른 사람에게 노출되어서 ID와 암호가 알려지더라도 피해를 최소화할 수 있기 때문입니다.
