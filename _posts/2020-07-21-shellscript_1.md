---
layout: article
title: ShellScript(1) - 연산자
tags: [Linux, ShellScript]
key: 20200721_shell_script_01
---

> Linux Shell Script의 기본적인 내용을 정리합니다.

<br>

## 1. 파일관련연산

| 파일관련연산자 | 의미 |
|:---:|:------------------:|
|`-d` | 파일이 디렉토리인지 체크 |
|`-e` | 파일이 존재하는지 체크 |
|`-a` | 파일이 존재하는지 체크 |
|`-r` | 파일이 읽기 가능인지 체크 |
|`-w` | 파일이 쓰기 가능인지 체크 |
|`-x` | 파일이 실행 가능인지 체크 |
|`-o` | 사용자가 해당파일의 소유자인지 체크 |
|`-z` | 해당파일의 크기가 0이면 참 |
|`-f` | 파일이 일반적인 파일인지 체크 |
|`-g` | 파일이 SGID 퍼미션을 가졌는지 체크 |
|`-s` | 파일의 크기가 0이 아닌지 체크<br>(0이 아니면 true 0이면 false) |
|`-u` | 파일이 SUID 퍼미션을 가졌는지 체크 |
|`-h` | 심볼릭 링크파일 |


예) test에서 -f 연산자를 사용하여 일반적인 파일인지 체크

```
if test -f /etc/passwd
then
```
<br>

예) 대괄호가 test 역할을 함. 대괄호 앞뒤 사이에 공백문자가 있어야함.
```
if [ -f /etc/passwd ];then
```

<br>

## 2. 산술비교 연산자

| 연산자 | 의미 |
|:--:|:--:|
| x `-eq` y | x가 y와 같은지 체크 |
| x `-ne` y | x가 y와 같지 않은지 체크 |
| x `-lt` y | x가 y 보다 작은지 체크 |
| x `-le` y | x가 y 보다 작거나 같은지 체크 |
| x `-gt` y | x가 y 보다 큰지 체크 |
| x `-ge` y | x가 y 보다 크거나 같은지 체크 |

<br>

## 3. 문자열 비교연산자

| 연산자 | 의미 |
|:--:|:--:|
| x `=` y |  문자열 x가 문자열 y와 같은지 체크 |
| x `!=` y | 문자열 x가 문자열 y와 다른지 체크 |
| `-n` x  | 문자열 x가 널 문자가 아니면 true로 간주함 |
| `-z` x |  문자열 x가 널 문자이면 true로 간주함. |

<br>

## 4. 논리연산

```
조건1 -a 조건2         # AND
조건1 -o 조건2         # OR
조건1 && 조건2         # 양쪽 다 성립
조건1 || 조건2         # 한쪽 또는 양쪽다 성립
!조건                 # 조건이 성립하지 않음
true                 # 조건이 언제나 성립
false                # 조건이 언제나 성립하지 않음
```

<br>

## 5. 산술연산예제

{% highlight bash lineos %}
#!/bin/bash

#변수
a=9
b=4

echo "a 값:" $a
echo "b 값:" $b

#연산
c=`expr $a + $b`
d=$((a*b))
let e=a-b

#결과
echo " 'expr $a + $b' 의 결과: " $c
echo " '\$((a*b))'의 결과: " $d
echo " 'let e=a-b'의 결과: " $e
{% endhighlight %}

<br>

{% highlight result lineos %}
a 값: 9
b 값: 4
 'expr $a + $b' 의 결과:  13
 '$((a*b))'의 결과:  36
 'let e=a-b'의 결과:  5
{% endhighlight %}
