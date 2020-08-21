---
layout: article
title: ShellScript(6) - case
tags: [Linux, ShellScript]
key: 20200727_shell_script_06
---

{% include googlead.html %}

## 리눅스 ShellScript 예제
---

> `case` 문을 알아보겠습니다.

<br>

### 기본문법

{% highlight bash linenos %}
case word in
  pattern)
    command ;;
esac
{% endhighlight %}

<br>

### 예제.1

{% highlight bash linenos %}
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
{% endhighlight %}

<br>

### 예제.2

{% highlight bash linenos %}
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
{% endhighlight %}

<br>

### 예제.3

{% highlight bash linenos %}
#!/bin/bash
case "$1" in
  abc) echo "$variable = abc" ;;
  xyz) echo "$variable = xyz" ;;
esac
{% endhighlight %}

<br>

### 예제.4

{% highlight bash linenos %}
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
{% endhighlight %}

<br>

### 예제.5

{% highlight bash linenos %}
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
{% endhighlight %}

<br>

### 예제.6

{% highlight bash linenos %}
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
{% endhighlight %}

<br>

### 예제.7

{% highlight bash linenos %}
read val

echo $val
case $val in
[0-9]*)
    echo "number";;
[^0-9]*)
    echo "not number";;
esac
{% endhighlight %}
