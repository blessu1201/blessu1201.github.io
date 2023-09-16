---
layout: article
title: 서버관리_17 MySQL 데이터베이스 백업하기
tags: [Linux, mysqldump, date, gzip, find, xargs, ShellScript]
key: 20230908-linux_server_manage_17
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어  

> 명령어: mysqldump, date, gzip, find, xargs  
> 키워드: MySQL, 데이터베이스, 백업, 덤프 파일  
> 사용처: MySQL 데이터베이스 백업을 정기적으로 자동 수행하고 싶을 때    

> 실행 예제  

```
$ ./musql-dbbackup.sh
/home/user1/backup에 백업 파일이 작성됨
```

> 스크립트

```bash
#!/bin/sh

# 데이터베이스 접속 설정
DBHOST="192.168.11.5" # ----------------------------------- 1
DBUSER="backup"
DBPASS="PASSWORD"
DBNAME="hamilton"

# 데이터베이스 백업 설정
BACKUP_DIR="/home/user1/backup" # ------------------------- 2
BACKUP_ROTATE=3
MYSQLDUMP="/usr/bin/mysqldump"

# 백업 출력할 디렉터리 확인
if [ ! -d "$BACKUP_DIR"]; then # -------------------------- 3
  echo "백업용 디렉터리가 존재하지 않습니다: $BACKUP_DIR" >&2
  exit 1
fi

today=$(date '+%Y%m%d') # --------------------------------- 4

# mysqldump 명령어로 데이터베이스 백업을 실행
$MYSQLDUMP -h "${DBHOST}" -u "${$DBUSER}" -p"${DBPASS}" "${DBNAME}" > "${BACKUP_DIR}/${DBNAME}-${today}.dump" # -- 5

# mysqldump 명령어 종료 스테이터스 $?로 성공, 실패 확인
if [ $? -eq 0 ]; then # ----------------------------------- 6
  gzip "${BACKUP_DIR}/${DBNAME}-${today}.dump"

  # 오래된 백업 파일 삭제
  find "$BACKUP_DIR" -name "${DBNAME}-*.dump.gz" -mtime +${BACKUP_ROTATE} | xargs rm -f # --- 7
else
  echo "백업 작성 실패:${BACKUP_DIR}/${DBNAME}-${today}.dump"
  exit 2
fi
```

## **해설**

이 스크립트는 **MySQL** 서버에서 데이터베이스 백업 파일을 작성하고 저장합니다. 취득한 백업 파일은 gzip 압축으로 저장하고 오래된 백업 파일은 자동으로 삭제합니다.

여기서 MySQL 데이터베이스는 이미 가동 중이고 `1`{:.info}에서 정의한 설정으로 데이터베이스에 정상적으로 접속 가능하다고 가정합니다. MySQL 설치나 설정은 다른 전문 서적을 참조하기 바랍니다.

`2`{:.info}에서 데이터베이스 백업 설정을 정의합니다. 정의한 셸 변수 의미는 다음과 같습니다.

- 스크립트에서 사용하는 백업 설정 관련 셸 변수

|변수|설명|
|:--|:---|
|BACKUP_DIR|백업 파일 저장 디렉터리|
|BACKUP_ROTATE|과거 몇 회분 백업 파일을 저장할지 관련|
|MYSQLDUMP|mysqldump 명령어 경로|

`3`{:.info}에서 셸 변수 BACKUP_DIR로 지정한 백업 파일 출력 디렉터리가 존재하는지 확인합니다. -d는 대상이 디렉터리인지 확이나는 연산자입니다. 부정 연산자 !와 함께 써서 디렉터리가 아니면 에러를 표시하고 종료합니다.

`4`{:.info}에서 파일명에 사용할 현재 시각을 **date 명령어**를 이용해 YYYYMMDD 형식으로 얻습니다. 오늘이 2023년 9월 8일이면 20230908을 얻습니다.

`5`{:.info}에서 실제 데이터베이스 덤프를 얻습니다. **mysqldump 명령어**에 지정하는 옵션은 다음과 같습니다.

- 스크립트에서 사용하는 mysqldump 명령어 옵션

|옵션|설명|
|:--|:---|
|-h|MySQL 서버 호스트명|
|-u|MySQL 서버 접속 사용자명|
|-p|MySQL 서버 접속 암호|

`5`{:.info}의 mysqldump 명령어 출력은 리다이렉트해서 ${DBNAME}-${today}.dump로 출력합니다. 이렇게 파일명에 날짜를 넣어두면 나중에 사용할 때 언제 백업한 것인지 바로 알 수 있습니다.

`6`{:.info}은 mysqldump 명령어가 성공했는지 실패했는지에 따라 분기합니다. 종료 스테이터스 $?가 0이면 정상적으로 끝난 것이므로 우선 취득한 덤프 파일을 gzip 명령어로 압축합니다. mysqldump 명령어로 취득한 덤프 파일은 단순한 텍스트 파일이므로 데이터베이스 규모에 따라서는 무척 큰 파일이 되기도 합니다. 따라서 이렇게 압축해서 저장해두는 편이 좋습니다.

`7`{:.info}에서 **find 명령어 -mtime 옵션**을 이용해서 셸 변수 BACKUP_ROTATE로 지정한 날보다 이전에 만든 백업 파일을 **xargs 명령어**로 삭제합니다.

이렇게 해서 MySQL 데이터베이스 백업을 자동으로 취득할 수 있습니다. cron에 등록해서 하루에 한 번 정기적으로 실행하는 것이 좋습니다.

## **주의사항**

- mysqldump 명령어를 실행하려면 접속한 MySQL 계정에 적절한 권한이 설정되어 있어야 합니다. 일반적으로 SELECT/SHOW VIEW/LOCK TABLES 권한이 필요한데 mysqldump 명령어에 지정하는 옵션에 따라서는 추가 권한이 필요합니다. 자세한 것은 전문서를 참조하기 바랍니다.

- 이 스크립트는 MySQL 서버 접속 암호가 적혀 있으므로 파일 권한에 주의해야 합니다. 또한, 데이터베이스 백업 파일은 데이버테이스의 모든 정보가 담겨 있는 무척 중요한 파일이므로 파일을 저장하는 디렉터리도 다른 사용자가 볼 수 없도록 적절한 권한을 설정해둬야 합니다. 일반적으로 데이터베이스 보안 대책에 비해 백업 서버의 보안 대책은 가볍게 넘어갈 때가 많습니다. 백업 서버에도 데이터베이스 서버와 동일하거나 그 이상의 보안 대책이 필요하다는 걸 인식하기 바랍니다.