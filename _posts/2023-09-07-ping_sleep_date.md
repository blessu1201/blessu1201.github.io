---
layout: article
title: 서버관리_11 서버 ping 감시하기
tags: [Linux, ping, sleep, date, ShellScript]
key: 20230907-linux_server_manage_11
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어  

> 명령어: ping, sleep, date  
> 키워드: 서버 감시, 네트워크, 종료 스테이터스   
> 사용처: 네트워크 상태가 이상하지 않은지 또는 서버가 정지했는지 ping 명령어로 감시하고 싶을 때   

> 실행 예제  

```bash
$ ./ping_alert.sh 192.168.2.1
[2021/05/12 13:43:12] Ping OK: 192.168.2.1
```

> 스크립트

```bash
#!/bin/sh

# ping 실행 결과 스테이터스, 0이면 성공이므로 1로 초기화
result=1 # ------------------------------------------------------ 1

# 대상 서버가 명령행 인수로 지정되지 않으면 에러 종료
if [ -z "$1" ]; then # if문 ------------------------------------- 2
  echo "대상 호스트를 지정하세요." >&2
  exit 1
fi

# ping 명령어를 3회 실행, 성공하면 result를 0으로
i=0 # ---------------------------------------------------------- 3
while [ $i -lt 3 ]
do
  # ping 명령어 실행, 종료 스테이스만 필요하므로
  # /dev/null에 리다이렉트
  ping -c 1 "$1" > /dev/null # --------------------------------- 4

  # ping 명령어 종료 스테이터스 판별, 성공하면 result=0으로 반복문 탈출
  # 실패하면 3초 대기 후 재실행
  if [ $? -eq 0 ]; then # -------------------------------------- 5
    result=0
    break
  else
    sleep 3
    i=$(expr $i + 1)
  fi
done

# 현재 시각을 [2023/03/01 13:15:44] 형태로 조합
date_str=$(date '+%Y/%m/%d %H:%M:%S') # ----------------------- 6

# ping 실행 결과를 $result로 판별해서 표시
if [ $result -eq 0 ]; then # if문 ----------------------------- 7
  echo "[$date_str] Ping OK: $1"
else
  echo "[$date_str] Ping NG: $1"
fi
```

## **해설**

이 스크립트는 **ping 명령어**로 서버가 정상적으로 기동하고 있는지 감시합니다. 명령행 인수에 대상 서버 IP 주소 또는 호스트명을 지정해서 실패하면 대상 서버에 ping 결과를 OK/NG로 표시합니다. 이렇게 대상 서버 ping 응답을 감시해서 서버가 정상적으로 움직이고 있는지 판별할 수 있습니다.

ping 명령어는 대상 서버를 지정해서 **ICMP**라는 프로토콜로 패킷을 송신합니다. ICMP에는 몇 가지 메시지 타입이 있는데 ping 명령어는 Echo Request 패킷을 송신해서 그 응답으로 Echo Reply가 돌아오는지로 통신 상태를 확인합니다. ping 명령어에서 자주 사용하는 옵션은 다음과 같습니다.

|옵션|설명|
|:---|:---|
|-c <count>|count 개의 ICMP 패킷을 송신한 후 정지|
|-i <초>|패킷을 보낼 때마다 지정한 초만큼 기다림. 기본값은 1초|
|-q|조용한(quiet)모드, 시작과 끝만 메시지를 출력하고 중간 결과는 표시하지 않음|

그런데 셸 스크립트에서 ping 명령어로 대상 호스트를 감시하려면 주의가 필요합니다. 예를 들어 호스트는 정상이더라도 네트워크 상태가 이상해서 가끔 응답이 안 올 수도 있습니다. 한 번 에러가 발생한 것으로 이상 상태로 판단해 경고를 띄우는 것은 바람직하지 못합니다. **몇 번 반복했을 때 한 번도 응답이 오지 않으면 이상**이라고 판별하는 것이 적절합니다. 예제에서도 1, 2회 실패는 무시하고 3회 연속 실패일 때만 상태 이상이라고 판단하고 가정합니다.

예제 [1](#){:.button.button--primary.button--rounded.button--xs} 에서 ping 명령어 실행 결과 스테이터스를 저장하는 셸 변수 result를 정의합니다. 예제에서는 성공하면 0이 되므로 여기에서는 1로 초기화합니다.

[2](#){:.button.button--primary.button--rounded.button--xs} 에서 **test 명령어 -z 연산자**를 이용해서 명령행 인수에 대한 호스트가 지정되었는지 확인합니다. **$1**은 명령행 인수 첫 번째 값이 들어 있는 특수 변수입니다. -z는 빈문자이이면 참이 되므로 [1](#){:.button.button--primary.button--rounded.button--xs} 의 if문이 참이면 인수 지정이 없습니다 .따라서 "대상 호스트를 지정하세요." 라는 에러를 출력하고 exit 1로 종료합니다.

[3](#){:.button.button--primary.button--rounded.button--xs} 은 ping 명령어를 실행하는 while문입니다. 셸 변수 i는 반복 카운터로 0으로 초기화합니다.

[4](#){:.button.button--primary.button--rounded.button--xs}에서 ping 명령어 **-c 옵션**을 이용해서 1회만 ping을 실행합니다. [5](#){:.button.button--primary.button--rounded.button--xs}에서 종료 스테이터스가 셸 특수 변수 $?에 들어 있으므로 if문으로 0인지 판별합니다. 종료 스테이터스가 0이면 ping 명령어는 성공이므로 셸 변수 result를 0(성공)으로 지정하고, break로 while문을 빠져 나옵니다. 한편 ping 명령어 종료 스테이터스가 0이 아니면(즉 ping 명령어 실패, Echo Reply가 돌아오지 않음) **sleep 명령어**로 3초간 기다리고 다시 ping을 반복합니다.

[6](#){:.button.button--primary.button--rounded.button--xs}에서 **date 명령어**로 현재 시각을 "2023/09/07 15:45:18" 같은 형식으로 조합합니다. 이런 감시 스크립트는 문제 발생 시간을 나중에 확인하게 되므로 OK/NG를 판별한 시간을 함께 기록하는 것이 중요합니다. 따라서 이 시각을 나중에 출력 시 사용합니다. 

마지막으로 [7](#){:.button.button--primary.button--rounded.button--xs}에서 ping 명령어 결과를 출력합니다. 정상인지 비정상인지는 셸 변수 result를 써서 0이면 정상, 1이면 상태 이상이라고 판별합니다.

이렇게 하면 ping 명령어로 대상 호스트 감시가 가능합니다. 정기적으로 실행하도록 cron 등에 등록해서 실패하면 경고 메일을 보내는 스크립트를 실행하게 하는 등 여러분의 호나경에 맞게 수정하기 바랍니다.

## **주의사항**

- 이 스크립트를 이용하기 전에 우선 대상 서버에 ping 명령어를 직접 실행해보고 정상적으로 응답이 돌아오는지 확인하기 바랍니다. 최근 OS는 보안상의 이유로 ping 응답을 하지 않도록 설정하는 경우가 있습니다.

- 이 스크립트를 테스트하려면 ping에 응답하기도 하고 아니기도 한 상태를 설정할 서버가 필요합니다. 리눅스에서는 다음 명령어로 커널 파라미터를 일시적으로 변경하면 ping에 응답하지 않도록 설정할 수 있어 간단히 테스트할 수 있습니다.

  ```
  # 서버가 ping에 응답하지 않게 하기
  echo "1" > /proc/sys/net/ipv4/icmp_echo_ignore_all

  # 서버가 ping에 응답하게 설정
  echo "0" > /proc/sys/net/ipv4/icmp_echo_ignore_all
  ```
