---
layout: article
title: 서버관리_10 프로세스를 감시해서 다운 시 자동으로 재실행하기
tags: [Linux, service, ps, wc, grep, date, echo, ShellScript]
key: 20230907-linux_server_manage_10
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어  

> 명령어: service, ps, wc, grep, date, echo  
> 키워드: 프로세스, 감시, 재실행, 자동화  
> 사용처: 웹 서버 운용 시 프로세스가 다운하면 재실행해서 자동으로 장애 대응을 하고 싶을 때   
 
> 실행 예제  

```bash
$ ./process-restart.sh
[2023/05/30 10:30:15] /usr/sbin/httpd 찾지 못했습니다.
[2023/05/30 10:30:15] 프로세스 /usr/sbin/httpd 실행
Starting httpd: [ OK ]
```

> 스크립트

```bash
#!/bin/sh

# 감시할 프로세스 명령어
commname="/usr/sbin/httpd" # ----------------------------------------------- 1

# 감시 프로세스 실행 명령어
start=""service httpd start # ---------------------------------------------- 2

# 감시 대상 명령어 프로세스 수 카운트
count=$(ps ax -o command | grep "$commname" | grep -v "^grep" | wc -l) # --- 3

# grep 명령어 출력 결과가 0이면 프로세스가
# 존재하지 않거나 이상 상황이라고 보고 프로세스 재실행
if [ "$count" -eq 0 ]; then # ---------------------------------------------- 4
  # 로그에 시각 표시
  date_str=$(date '+%Y/%m/%d %H:%M:%S') # ---------------------------------- 5
  echo "[$date_str] 프로세스 $commname 찾지 못했습니다." >&2
  echo "[$date_str] 프로세스 $commname 실행" >&2

  # 감시 프로세스 실행
  $start # ----------------------------------------------------------------- 6
fi
```

## **해설**

이 스크립트는 셸 변수 commname으로 지정한 명령어 프로세스를 감시해서 프로세스가 발견되지 않으면 자동으로 재실행하는 복구 처리를 합니다. 여기서는 웹 서버에서 자주 사용하는 아파치 httpd 서버를 대상 프로세스로 가정합니다. 그리고 이 스크립트는 기본적으로 cron에 설정해서 자동 실행된다고 가정합니다.

프로세스 감시는 웹 서비스를 제공하는데 있어 중요한 요소입니다. 셸 스크립트로 프로세스를 감시하는 방법은 [서버관리_08](https://blessu1201.github.io/2023/09/05/02_ps_grep_wc.html)에서 설명햇으므로 여기에서는 그 결과를 이용해서 프로세스를 자동 재실행하는 방법과 주의점을 설명합니다.

서버 운용에 있어 자동화는 무척 중요한 기술입니다. 여러분이 처음으로 서버를 구축할때는 그다지 고마움을 느끼지 못할 수도 있습니다. 그 서버에서 딱히 중요한 프로그램이 동작하지 않거나 프로세스가 한밤중에 정지해도 다음날 대응하면 되는 수준일지도 모릅니다.

하지만 운용 기간이 늘어나거나 이용자 요구 수준이 높아져서 서버를 수십 대로 늘리거나 24시간 내내 프로세스 다운에 즉시 대응해야 하는 상황에 처할지도 모릅니다. 또는 동작한다고 생각한 프로세스가 어느새 정지했는데 그걸 놓쳤을 수도 있습니다. 이 예제는 그런 장애 대응에 무척 유용합니다.

우선 [1](#){:.button.button--primary.button--rounded.button--xs} 에서 감시할 프로세스 명령어를 지정합니다. 이때 아파치 httpd 대상으로 합니다.

[2](#){:.button.button--primary.button--rounded.button--xs} 는 프로세스를 실행하는 명령어를 지정합니다. 리눅스 **service 명령어**를 사용해서 httpd를 실행한다고 설정합니다. Mac이나 FreeBSD는 주의사항을 참조하기 바랍니다.

[3](#){:.button.button--primary.button--rounded.button--xs} 에서 셸 변수 commname으로 지정한 프로세스가 존재하는지 **ps 명령어**로 확인합니다. 셸 변수 count에 현재 프로세스 수가 대입되므로 이걸 [4](#){:.button.button--primary.button--rounded.button--xs} 의 if문으로 비교합니다. **test 명령어 -eq 연산자**로 0과 비교해서 0이면 프로세스가 존재하지 않는다고 보고 if문 내부의 명령어를 실행합니다.

[5](#){:.button.button--primary.button--rounded.button--xs} 는 현재 시각을 넣어서 **echo 명령어**로 상태를 표시합니다. 이런 시스템 관리 스크립트는 나중에 장애 시각을 조사해야 해서 시간이 중요합니다. 따라서 **date 명령어**를 이용해 현재 시간을 셸 변수 date_str에 대입해서 표시합니다.

[6](#){:.button.button--primary.button--rounded.button--xs} 은 감시 프로세스를 재실행합니다. 미리 셸 변수 start로 정의해둔 명령어를 그대로 실행합니다. 이렇게 해서 프로세스 정지를 발견해서 자동으로 재실행할 수 있습니다.

이 스크립트를 5분에 한 번 정기적으로 실행하고 싶습니다. 스크립트 정기적 실행은 cron을 사용합니다. 아파치 httpd를 재실행하고 싶을 때는 root 권한이 필요하므로 root 사용자의 cron에 설정하면 됩니다. 구체적으로는 /etc/crontab에 다음 내용을 추가합니다.

```bash
*/5 * * * * root /usr/local/bin/process-restart.sh >> /var/log/myapp/start.log 2>&1
```
분을 */5로 지정했으므로 5분마다 프로세스를 확인하게 됩니다.

대상 프로세스가 아파치 http인데 이 같은 웹 서버는 리퀘스트에 따라 내용을 돌려주는 소프트웨어로 그저 재실행하면 해결되는 경우가 많습니다.

반면, MySQL 같은 데이터베이스 서버에 이런 자동 재실행 스크립트를 무작정 적용하면 안됩니다. 데이터베이스 서버가 예상하지 못하게 정지했다면 디스크 용량이 부족해 I/O 에러가 발생했다든가 하는 이유가 있기 마련입니다.

그런 원인을 확인하지 않고 자동 스크립트로 강제적으로 재실행을 반복하면 최악의 경우 데이터베이스가 파손되는 치명적인 장애가 생길 수도 있습니다.

따라서 MySQL 서버 같은 데이터베이스의 프로세스 감시는 해야 하지만 프로세스 이상 시 재실행하는 스크립트까지 적용할지는 신중히 결정해야 합니다. 프로세스 다운 같은 문제 발생 시 그 상태를 유지한 채 수동으로 복구하는 것을 원칙으로 하는 시스템도 있으므로 자동 재실행의 적용은 사전에 검토해야 합니다.

일반적으로 웹 서버나 프록시 서버 등은 자동 재실행해도 큰 문제가 없습니다. 데이터베이스 서버의 자동 재실행을 고려할 때는 꼼꼼히미리 검증 및 설계하는 것이 좋습니다.

## **주의사항**

- 이 예제는 리눅스(CentOS)로 아파치 httpd를 rpm으로 설치했을 때 제공된 실행 스크립트로 재실행합니다. FreeBSD나 Mac에서 아파치 httpd 실행 스크립트가 제공되지 않으면 apachectl 명령어로 직접 실행하면 됩니다. Mac에는 /usr/sbin에 apachectl 명령어가 있으므로 "2" 를 다음처럼 수정합니다.
```bash
start="/usr/sbin/apachectl start"
```
