---
title: ShellScript(11) - read a File
date: 2020-07-30
categories: [Linux, ShellScript]
tags: [Linux, ShellScript, read_a_file]
comments: true
seo:
  date_modified: 2020-08-15 16:59:05 +0900
---

## 리눅스 ShellScript 예제
---

> 데이터 파일을 만들어 Script 에서 가져다 사용하는 방법을알아보겠습니다.

<br>

### 예제.1 - Read a File

``` bash
$ vi read_file.sh
#!/bin/bash
file='book.txt'
while read line; do
        echo $line
done < $file
```
```
$ vi book.txt
1. Pro AngularJS
2. Learning JQuery
3. PHP Programming
4. CodeIgniter 3
```
```
$ ./read_file.sh
1. Pro AngularJS
2. Learning JQuery
3. PHP Programming
4. CodeIgniter 3
```
<br>

### 예제.2 - Reading file content from command line

```bash
$ vi company.txt
Samsung
Nokia
LG
Symphony
iphone
```
```
$ while read line; do echo $line; done < company.txt
Samsung
Nokia
LG
Symphony
iphone
```
<br>

### 예제.3 - Reading file content using script

```bash
$ vi readfile3.sh
#!/bin/bash
filename='company.txt'
n=1
while read line; do
# reading each line
    echo "Line No. $n : $line"
    n=$((n+1))
done < $filename
```
```
$ ./readfile2.sh
Line No. 1 : Samsung
Line No. 2 : Nokia
Line No. 3 : LG
Line No. 4 : Symphony
Line No. 5 : iphone
```
<br>

### 예제.4 - Passing filename from the command line and reading the file

``` bash
$ vi readfile4.sh
#!/bin/bash
filename=$1
while read line; do
# reading each line
    echo $line
done < $filename
```
```
$ ./readfile4.sh company.txt
Samsung
Nokia
LG
Symphony
iphone
```
<br>

### 예제.5 - Reading file by omitting backslash escape

``` bash
$ ./readfile5.sh
#!/bin/bash
while read -r line; do
# Reading each line
    echo $line
done < company2.txt
```

`-r` 옵션을 주면 \ (escape) 문자를 그대로 출력할 수 있습니다.

```
$ sh readfile5.sh company2.txt
\Samsu\ng
\Nokia
\LG
\Symphony
\Apple
```
