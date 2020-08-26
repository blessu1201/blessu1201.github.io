---
layout: article
title: ShellScript(3) - while, for
tags: [Linux, ShellScript]
key: 20200724_shell_script_03
---

{% include googlead.html %}

---

> 반복문  `while`{:.info}, `for`{:.info} 의 문법을 살펴보겠습니다.

<br>

# 1. 반복문 while (Using While Loop) 문법

> `condition`(조건식)에 따라 `do` 와 `done` 사이의 `commands`(명령)을 반복합니다.  

{% highlight bash linenos %}
#!/bin/bash
while [ condition ]
do
    commands
done
{% endhighlight %}

<br>

## 예제.1

> n이 1보다 작거나 같으면 true가되어 do 와 done 사이의 명령을 반복 실행합니다.

{% highlight bash linenos %}
#!/bin/bash
n=1
while [ $n -le 5 ]
do
      echo "Running $n time"
      (( n++ ))
done
{% endhighlight %}

{% highlight result %}
Running 1 time
Running 2 time
Running 3 time
Running 4 time
Running 5 time
{% endhighlight %}

<br>

## 예제.2 - break

>n이 10보다 작거나 같으면 실행되는 조건이지만, 중간에 if 조건문이 있습니다.  
>n이 6이 되는 순간에 terminated를 출력한 후 break 되어 스크립트가 종료됩니다.

{% highlight bash linenos %}
#!/bin/bash
n=1
while [ $n -le 10 ]
do
    if [ $n == 6 ]
    then
           echo "terminated"
           break
     fi
     echo "Position: $n"
     (( n++ ))
done
{% endhighlight %}

{% highlight result %}
Position: 1
Position: 2
Position: 3
Position: 4
Position: 5
terminated
{% endhighlight %}

<br>

## 예제.3 - continue

>n이 3이 되면 처음부터 코드를 다시 반복합니다.(아래 명령은 생략됨)

{% highlight bash linenos %}
#!/bin/bash
n=0
while [ $n -le 5 ]
do
     (( n++ ))

     if [ $n == 3 ]
     then
           continue
     fi
     echo "Position: $n"

done
{% endhighlight %}

{% highlight result %}
Position: 1
Position: 2
Position: 4
Position: 5
Position: 6
{% endhighlight %}

<br>

## 예제.4 - infinite loop

>이 code 는 무한루프 구조이기에 n이 특정값 10이 될 때 프로그램을 종료하는 code를 넣었습니다.

{% highlight bash linenos %}
#!/bin/bash
n=1
while :
do
         printf "The current value of n=$n\n"
         if [ $n == 3 ]
         then
                   echo "good"
         elif [ $n == 5 ]
         then
                  echo "bad"
         elif [ $n == 7 ]
         then
                  echo "ugly"
         elif [ $n == 10 ]
         then
                   exit 0
         fi
         ((n++))
done
{% endhighlight %}

{% highlight result %}
The current value of n=1
The current value of n=2
The current value of n=3
good
The current value of n=4
The current value of n=5
bad
The current value of n=6
The current value of n=7
ugly
The current value of n=8
The current value of n=9
The current value of n=10
{% endhighlight %}

---

<br>

# 2. 반복문 for (Using For Loop) 문법

> `lists` 의 갯수만큼 `lists` 의 내용들을 `variable_name` 에 대입,  
> `do` 와 `done` 사이의 `commands`(명령)을 반복합니다.

{% highlight bash linenos %}
#!/bin/bash
for variable_name in lists
do
commands
done
{% endhighlight %}

<br>

>`condition`(조건)을주어 true 일 동안 `do` 와 `done` 사이의 `commands`(명령)을 반복합니다.  

{% highlight bash linenos %}
#!/bin/bash
for (( condition ))
do
commands
done
{% endhighlight %}

<br>

## 예제.1 - Reading static values

{% highlight bash linenos %}
#!/bin/bash
for color in Blue Green Pink White Red
do
    echo "Color = $color"
done
{% endhighlight %}

{% highlight result %}
Color = Blue
Color = Green
Color = Pink
Color = White
Color = Red
{% endhighlight %}

<br>

## 예제.2 - Reading Array Variable

{% highlight bash linenos %}
#!/bin/bash
ColorList=("Blue Green Pink White Red")
for color in $ColorList
do
if [ $color == 'Pink' ];then
    echo "My favorite color is $color"
fi
done
{% endhighlight %}

{% highlight result %}
My favorite color is Pink
{% endhighlight %}

<br>

## 예제.3 - Reading Command-line arguments

```bash
$ vi for3.sh
```
{% highlight bash linenos %}
for myval in $*
do
    echo "Argument: $myval"
done
{% endhighlight %}

{% highlight result %}
$ ./for3.sh I like ShellScript
Argument: I
Argument: like
Argument: ShellScript
{% endhighlight %}

<br>

## 예제.4 - Finding odd and even number using three expressions

{% highlight bash linenos %}
#!/bin/sh
for (( n=1; n<=5; n++ ))
do
if (( $n%2==0 ))
then
    echo "$n is even"
else
    echo "$n is odd"
fi
done
{% endhighlight %}

{% highlight result %}
1 is odd
2 is even
3 is odd
4 is even
5 is odd
{% endhighlight %}

<br>

## 예제.5 - Reading file content

```bash
$ vi for5.sh
```
{% highlight bash linenos %}
i=1
for var in `cat weekday.txt`
do
    echo "Weekday $i: $var"
    ((i++))
done
{% endhighlight %}

<br>

```bash
$ vi weekday.txt
```
{% highlight bash linenos %}
Sunday
Monday
Tuesday
Wednesday
Thursday
Friday
Saturday
{% endhighlight %}

<br>

{% highlight result %}
Weekday 1: Sunday
Weekday 2: Monday
Weekday 3: Tuesday
Weekday 4: Wednesday
Weekday 5: Thursday
Weekday 6: Friday
Weekday 7: Saturday
{% endhighlight %}
