---
layout: article
title: 변환 처리_04 값이 정수인지 확인해서 계산하기  
tags: [Linux, ShellScript, test, expr]
key: 20240323-linux-test-expr
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: test, expr  
> 키워드: 숫자 확인, 인수 확인, 에러 처리  
> 사용처: expr 명령어 등으로 계산하기 전에 변수값이 정수인지 확인하고 싶을 때

--- 

> 실행예제

```
$ ./int-check.sh 100a
Argument is not Integer.

$ ./int-check.sh 100
Argument is Integer.
110
```

> 스크립트

```bash
#!/bin/sh

# 인수가 정수인지 확인
test "$1" -eq 0 2>/dev/null  #------------- 1

if [ $? -lt 2 ]; then  #------------------- 2
  echo "Argument is Integer"
  expr 10 + $1
else
  echo "Argument is not Integer."
  exit 1
fi
```

&nbsp;
&nbsp;

## **해설**

이 스크립트는 명령행 인수로 지정한 정수값에 10을 더한 값을 돌려줍니다. 정수 이외의 값이 지정되면 "Argument is not Integer."라고 표시하고 에러를 냅니다. 덧셈, 뺄셈 같은 **사칙 연산**을 **expr 명령어**로 할 수 있습니다. 곱셈을 할 땐 *(애스터리스크)가 셸에서 해석되지 않도록 \ 기호로 이스케이프해야 합니다.

```
expr $i + $j	# 더하기
expr $1 - $j	# 빼기
expr $i \* $j	# 곱하기
expr $i / $j	# 나누기
```

expr 명령어는 소수점에 대응하지 않으므로 **정수가 아닌 값을 사칙 연산하면 에러**가 발생합니다. 따라서 명령어를 실행하기 전에 변수가 바른 값인지 확인하고 싶을 때가 있습니다. 특히 이 예제처럼 사용자가 입력한 값으로 처리하는 경우에 입력값을 제대로 확인하지 않으면 예상과 다른 결과가 나오게 됩니다.

따라서 `1`{:.info}에서 인수 확인을 합니다. **test 명령어**를 써서 명령행 인수`($1)`가 0과 같은지 **-eq 연산자**로 확인합니다. test 명령어 출력 결과 자체는 필요 없으므로 표준 에러 출력은 /dev/null로 리다이렉트해서 버립니다. `1`{:.info}처리의 종료 스테이터스($?)는 다음과 같습니다.

- 명령행 인수가 0과 같으면 0
- 명령행 인수가 0이 아니면 1
- 명령행 인수가 0과 비교 불가능한 문자열이면 2

따라서 `2`{:.info}에서 종료 스테이터스를 비교해서 2보다 작으면(-lt) 정수로 보고 그대로 계산을하고, 아니면 정수가 아니라고 판단해서 에러를 내고 종료합니다.

&nbsp;
&nbsp;

## **주의사항**

- 이 스크립트는 "0000" 같은 문자열 값을 expr 명령어에서 정수 0으로 정상적으로 계산 가능하므로 에러로 보지 않습니다.
