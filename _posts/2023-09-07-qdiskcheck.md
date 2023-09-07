---
layout: article
title: 서버관리_13 / 디스크 용량 감시하기
tags: [Linux, df, awk, read, echo, rm, ShellScript]
key: 20230908-linux_server_manage_13
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

## 디스크 용량 감시하기

> 명령어: df, awk, read, echo, rm  
> 키워드: 디스크, 사용량, 사용률, 용량    
> 사용처: 디스크 사용률을 정기적으로 감시하여 허용값 이상으로 올라가면 경고하고 싶을 때 

> 실행 예제  

```bash
$ ./df-diskcheck.sh
[2023/09/07 15:15:15] Disk Capacity Alert: /usr/local (92% used)
ALERT...
```

> 스크립트

```bash
#!/bin/sh

# 감시할 디스크 사용률의 허용값 %
used_limit=90 # --------------------------------------------------------- 1
# df 명령어 출력 결과 임시 파일명
tmpfile="df.tmp.$$" # --------------------------------------------------- 2

# df 명령어로 디스크 사용량 표시. 첫 줄은 헤더이므로 제거
df -P | awk 'NR >=2 {print $5,$6}' > "$tmpfile" # ----------------------- 3

# df 명령어 출력 임시 파일에서 사용률 확인
while read percent mountporint # ---------------------------------------- 4
do
  # "31%"을 "31"로 % 기호 삭제
  percent_val=${percent%\%} # ------------------------------------------- 5

  # 디스크 사용량이 허용값 이상이면 경고
  if [ "$percent_val" -ge "$used_limit" ]; then # ----------------------- 6
    # 현재시각을 [2015/02/01 13:15:44] 형식으로 조합
    date_str=$(date '+%Y/%m/%d %H:%M:%S') # ----------------------------- 7

    echo "[$date_str] Disk Capacity Alert: $mountpoint ($percent used)"
    /home/user1/bin/alert.sh
  fi
done < "$tmpfile"

# 임시파일 삭제
rm -f "$tmpfile" # ------------------------------------------------------ 8
```

[1](#){:.button.button--primary.button--rounded.button--xs}
[2](#){:.button.button--primary.button--rounded.button--xs}
[3](#){:.button.button--primary.button--rounded.button--xs}
[4](#){:.button.button--primary.button--rounded.button--xs}
[5](#){:.button.button--primary.button--rounded.button--xs}
[6](#){:.button.button--primary.button--rounded.button--xs}
[7](#){:.button.button--primary.button--rounded.button--xs}
[8](#){:.button.button--primary.button--rounded.button--xs}


### **해설**

이 스크립트는 서버가 마운트한 각각의 디스크 사용률을 감시해서 지정한 값보다 사용률이 크면 경고합니다. 여기서는 **df 명령어**로 디스크 빈 용량을 조사해서 셸 변수 used_limit로 지정한 허용값 퍼센트 보다 사용률이 크면 alert.sh 라는 스크립트를 실행해서 경고를 발생시킵니다.

그리고 예제에서 alert.sh는 통지 메일을 송신하는 등의 경고 처리를 하는 스크립트라고 가정합니다.


서버 운용에서 디스크 사용량은 놓치기 쉬운 부분입니다. 서비스를 시작할 때는 디스크에 빈 공간이 많아서 사용량에 신경 쓰는 사람이 없어 감시조차 하지 않는 경우도 많습니다. 하지만 몇 년이 지나면 로그 파일이나 임시 파일, 애플리케이션 출력 데이터 파일이 쌓여서 디스크를 압박하게 됩니다. 그리고 어느날 갑자기 서버가 다운되어서 조사해보면 디스크 사용량이 100%였다는 경험담을 들어봤을 겁니다.

그러므로 서버 운용 시작부터 예제와 같은 디스크 감시 스크립트를 cron에 넣어두면 도움이 될 것입니다.

[1](#){:.button.button--primary.button--rounded.button--xs}에서는 우선 이 스크립트가 감시하는 디스크 사용률 허용값을 셸 변수 used_limit에 정의합니다. 여기서 설정한 퍼센트 값보다 디스크 사용률이 높으면 경고를 발생시킵니다. 예를 들어 used_limit에 90을 설정하고, 대상 디스크 용량이 50GB일 때는 45GB 이상 디스크를 사용하면 경고하게 됩니다.

[2](#){:.button.button--primary.button--rounded.button--xs}에서 df 명령어 출력을 저장하는 임시 파일의 파일명을 정의합니다. 여기서 셸 특수 변수 **$$**로 프로세스 ID를 파일명에 사용합니다.

[3](#){:.button.button--primary.button--rounded.button--xs}은 df 명령어 출력을 **awk 명령어**로 처리해서 사용률을 추출합니다. df 명령어는 디스크 사용량 등을 표시하는 명령어로 옵션 없이 실행한 출력 예는 다음과 같습니다.

- df 명령어 실행 예

```
$ df
Filesystem      1K-blocks      Used  Available  Use%  Mounted on
/dev/vda3       100893076   2195932	  93571976	  3%	/
tmpfs		           510208		      0	    510208		0%	/dev/shm
/dev/vda1          247919		  51510	    183609		22%	/boot
nfsdisk001.example.com:/export/home	
                 34600237	  8869759	  22270454	  28%	/mnt/nfs
```

출력은 왼쪽에서부터 파일시스템, 디스크 전체 용량, 디스크 사용량, 디스크 빈 용량, 디스크 사용률(%), 마운트 포인트입니다. 그리고 df 명령어에는 다음과 같은 옵션이 있습니다.

- df 명령어 주요 옵션

|옵션|의미|
|:---|:---|
|-h|사람이 읽기 쉬운 형식(human-readable)으로 크기 표시
    2기가 바이트면 2G로 표시|
|-k|1024바이트(1킬로바이트) 단위로 크기 표시|
|-i|i 노드 정보 표시|
|-p|POSIX 출력 형식 사용. 파일 시스템명이 길어도 한 줄로 표시|
|-l|로컬 파일시스템만 대상. NFS 등은 표시하지 않음|

예제에서는 **-P 옵션**을 이용합니다. 앞서 실행 예의 마지막 줄을 보면 알 수 있듯 파일 시스템명이 길면 df 명령어는 자동으로 줄바꿈을 합니다. 셸 스크립트를 다룰 때는 이런 부분이 불편하므로 -P 옵션을 이용해서 한 줄로 표시합니다.

[3](#){:.button.button--primary.button--rounded.button--xs}에서는 df 명령어 첫 줄은 헤더라 불필요하므로 awk 명령어로 필터를 NR >=2로 지정해서 두 번째 줄 이후를 표시합니다. 그리고 **NR**은 awk 내장 변수로 현재 처리 줄을 나타냅니다. 그리고 디스크 사용률과 마운트 포인트를 취득하므로 다섯 번째($5)와 여섯 번째($6)를 awk 명령어로 print합니다. 결과는 나중에 사용하므로 임시 파일 $tmpfile로 리다이렉트합니다. 임시 파일 $tmpfile 내용은 다음과 같습니다.

- 임시파일 내용

```
3% /
0% /dev/shm
22% /boot
28% /mnt/nfs
```
[4](#){:.button.button--primary.button--rounded.button--xs}에서 임시 파일 $tmpfile 내용을 while문에 입력 리다이렉트해서 읽습니다. **read 명령어**를 사용해서 셸 변수 percent 및 mountpoint에 각각 이용률과 마운트 포인트를 대입합니다.

[5](#){:.button.button--primary.button--rounded.button--xs}는 이용률 문자열에서 퍼센트 기호(%)를 삭제합니다. 그림에서 봤듯이 이용률은 퍼센트로 표시되는데 이것은 숫자값 비교를 할 때 방해가 되므로 삭제하고 숫자만 남깁니다. 퍼센트 기호(%)를 삭제하는데 셸 파라미터 확장을 이용합니다.

셸 **파라미터 확장**은 ${parameter%word}라고 작성하면 '변수 parameter값에서 word로 후방 일치로 일치하는 부분을 삭제한 값'을 얻는 기능 입니다. [5](#){:.button.button--primary.button--rounded.button--xs}에서 %를 삭제하려면 파라미터 확장은 % 자체가 메타 문자이므로 이스케이프해서 ${percent%\%}라고 작성합니다. 이것으로 셸 변수 percent에서 제일 뒤에 있는 %를 삭제한 값을 얻게됩니다.

디스크 사용률을 숫자로 얻었으므로 [6](#){:.button.button--primary.button--rounded.button--xs}에서 **test 명령어**의 '이상'을 의미하는 **-ge 연산자**로 허용값과 비교합니다. 사용률이 허용값 이상이면 경고를 표시하고, 알람을 발생하는 스크립트 alert.sh를 실행합니다. [7](#){:.button.button--primary.button--rounded.button--xs}에서 **date 명령어**를 이용해서 현재 시각을 2023/09/07 15:15:15 같은 형태로 조합합니다. 그 결과는 경고 표시에서 시간을 표시할 때 사용합니다.

마지막에 [8](#){:.button.button--primary.button--rounded.button--xs}에서 df 명령어 임시 파일을 삭제합니다. 여기서 임시 파일을 삭제하지 않으면 계속 남아서 디스크 용량을 소비하기 때문에 주의해야 합니다.

이렇게 해서 디스크 사용률 감시가 가능합니다. cron에 등록해서 정기적으로 실행하도록 설정하면 좋습니다.

### **주의사항**

- FreeBSD나 Mac은 특수한 디바이스 파일시스템 devfs와 map의 Capacity(사용률)가 늘 100%입니다. 이런 디바이스는 제외하는 것이 좋습니다. 다음처럼 df 명령어를 변경합니다.

```bash
df -P | grep -v '^devfs\|map ' | awk ' NR >=2 {print $5, $6}' > "$tmpfile"
```

