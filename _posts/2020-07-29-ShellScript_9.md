---
layout: article
title: ShellScript(9) - Arithmetic Operations (산술연산)
tags: [Linux, ShellScript]
---

{% include googlead.html %}

## 리눅스 ShellScript 예제
---

> 산술연산 방법에 대해 알아보겠습니다.

<br>

##### 예제.1 - Using ‘expr’ command

``` bash
#!/bin/bash

# Works as string
expr '10 + 30'

# Works as string
expr 10+30

#Perform the addition
expr 10 + 30

#Find out the remainder value
expr 30 % 9

#Using expr with backtick
myVal1=`expr 30 / 10`
    echo $myVal1

#Using expr within command substitute
myVal2=$( expr 30 - 10 )
    echo $myVal2
```
```
$ ./arith1.sh
10 + 30
10+30
40
3
3
20
```
<br>

##### 예제.2 - Using ‘expr’ command

``` bash
#!/bin/bash

# Multiplying 9 by 8
let val1=9*3
    echo $val1

# Dividing 8 by 3
let "val2 = 8 / 3"
    echo $val2

# Subtracting 3 from 9
let val3=9-3
    echo $val3

# Applying increment
let val4=7
let val4++
    echo $val4

# Using argument value in arithmetic operation
let "val5=50+$1"
    echo $val5
```
<pre>마지막 Script에는 $1 이 있으므로 인수를 1개 적어줘야 합니다. 없으면 에러가발생합니다.</pre>
```
$ ./arith2.sh 60
27
2
6
8
110
```
<br>

##### 예제.3 - Using double brackets

``` bash
#!/bin/bash

# Calculate the mathematical expression
val1=$((10*5+15))
    echo $val1

# Using post or pre increment/decrement operator
((val1++))
    echo $val1
val2=41
((--val2))
    echo $val2

# Using shorthand operator
(( val2 += 60 ))
    echo $val2

# Dividing 40 by 6
(( val3 = 40/6 ))
    echo $val3
```
```
$ ./arith3.sh
65
66
40
100
6
```

<br>

##### 예제.4 - Using ‘bc’ command for float or double numbers

``` bash
#!/bin/bash

# Dividing 55 by 3 with bc only
echo "55/3" | bc

# Dividing 55 by 3 with bc and -l option
echo "55/3" | bc -l

# Dividing 55 by 3 with bc and scale value
echo "scale=2; 55/3" | bc

#거듭제곱
echo "2^10" | bc
```
<pre>bc(basic calculator)는 리눅스 기본계산기 입니다.</pre>
```
$ ./arith4.sh
18
18.33333333333333333333
18.33
1024
```
