---
title: ShellScript(6) - case
date: 2020-07-27
categories: [Linux, ShellScript]
tags: [Linux, ShellScript, case]
comments: true
seo:
  date_modified: 2020-08-15 16:59:05 +0900
---

## 리눅스 ShellScript 예제
---


> `case` 문을 알아보겠습니다.

<br>

##### 기본문법

``` bash
case word in
  pattern )
    command ;;
esac
```
<br>
<br>

##### 예제.1

``` bash
#!/bin/bash
echo "Enter your lucky number"
read n
case $n in
101)
    echo echo "You got 1st prize" ;;
510)
    echo "You got 2nd prize" ;;
999)
    echo "You got 3rd prize" ;;
*)
    echo "Sorry, try for the next time" ;;
esac
```

<br>

##### 예제.2

``` c
#!/bin/bash
echo "What is your preferred programming / scripting language"
echo "1) bash"
echo "2) perl"
echo "3) phyton"
echo "4) c++"
echo "5) I do not know !"
read case;
# simple case bash structure
# note in this case $case is variable and does not have to
# be named case this is just an example
case $case in
    1) echo "You selected bash";;
    2) echo "You selected perl";;
    3) echo "You selected phyton";;
    4) echo "You selected c++";;
    5) exit
esac
```

<br>

##### 예제.3

``` bash
#!/bin/bash
case "$1" in
  abc) echo "$variable = abc" ;;
  xyz) echo "$variable = xyz" ;;
esac
```

<br>

##### 예제.4

``` bash
#!/bin/bash
echo "1) kim"
echo "2) lee"
echo "3) park"

echo -n "select your first name ? :"
read name

case $name in
1)
    echo " your first name is kim";;
2)
    echo " your first name is lee";;
*)
    echo " your first name is park";;
esac
```

<br>

##### 예제.5

``` bash
#!/bin/sh
echo "리눅스가 재미있나요?(Yes / no)"
read answer
case $answer in
  yes|y|Y|Yes|YES)
    echo "다행입니다."
    echo "더욱 열심히 하세요^^";;
  [nN]*)
    echo "안타깝네요.ㅠㅠ";;
  *)
    echo "yes 아니면 no 만 입력했어야죠"
    exit 1;;
esac
    exit 0
```

<br>

##### 예제.6

``` bash
#!/bin/sh
case "$1" in
case1)
    echo "case1 - 외로워도 슬퍼도"
;;
case2)
    echo "case2 - 고바리안 고바리안"
;;
*)
    echo "잘못고르셨어요"
;;
esac
exit 0
```

<br>

##### 예제.7

``` bash
read val

echo $val
case $val in
[0-9]*)
    echo "number";;
[^0-9]*)
    echo "not number";;
esac
```
