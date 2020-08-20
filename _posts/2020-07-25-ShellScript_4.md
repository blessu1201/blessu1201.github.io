---
layout: article
title: ShellScript(4) - read
tags: [Linux, ShellScript]
key: 20200725_shell_script_04
---

{% include googlead.html %}

## 리눅스 ShellScript 예제
---

출처 : <https://linuxhint.com/30_bash_script_examples/>

> `read` 를 사용하여 사용자가 입력을 할 수 있습니다.


<br>

### 예제.1 - Using simple read command

``` bash
$ vi read1.sh
#!/bin/bash
echo -n "What is your favorite food : "
read answer
echo "Oh! you like $answer!"
```
<pre>apple 을 입력해 보겠습니다.</pre>
```
$ ./read1.sh
What is your favorite food : apple
Oh! you like apple!
```

<br>

### 예제.2 - Using read command with options

``` bash
$ vi read2.sh
#!/bin/bash
# Type your Login Information
read -p 'Username: ' user
read -sp 'Password: ' pass

if [[ ( $user == "admin" && $pass == "12345" )]]
then
     echo -e "\nSuccessful login"
else
     echo -e "\nUnsuccessful login"
fi
```
<pre>-p 옵션은 입력을 위한 prompt를 활성화 시킵니다.
-s 옵션은 Secret mode 입니다.</pre>
```
$ ./read2.sh
Username: admin
Password:
Successful login
```
```
Username: test
Password:
Unsuccessful login
```

<br>

### 예제.3 - Using read command to take multiple inputs

``` bash
$ vi read3.sh
#!/bin/bash
# Taking multiple inputs
echo "Type four names of your favorite programming languages"
read lan1 lan2 lan3 lan4
echo "$lan1 is your first choice"
echo "$lan2 is your second choice"
echo "$lan3 is your third choice"
echo "$lan4 is your fourth choice"
```

```
$ ./read3.sh
Type four names of your favorite programming languages
java php c++ python
java is your first choice
php is your second choice
c++ is your third choice
python is your fourth choice
```

<br>

### 예제.4 - Using read command with the time limit

``` bash
$ vi read4.sh
#!/bin/bash
read -t 5 -p "Type your favorite color : " color
echo $color
```

<pre>-t 옵션은 일정시간 후에 입력대기를 종료하는 옵션입니다.
(여기서는 5초동안 입력이 없으면 자동종료됩니다.)</pre>
```
$ ./read4.sh
Type your favorite color : black
black
```
```
$ ./read4.sh
Type your favorite color :
$
```
