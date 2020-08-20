---
layout: article
title: ShellScript(11) - read a File
tags: [Linux, ShellScript]
key: 20200730_shell_script_11
---

## 리눅스 ShellScript 예제
---

데이터 파일을 만든 후 ShellScript에서 사용하는 방법을 알아보겠습니다.
{:.warning}


<br>

### 예제.1 - Read a File

``` bash
$ vi read_file.sh
```

{% highlight bash linenos %}
#!/bin/bash
file='book.txt'
while read line; do
        echo $line
done < $file
{% endhighlight %}

<br>

``` bash
$ vi book.txt
```
{% highlight bash linenos %}
1. Pro AngularJS
2. Learning JQuery
3. PHP Programming
4. CodeIgniter 3
{% endhighlight %}

<br>

``` bash
$ ./read_file.sh
```
{% highlight result %}
Pro AngularJS
Learning JQuery
PHP Programming
CodeIgniter 3
{% endhighlight %}

<br>

### 예제.2 - Reading file content from command line

``` bash
$ vi company.txt
```

{% highlight bash linenos %}
Samsung
Nokia
LG
Symphony
iphone
{% endhighlight %}

``` bash
$ while read line; do echo $line; done < company.txt
```

{% highlight result %}
Samsung
Nokia
LG
Symphony
iphone
{% endhighlight %}

<br>

### 예제.3 - Reading file content using script

```bash
$ vi readfile3.sh
```
{% highlight bash linenos %}
#!/bin/bash
filename='company.txt'
n=1
while read line; do
# reading each line
    echo "Line No. $n : $line"
    n=$((n+1))
done < $filename
{% endhighlight %}

``` bash
$ ./readfile2.sh
```

{% highlight result %}
Line No. 1 : Samsung
Line No. 2 : Nokia
Line No. 3 : LG
Line No. 4 : Symphony
Line No. 5 : iphone
{% endhighlight %}

<br>

### 예제.4 - Passing filename from the command line and reading the file

``` bash
$ vi readfile4.sh
```

{% highlight bash linenos %}
#!/bin/bash
filename=$1
while read line; do
# reading each line
    echo $line
done < $filename
{% endhighlight %}

```bash
$ ./readfile4.sh company.txt
```

{% highlight result %}
Samsung
Nokia
LG
Symphony
iphone
{% endhighlight %}

<br>

### 예제.5 - Reading file by omitting backslash escape

> `-r`{:.info} 옵션을 주면 \ (escape) 문자를 그대로 출력할 수 있습니다.

``` bash
$ ./readfile5.sh
```

{% highlight bash linenos %}
#!/bin/bash
while read -r line; do
# Reading each line
    echo $line
done < company2.txt
{% endhighlight %}


```bash
$ sh readfile5.sh company2.txt
```

{% highlight result %}
\Samsu\ng
\Nokia
\LG
\Symphony
\Apple
{% endhighlight %}
