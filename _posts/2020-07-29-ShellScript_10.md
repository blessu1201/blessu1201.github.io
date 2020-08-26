---
layout: article
title: ShellScript(10) - function(함수)
tags: [Linux, ShellScript]
key: 20200729_shell_script_10
---

{% include googlead.html %}

---

> 'function'(함수) 사용방법에 대해 알아보겠습니다.

<br>

## 예제.1 - Create Function

{% highlight bash linenos %}
#!/bin/bash
function F1()
{
echo 'I like bash programming'
}

F1
{% endhighlight %}

{% highlight result %}
I like bash programming
{% endhighlight %}

<br>

## 예제.2 - Create function with Parameters

{% highlight bash linenos %}
#!/bin/bash
Rectangle_Area() {
    area=$(($1 * $2))
    echo "Area is : $area"
}

Rectangle_Area 10 20
{% endhighlight %}

{% highlight result %}
Area is : 200
{% endhighlight %}

<br>

## 예제.3 - Pass Return Value from Function

{% highlight bash linenos %}
#!/bin/bash
function greeting() {
    str="Hello, $name"
    echo $str

}
    echo "Enter your name"
    read name

val=$(greeting)
    echo "Return value of the function is $val"
{% endhighlight %}

{% highlight result %}
Enter your name
kim
Return value of the function is Hello, kim
{% endhighlight %}

<br>

## 예제.4 - Using Global Variable

{% highlight bash linenos %}
#!/bin/bash
function F1()
{
    retval='I like programming'
}

    retval='I hate programming'
    echo $retval
F1
    echo $retval
{% endhighlight %}

{% highlight result %}
I hate programming
I like programming
{% endhighlight %}

<br>

## 예제.5 - Using Function Command

{% highlight bash linenos %}
#!/bin/bash
function F2()
{
    local  retval='Using BASH Function'
    echo "$retval"
}
    getval=$(F2)  
    echo $getval
{% endhighlight %}

{% highlight result %}
Using BASH Function
{% endhighlight %}

<br>

## 예제.6 - Using Variable

{% highlight bash linenos %}
#!/bin/bash
function F3()
{
    local arg1=$1

    if [[ $arg1 != "" ]];
    then
        retval="BASH function with variable"
    else
        echo "No Argument"
    fi
}
getval1="Bash Function"
F3 $getval1
    echo $retval
getval2=$(F3)
    echo $getval2
{% endhighlight %}

{% highlight result %}
BASH function with variable
No Argument
{% endhighlight %}

<br>

## 예제.7 - Using Return Statement

{% highlight bash linenos %}
#!/bin/bash
function F4() {
echo 'Bash Return Statement'
return 35
}

F4
echo "Return value of the function is $?"
{% endhighlight %}

{% highlight result %}
Bash Return Statement
Return value of the function is 35
{% endhighlight %}
