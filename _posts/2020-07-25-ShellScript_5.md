---
layout: article
title: ShellScript(5) - if, and, or
tags: [Linux, ShellScript]
key: 20200725_shell_script_05
---

{% include googlead.html %}

---

> `if` 문의 몇가지 예제를 통해 사용방법을 알아보도록 하겠습니다.

<br>

| 연산자 | 의미 |
|:----:|:---:|
| x `-eq` y | x가 y와 같은지 체크 |
| x `-ne` y | x가 y와 같지 않은지 체크 |
| x `-lt` y | x가 y 보다 작은지 체크 |
| x `-le` y | x가 y 보다 작거나 같은지 체크 |
| x `-gt` y | x가 y 보다 큰지 체크 |
| x `-ge` y | x가 y 보다 크거나 같은지 체크 |


<br>
<br>

## 예제.1 - simple if

{% highlight bash linenos %}
#!/bin/bash
n=10
if [ $n -lt 10 ];then
    echo "It is a one digit number"
else
    echo "It is a two digit number"
fi
{% endhighlight %}

{% highlight result %}
$ ./simple_if.sh
It is a two digit number
{% endhighlight %}

<br>

## 예제.2 - AND연산  "&&"

{% highlight bash linenos %}
#!/bin/bash
echo "Enter username"
read username
echo "Enter password"
read password

if [[ ( $username == "admin" && $password == "secret" ) ]]; then
    echo "valid user"
else
    echo "invalid user"
fi
{% endhighlight %}

{% highlight result %}
Enter username
admin
Enter password
secret
valid user
{% endhighlight %}

{% highlight result %}
Enter username
admin
Enter password
12345
invalid user
{% endhighlight %}

<br>

## 예제.3 - OR연산 ||

{% highlight bash linenos %}
#!/bin/bash
echo "Enter any number"
read n

if [[ ( $n -eq 15 || $n  -eq 45 ) ]]
then
    echo "You won the game"
else
    echo "You lost the game"
fi
{% endhighlight %}

{% highlight result %}
Enter any number
15
You won the game
{% endhighlight %}

{% highlight result %}
Enter any number
45
You won the game
{% endhighlight %}

{% highlight result %}
Enter any number
20
You lost the game
{% endhighlight %}

<br>

## 예제.4 - if ~ elif ~ else ~ fi

{% highlight bash linenos %}
#!/bin/bash
echo "Enter your lucky number"
read n
if [ $n -eq 101 ];then
    echo "You got 1st prize"
elif [ $n -eq 510 ];then
    echo "You got 2nd prize"
elif [ $n -eq 999 ];then
    echo "You got 3rd prize"
else
    echo "Sorry, try for the next time"
fi
{% endhighlight %}

{% highlight result %}
Enter your lucky number
101
You got 1st prize
{% endhighlight %}

{% highlight result %}
Enter your lucky number
510
You got 2nd prize
{% endhighlight %}

{% highlight result %}
Enter your lucky number
999
You got 3rd prize
{% endhighlight %}

{% highlight result %}
Enter your lucky number
9999
Sorry, try for the next time
{% endhighlight %}
