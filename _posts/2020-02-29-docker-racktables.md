---
layout: article
title: Docker에서 racktables 운영하기
tags: [Docker]
key: 20200229_docker_racktables
---

{% include googlead.html %}

## Docker-Racktables 활용

---
> 현재 사내에서 `racktables`{:.info} 을 사용하고 있는데요.  
> `Docker`{:.info}를 사용하면 장애발생 시 빠르게 복구할 수 있는 장점이 있습니다.


- [Dockerfile 및 추가 파일 다운로드](https://github.com/planet/docker-racktables)  
- [racktables 버전별 Download](https://github.com/RackTables/racktables/releases)

<br>

### 1. Dockfile 로 부터 Image Build.

> Dockfile 위치에서 image를 build 합니다.

```
$ docker build -t racktables-test .
```

<br>

### 2. Build 된 Image 확인

> 정상적으로 작업이 끝나면 아래와 같은 Image를 확인할 수 있습니다.

```
$ docker images
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
racktables_test     latest              c0f598aece7e        37 seconds ago      597 MB
docker.io/centos    centos6             d0957ffdf8a2        11 months ago       194 MB
```

<br>

### 3. Build 된 이미지로 부터 Container 실행

> 저는 외부에서 접근시 7777포트를 사용합니다.(사용하고자 하는 포트를 입력하시면 됩니다.)

```
$ docker run -d -p 7777:80 --name racktables c0f598aece7e
```

<br>

### 4. Container 확인

> Container가 정상으로 올라오면 아래와 같이 확인이 됩니다.

```
$ docker ps
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                  NAMES
26e140d4411d        c0f598aece7e        "/bin/sh -c '/usr/..."   10 minutes ago      Up 10 minutes       0.0.0.0:7777->80/tcp   racktables
```


<br>

### 5. Browser에서 접속

> 브라우저 주소창에서 ip-address 에는 현재 서버의 ip를 입력.

`http://<ip-address>:7777/?module=installer`
{:.info}

<br>

### 6. 설치 진행

> 브라우저에서 설치를 진행합니다.(총 7단계로 진행이 됩니다.)

<br>

### 7. Brower에서 설치진행

> 설치 진행 중 하기와 같은 메세지가 출력이되면 8번 container 접속파트를 참고하세요.

" chown nobody:nogroup secret.php; chmod 400 secret.php"
{:.warning}

<br>

### 8. Container 접속하여, 파일 속성 변경

> 아래와같이 container에 접속 후 파일의 속성을 변경한 후 다음단계로 진행합니다.

```
$ docker exec -it 26e140d4411d /bin/bash
26e140d4411d>$ chown apache:apache /var/www/html/inc/secret.php
26e140d4411d>$ chmod 400 /var/www/html/inc/secret.php
```


<br>

### 9. Docker에서 Data 복구 및 백업 방법

> 장애가 발생했다는 가정하에서 평소 백업해 두었던 sql 파일로 복구진행을 하면 됩니다.  
> 추후 Docker를 사용하여 계속 사용할 것을 생각하여 복구, 백업 모두 기록해 놓았습니다.

Docker MySQL 복구

```
$ cat backup.sql | docker exec -i CONTAINER /usr/bin/mysql -u root --password=$PASSWORD DATABASE [--max_allowed_packet=16G]
```

Docker MySQL 백업

```
$ docker exec CONTAINER /usr/bin/mysqldump -u root --password=$PASSWORD DATABASE > backup.sql
```

<br>

### 10. Data 복구 ERROR 발생시 Trouble Shooting

> 하기와 같은 에러가 발생하게 되면,

```
ERROR 1153 (08S01) at line 522: Got a packet bigger than 'max_allowed_packet' bytes
```

> Docker내에 실행된 mysql에 접속하여 mysql set 변경을 합니다.

```
mysql> set global max_allowed_packet=1000000000;
mysql> set global net_buffer_length=1000000;
```

> Dockerfile 안에서 이 부분은 설정해 보았으나 안되서 수동으로 진행했네요.

<br>

### 11. Docker MySQL 복구

> 9단계에서 실패한 복구 과정을 다시 실행하면 복구가 잘되는 걸 확인할 수 있습니다.

```
$ cat racktables_db.sql | docker exec -i 26e140d4411d /usr/bin/mysql -u root --password= racktables_db
```

<br>

### 12. Browser 에서 접속 및 확인

> 로그인시 계정과 패스워드도 함께 복구가 되므로 기존사용하던 계정, 패스워드가 있을경우 기존계정을 입력하시면 됩니다.
