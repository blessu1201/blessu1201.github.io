---
layout: article
title: 시스템 관리_14 "SSL 인증서 갱신 후에도 'Certificate has expired' 오류가 발생하는 원인 및 신뢰 체인(Chain of Trust) 해결 가이드"
tags: [Linux, SSL, TLS, Nginx, Apache, Certbot, OpenSSL, Certificate-Chain]
keys: 260926-linux-network-014
---

- 출처 / 참고: OpenSSL Documentation (verify(1), x509(1)), RFC 5280 (PKI Certificate and CRL Profile)

> 명령어: `openssl`, `systemctl`, `certbot`, `update-ca-certificates`, `trust`  
> 키워드: Certificate has expired, Chain of Trust, Intermediate CA, Cross-Signing, fullchain.pem, OpenSSL verify  
> 사용처: Let's Encrypt 또는 유료 인증서 갱신 후 웹 브라우저/API 클라이언트에서 만료 경고 지속 발생 시 원인 분석 및 긴급 복구  

---

> 실행예제

인증서를 디스크 상에 새로 발급/다운로드했음에도 클라이언트에서 만료 오류가 지속되는 경우, 실제 웹 서버 프로세스가 물고 있는 메모리 상의 인증서와 인증서 체인(Intermediate/Root CA)을 점검해야 합니다.

```bash
# 1. 실제 외부(또는 로컬) 포트에서 서빙 중인 인증서의 유효기간 및 체인 확인
$ openssl s_client -connect example.com:443 -servername example.com -showcerts < /dev/null 2>/dev/null | openssl x509 -noout -dates -subject -issuer
notBefore=Sep 28 00:00:00 2026 GMT
notAfter=Dec 27 23:59:59 2026 GMT
subject=CN = example.com
issuer=C = US, O = Let's Encrypt, CN = R3

# 2. 서버 전체 체인 검증 (만료된 중간 CA 또는 크로스 서명 CA가 체인에 포함되어 있는지 확인)
$ openssl s_client -connect example.com:443 -servername example.com < /dev/null
# Verify return code 출력 확인:
# -> verify error:num=10:certificate has expired (체인 상에 만료된 상위/크로스 서명 CA가 존재함)

# 3. 디스크에 저장된 인증서 파일과 실제 메모리에서 서비스 중인 인증서의 해시값 비교
$ openssl x509 -noout -fingerprint -sha256 -in /etc/letsencrypt/live/example.com/cert.pem
# 외부에서 직접 받아온 인증서 핑거프린트
$ echo | openssl s_client -connect 127.0.0.1:443 -servername example.com 2>/dev/null | openssl x509 -noout -fingerprint -sha256

# 4. 클라이언트(서버 로컬)의 자체 신뢰 저장소(CA-Bundle) 기준 검증
$ openssl verify -CApath /etc/ssl/certs /etc/letsencrypt/live/example.com/fullchain.pem
```

&nbsp;
&nbsp;

## 스크립트

서버가 제공 중인 인증서 체인 각 단계(리프 인증서, 중간 CA, 루트 CA)의 유효기간을 하나씩 분리하여 만료 여부를 판별하고 프로세스 리로드 누락을 진단하는 스크립트입니다.

```bash
#!/bin/bash
# check_cert_chain.sh - Validate SSL Chain of Trust and expiration dates

TARGET_HOST=${1:-"localhost"}
TARGET_PORT=${2:-"443"}

echo "=========================================="
echo " [신뢰 체인 진단 시작] 대상: ${TARGET_HOST}:${TARGET_PORT}"
echo "=========================================="

TMP_CERTS_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_CERTS_DIR"' EXIT

# 1. 원격지로부터 서빙 중인 전체 인증서 체인 추출
echo -e "\n[1] 웹 서버 제공 인증서 체인 다운로드..."
echo | openssl s_client -connect "${TARGET_HOST}:${TARGET_PORT}" -servername "${TARGET_HOST}" -showcerts 2>/dev/null > "${TMP_CERTS_DIR}/raw_chain.txt"

if ! grep -q "BEGIN CERTIFICATE" "${TMP_CERTS_DIR}/raw_chain.txt"; then
    echo "  [오류] 인증서 체인을 가져올 수 없습니다. 포트가 닫혀있거나 TLS 연결이 불가능합니다."
    exit 1
fi

# 2. 개별 인증서 블록 분리 후 각 단계 만료일 검사
awk 'BEGIN {c=0;} /BEGIN CERTIFICATE/ {c++} { print > ("'${TMP_CERTS_DIR}'/cert_" c ".crt") }' "${TMP_CERTS_DIR}/raw_chain.txt"

CURRENT_DATE_EPOCH=$(date +%s)
HAS_EXPIRED=false

echo -e "\n[2] 체인 단계별 유효 기간 및 발급자 검사:"
for cert_file in "${TMP_CERTS_DIR}"/cert_*.crt; do
    echo "----------------------------------------"
    SUBJECT=$(openssl x509 -in "$cert_file" -noout -subject | sed 's/subject=//')
    ISSUER=$(openssl x509 -in "$cert_file" -noout -issuer | sed 's/issuer=//')
    END_DATE_STR=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    END_DATE_EPOCH=$(date -d "$END_DATE_STR" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$END_DATE_STR" +%s)

    echo "  - Subject: $SUBJECT"
    echo "  - Issuer : $ISSUER"
    echo "  - 만료일 : $END_DATE_STR"

    if [ "$CURRENT_DATE_EPOCH" -gt "$END_DATE_EPOCH" ]; then
        echo "  [!] 경고: 해당 체인 인증서는 이미 만료되었습니다!"
        HAS_EXPIRED=true
    else
        DAYS_LEFT=$(( (END_DATE_EPOCH - CURRENT_DATE_EPOCH) / 86400 ))
        echo "  [정상] 만료까지 ${DAYS_LEFT}일 남음"
    fi
done

# 3. 디스크 vs 구동 중인 프로세스 불일치 확인 (Nginx/Apache 미재기동 여부)
echo -e "\n[3] 웹 데몬 리로드 점검:"
if [ "$TARGET_HOST" == "localhost" ] || [ "$TARGET_HOST" == "127.0.0.1" ]; then
    NGINX_PID=$(pgrep -o nginx)
    if [ -n "$NGINX_PID" ]; then
        START_TIME=$(ps -o lstart= -p "$NGINX_PID")
        echo "  - Nginx 프로세스 구동 시각: $START_TIME"
        echo "  -> 갱신 후 'nginx -s reload'를 실행했는지 확인하십시오."
    fi
fi

echo -e "\n=========================================="
if [ "$HAS_EXPIRED" = true ]; then
    echo " [진단 결과] 체인 내부(중간 CA 또는 크로스 서명)에 만료된 인증서가 포함되어 있습니다."
else
    echo " [진단 결과] 체인 자체는 유효합니다. 클라이언트 측 CA 번들(신뢰 저장소) 노후화 여부를 점검하세요."
fi
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

인증서를 성공적으로 갱신했음에도 브라우저나 API 호출(curl, Python requests 등) 시 `Certificate has expired` 오류가 지속되는 원인은 주로 **웹 서버 미재기동**, **불완전한 인증서 체인(cert.pem 사용)**, 또는 **상위 크로스 서명(Cross-signed) 중간 CA의 만료** 때문입니다.

### 1. 주요 발생 원인

1. **웹 서버 프로세스 미재기동 (가장 흔한 실수)**:
   * Certbot 등으로 파일(`/etc/letsencrypt/...`)은 갱신되었으나, Nginx나 Apache 프로세스를 `reload` 또는 `restart`하지 않아 메모리에 이전 만료 인증서가 계속 로드되어 있는 경우.
2. **단일 인증서(`cert.pem`)만 등록 (중간 인증서 누락)**:
   * `ssl_certificate` 경로에 중간 CA가 포함된 `fullchain.pem`이 아닌 `cert.pem` 단독 파일만 지정한 경우. 최신 브라우저는 AIA 패치로 보완하기도 하지만, 구형 클라이언트나 API 도구(Python, Java, curl)는 신뢰 체인 검증에 실패하여 만료 오류를 냅니다.
3. **만료된 크로스 서명(Cross-signed) 체인 잔존**:
   * Let's Encrypt의 구형 루트 CA(IdenTrust DST Root CA X3) 만료 사태처럼, 상위 인증 기관의 크로스 서명 중간 인증서가 만료되었으나 서버의 체인 파일에 구형 체인이 여전히 포함되어 있는 경우.
4. **클라이언트 시스템의 `ca-certificates` 노후화**:
   * 서버 설정은 정상이지만, 요청을 보내는 클라이언트(서버, 컨테이너, 임베디드 기기 등)의 로컬 루트 CA 신뢰 저장소가 오래되어 갱신된 최신 루트 CA(ISRG Root X1 등)를 신뢰하지 못하는 경우.

### 2. 단계별 복구 및 해결 방법

1. **웹 서버 무중단 리로드**:
   * 파일 갱신 후 반드시 설정 리로드를 실행합니다:
     ```bash
     sudo nginx -t && sudo systemctl reload nginx
     # Apache의 경우
     sudo apachectl configtest && sudo systemctl reload apache2
     ```
2. **올바른 체인 파일(`fullchain.pem`) 연결**:
   * 웹 서버 설정 파일에서 반드시 단일 인증서가 아닌 체인 일체형 파일을 지정합니다:
     ```nginx
     # Nginx
     ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
     ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
     ```
3. **Certbot 자동 갱신 훅(Hook) 등록**:
   * 갱신 성공 시 서버가 자동으로 리로드되도록 `/etc/letsencrypt/renewal-hooks/deploy/` 경로에 훅 스크립트를 추가하거나 `certbot renew --deploy-hook "systemctl reload nginx"` 옵션을 지정합니다.
4. **클라이언트 시스템의 루트 CA 신뢰 저장소 업데이트**:
   * API 서버 또는 호출 클라이언트 환경에서 최신 신뢰 목록을 갱신합니다:
     ```bash
     # Ubuntu / Debian
     sudo apt-get install --reinstall ca-certificates
     sudo update-ca-certificates

     # RHEL / CentOS / Rocky
     sudo yum reinstall ca-certificates
     sudo update-ca-trust
     ```

&nbsp;
&nbsp;

## 주의사항

1. **`cert.pem`과 `chain.pem` 순서**:
   * 수동으로 `fullchain.pem`을 병합할 경우, 반드시 **내 도메인 인증서(Leaf)가 가장 위**, 그 아래에 **중간 인증서(Intermediate CA)** 순서로 결합되어야 합니다. 순서가 바뀌면 핸드셰이크 시 파싱 오류가 발생합니다.
2. **도커(Docker) 및 컨테이너 환경 주의**:
   * 호스트 OS에서 볼륨 마운트로 인증서 디렉터리를 연결한 경우, 심볼릭 링크(`live/` 디렉터리의 링크) 참조가 깨지거나 컨테이너 내부 프로세스가 파일 변경 이벤트를 감지하지 못할 수 있습니다. 마운트 대상 컨테이너도 함께 재시작(`docker compose restart web`)해주어야 합니다.
3. **Java 애플리케이션(JVM Keystore) 주의**:
   * Java 기반 서버(Tomcat, Spring Boot)나 API 클라이언트는 OS의 `/etc/ssl/certs` 대신 JVM 내부의 `cacerts` 키스토어를 별도로 참조합니다. 시스템 CA를 업데이트해도 JVM `cacerts`에 루트/중간 CA가 없으면 동일한 만료 예외(`ValidatorException: PKIX path validation failed`)가 발생하므로 필요시 `keytool`로 수동 임포트해야 합니다.