---
layout: article
title: 네트워크_08 ftp로 자동 내려받기, 자동 올리기
tags: [Linux, ftp, ShellScript]
key: 20230925-linux_network_08
---

- 출처 : 유닉스 리눅스 쉘스크립트 예제사전_한빛미디어

> 명령어: ftp  
> 키워드: ftp, 로그인, 자동화   
> 사용처: ftp로 파일 연계하는 시스템에서 로그인 처리나 파일 내려받기, 올리기를 자동화하고 싶을 때  

> 실행 예제  

```
$ ./autoftp.sh
$ ls
autofs.sh app.log <-- app.log를 내려받기
```

> 스크립트

```bash
#!/bin/sh

# FTP 접속 설정
server="192.168.2.5"
user="user1"
password="패스워드 입력" # ----------- 1
dir="/home/park/myapp/log"
filename="app.log"

ftp -n "$server" << __EOT__  # --- 2
user "$user" "$password"
binary
cd "$dir"
get "$filename"
__EOT__
```

&nbsp;
&nbsp;

## **해설** 

이 스크립트는 지정한 FTP 서버에서 **ftp 명령어**를 이용해서 자동으로 파일을 내려받습니다. 스크립트 셸 변수로 접속할 FTP 서버나 계정 정보를 지정하면 자동으로 로그인해서 파일을 내려받습니다.

ftp는 파일 전송을 위한 프로토콜로 서버 간에 파일을 다루기 위해 사용합니다. 오래된 프로토콜인 ftp는 평문으로 ID와 암호를 전송하므로 보안 면에서는 취약해 요즘 시스템에서는 사용하지 않는 편입니다. 하지만 역사가 오래된 프로토콜이므로 실제 시스템 운용에서는 아직도 많이 사용됩니다.

여기에서는 백업 서버에서 정기적으로 스크립트를 실행해서 FTP 서버 및 애플리케이션 서버와 app.log 로그 파일을 취득한다고 가정합니다. 이런 로그 파일 등을 정기적으로 ftp로 가져오는 것은 요즘에도 비교적 자주 쓰는 방법입니다.

우선 `1`{:.info}에서 ftp 접속을 위한 각종 설정을 셸 변수에 대입합니다.

- server: FTP 서버의 IP주소 또는 호스트명
- user : FTP 서버 로그인 ID
- password : FTP 서버 로그인 암호
- dir : FTP 서버의 파일 보존 디렉터리
- filename : 내려받을 파일명

`2`{:.info}에서 ftp 명령어를 실행합니다. ftp 명령어를 옵션 없이 실행하면 대화형 모드로 실행됩니다. 사람이 직접 입력한다면 알기 쉽지만 셸 스크립트로 자동 실행한다면 이런 대화형은 오히려 다루기 힘든 모드입니다.

- ftp 명령어를 옵션없이 실행하면 대화형 모드가 됨
```
$ ftp 192.168.2.5
Connected to 192.168.2.5 (192.168.2.5).
220 ftpserver FTP server (Version 6.00LS) ready.
Name (192.168.2.5:park): park
331 Password required for park.
Password: 암호 입력
230 User park logged in.
Remote system type is UNIX.
Usingbinary mode to transfer files.
ftp> cd /home/park/ftp
250 CWD command successful.
```

여기서 셸 스크립트로 자동 실행하는 경우는 `2`{:info}처럼 ftp 명령어에 **-n 옵션**을 사용합니다. -n 옵션은 .netrc 파일로 자동 로그인하지 않도록 하는데 사용할 뿐만 아니라 셸 스크립트 자동화에도 사용합니다.

ftp 명령어는 홈 디렉터리 아래에 있는 .netrc 파일에 로그인 정보를 작성하면 자동 로그인합니다. 여기서 -n 옵션을 쓰면 .netrc 파일을 사용하지 않는 대신 표준 입력에서 ftp 명령어를 입력할 수 있습니다. 예제에서는 이 기능을 사용해서 `2`{:info}에서 **히어 도큐먼트** 형식으로 ftp 명령어를 자동 실행합니다.

`2`{:.info}에서 히어 도큐먼트로 실행할 ftp 명령어는 구체적으로 다음과 같습니다.

1. user 명령어로 로그인합니다.
2. binary 명령어로 바이너리 모드를 설정합니다.
3. cd 명령어로 디렉터리를 이동합니다.
4. get 명령어로 파일을 다운로드 합니다.

이렇게 ftp 명령어 -n 옵션을 사용하면 ftp 프로토콜을 사용해서 파일 내려받기를 셸 스크립트로 자동화할 수 있습니다. 예제의 히어 도큐먼트에 있는 get 부분을 put으로 바꾸면 파일 업로드 자동화도 가능합니다.

&nbsp;
&nbsp;

## **주의사항**
 
- CentOS는 ftp 명렁어가 설치되어 있지 않습니다. 아래와 같이 yum 명령어로 설치합니다.
```
yum install ftp
```

- 리눅스 ftp 명령어는 -n 옵션을 쓰면 실행 예처럼 아무것도 표시하지 않습니다.

- FreeBSD나 Mac에서는 -n 옵션을 써도 ftp 서버 간 통신을 표시합니다. 표시를 제거하려면 -V 옵션을 사용합니다.

- 이 셸 스크립트는 ftp 접속을 위한 ID나 암호가 직접 적혀 있으므로 다른 사람이 보지 못하도록 해야 합니다. 파일 권한을 700으로 바꾸는 등 적절한 설정이 필요합니다.

- ftp는 평문으로 통신하므로 통신 내용을 도청당하면 ID나 암호를 간단히 들키게 됩니다. 따라서 이 스크립트는 기본적으로 인트라넷에서만 사용하고 인터넷 경유로 파일을 전송한다면 scp나 sftp같은 암호화 통신이 가능한 프로토콜을 선택하기 바랍니다.