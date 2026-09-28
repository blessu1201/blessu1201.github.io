---
layout: article
title: 시스템 관리_13 "Nginx/Apache SSL/TLS 핸드셰이크 실패(ERR_SSL_PROTOCOL_ERROR) 원인 및 완벽 해결 가이드"
tags: [Linux, Nginx, Apache, SSL, TLS, OpenSSL, HTTPS, Troubleshooting]
keys: 260925-linux-network-013
---

- 출처 / 참고: OpenSSL Documentation (s_client(1)), Mozilla SSL Configuration Generator, RFC 8446 (TLS 1.3)

> 명령어: `openssl`, `curl`, `nginx -t`, `apachectl -t`, `certbot`, `ss`  
> 키워드: ERR_SSL_PROTOCOL_ERROR, SSL Handshake Failed, ssl_certificate, SSLEngine, TLS Cipher, SNI  
> 사용처: 웹 서버(HTTPS) 접속 장애 해결, 브라우저 보안 경고 분석, SSL 인증서 갱신 후 서비스 비정상 동작 조치  

---

> 실행예제

`ERR_SSL_PROTOCOL_ERROR`는 클라이언트(브라우저)가 TLS 통신을 시도했으나 서버가 평문(HTTP)으로 응답하거나, 유효하지 않은 인증서 체인/암호화 스위트를 반환할 때 발생합니다. 문제 원인을 파악하기 위해 아래 명령어로 진단합니다.

```bash
# 1. OpenSSL s_client 명령어를 이용한 정밀 핸드셰이크 디버깅 (SNI 명시)
$ openssl s_client -connect example.com:443 -servername example.com -tls1_2
# -> 만약 "CONNECTED" 후 "write:errno=104" 또는 "error:140770FC:SSL routines:SSL23_GET_SERVER_HELLO:unknown protocol"
#    등이 출력되면 443 포트에 SSL 엔진 활성화가 안 되어 있거나 HTTP 평문이 응답하는 상태임

# 2. Curl 명령어로 SSL 상세 협상 과정 추적
$ curl -Iv https://example.com --tlsv1.2
*   Trying 192.168.1.100:443...
* Connected to example.com (192.168.1.100) port 443
* error:1408F10B:SSL routines:ssl3_get_record:wrong version number
* Closing connection 0
curl: (35) error:1408F10B:SSL routines:ssl3_get_record:wrong version number

# 3. 서버 내부 설정 문법 검사
# Nginx
$ sudo nginx -t

# Apache
$ sudo apachectl configtest

# 4. 443 포트가 실제로 웹 서버 프로세스에 의해 리스닝 중인지 확인
$ sudo ss -tulpn | grep :443
```

&nbsp;
&nbsp;

## 스크립트

웹 서버(Nginx / Apache)의 443 포트 수신 상태, SSL 인증서 및 개인키의 쌍(Pair) 일치 여부, 만료 일자를 자동으로 검증하는 점검 스크립트입니다.

```bash
#!/bin/bash
# ssl_troubleshoot.sh - Check SSL configuration, certificate validity, and key match

DOMAIN=${1:-"localhost"}
CERT_PATH=${2:-""}
KEY_PATH=${3:-""}

echo "=========================================="
echo " [SSL/TLS 진단 시작] 대상: ${DOMAIN}"
echo "=========================================="

# 1. 443 포트 리스닝 프로세스 확인
echo -e "\n[1] 443 포트 수신 상태:"
PORT_INFO=$(ss -tulpn | grep ':443 ')
if [ -z "$PORT_INFO" ]; then
    echo "  [오류] 443 포트가 리스닝 상태가 아닙니다. 웹 서버가 기동 중인지 확인하세요."
else
    echo "  [정상] 443 포트 리스닝 감지:"
    echo "  $PORT_INFO"
fi

# 2. OpenSSL을 통한 로컬 443 포트 SSL 핸드셰이크 테스트
echo -e "\n[2] 로컬 443 포트 SSL 핸드셰이크 테스트:"
HANDSHAKE_RES=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$DOMAIN" 2>&1)

if echo "$HANDSHAKE_RES" | grep -q "Verify return code: 0"; then
    echo "  [정상] 핸드셰이크 성공 및 유효한 인증서 확인."
elif echo "$HANDSHAKE_RES" | grep -q "wrong version number"; then
    echo "  [오류] 443 포트에서 평문(HTTP) 응답이 반환되고 있습니다."
    echo "  -> Nginx의 'listen 443 ssl;' 또는 Apache의 'SSLEngine on' 누락 점검 필요."
else
    ERROR_DETAIL=$(echo "$HANDSHAKE_RES" | grep -E "(error:|handshake failure|Connection refused)")
    echo "  [경고] 핸드셰이크 실패 또는 경고 발생:"
    echo "  ${ERROR_DETAIL:-$HANDSHAKE_RES}"
fi

# 3. 인증서와 개인키 파일 무결성 및 매칭 검사 (경로 지정 시)
if [ -n "$CERT_PATH" ] && [ -n "$KEY_PATH" ]; then
    echo -e "\n[3] 인증서와 개인키 모듈러스(Modulus) 일치 여부 검증:"
    if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
        echo "  [오류] 인증서 또는 키 파일 경로가 잘못되었습니다."
    else
        CERT_HASH=$(openssl x509 -noout -modulus -in "$CERT_PATH" 2>/dev/null | openssl md5)
        KEY_HASH=$(openssl rsa -noout -modulus -in "$KEY_PATH" 2>/dev/null | openssl md5)
        
        echo "  - Cert Hash: $CERT_HASH"
        echo "  - Key Hash : $KEY_HASH"
        
        if [ "$CERT_HASH" == "$KEY_HASH" ] && [ -n "$CERT_HASH" ]; then
            echo "  [정상] 인증서와 개인키의 키 쌍이 일치합니다."
        else
            echo "  [오류] 인증서와 개인키가 일치하지 않습니다! (핸드셰이크 실패의 직접적 원인)"
        fi
        
        # 만료 일자 체크
        echo -e "\n[4] 인증서 유효 기간:"
        openssl x509 -noout -dates -in "$CERT_PATH" | sed 's/^/  /'
    fi
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

`ERR_SSL_PROTOCOL_ERROR`는 웹 브라우저가 보안 채널(TLS) 수립을 위해 `Client Hello`를 전송했으나, 서버의 응답 규격이 TLS 프로토콜 표준을 따르지 않거나 거부될 때 브라우저에 표시되는 대표적인 에러입니다.

### 1. 주요 원인

1. **443 포트에 SSL 지시어 누락 (가장 흔한 원인)**:
   * 443 포트로 바인딩했으나 실제로는 암호화가 활성화되지 않아 일반 평문 HTTP로 응답하는 경우 (`wrong version number` 유발).
   * **Nginx**: `listen 443;`으로만 설정하고 `ssl` 파라미터를 빠뜨린 경우.
   * **Apache**: `<VirtualHost *:443>` 내부에 `SSLEngine on`이 빠진 경우.
2. **인증서와 개인키 불일치 (Key Mismatch)**:
   * 재발급 또는 갱신 과정에서 `ssl_certificate`와 `ssl_certificate_key`의 쌍이 맞지 않아 서버가 TLS 협상을 비정상 종료시키는 경우.
3. **중간 인증서 체인(Chain) 누락**:
   * 루트 CA까지 이어지는 중간 인증서(Fullchain)가 아닌 리프(도메인) 인증서만 등록하여 브라우저가 신뢰할 수 없는 프로토콜로 판단하는 경우.
4. **TLS 프로토콜 및 암호화 스위트(Cipher Suite) 불일치**:
   * 서버가 지원 중단된 구형 프로토콜(SSLv3, TLS 1.0, 1.1)만 허용하고 최신 TLS 1.2/1.3을 비활성화해두었거나 호환되는 암호화 스위트가 없는 경우.

### 2. 해결 방법

#### 1) Nginx 올바른 VirtualHost 구성
```nginx
server {
    listen 80;
    server_name example.com;
    return 301 https://$host$request_uri;
}

server {
    # 'ssl' 파라미터가 필수입니다. (Nginx 1.25.1+ HTTP/2는 'http2 on;' 권장)
    listen 443 ssl;
    server_name example.com;

    # 단일 crt가 아닌 fullchain.pem을 지정해야 체인 오류 방지
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    # 안전한 프로토콜 및 암호화 설정
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        root /var/www/html;
        index index.html;
    }
}
```

#### 2) Apache 올바른 VirtualHost 구성
```apache
<VirtualHost *:443>
    ServerName example.com
    DocumentRoot /var/www/html

    # SSLEngine 활성화 필수
    SSLEngine on

    SSLCertificateFile /etc/letsencrypt/live/example.com/cert.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/example.com/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/example.com/chain.pem

    # 최신 아파치의 경우 Fullchain 사용 가능
    # SSLCertificateFile /etc/letsencrypt/live/example.com/fullchain.pem
    # SSLCertificateKeyFile /etc/letsencrypt/live/example.com/privkey.pem

    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
</VirtualHost>
```

&nbsp;
&nbsp;

## 주의사항

1. **중간 인증서(Intermediate Certificate) 결합 필수**:
   * `cert.pem` 단독 사용 시 일부 데스크톱 브라우저는 로컬 캐시로 동작하더라도 모바일 기기나 특정 OS에서는 `ERR_SSL_PROTOCOL_ERROR` 또는 `SEC_ERROR_UNKNOWN_ISSUER`가 발생합니다. 항상 `fullchain.pem`을 사용해야 합니다.
2. **Reverse Proxy / 로드밸런서(ALB, Cloudflare 등) 환경의 SSL 종료(SSL Termination)**:
   * 로드밸런서에서 SSL을 해제(Termination)하고 백엔드 웹 서버와는 80번 HTTP로 통신하는 구조라면, 백엔드 Nginx/Apache에 별도의 443 포트 SSL 설정을 강제할 필요가 없습니다. 백엔드로 443 요청이 그대로 바이패스되는지, 평문으로 넘어오는지 아키텍처를 확인해야 합니다.
3. **방화벽/보안 장비의 DPI(Deep Packet Inspection) 차단**:
   * 사내 방화벽이나 클라우드 WAF가 비인가된 TLS 1.3 트래픽 또는 SNI 필터링을 수행하면서 핸드셰이크 패킷을 강제로 RST 시킬 경우 동일한 에러가 발생할 수 있습니다.