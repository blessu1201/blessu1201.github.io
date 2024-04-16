---
layout: article
title: 사용자 인터페이스_07 선택식 메뉴를 표시해서 입력된 숫자값 처리하기
tags: [Linux, ShellScript, read, case]
key: 20240417-linux-read-case
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: read, case  
> 키워드: 표준 입력, 키보드  
> 사용처: 키보드로 입력한 값을 써서 대화식 처리를 하고 싶을 때

--- 

> 실행예제

```
$ ./select.sh
Menu :
1) list file
2) current directory
3) exit
2
/home/user/

Menu :
1) list file
2) current directory
3) exit
3
```

> 스크립트

```bash
#!/bin/sh

while :
do
  echo "Menu"
  echo "1) list file"
  echo "2) current directory"
  echo "3) exit"

  read number  #---------------------- 1
  case $number in  #------------------ 2
    1)
      ls
      ;;
    2)
      pwd
      ;;
    3)
      exit
      ;;
    *)  #----------------------------- 3
      echo "Error: Unknown Command"
      ;;
  esac

  echo
done
```

&nbsp;
&nbsp;

## **해설**

번호가 적힌 메뉴를 표시해서 사용자에게 값을 입력받아 지정한 번호를 처리합니다.

이런 메뉴가 있는 스크립트를 만들 때는 번호와 처리 내용을 echo 명령어로 표시하고, 사용자 입력을 **read 명령어**로 얻어서 입력 내용을 **case문**으로 판단해서 분기하는 방법이 자주 쓰입니다. read 명령어는 `1`{:.info}처럼 셸 변수를 인수로 지정하면 표준 입력(여기에서는 키보드 입력)을 셸 변수에 대입할 수 있습니다. 이 예제에서 셸 변수 number에 사용자가 키보드로 입력한 값이 들어갑니다.

이어서 `2`{:.info} case문에서 입력된 메뉴 번호에 따른 처리를 합니다. 1이 입력되면 현재 디렉터리 파일을 ls 명령으로 표시, 2는 현재 디렉터리를 pwd 명령어로 실행, 3은 exit 명령어로 종료합니다. 입력에 따른 분기는 if문으로도 가능하지만 이 예제처럼 셸 변수값으로 분기할 때는 case 문을 쓰는 것이 편리합니다. 명령어 실행 후 원래 메뉴로 돌아가기 위해서 전체를 while 문으로 무한 반복합니다.

한편, 사용자 입력값으로 숫자를 입력받는다고 가정하고 있지만 문자열을 입력하는 등 예상하지 못한 입력값이 있기도 합니다. `3`{:.info}처럼 case 문 마지막에 *를 쓰면 지금까지의 조건에 일치하지 않는 값을 처리합니다. 스크립트가 의도하지 않은 동작을 하지 않도록 이런 에러 처리를 잊지 맙시다.

