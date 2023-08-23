---
layout: article
title: 서버관리_02 / Server Get User List
tags: [Linux Get User List, Shellscript]
key: 20230823-linux_server_manage_02 
---

{% include googlead.html %}

---


- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

## 서버에 작성된 사용자 계정 목록 얻기

> 명령어: grep, cut
> 키워드: 사용자 계정, 구분자, 컬럼
> 사용처: 텍스트 파일에서 구분자를 지정해서 특정 컬럼을 추출하고 싶을 때

- 실행예제

 ```bash
#!/bin/bash

filename="/etc/passwd"

# 줄 첫글자가 #인 주석 줄은 제외하고 cut 명령어로
# * 첫 번째 값을 표시 [-f 1]
# * 구분자 기호는 : [-d ":"]로 표시
grep -v "^#" "$filename" | cut -f 1 -d ":"
```

스크립트 실행 결과
```
root
daemon
bin
sys
sync
games
man
lp
mail
news
....
systemd-coredump
lxd
dnsmasq
prometheus
grafana
```


> /etc/passwd 파일은 사용자 관리에 사용하는 시스템 파일로 다음과 같은 형식입니다.

```
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
sys:x:3:3:sys:/dev:/usr/sbin/nologin
sync:x:4:65534:sync:/bin:/bin/sync
...
```

> 파일내용은 ":" 으로 나뉘는데 각 항목은 아래와 같습니다.

| 컬럼 | 설명 |
|:--------:|:--------:|
|컬럼1|사용자명|
|컬럼2|암호|
|컬럼3|UID(사용자ID)|
|컬럼4|GID(그룹ID)|
|컬럼5|코멘트(풀네임이 들어가기도 함)|
|컬럼6|홈 디렉토리 경로|
|컬럼7|로그인 쉘|

 