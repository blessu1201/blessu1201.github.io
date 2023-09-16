---
layout: article
title: Amazon Linux 2023에서 Let's Encrypt SSL 설정 하기
tags: [Linux, Amazon-linux-2023, aws-lightsail, let's encrypt, wordpress, SSL]
key: 20230917-Amazon-linux-2023-lets-encrypt
---

# Amazon Linux 2023에서 Let's Encrypt SSL 설정 하기

> Amazon Web Service의 light-sail에 워드프레스를 설치한 후 SSL을 설정하는 과정입니다.
>
> Let's Encrypt를 사용하였습니다. [홈페이지](https://letsencrypt.org/)

&nbsp;
&nbsp;

## 1. Certbot 설치하기

설치하기에 앞서 작업편의상 **`root계정`{:.info}**으로 작업하였습니다.  
`/usr/bin/certbot`{:.success}명령을 사용하기 위해 아래과 같이 순차적으로 명령을 실행합니다.

```
# dnf install -y python3 augeas-libs pip
...(생략)
Complete!
```
```
# python3 -m venv /opt/certbot/
```
```
# ls /opt/certbot
bin  include  lib  lib64  pyvenv.cfg
```
```
# ls /opt/certbot/bin
Activate.ps1  activate  activate.csh  activate.fish  pip  pip3  pip3.9  python  python3  python3.9
```
```
# /opt/certbot/bin/pip install --upgrade pip
...(생략)
Successfully installed pip-23.1.2
```
```
# /opt/certbot/bin/pip install certbot
...(생략)
Successfully installed ConfigArgParse-1.5.3 PyOpenSS-23.1.1 acme-2.6.0 certbot-2.6.0 certifi-2023.5.7 cffi-1.15.1 charset-normalizer-3.1.0 configobj-5.0.8 cryptography-40.0.2 distro-1.8.0 idna-3.4 josepy-1.13.0 parsedatetime-2.6 pycparser-2.21
```
```
# ln -s /opt/certbot/bin/certbot /usr/bin/certbot
```

&nbsp;
&nbsp;

## 2. CA가 서명한 인증서 작성

아파치 httpd 서버를 중지하고 CA가 서명한 인증서 `privkey.pem`{:.success} ,`cert.pem`{:.success}, `chain.pem`{:.success}를 만들기 위해
아래와 같이 명령어를 입력 후 순차적으로 값을 입력합니다.

```
# systemctl stop httpd
^
# certbot certonly --standalone
Saving debug log to /var/log/letsencrypt/letsencrypt.log
Enter email address (used for urgent renewal and security notices)
 (Enter 'c' to cancel): my-email-address@gmail.com <-------------------------------- 이메일 주소 입력
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Please read the Terms of Service at

 You must
agree in order to register with the ACME server. Do you agree?
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
(Y)es/(N)o: Y                                      <-------------------------------- Y
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Would you be willing, once your first certificate is successfully issued, to
share your email address with the Electronic Frontier Foundation, a founding
partner of the Let's Encrypt project and the non-profit organization that
develops Certbot? We'd like to send you email about our work encrypting the web,
EFF news, campaigns, and ways to support digital freedom.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
(Y)es/(N)o: N                                      <-------------------------------- N
Account registered.
Please enter the domain name(s) you would like on your certificate (comma and/or
space separated) (Enter 'c' to cancel): www.sample.com <---------------------------- 도메인 입력
Requesting a certificate for www.sample.com

Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/www.sample.com/fullchain.pem
Key is saved at:         /etc/letsencrypt/live/www.sample.com/privkey.pem
This certificate expires on 2024-12-14.
These files will be updated when the certificate renews.

NEXT STEPS:
- The certificate will need to be renewed before it expires. Certbot can automatically renew the certificate in the background, but you may need to take steps to enable that functionality. See https://certbot.org/renewal-setup for instructions.

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
If you like Certbot, please consider supporting our work by:
 * Donating to ISRG / Let's Encrypt:   https://letsencrypt.org/donate
 * Donating to EFF:                    https://eff.org/donate-le
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
```

&nbsp;
&nbsp;

## 3. ssl 모듈 설치

Apache의 SSL설정을 위해서는 `mod_ssl.so`{:.success}이 설치되어 있어야 합니다.
하기 명령어를 통해 사전에 설치가 되어 있는지 확인 후 설치가 되어있지 않다면 설치합니다.

```
# rpm -qa|grep mod_ssl
# ls -al /etc/httpd/modules/mod_ssl*
ls: cannot access mod_ssl*: No such file or directory
```
```
# yum -y install mod_ssl
```
```
# rpm -qa|grep mod_ssl
mod_ssl-2.4.6-90.el7.centos.x86_64
```
```
# ls -al /etc/httpd/modules/mod_ssl*
-rwxr-xr-x 1 root root 219536 Aug  8 20:42 /etc/httpd/modules/mod_ssl.so
```
```
# ls -al /etc/httpd/conf.d/ssl.conf
-rw-r--r-- 1 root root 9443 Sep 15 13:46 ssl.conf
```

&nbsp;
&nbsp;

## 4. 인증서 설정

ssl 모듈을 설치하면 하기 경로에 `ssl.conf`{:.success} 파일이 생성됩니다. 생성된 conf파일에 아래와 같이 설정합니다.  
www.sample.com은 예시입니다. `2`{:.info}에서 입력했던, 보유 중인 도메인을 입력합니다.

```
# cat /etc/httpd/conf.d/ssl.conf
```

```bash
...(생략)
SSLCertificateFile /etc/letsencrypt/live/www.sample.com/cert.pem
SSLCertificateKeyFile /etc/letsencrypt/live/www.sample.com/privkey.pem
SSLCertificateChainFile /etc/letsencrypt/live/www.sample.com/chain.pem
...(생략)
```

아파치 시작 (중지했던 Apache를 시작해줍니다.)
```
# systemctl start httpd
```

&nbsp;
&nbsp;

## 5. Crontab 스케줄 등록(자동갱신)

crontab에 스케줄을 등록합니다. let's encryt의 경우 최대 3개월까지 사용 가능하며, 이 후 갱신을 해줘야 합니다.  
매 3개월마다 수동으로 갱신하려면 번거롭기 때문에 crontab에 등록하여 서버거 자동갱신을 할 수 있도록 합니다.

crontab 설치
```
# dnf install cronie-noanacron
```

crontab 규칙은 순서대로 분, 시, 일, 월, 요일 입니다.  
아래 설정의 경우 매월 1일 오전 1시 30분에 인증서가 갱신 될 예정입니다.
```
# crontab -e
30 1 1 * *  root /usr/bin/certbot renew --pre-hook "systemctl stop httpd" --post-hook "systemctl start httpd"
```

&nbsp;
&nbsp;

참고사이트  
<https://blog.naver.com/PostView.naver?blogId=hanajava&logNo=221783483395>
<https://www.zinnunkebi.com/amazon-linux-2023-lets-encrypt>