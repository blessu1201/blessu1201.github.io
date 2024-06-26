---
layout: article
title: 사용자 인터페이스_04 암호 입력 시 사용자 키 입력을 표시하지 않기
tags: [Linux, ShellScript, stty, read, wget, curl]
key: 20240414-linux-stty-read-wget-curl
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: stty, read, wget, curl  
> 키워드: 암호  
> 사용처: 사용자가 암호를 입력하는 처리에서 입력된 문자열을 화면에 표시하고 싶지 않을 때

--- 

> 실행예제

```
$ ./pass_wget.sh
Password :   <--------- 입력한 값이 표시되지 않음
```

> 스크립트

```bash
#!/bin/sh

username=guest
hostname=localhost

echo -n "Password: "

#에코백 OFF(-echo)
stty -echo  #------------------------------------- 1
read password  #---------------------------------- 2

#에코백 ON(echo)
stty echo  #-------------------------------------- 3

echo

# 입력한 암호로 내려받기
wget -q --password="$password" "ftp://${username}@${hostname}/filename.txt"  #--- 4
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 사용자로부터 암호를 입력받아 ftp 사이트에서 파일을 내려받습니다. 암호 입력 시 화면에 입력값을 표시하지 않도록 합니다. 사용자 키 입력을 **read 명령어**로 획득할 때 입력된 문자는 그대로 화면에 표시됩니다. 당연한 듯하지만 이는 에코백이라는 기능으로 입력된 문자를 화면에 표시하도록 터미널에 설정되어 있기 때문에 가능한 일입니다. 암호를 입력받는 프로그램은 누군가가 화면을 훔쳐볼 위험성이 있습니다. 대응책으로 입력된 문자가 화면에 표시되지 않도록 **에코백을 끄는 게(off)** 보통입니다.

에코백하지 않도록 설정하려면 `1`{:.info}처럼 터미널 설정을 변경하는 **stty 명령어**로 -echo를 지정합니다. 이러면 에코백되지 않아서 입력한 문자가 화면에 표시되지 않습니다. 입력된 암호는 read 명령어로 셸 변수 password에 대입됩니다`2`{:.info}. 이대로 두면 에코백하지 않는 설정이 그대로 남으므로 암호 입력이 끝나면 `3`{:.info}처럼 stty 명령어로 echo를 지정해서 원래 상태로 되돌립니다. 이렇게 하면 터미널은 다시 에코백하므로 입력한 문자가 그대로 표시됩니다.

예제에서 입력한 암호를 써서 **wget 명령어**로 ftp 서버에서 파일을 내려받습니다. wget 명령어로 사용자명, 암호를 입력할 때  `4`{:.info}처럼 **--password 옵션** 인수에 암호를 지정하고 내려받을 호스트명 앞에 @을 붙여서 사용자명을 입력합니다. 또한 wget 명령어에 동작 상태가 출력되지 않게 **-q 옵션**(quit 모드)을 써서 파일 내려받기만 하도록 지정합니다.

&nbsp;
&nbsp;

## **주의사항**

- 에코백 기능을 잘 모르겠으면 터미널 창에서 다음 명령어를 실행합니다.

  ```
  stty -echo
  ```

  그러면  이후부터는 명령어를 입력해도 화면에는 표시되지 않지만 `Enter`를 누르면 명령어 실행 결과가 표시됩니다. 원래대로 돌리려면(보이진 않지만) stty echo라고 입력하고 `Enter` 키를 누릅니다. 그러면 다시 키 입력이 표시됩니다.

- Mac에는 wget이 설치되어 있지 않습니다. 대시 **curl 명령어**를 써서 다음처럼 입력합니다.

  ```
  curl -s -u "${username}:${password}" -O "ftp://${hostname}/filename.txt"
  ```