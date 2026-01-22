---
layout: article
title: 리눅스 nohup 명령어 / Linux nohup
tags: [Linux, Nohup]
key: 20230812-linux nohup
---

## nohup 명령어를 통해 데몬 프로세스 구동

> 리눅스에서 백그라운드로 데몬을 실행시키는 nohup 명령어입니다.
> 데몬을 시작하거나, 중지시킬 경우 하기와 같이 script를 작성해 놓으면
> 구동 및 중지하는데 간편하게 할 수 있습니다.

> 예전에 사용했던 프로메태우스의 Alert 설정 시 사용했던 스크립트 입니다.
> 참고하셔서 알맞게 수정 후 사용하시면 됩니다.
 
```bash
vi start.sh

#!/bin/sh
nohup ./alertmanager --config.file=alertmanager-config.yml 1> /dev/null 2>&1 &
```

```bash
vi stop.sh

#!/bin/sh
PID=`ps -ef | grep "./alertmanager --config.file" | grep -v grep | awk '{print $2}'`
echo "Process ID: $PID"

if [ -z $PID ]; then
  echo "No process is running"
else
  echo "Kill process : " $PID
  kill -9 $PID
fi
```
