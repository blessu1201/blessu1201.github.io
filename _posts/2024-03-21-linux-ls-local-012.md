---
layout: article
title: 변환 처리_02 지역 변수를 함수 안에 정의해서 호출한 곳의 변수가 파괴되지 않게 하기
tags: [Linux, ShellScript, ls, local]
key: 20240321-linux-ls-local
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: ls, local  
> 키워드: 지역 변수, 전역 변수, 스코프  
> 사용처: 함수 내부에서 변수를 다룰 때 호출한 곳에 영향을 주지 않도록 지역 변수로 정의하고 싶을 때

--- 

> 실행예제

```
$ ./local-var.sh
directory: /home/user1/logdir
20131020.log 20131022.log

directory: /var/tmp
tmp.dat	tmp.3113
```

> 스크립트

```bash
#!/bin/sh

DIR=/var/tmp

ls_home()
{
  # 변수 DIR을 함수 내부 변수로 정의
  local DIR  #----------------------- 1

  DIR=~/$1  #------------------------ 2
  echo "directory: $DIR"
  ls $DIR
}

ls_home logdir  #-------------------- 3

echo "directory: $DIR"  #------------ 4
ls $DIR
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 홈 디렉터리 바로 아래에 logdir이라는 디렉터리 안에 있는 파일과 셸 변수 DIR로 지정한 /var/tmp 디렉터리 안에 있는 파일을 **ls 명령어**로 순서대로 표시하는 간단한 스크립트입니다.

시작할 때 ls_home이라는 함수를 만드는데 이 함수는 홈 디렉터리 아래에 있는 인수($1)로 받은 이름의 서브디렉터리를 표시합니다. `3`{:.info}에서 logdir이라는 인수를 넘기므로 `2`{:.info}의 $1값은 logdir이 됩니다.

또한 `2`{:.info}에서는 **~(틸다) 기호**를 사용하여 홈 디렉터리 경로를 얻습니다. 셸 스크립트에서 ~는 홈 디렉터리 경로가 됩니다. 즉, 스크립트를 실행한 사용자명이 user1이라면 ~/ 는 /home/user1/가 됩니다. 따라서 `2`{:.info}는 실행 시 "DIR=/home/user1/logdir" 같이 됩니다.

많은 프로그래밍 언어가 함수에서 정의한 변수를 그 함수 안에서만 유효한 지역 변수로 삼습니다. 하지만 셸 스크립트는 기본적으로 **변수 모두를 전역 변수**로 취급합니다. 따라서 함수 안에서 변수값을 변경하면 스크립트 전체에 영향을 미칩니다.

즉 `2`{:.info}의 셸 변수 대입문은 이 스크립트 서두에 선언한 DIR=/var/tmp에 영향을 줍니다. 이를 피하기 위해 `1`{:.info}에서 **local 명령어**를 써서 변수를 선언합니다. 호출한 시점에 이미 DIR이라는 셸 변수가 사용되었지만 ls_home 함수 안에 있는 같은 이름의 셸 변수 DIR은 지역 변수이므로 호출한 곳에 영향을 주지 않습니다.

만약 함수안에서 local 명령어를 쓰지 않았다면 변수값은 변경되어 `4`{:.info}에서 /var/tmp가 아닌 ~/logdir이 출력되겠지요.

- local 명령어를 사용하지 않으면 함수 내부에서 변숫값이 변경된다.

  ```
  $ ./local.sh
  directory : /home/user1/logdir
  20131020.log	20131022.log

  directory : /home/user1/logdir
  20131020.log	20131022.log
  ```