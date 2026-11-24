---
layout: article
title: 시스템 관리_72 SSL TLS 인증서 체인 오류 및 프로토콜 버전 불일치 핸드셰이크 실패 해결 가이드
tags: [Network, Security, SSL, TLS, Certificate-Chain, Intermediate-CA, Handshake-Failure, OpenSSL, Nginx, Troubleshooting]
keys: 261124-linux-network-072
---

- 출처 / 참고: IETF RFC 8446 (The Transport Layer Security Protocol Version 1.3), OpenSSL Documentation (openssl-s_client(1), openssl-verify(1)), Mozilla Server Side TLS Guidelines

> 명령어: `openssl`, `curl`, `ssllabs`, `cat`, `nginx`, `update-ca-trust`  
> 키워드: SSL Handshake Failure, Certificate Chain, Intermediate CA, Unable to verify the first certificate, TLS 1.2, TLS 1.3, Cipher Suite, SNI  
> 사용처: 웹 서버 또는 API 게이트웨이 SSL 인증서 갱신 후 PC 브라우저에서는 정상이나 모바일 앱/백엔드 API 호출 시 인증서 검증 실패(PKIX path building failed)가 발생하는 장애 해결

---

> 실행예제

SSL/TLS 인증서 설치 및 갱신 후 일반 크롬 브라우저에서는 정상 접속되지만, 백엔드 서버 간 API 호출(`curl`, Java `RestTemplate`, Python `requests`) 시 `SSL certificate problem: unable to get local issuer certificate` 또는 `handshake failure` 오류가 발생할 때 인증서 체인과 암호화 스위트를 점검합니다.

```bash
# 1. openssl s_client로 대상 서버가 내려주는 실제 인증서 체인(Chain) 깊이 확인
$ openssl s_client -connect example.com:443 -servername example.com -showcerts </dev/null
# CONNECTED(00000003)
# depth=0 CN = *.example.com
# verify error:num=20:unable to get local issuer certificate
# verify return:1
# depth=0 CN = *.example.com
# verify error:num=21:unable to verify the first certificate
# verify return:1
# ---
# Certificate chain
#  0 s:CN = *.example.com
#    i:C = US, O = DigiCert Inc, CN = DigiCert Global G2 TLS RSA SHA256 2020 CA1
# ---
# -> Certificate chain 목록에 0번(서버 인증서)만 있고 1번(중간 인증서, Intermediate CA)이 누락됨 확인!

# 2. 구형 클라이언트 호환성을 위한 TLS 1.2 및 TLS 1.3 프로토콜 핸드셰이크 개별 테스트
$ openssl s_client -connect example.com:443 -tls1_2 </dev/null | grep -E "Protocol|Cipher"
#     Protocol  : TLSv1.2
#     Cipher    : ECDHE-RSA-AES256-GCM-SHA384
$ openssl s_client -connect example.com:443 -tls1_3 </dev/null | grep -E "Protocol|Cipher"
#     Protocol  : TLSv1.3
#     Cipher    : TLS_AES_256_GCM_SHA384

# 3. 로컬 인증서 파일(.crt)과 개인키(.key)의 Modulus 해시 일치 여부 검증
$ openssl x509 -noout -modulus -in /etc/nginx/ssl/server.crt | openssl md5
# MD5(stdin)= 8a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d
$ openssl rsa -noout -modulus -in /etc/nginx/ssl/server.key | openssl md5
# MD5(stdin)= 8a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d
# -> 두 MD5 해시값이 정확히 일치해야 웹 서버 구동 시 'key values mismatch' 오류가 발생하지 않음
```

&nbsp;
&nbsp;

## 스크립트

원격 도메인 엔드포인트 또는 로컬 인증서 파일들을 검사하여 **1) 서버 인증서와 개인키의 짝(Modulus) 일치 여부, 2) 중간 인증서(Intermediate CA) 체인 누락 및 순서 오류 여부, 3) 만료 잔여 일수, 4) 지원 TLS 버전(1.0/1.1 취약 프로토콜 및 1.2/1.3 지원 상태)**을 일괄 검증하는 감사 쉘 스크립트입니다.

```bash
#!/bin/bash
# audit_ssl_tls_chain.sh - Audit SSL/TLS certificate chain completeness, expiry, and protocol support

TARGET_HOST=${1:-""}
TARGET_PORT=${2:-443}

echo "=========================================="
echo " [SSL/TLS 인증서 체인 및 프로토콜 정밀 진단기]"
echo "=========================================="

if [ -z "$TARGET_HOST" ]; then
    echo "  [오류] 점검할 도메인 호스트명을 입력하십시오."
    echo "  사용법: $0 <도메인명> [포트번호]"
    echo "  예시  : $0 api.example.com 443"
    exit 1
fi

if ! command -v openssl &>/dev/null; then
    echo "  [오류] openssl 패키지가 설치되어 있지 않습니다."
    exit 1
fi

echo "  점검 대상: ${TARGET_HOST}:${TARGET_PORT} (SNI 적용)"

# 1. 인증서 체인 개수 및 검증 상태 추출
echo -e "\n[1] 인증서 체인(Chain) 무결성 및 중간 인증서 점검:"
RAW_OUTPUT=$(echo | openssl s_client -connect "${TARGET_HOST}:${TARGET_PORT}" -servername "$TARGET_HOST" -showcerts 2>&1)

if echo "$RAW_OUTPUT" | grep -q "Connection refused\|Name or service not known"; then
    echo "  [오류] 대상 서버(${TARGET_HOST}:${TARGET_PORT})에 연결할 수 없습니다."
    exit 1
fi

CHAIN_COUNT=$(echo "$RAW_OUTPUT" | grep -c "BEGIN CERTIFICATE")
VERIFY_CODE=$(echo "$RAW_OUTPUT" | grep "Verify return code:" | awk -F':' '{print $2}' | tr -d ' ')

echo "  - 서버가 전송한 인증서 체인 수 : ${CHAIN_COUNT} 개"
echo "  - OpenSSL 검증 결과 코드       : ${VERIFY_CODE}"

if [ "$CHAIN_COUNT" -lt 2 ]; then
    echo "  [치명적 경고] 중간 인증서(Intermediate CA)가 서버 설정에서 누락되었습니다!"
    echo "  -> 현상: PC 브라우저는 캐시로 접속되나 Java, Python, curl, 모바일 앱에서는 'PKIX/unable to verify' 에러가 발생합니다."
    echo "  -> 조치: 서버 인증서(Leaf) 하단에 중간 인증서(Chain)를 순서대로 병합(cat server.crt chain.crt > fullchain.crt)하십시오."
elif echo "$VERIFY_CODE" | grep -q "^0 "; then
    echo "  [정상] 서버 및 중간 인증서 체인이 루트 CA까지 완벽하게 연결되어 있습니다."
else
    echo "  [주의] 인증서 체인 검증 오류가 감지되었습니다: ${VERIFY_CODE}"
fi

# 2. 인증서 만료일 및 잔여 일수 계산
echo -e "\n[2] 인증서 유효 기간 및 만료일 확인:"
END_DATE_STR=$(echo "$RAW_OUTPUT" | openssl x509 -noout -enddate 2>/dev/null | cut -d'=' -f2)
if [ -n "$END_DATE_STR" ]; then
    END_EPOCH=$(date -d "$END_DATE_STR" +%s 2>/dev/null)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (END_EPOCH - NOW_EPOCH) / 86400 ))
    echo "  - 만료 일시 : ${END_DATE_STR}"
    echo "  - 잔여 일수 : ${DAYS_LEFT} 일 남음"
    
    if [ "$DAYS_LEFT" -lt 30 ]; then
        echo "  [경고] 인증서 만료가 30일 이내로 임박했습니다! 갱신 절차를 진행하십시오."
    fi
fi

# 3. TLS 프로토콜 버전별 지원 현황 테스트
echo -e "\n[3] 지원 TLS 프로토콜 버전 테스트:"
for PROTO in tls1 tls1_1 tls1_2 tls1_3; do
    TEST_RES=$(echo | openssl s_client -connect "${TARGET_HOST}:${TARGET_PORT}" -servername "$TARGET_HOST" -"$PROTO" 2>&1)
    if echo "$TEST_RES" | grep -q "Cipher is "; then
        CIPHER_USED=$(echo "$TEST_RES" | grep "Cipher is " | awk '{print $NF}')
        if [ "$PROTO" = "tls1" ] || [ "$PROTO" = "tls1_1" ]; then
            echo "  - ${PROTO^^} : [활성화됨 - 보안 취약!] 구형 취약 프로토콜 비활성화 권고 (Cipher: ${CIPHER_USED})"
        else
            echo "  - ${PROTO^^} : [정상 지원] (Cipher: ${CIPHER_USED})"
        fi
    else
        echo "  - ${PROTO^^} : 미지원/비활성화"
    fi
done

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

SSL/TLS 인증서를 신규 발급받거나 갱신한 직후, **"담당자 PC의 크롬/엣지 브라우저에서는 자물쇠 아이콘이 뜨면서 정상 접속되는데, 유독 리눅스 백엔드 API 서버(Java/Python/curl)나 모바일 앱에서만 SSL 검증 오류가 나며 통신이 안 되는 현상"**은 실무에서 가장 자주 겪는 장애입니다.

### 1. 왜 브라우저에서는 되는데 API 서버에서는 실패하는가 (중간 인증서 누락)

공인 인증기관(DigiCert, Sectigo, Let's Encrypt 등)은 루트 인증서(Root CA)의 개인키를 보호하기 위해 직접 서버 인증서를 발급하지 않고, 중간에 **중간 인증서(Intermediate CA)**를 거쳐 서명합니다.

* **브라우저의 AIA(Authority Information Access) 자동 보완**:
  * 데스크톱 웹 브라우저는 서버가 중간 인증서를 안 내려주더라도, 인증서 내부에 적힌 AIA URL을 보고 백그라운드에서 중간 인증서를 몰래 다운로드하여 체인을 스스로 완성해 줍니다.
* **백엔드 라이브러리(OpenSSL, Java JSSE)의 엄격한 검증**:
  * 리눅스의 `curl`, `openssl`, Java `HttpClient`는 보안을 위해 외부에서 인증서를 몰래 다운로드하지 않습니다. 서버가 핸드셰이크 과정에서 **서버 인증서 + 중간 인증서 체인 전체(`fullchain.pem`)**를 한 번에 내려주지 않으면 신뢰 고리가 끊어져 `PKIX path building failed` 또는 `unable to get local issuer certificate` 에러를 내며 연결을 거부합니다.

### 2. 올바른 인증서 체인 병합 순서 (Chain Order)

인증서 파일을 하나로 합칠 때는 반드시 **하위(서버)에서 상위(루트 방향) 순서**대로 쌓아야 합니다.

```bash
# 올바른 병합 순서: 1. 서버 도메인 인증서 -> 2. 중간 인증서(Chain) -> (선택) 루트 인증서
cat domain.crt intermediate_ca.crt > fullchain.crt
```
* 순서가 뒤바뀌어 중간 인증서가 맨 위에 오면 Nginx/Apache 구동 시 `SSL_CTX_use_PrivateKey_file: key values mismatch` 오류가 발생합니다.

### 3. TLS 1.2 / 1.3 및 안전한 암호화 스위트 표준 구성 (Nginx 기준)

구형 취약 프로토콜(TLS 1.0, TLS 1.1)을 차단하고 최신 보안 및 성능을 확보하는 표준 설정입니다.

```nginx
server {
    listen 443 ssl http2;
    server_name api.example.com;

    # 반드시 중간 인증서가 포함된 fullchain 파일 지정
    ssl_certificate /etc/nginx/ssl/fullchain.crt;
    ssl_certificate_key /etc/nginx/ssl/domain.key;

    # 안전 프로토콜만 허용
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;

    # SSL 세션 캐시 및 OCSP Stapling 활성화로 핸드셰이크 지연 단축
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_stapling_verify on;
}
```

&nbsp;
&nbsp;

## 주의사항

1. **사설(Private) CA 인증서 연동 시 클라이언트 OS 신뢰 저장소 등록 필수**:
   * 내부망 전용 사설 CA(OpenSSL 자체 서명 등)로 발급한 인증서를 연동할 때는 서버 측 체인 구성뿐만 아니라, 호출하는 클라이언트 서버의 OS 신뢰 저장소(`/etc/pki/ca-trust/source/anchors/` 후 `update-ca-trust`) 및 Java `cacerts` 키스토어에 해당 사설 루트 CA를 직접 임포트해야 합니다.

2. **SNI(Server Name Indication) 미지원 구형 클라이언트 주의**:
   * 단일 IP에 여러 개의 도메인 SSL 인증서를 호스팅하는 경우, TLS 핸드셰이크 초기 `ClientHello` 패킷에 도메인명을 실어 보내는 **SNI** 확장이 필수입니다. 매우 오래된 레거시 시스템이나 구형 모니터링 에이전트는 SNI를 보내지 않아 첫 번째 기본(Default) 가상 호스트의 잘못된 인증서를 받아 검증 실패를 일으킬 수 있습니다.

3. **개인키(`.key`) 파일 권한 엄격 통제**:
   * 인증서 개인키 파일이 타 사용자에게 노출되면 트래픽 복호화 및 중간자(MITM) 위조가 가능해지므로, 반드시 소유자를 `root`로 하고 파일 퍼미션을 `600` (`chmod 600 domain.key`)으로 제한해야 합니다.