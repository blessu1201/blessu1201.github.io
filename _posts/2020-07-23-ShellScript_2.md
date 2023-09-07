---
layout: article
title: ShellScript(2) - echo , 주석처리
tags: [Linux, ShellScript]
key: 20200723_shell_script_02
---

- 출처 : <https://linuxhint.com/30_bash_script_examples/>

>리눅스 쉘스크립트예제를 통해서 기본적인 문법을 익혀보도록 하겠습니다.  
>저는 vim을 사용했지만, 각자 기호에 맞는 에디터를 사용하시면 됩니다.  
>화면출력(echo)와 주석처리에 대해 살펴보겠습니다.

<br>

## 1.  ShellScript 생성 및 실행

> echo 명령으로 Hello World 를 출력해 봅시다.

```bash
$ vi first.sh
```

{% highlight bash linenos %}
#!/bin/bash
echo "Hello World"
{% endhighlight %}

> 만들어진 shell 파일을 실행해 봅시다.

```bash
$ sh first.sh
```
> 또는 .sh 파일에 실행권한을 부여한 후 실행하셔도 됩니다.

```bash
$ chmod a+x first.sh
$ ./first.sh
```

{% highlight result %}
Hello World
{% endhighlight %}

<br>

## 2. echo 명령 옵션 (Use of echo command)

```bash
$ vi echo_example.sh
```

{% highlight bash linenos %}
#!/bin/bash
echo "Printing text with newline"
echo -n "Printing text without newline"
echo -e "\nRemoving \t backslash \t characters\n"
{% endhighlight %}

{% highlight result %}
Printing text with newline
Printing text without newline
Removing         backslash       characters

{% endhighlight %}

- echo 에 옵션을 주지 않으면 줄을 바꿔서 출력
- echo -n 옵션을 주면 줄을 바꾸지 않고 출력
- echo -e 옵션을 주면 출력시 \ 문자를 출력하지않고 \n 줄바꿈, \t 탭 으로 사용이 가능

<br>

## 3. 주석 (use of comment)

> 주석을 입력하는 방법에는 아래 3가지 방법이 있습니다.

1. `#`{:.info} 한 줄 주석
2. `:'`{:.warning} 여러 줄 주석 `'`{:.warning}
3. `<<word`{:.success} 여러 줄 주석 `word`{:.success}

<br>

{% highlight bash linenos %}
#!/bin/bash

# Add two numeric value
((sum=25+35))

#Print the result
echo $sum
{% endhighlight %}


{% highlight result %}
60
{% endhighlight %}

<br>

{% highlight bash linenos %}
#!/bin/bash
: '
The following script calculates
the square value of the number, 5.
'
((area=5*5))
echo $area
{% endhighlight %}

{% highlight result %}
25
{% endhighlight %}

<br>

{% highlight bash linenos %}
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
{% endhighlight %}

{% highlight result %}
125
{% endhighlight %}
