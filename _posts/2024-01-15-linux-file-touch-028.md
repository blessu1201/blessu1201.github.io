---
layout: article
title: 파일처리_06 신규 파일을 만들지 않고 이미 있는 파일만 파일 갱신일을 바꾸기
tags: [Linux, ShellScript, touch]
key: 20240115-Linux-file-touch
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: touch  
> 키워드: 타임 스탬프, 신규 파일, 갱신일  
> 사용처: touch 명령어로 타임스탬프를 갱신하는 초기화 스크립트 등에서 존재하지 않는 파일은 새롭게 만들고 싶지 않을 때



> 실행 예제  

```
$ ./touch.sh
```

> 스크립트

```bash
#!/bin/sh
 
# [YYYYMMDDhhmm.SS]로 [년월일시분.초] 지정
timestamp="201311190123.45"
 
# 파일 타임스탬프 갱신
# -c 옵션이 있으므로 lock 파일은 신규 파일을 만들지 않음
touch -t $timestamp app1.log  # ---------------------- 1
touch -c $timestamp lock.tmp  # ---------------------- 2
```

&nbsp;
&nbsp;

## **해설** 

이 스크립트는 app1.log와 lock.tmp라는 두 파일의 타임스탬프를 갱신합니다. 로그 파일을 조작하는 다른 프로그램을 위해 테스트 자료를 만드는 경우를 생각해볼 수 있습니다. 그 프로그램은 로그 파일(app1.log)의 타임스탬프를 판별해서 무엇인가 처리를 합니다. 테스트를 할 때마다 셸 스크립트를 실행해서 테스트 자료를 초기화하는 것은 자주 쓰는 방법입니다. 이 예제는 그런 테스트 일환으로 작성한 셸 스크립트 입니다.

스크립트에서는 타임스탬프 조작에 **touch 명령어**를 사용합니다. 우선 touch 명령어를 설명하기 전에 유닉스에서 파일 스탬프가 어떤 구조인지 알아봅시다. 유닉스에는 세 가지 파일 타임스탬프가 있습니다. 파일 내용을 수정하면 mtime이 갱신됩니다. ctime은 create time(파일 작성 시각)이 아니라 change time(상태 변경 시각)입니다.

- 유닉스 파일 타임스탬프

  |종류|설명|
  |:---|:---|
  |atime|최종 접근시각(access time)|
  |mtime|최종 수정시각(modify time)|
  |ctime|최종 상태변경시각(change time)|

이런 타임스탬프는 다음처럼 stat 명령어로 자세히 살펴볼 수 있습니다.

- stat 명령어로 타임스탬프 확인하기(리눅스)

  ```
  $ stat touch.sh
    File: 'touch.sh'
    Size: 261		Blocks: 8		IO Block: 4096 regular file
  Device: fc03h/64515d Inode: 3276911 Links: 1
  Access: (0775/-rwxrwxr-x) Uid: (1003/ user1) Gid: (1003/ user1)
  Access: 2013-04-10 11:15:13.000000000 +0900
  Modify: 2011-07-17 18:52:26.000000000 +0900
  Change: 2013-11-11 22:58:16.461418708 +0900
  ```

  stat 명령어를 보기 쉽도록 FreeBSD나 Mac은 **-x 옵션**을 제공합니다.

  ```
  $ stat -x touch.sh
    File: 'touch.sh'
    Size: 309		FileType: Regular File
    Mode: (0777/-rwxrwxrwx) Uid: (501/TechnicalBook) Gid: (20/ staff)
  Device: 1,2 Inode: 11630161 Links: 1
  Access: Thu May 22 18:21:10 2014
  Modify: Fri Dec 13 15:03:04 2013
  Change: Thu May 22 18:21:10 2014
  ```

  stat 명령어 실행 예에서 마지막 세줄, 즉 Access/Modify/Change는 각각 atime/mtime/ctime이 됩니다. 실제 프로그램에서는 파일 타임스탬프 중에서 최종 수정 시각 (mtime)을 보고 판단하는 일이 많을 겁니다.

`1`{:.info}에서 사용한 touch 명령어는 **-t 옵션**으로 시각을 지정하면 파일 atime과 mtime을 갱신합니다(-a 옵션 또는 -m 옵션을 쓰면 atime이나 mtime 한쪽만 변경할 수도 있습니다). -t 옵션은 갱신할 시각[년월일시분.초]를 [YYYYMMDDhhmm.SS]로 지정합니다. 즉 `1`{:.info}은 "2013년 11월 19일 1시 23분 45초"를 지정해서 파일 타임스탬프 atime과 mtime을 갱신합니다.

이어서 `2`{:.info}에서 락 파일의 타임스탬프도 변경합니다. 락 파일을 다룰 때 **-c 옵션**을 사용합니다. 파일이 없으면 새로운 파일을 만들지 않기 위한 처리입니다.

**touch 명령어를 사용하면 빈 파일을 작성한다**라는 것은 잘 알려진 동작입니다. 하지만 이런 텍스트 파일 초기화에서는 '파일이 있으면 타임스탬프를 변경하지만 파일이 없으면 아무것도 안하고 싶은 경우(파일을 만들지 않음)'도 자주 있습니다.

파일 존재를 if문으로 확인하는 것은 가독성도 좋지 않고 나중에 수정하기도 힘듭니다.

```
if [ -e lock.tmp ]; then
    touch -t $timeestamp lock.tmp
fi
```

그보다는 예제처럼 touch 명령어에 -c 옵션을 사용하면 존재하지 않는 파일은 작성하지 않도록 간단히 지정할 수 있습니다.

&nbsp;
&nbsp;

## **주의사항**

- touch 명령어를 -t 옵션 없이 실행하면 파일 타임스탬프는 명령어 실행 시각으로 갱신됩니다. 파일 내용은 변경하지 않지만 타임스탬프만 변경하고 싶을 때 자주 사용합니다.
```
# 파일 타임스탬프를 지금 시간으로 변경하기
touch app1.log
```

- 타임 스탬프를 써서 파일을 검색하려면 find 명령어에 **-mtime 옵션**을 사용합니다.
