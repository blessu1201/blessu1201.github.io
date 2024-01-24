---
layout: article
title: 파일처리_09 작업 파일 디렉터리에서 1년 이상 갱신되지 않은 파일 삭제하기
tags: [Linux, ShellScript, find, xargs]
key: 20240119-Linux-find-xargs
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: find, xargs  
> 키워드: 갱신일, 날짜, 파일 삭제, 자동 삭제  
> 사용처: 오랫동안 변경되지 않은 파일이나 오래된 로그 파일을 삭제하고 싶을 때
  
---

> 실행 예제  

```
$ ./find-del.sh # --------------현재 날짜가 2013년 11월 26일이라면
/var/log/myapp/201211250147.log
/var/log/myapp/201211200147.log
/var/log/myapp/201211150147.log
```

> 스크립트

```bash
#!/bin/sh
 
logdir="/var/log/myapp"
 
# 최종 갱신일이 1년 이상된 오래된 파일 삭제
find $logdir -name "*.log" -mtime +364 -print | xargs rm -fv # --- 1
```

&nbsp;
&nbsp;

## **해설** 

이 스크립트는 셸 변수 logdir로 지정한 디렉터리에서 1년(365일) 이상 갱신이 없는 로그 파일을 find 명령어로 찾아서 삭제합니다. 디렉터리 /var/log/myapp에는 파일 갱신일이 파일명에 있는 로그 파일이 많다고 가정합니다. 파일 목록을 xargs 명령어로 처리하는 것이 예제의 포인트입니다. 이 예제에서 1년 이상 변경이 없는 파일을 **find 명령어**에 -mtime 옵션으로 얻습니다.
 
이 스크립트에서 사용하는 **xargs** 명령어는 파일 목록을 인수로 받아서 임의의 명령어를 실행합니다. find 명령어로 특정 조건에 일치하는 파일 목록을 출력해서 파이프로 xargs 명령어로 받아서 처리하는 사용법이 일반적입니다.

```
find <대상 경로> <리스트> | xargs <실행할 명령어>
```

`1`{:.info}에서 우선 셸 변수 logdir로 지정한 디렉터리에서 -name 옵션으로 확장자가 .log인 파일을 얻습니다. 이때 **-mtime**을 써서 변경일이 365일보다 오래된 파일을 선택합니다. 이런 조건에 일치하는 파일 목록을 출력해서 xargs 명령어에 넘겨서 파일을 삭제하는 **rm 명령어**를 실행합니다. rm 명령어에는 해당 파일이 하나도 없을 때도 에러가 발생하지 않도록 **-f 옵션**을 쓰고, 동시에 **-v 옵션**도 써서 삭제한 파일명을 표시합니다.

이 예제처럼 오래된 파일을 삭제하는 스크립트는 장시간 가동한 웹 애플리케이션 등을 위한 배치 처리에서 자주 사용합니다. 임시 파일이나 동작 로그 파일을 별 생각 없이 일단 출력하는 개발 편의의 애플리케이션을 종종 보게 됩니다. 몇 년이나 가동한 시스템에서는 이런 임시 파일을 그대로 방치하기도 하므로 주의해야 합니다. 구체적으로는 다음과 같은 경우입니다.
 
1. 초기 버전에서 개발자가 디버그를 위해 일단 임시 파일을 출력하도록 개발하고는 그대로 릴리스함
2. 초기 개발자가 퇴사하여 운용 담당자가 서버째 인수 받음
3. 몇 년 지난 후 삭제하지 않은 임시 파일이 점점 쌓여서 디스크 사용률 100% 가까이 되어서 시스템이 다운됨
 
이런 일을(안타깝지만) 이러저런 현장에서 자주 보게 됩니다. 이런 사태는 시스템 릴리스 때부터 오래된 파일을 삭제하도록 고려하면 막을 수 있는 문제들입니다. 크기가 큰 임시 파일과 로그 파일을 작성하는 애플리케이션을 만들 때는 나중에 디스크가 꽉 차는 사고가 발생하지 않도록 오래된 파일을 자동 청소하는 배치를 만들어둡시다.

&nbsp;
&nbsp;

## **주의사항**

- 갑자기 파일을 삭제하는 스크립트를 작성하는 것은 위험하므로 우선 확인부터 합니다. 구체적으로는 다음처럼 xargs로 실행하는 명령어를 ls로 확인해보면 좋습니다.

```
find $logdir -name "*.log" -mtime +364 -print | xargs ls
```

이렇게 하면 실제로 xargs로 명령어를 실행하는 대상 파일 목록만 표시할 수 있습니다. 의도하지 않은 파일이 대상에 포함되지 않았는지 확인한 다음, 실행할 명령어를 ls에서 rm으로 바꿉니다.

- 테스트용의 오래된 파일은 touch 명령어 -t 옵션으로 작성할 수 있습니다.
- 파일명에 공백문자(스페이스)가 있으면 이 예제에서는 에러가 발생합니다. 그럴 때는 문자열 구분자로 공백이 아닌 널 문자를 사용한다고 보는 xargs 명령어의 -0(제로) 옵션을 사용합니다. 이때 find 명령어도 구분자를 널 문자로 출력하도록 print0 옵션을 사용합니다.

```
find $logdir -name "*.log" -mtime +364 print0 | xargs -0 rm -fv
```

이러면 공백문자를 포함한 파일명도 잘 다룰 수 있습니다. 