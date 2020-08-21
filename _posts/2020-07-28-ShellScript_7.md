---
layout: article
title: ShellScript(7) - argument , getopts
tags: [Linux, ShellScript]
key: 20200728_shell_script_07
---

{% include googlead.html %}

## 리눅스 ShellScript 예제
---

> `argument` 명령줄에서 인수를 처리하는 방법입니다.<br>

인수는 $0에서 시작합니다.  
스크립트 파일이름이 $0, 파일 이름 뒤에 2개의 인수가 전달되면,  
$1, $2 변수에 순차적으로 수신됩니다.

<br>

### 예제.1 - Sending three numeric values as arguments

{% highlight bash linenos %}
#!/bin/bash

# Counting total number of arguments
    echo "Total number of arguments : $#"

# Reading argument values individually
    echo "First argument value : $1"
    echo "Second argument value : $2"
    echo "Third argument value : $3"

# Reading argument values using loop
for argval in "$@"
do
    echo -n "$argval  "
done

# Adding argument values
sum=$(($1+$2+$3))

# print the result
echo -e "\nResult of sum = $sum"
{% endhighlight %}

{% highlight result %}
$ sh argu1.sh 10 15 20
Total number of arguments : 3
First argument value : 10
Second argument value : 15
Third argument value : 20
10  15  20  
Result of sum = 45
{% endhighlight %}

<br>

### 예제.2 - Taking filename as argument

```bash
$ vi argu2.sh
```

{% highlight bash linenos %}
#!/bin/bash
filename=$1
totalchar=`wc -c $filename`
    echo "Total number of characters are $totalchar"
{% endhighlight %}

```bash
$ vi argu_test.txt
abcde
fghij
klmno
```
{% highlight result %}
$ ./argu2.sh argu_test.txt
Total number of characters are 18 argu_test.txt
{% endhighlight %}

<br>

### 예제.3 - Reading arguments by getopts function

{% highlight bash linenos %}
#!/bin/bash
while getopts ":i:n:m:e:" arg; do
  case $arg in
    i) ID=$OPTARG;;
    n) Name=$OPTARG;;
    m) Manufacturing_date=$OPTARG;;
    e) Expire_date=$OPTARG;;
  esac
done
echo -e "\n$ID  $Name   $Manufacturing_date $Expire_date\n"
{% endhighlight %}

{% highlight result %}
$ ./getops.sh -i c01 -n 'hot cake' -m 2020-07-20 -e 2020-12-31

c01  hot cake   2020-07-20 2020-12-31
{% endhighlight %}
