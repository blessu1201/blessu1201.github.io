---
layout: article
title: 파일처리_27 sed로 파일 치환 심볼릭 링크를 실제 파일로 바꾸지 않게 하기
tags: [Linux, ShellScript, sed, readlink]
key: 20240207-linux-sed,readlink
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: sed, readlink  
> 키워드: 심볼릭 링크, 파일 치환, 실제 파일   
> 사용처: sed 명령어 -i 옵션으로 심볼릭 링크를 대상으로 할 때


--- 

> 실행예제

```
$ ls -F
orig/	sed-symlink.sh*	target.txt@  #---------- 현재 디렉터리에 심볼릭 링크 target.txt@가 있고 orig/ 디렉터리에 실제 파일이 존재함

$ ls orig/
target.txt

$ ./sed-symlink.sh
$ ls -F
orig/	sed-symlink.sh*	target.txt@

$ ls -F orig/
target.txt	target.txt.bak  #----------------- 실제 파일이 바뀜
```

> 스크립트

```bash
#!/bin/sh
 
filename="target.txt"

if [ ! -e "$filename" ]; then  #---------------------------- 1
    # 대상 파일이 존재하지 않으면 에러 종료
    echo "ERROR: File not exists." >&2
    exit 1
elif [ -h "$filename" ]; then  #---------------------------- 2
    # 대상 파일이 심볼릭 링크면 readlink 명령어로 
    # 실제 파일을 대상으로 처리하기
    sed -i .bak "s/Hello/Hi/g" "$(readlink "$filename")"  #-- 3
else
    sed -i .bak "s/Hello/Hi/g" "$filename"
fi
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 **sed 명령어**의 **-i 옵션**으로 파일을 덮어쓸 때 심볼링 링크를 그대로 링크로 다룹니다. 현재 디렉터리에 target.txt라는 심볼릭 링크가 있고 이 링크의 실제 파일은 orig 디렉터리에 있다고 가정합니다. 이것은 ls 명령어에서도 -l 옵션으로 확인할 수 있습니다.

- 심볼릭 링크는 실제 파일을 가리킴
```
lrwxrwxrwx.	1 user1.user1	236	Dec 21 17:02 target.txt -> orig/target.txt
```

예제에서는 target.txt라는 심볼릭 링크를 대상으로 sed 명령어를 실행해서 "Hello"를 "Hi"로 치환합니다.

그리고 sed 명령어는 필터 명령어이므로 보통은 입력 파일을 덮어쓰지 않습니다. 따라서 치환한 결과로 원래 파일을 덮어쓰려면 중간 파일을 만들어야 합니다.

- 중간 파일을 만들어서 덮어쓰기
```
$ sed "s/Hello/Hi/g" target.txt > tmp
$ mv tmp target.txt
```

하지만 이런 중간 파일을 만들고 싶지 않다면 sed 명령어에 있는 원래 파일을 덮어쓰는 -i 옵션을 사용합니다.

-i 옵션을 쓸 때 원래 파일을 백업할 수 있습니다. 원래 파일에 .bak 확장자를 붙여서 백업하고 덮어쓰려면 다음과 같습니다. 치환한 결과 파일로 target.txt와 원래 파일의 백업 파일로 target.txt.bak이 만들어집니다.

```
sed -i .bak "s/Hello/Hi/g" target.txt
```

그런데 -i 옵션은 심볼릭 링크가 대상이면 묘해집니다. -i 옵션은 대상 파일이 심볼릭 링크라도 덮어쓰므로 예제의 경우 현재 디렉터리에 있는 심볼릭 링크를 치환한 내용으로 덮어씁니다. 그 결과 파일이 두개가 됩니다.

- 현재 디렉터리에 있는 치환 후 target.txt
- orig/ 디렉터리에 있는 원본 target.txt

이러면 관리상 문제가 생기므로 예제에서는 대상이 심볼릭 링크라면 처리를 변경합니다.  
`1`{:.info}에서 파일이 존재하는지 **test 명령어 -e 연산자**로 판정해서 파일이 아니면 **exit 명령어**로 종료합니다.

`2`{:.info}에서 test 명령어 **-h 연산자**로 대상 파일이 심볼릭 링크인지 확인합니다. 심볼릭 링크라면 `3`{:.info}에서 **readlink 명령어**로 실제 파일 경로를 얻어서 이 실제 파일을 대상으로 sed 명령어를 실행합니다. readlink 명령어는 다음처럼 심볼릭 링크를 인수로 실제 파일 경로를 표시합니다.

```
$ readlink target.txt
orig/target.txt
```

현재 디렉터리 target.txt는 orig/target.txt의 심볼릭 링크입니다.

이렇게 readlink 명령어 출력 결과를 sed 명령어로 처리하면 원래 파일을 덮어쓰므로 심볼릭 링크를 남긴 채 파일을 문제없이 처리할 수 있습니다.

&nbsp;
&nbsp;

## **주의사항**

- 리눅스 sed는 심볼릭 링크 출처를 쫓아가는 **--follow-symlinks**라는 옵션이 있습니다. 이 옵션을 쓰면 예제는 다음처럼 간결해집니다. 이때 대상 파일이 일반 파일이면 그 파일을 대상으로 처리하고 심볼릭 링크면 링크 원본 파일을 처리하므로 링크는 망가지지 않습니다.
```
sed -i .bak --follow-symlinks "s/Hello/Hi/g" "$filename"
```
