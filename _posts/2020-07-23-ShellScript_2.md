---
title: ShellScript(2) - echo , 주석처리
date: 2020-07-23
categories: [Linux, ShellScript]
tags: [Linux, ShellScript, echo, 주석처리]
comments: true
seo:
  date_modified: 2020-08-15 16:59:05 +0900
---

## 리눅스 ShellScript(2)
---

출처 : <https://linuxhint.com/30_bash_script_examples/>

>리눅스 쉘스크립트예제를 통해서 기본적인 문법을 익혀보도록 하겠습니다.<br>
>저는 vim을 사용했지만, 각자 기호에 맞는 에디터를 사용하시면 됩니다.<br>
>화면출력(echo)와 주석처리에 대해 살펴보겠습니다.

<br>

#### 1.  스크립트 생성 및 실행 (Create and Execute First BASH Program)

_echo 명령으로_ **Hello World**  _를 출력해 봅시다._

```
$ vi first.sh
```

``` bash
#!/bin/bash
echo "Hello World"
```
_만들어진 shell 파일을 실행해 봅시다._
```
$ sh first.sh
```
또는 .sh 파일에 실행권한을 부여한 후 실행하셔도 됩니다.
```
$ chmod a+x first.sh
$ ./first.sh
```
실행결과
```
Hello World
```

<br>

#### 2. echo 명령 옵션 (Use of echo command)

```
$ vi echo_example.sh
```
``` bash
#!/bin/bash
echo "Printing text with newline"
echo -n "Printing text without newline"
echo -e "\nRemoving \t backslash \t characters\n"
```
_실행결과_
```
Printing text with newline
Printing text without newline
Removing         backslash       characters

```
<pre>- echo 에 옵션을 주지 않으면 줄을 바꿔서 출력
- echo -n 옵션을 주면 줄을 바꾸지 않고 출력
- echo -e 옵션을 주면 출력시 \ 문자를 출력하지않고 \n 줄바꿈, \t 탭 으로 사용이 가능</pre>

<br>

#### 3. 주석 (use of comment)

_주석을 입력하는 방법에는 아래 3가지 방법이 있습니다._

1. `# 한 줄 주석`
2. `:' 여러 줄 주석 '`
3. `<<word 여러 줄 주석 word`

<br>

``` bash
#!/bin/bash

# Add two numeric value
((sum=25+35))

#Print the result
echo $sum
```

_실행결과_
```
60
```

``` bash
#!/bin/bash
: '
The following script calculates
the square value of the number, 5.
'
((area=5*5))
echo $area
```
_실행결과_
```
25
```
``` bash
#!/bin/bash
<<LongComment
여기에 주석을 입력하세요.
여러줄로 입력해도 됩니다.
LongComment 외에 사용하고 싶은 단어를 사용해도 됩니다.
LongComment
n=5
#Calculate 5 to the power 3
((result=$n*$n*$n))
#Print the area
echo $result
```
_실행결과_
```
125
```
