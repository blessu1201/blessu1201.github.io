---
layout: article
title: 사용자 인터페이스_01 명령어 옵션 처리하기
tags: [Linux, ShellScript, getopts, case, shift]
key: 20240411-linux-getopts-case-shift
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: getopts, case, shift  
> 키워드: 옵션, 플래그, 명령행 인수  
> 사용처: 스크립트에서 (-a 같은) 옵션을 해석해서 동작을 변경할 때

--- 

> 실행예제

```
$ ./getopts.sh -a -p '=====sep=====' /home/user1/docs
. .. a.txt readme.txt
=====sep=====
```

> 스크립트

```bash
#!/bin/sh

# -a 옵션이 있는지 플래그 변수 a_flag와
# -p 옵션의 구분자를 정의하기
a_flag=0  #----------------------------------------------------------- 1
separator=""  #------------------------------------------------------- 1
while getopts "ap:" option  #----------------------------------------- 2
do
  case $option in
    a)
      a_flag=1  #----------------------------------------------------- 3
      ;;
    p)
      separator="$OPTARG"  #------------------------------------------ 4
      ;;
    \?)  #------------------------------------------------------------ 5
      echo "Usage: getopts.sh [-a] [-p separator] target_dir" 1>&2
      exit 1
    ;;
  esac
done

# 옵션 지정을 위치 파라미터에서 삭제하기
shift $(expr $OPTIND - 1)  #------------------------------------------ 6
path="$1"  #---------------------------------------------------------- 7

# -a 옵션이 지정되었는지 셸 변수 a_flag 값으로 판단하기
if [ $a_flag -eq 1 ]; then  #----------------------------------------- 8(if문)
  ls -a -- "$path"
else
  ls -- "$path"
fi

if [ -n "$separator" ]; then  #--------------------------------------- 9(if문)
  echo "$separator"
fi
```

&nbsp;
&nbsp;

## **해설**

유닉스 명령어는 실행할 때 다양한 파라미터를 지정하는 것이 보통입니다. 예를 들어 파일을 복사하는 cp 명령어는 파일이 존재하더라도 확인 없이 덮어쓰기가 기본값이지만 -i를 붙이면 다음 처럼 덮어쓰기 전에 확인을 받습니다.

- 덮어쓰기 전에 확인하기

  ```
  $ cp -i old.txt new.txt
  cp: overwrite 'new.txt'?
  ```

위에서 -i가 **옵션**입니다. 또한 이 예제에서 "-i old.txt new.txt"라는 명령어에 딸린 파라미터를 합쳐서 **명령행 인수**라고 부릅니다. 이렇게 옵션을 쓰게 되면 같은 명령어라도 기본값과 다른 동작을 하거나 특정 파라미터를 지정할 수 있습니다. 마찬가지로 셸 스크립트에서도 옵션을 지정해서 기본 동작을 변경하고 싶을 때가 있습니다. 옵션은 보통 -(하이픈)으로 시작하므로 명령행 인수를 스스로 해석해서 처리 분기를 만들면 구현 가능하지만 좀 귀찮은 작업입니다. 그것보다는 옵션 해석을 하는 전용 내부 명령어, **getopts** 명령어를 쓰면 편리합니다.

이 스크립트 예제에서는 현재 디렉터리에 있는 파일명 목록을 표시할 뿐이지만 옵션에 따라 다소 동작이 달라지는 것을 알 수 있습니다. -a 옵션을 쓰면 숨은 파일(.으로 시작하는 파일)도 표시하며 -p 옵션을 쓰면 마지막 줄에 구분자로 표시할 문자열을 지정할 수 있습니다.

또한, 기본값은 현재 디렉터리를 표시하지만 명령행 인수로 디렉터리를 지정하면 그 디렉터리가 대상 디렉터리가 됩니다. 이제부터 getopts 명령어 사용법을 알아봅시다. 작성법이 조금 까다로우므로 집중해 주세요.

우선 `1`{:.info}은 -a 옵션이 지정되었는지 판단하는 셸 변수 a_flag를 선업합니다. 이런 변수는 플래그(flag)라고 부르며 0으로 초기화하고 설정되면 1로 바꾸는 것이 일반적입니다.

`2`{:.info}에서 실제로 getopts로 옵션을 해석합니다. 옵션에 사용된 문자는 getopts 인수로 나열하며 그 옵션 자체가 인수를 받는 것은 콜론으로 지정합니다. 즉, "ap:"는 'a 옵션과 p 옵션을 이용한다. 그리고 p 옵션은 인수를 받는다'라는 의미입니다. getopts는 옵션을 앞에서 순서대로 처리합니다. getopts의 두 번째 인수는 셸 변수(스크립트의 option)를 지정합니다. 사용자가 입력한 옵션은 이 셸 변수 option에 대입되므로 다음 case 문에서 변수 option값에 따라 분기해서 입력된 옵션에 따른 처리를 수행합니다.

이런 getopts를 쓸 때 'while문 조건식으로 getopts를 쓰고 while 루프 내부의 case문으로 판단한다.'는 것은 거의 원칙이므로 잘 기억해두기 바랍니다.

예제에서 우선 'a 옵션이 지정되었을 때는 a_flag를 1로 바꾸고 a 옵션이 지정되었다'는 플래그를 설정합니다`3`{:.info}. 한편, 인수를 받는 옵션(즉 getopts에 콜론을 지정한 옵션)에서 그 인수는 OPTARG라는 셸 변수에 들어갑니다. `4`{:.info}에서는 그 값을 separator라는 셸 변수에 대입합니다. 이것은 마지막 출력에서 사용합니다.

지금까지 일치하지 않은 옵션을 `5`{:.info}에서 처리합니다. getopts에서는 무효한 옵션이 지정되면 "?"이 대입되므로 이걸 case 문에서 처리합니다. `5`{:.info}의 case 처리에 도착하면 옵션 지정에 에러가 있으므로 다음처럼 에러 메시지를 출력하며 종료합니다.

- 무효한 옵션이 지정되면

  ```
  $ ./getopts.sh -a -z
  ./getopts.sh : illegal option -- z
  Usage: getopts.sh [-a] [-p separator] target_dir
  ```

실행 예제를 보면 이 스크립트에 존재하지 않는 "illegal option"이라는 에러가 출력됩니다. 이것은 getopts 명령어 기능으로 정의되지 않은 옵션이 입력되면 자동으로 출력됩니다.

이어진 `6`{:.info}은 좀 어렵습니다. 관용적인 표현으로 통째로 외우는게 좋습니다. 이해를 돕기 위해 설명합니다.

이 줄의 목적은 명령행 인수를 **위치 파라미터**($1, $2, ...)로 처리하기 위함입니다. 원래 위치 파라미터는 옵션도 파라미터도 함께 $1, $2, $3, ... 으로 저장됩니다.

- 명령행 인수의 위치 파라미터

  ```
  $ ./getopts.sh -a -p /home/user1/docs /tmp
                $1 $2        $3         $4
  ```

getopts 명령어로 옵션 해석이 끝난 다음에 셸 변수 **OPTIND**는 '다음에 처리할 위치 파라미터 번호'를 나타냅니다. 위 예제에서라면 4가 됩니다.

여기서 OPTIND에서 1을 뺀 값으로 **shift 명령어**를 실행하면 옵션 부분을 무시하고 '진짜 명령행 인수'를 순서대로, 즉 $1, $2, $3으로 다룰 수 있습니다. 즉, shift $(expt $OPTIND -1)하면 $1에 /tmp가 들어가게 됩니다.

`7`{:.info}에서 이 구조를 이용합니다. 이 스크립트는 옵션이 아닌 일반 명령행 인수로 지정한 디렉터리도 대상입니다. 이때, 옵션이 몇 개 지정되는지 또는 하나도 지정되지 않았는지 미리 알지 못하므로 옵션 부분을 shift로 밀어낸 다음 $1을 취득해서 일반적인 명령행 인수를 얻습니다.

`3`{:.info}에서 설정한 a_flag값으로 옵션 -a가 지정되었는지를 `8`{:.info}에서 확인하여 처리를 분기한 뒤 ls 명령어로 디렉터리 내용을 표시합니다. 또한 여기서 "$path" 앞에 --(하이픈 두 개)로 옵션을 지정합니다. 이렇게 하면 파일명인 $path가 하이픈으로 시작하더라도 옵션이 아니라고 인식합니다. 

마지막으로 `9`{:.info}에서 -p로 지정한 구분자를 표시합니다. 구분자가 지정되지 않으면 셸 변수 separator는 빈 문자열이 됩니다. 문자열이 비었는지 여부를 **test 명령어**에 **-n 연산자**를 써서 판별하여 구분자 문자열이 있을 때만 출력합니다. test 명령어는 [파일처리_20 처리 시작 전에 실행 권한을 확인해서 정상 동작이 가능한지 확인 후 실행하기](https://blessu1201.github.io/2024/01/30/linux-file-test-042.html)를 참조합시다.

&nbsp;
&nbsp;

## **주의사항**

- 인수가 있는 옵션을 여러 개 쓰고 싶을 때는 다음처럼 콜론을 붙여서 나열합니다.

  ```
  getopts "ap:x:z:"
  ```

  a 옵션은 인수가 없고 p, x, z 옵션은 인수가 있습니다.