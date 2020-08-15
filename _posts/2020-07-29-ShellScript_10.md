---
title: ShellScript(10) - function(함수)
date: 2020-07-29
categories: [Linux, ShellScript]
tags: [Linux, ShellScript, function]
comments: true
seo:
  date_modified: 2020-08-15 16:59:05 +0900
---

## 리눅스 ShellScript 예제
---

> 'function'(함수) 사용방법에 대해 알아보겠습니다.

<br>

##### 예제.1 - Create Function

``` bash
#!/bin/bash
function F1()
{
echo 'I like bash programming'
}

F1
```
```
$ ./func1.sh
I like bash programming
```

<br>

##### 예제.2 - Create function with Parameters

``` bash
#!/bin/bash
Rectangle_Area() {
    area=$(($1 * $2))
    echo "Area is : $area"
}

Rectangle_Area 10 20
```
```
$ ./func2.sh
Area is : 200
```
<br>

##### 예제.3 - Pass Return Value from Function

``` bash
#!/bin/bash
function greeting() {
    str="Hello, $name"
    echo $str

}
    echo "Enter your name"
    read name

val=$(greeting)
    echo "Return value of the function is $val"
```
```
$ ./func3.sh
Enter your name
kim
Return value of the function is Hello, kim
```
<br>

##### 예제.4 - Using Global Variable

``` bash
#!/bin/bash
function F1()
{
    retval='I like programming'
}

    retval='I hate programming'
    echo $retval
F1
    echo $retval
```
```
$ sh func4.sh
I hate programming
I like programming
```
<br>

##### 예제.5 - Using Function Command

``` bash
#!/bin/bash
function F2()
{
    local  retval='Using BASH Function'
    echo "$retval"
}
    getval=$(F2)  
    echo $getval
```
```
$ ./func5.sh
Using BASH Function
```
<br>

##### 예제.6 - Using Variable

``` bash
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
```
```
$ ./func6.sh
BASH function with variable
No Argument
```
<br>

##### 예제.7 - Using Return Statement

``` bash
#!/bin/bash
function F4() {
echo 'Bash Return Statement'
return 35
}

F4
echo "Return value of the function is $?"
```
```
$ ./func7.sh
Bash Return Statement
Return value of the function is 35
```
