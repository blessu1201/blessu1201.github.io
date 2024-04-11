---
layout: article
title: bash_08 간단한 메뉴를 표시해서 사용자가 선택할 수 있게 하기
tags: [Linux, ShellScript, select, case]
key: 20240409-linux-select-case
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: select, case  
> 키워드: 메뉴, 선택  
> 사용처: 간단한 메뉴를 표시하고 사용자가 조작하게 만들고 싶을 때

--- 

> 실행예제

```
$ ./bash-select.sh
1) list file
2) current directory
3) exit
Menu: 2
/home/park/bin

Menu: 3  <------ 사용자가 3을 입력하면 스크립트 종료
```

> 스크립트

```bash
#!/bin/bash

# 메뉴 프롬프트 정의
PS3='Menu '  #------------------------------ 1

# 메뉴 표시 정의. 메뉴 각 항목은 in에 목록으로 지정
# $item은 선택한 목록 문자열이, $REPLY에는 입력한 숫자가 대입됨
select item in "list file" "current directory" "exit"
do
  case "$REPLY" in 
    1)
      ls
      ;;
    2)
      pwd
      ;;
    3)
      exit
      ;;
    *)
      echo "Error: Unknown Command"
      ;;
  esac

  echo
done
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 메뉴를 표시합니다. 메뉴 첫 항목 "list file"을 선택하면 ls 명령어를, "current directory"를 선택하면 pwd 명령어를, 세 번째는 "exit"를 선택하면 exit 명령어를 실행합니다. 이런 메뉴 표시 스크립트는 bash 기능인 select문을 이용합니다.

bash select문은 간단한 메뉴를 만드는 기능으로 다음처럼 이용합니다.

- select문 사용법

  ```
  PS3=프롬프트 문
  select <변수명> in <리스트>
  do
      ...(명령어)
  done
  ```


`<리스트>`{:.warning}로 지정하는 문자열을 바탕으로 bash는 메뉴를 조합해서 자동으로 번호를 할당해서 표시합니다 .select문의 in `<리스트>`{:.warning}부분은 생략 가능한데 생략하면 위치 파라미터 $@, 즉 명령행 인수가 지정되어 있다고 봅니다.

그리고 **PS3**는 select문이 이용하는 bash 셸 변수로 이 문자열을 메뉴 프롬프트로 표시합니다. 

select문은 사용자가 선택한 목록값이 <변수명>에 대입됩니다. 그리고 이때 사용자가 입력한 숫자는 동시에 셸 변수 REPLY에 대입됩니다. 메뉴로 case문을 이용해서 분기할 때 셸 변수 REPLY를 이용하면 편리합니다. 예제에서도 셸 변수 REPLY를 이용해서 선택한 메뉴를 취득합니다.

예제 스크립트는 우선 `1`{:.info}에서 셸 변수 PS3에 프롬프트문을 대입합니다. 여기서 설정한 값이 메뉴 표시에서 사용하는 질문문이 됩니다.

`2`{:.info}는 select문으로 메뉴를 정의합니다. "list file", "current directory", "exit" 의 세 가지 문을 목록으로 넘깁니다. 실행 예에서 보았듯 여기에 순서대로 1), 2), 3) 이라는 숫자를 bash가 자동으로 붙여주므로 스크립트에서는 작성하지 않아도 됩니다. 사용자가 입력한 숫자는 select문으로 셸 변수 REPLY에 대입되므로 이걸 case문으로 분기해서 처리를 실행합니다.

이러면 메뉴를 간단히 작성할 수 있습니다. 조작에 익숙하지 않은 초보자를 위한 스크립트에서 대화형 메뉴를 이용하고 싶을 때 사용하면 좋습니다.