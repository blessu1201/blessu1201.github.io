---
title: ShellScript(8) - String
date: 2020-07-28
categories: [Linux, ShellScript]
tags: [Linux, ShellScript, String (문자열)]
comments: true
seo:
  date_modified: 2020-08-15 16:59:05 +0900
---

## 리눅스 ShellScript 예제
---


> `String` (문자열)에 관한 내용입니다.

<br>

##### 예제.1 - Combine String variables

``` bash
#!/bin/bash

string1="Linux"
string2="Hint"
    echo "$string1$string2"
string3=$string1+$string2
string3+=" is a good tutorial blog site"
    echo $string3
```
```
$ ./string1.sh
LinuxHint
Linux+Hint is a good tutorial blog site
```

<br>

##### 예제.2 - Get substring of String

``` bash
#!/bin/bash
Str="Learn Linux from LinuxHint"
subStr=${Str:6:5}
    echo $subStr
```
```
$ ./string2.sh
Linux
```
