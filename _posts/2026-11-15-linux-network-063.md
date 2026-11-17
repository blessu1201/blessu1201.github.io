---
layout: article
title: 시스템 관리_63 웹 방화벽 WAF 오탐 False Positive 예외 처리 및 SSL 오프로딩 헤더 유실 해결 가이드
tags: [Network, Security, WAF, ModSecurity, Nginx, SSL-Offloading, X-Forwarded-For, False-Positive, Troubleshooting]
keys: 261115-linux-network-063
---

- 출처 / 참고: OWASP ModSecurity Core Rule Set (CRS) Documentation, Nginx Reverse Proxy & SSL Termination Guide, IETF RFC 7239 (Forwarded HTTP Extension)

> 명령어: `grep`, `awk`, `curl`, `nginx`, `tail`, `openssl`  
> 키워드: WAF, Web Application Firewall, False Positive, ModSecurity, SecRuleRemoveById, SSL Offloading, X-Forwarded-For, X-Forwarded-Proto, 403 Forbidden  
> 사용처: 웹 방화벽(WAF) 도입 후 정상적인 게시글 등록/API 호출이 403으로 차단되거나, 백엔드 웹 서버에서 클라이언트 실제 IP와 HTTPS 프로토콜을 인식하지 못하는 장애 해결

---

> 실행예제

웹 방화벽(WAF) 적용 후 정상적인 사용자 요청(예: 게시판 에디터 HTML 전송, JSON API 페이로드)이 `403 Forbidden`으로 차단되거나, WAF 뒤단의 Nginx/WAS에서 모든 접속자 IP가 WAF의 내부 사설 IP로 찍히는 현상을 진단합니다.

```bash
# 1. WAF 감사 로그(ModSecurity Audit Log 예시)에서 차단된 룰 ID 및 오탐 사유 추출
$ sudo grep -E "id \"[0-9]+\"|uri \"|msg \"" /var/log/modsec_audit.log | tail -n 15
# [출력 예시]
# [uri "/api/v1/board/write"]
# [id "941100"] [msg "XSS Attack Detected via libinjection"] [data "Matched Data: <p>Hello</p> found within ARGS:content"]
# -> 정상적인 웹 에디터 HTML 태그(<p>) 입력이 OWASP CRS 941100번 XSS 룰에 걸려 오탐(False Positive) 차단됨 확인

# 2. 클라이언트 관점: curl로 요청을 보내 WAF 차단 응답 코드 및 헤더 확인
$ curl -i -X POST https://example.com/api/v1/board/write -d "content=<p>Hello</p>"
# HTTP/2 403
# server: cloud-waf
# content-type: text/html
# -> 백엔드 WAS까지 도달하지 못하고 앞단 WAF에서 403 리턴됨 확인

# 3. 백엔드 웹 서버(Nginx) 액세스 로그에서 클라이언트 IP 및 프로토콜 인식 상태 확인
$ tail -n 5 /var/log/nginx/access.log
# 10.0.1.5 - - [15/Nov/2026:11:20:05 +0900] "GET /login HTTP/1.1" 302 154 "-" "Mozilla/5.0..."
# -> 모든 접속자 IP가 실제 사용자 공인 IP가 아닌 WAF 장비의 사설 IP(10.0.1.5)로 기록됨

# 4. WAF에서 백엔드로 넘어오는 실제 HTTP 요청 헤더(X-Forwarded-For, X-Forwarded-Proto) 덤프 확인
$ sudo tcpdump -A -s 0 -i eth0 port 8080 | grep -iE "Host:|X-Forwarded|X-Real-IP" -m 10
# Host: example.com
# X-Forwarded-For: 203.0.113.88
# X-Forwarded-Proto: https
# -> WAF는 헤더를 잘 붙여서 넘겨주었으나 백엔드 웹/WAS가 이를 신뢰(Trusted Proxy)하도록 설정되지 않아 유실됨
```

&nbsp;
&nbsp;

## 스크립트

ModSecurity 또는 리버스 프록시 로그에서 `403 Forbidden`으로 가장 빈번하게 차단된 오탐(False Positive) 룰 ID와 대상 URI 통계를 추출하여 즉각 적용 가능한 URI 기반 핀포인트 예외 처리(Rule Exclusion) 설정 스니펫을 생성해 주는 진단 쉘 스크립트입니다.

```bash
#!/bin/bash
# analyze_waf_false_positives.sh - Analyze WAF 403 blocks and generate targeted URI rule exclusions

AUDIT_LOG=${1:-"/var/log/modsec_audit.log"}

echo "=========================================="
echo " [웹 방화벽(WAF) 오탐(False Positive) 분석기]"
echo " 분석 대상 로그: ${AUDIT_LOG}"
echo "=========================================="

if [ ! -f "$AUDIT_LOG" ]; then
    echo "  [오류] WAF 감사 로그 파일을 찾을 수 없습니다: ${AUDIT_LOG}"
    echo "  사용법: sudo $0 [WAF_로그_경로]"
    exit 1
fi

# 1. 가장 많이 차단된 WAF Rule ID Top 10 추출
echo -e "\n[1] 최다 차단 탐지 룰 ID (Top 10):"
grep -oE '\[id "[0-9]+"\]' "$AUDIT_LOG" | awk -F'"' '{print $2}' | sort | uniq -c | sort -nr | head -n 10 | \
while read -r COUNT RULE_ID; do
    RULE_MSG=$(grep -m 1 "\[id \"${RULE_ID}\"\]" "$AUDIT_LOG" | grep -oE '\[msg "[^"]+"\]' | cut -d'"' -f2)
    printf "  - 차단 횟수: %-6s | 룰 ID: %-8s | 탐지 사유: %s\n" "${COUNT}건" "$RULE_ID" "${RULE_MSG:-"설명없음"}"
done

# 2. 오탐이 집중되는 특정 URI 경로 추출
echo -e "\n[2] 차단 이벤트 집중 발생 URI 경로 (Top 5):"
grep -oE '\[uri "[^"]+"\]' "$AUDIT_LOG" | awk -F'"' '{print $2}' | sort | uniq -c | sort -nr | head -n 5 | \
while read -r COUNT URI_PATH; do
    printf "  - 차단 횟수: %-6s | 대상 URI: %s\n" "${COUNT}건" "$URI_PATH"
done

# 3. 안전하고 정밀한 예외 처리(Pinpoint Exclusion) 권장 스니펫 출력
TOP_RULE=$(grep -oE '\[id "[0-9]+"\]' "$AUDIT_LOG" | awk -F'"' '{print $2}' | sort | uniq -c | sort -nr | head -n 1 | awk '{print $2}')
TOP_URI=$(grep -oE '\[uri "[^"]+"\]' "$AUDIT_LOG" | awk -F'"' '{print $2}' | sort | uniq -c | sort -nr | head -n 1 | awk '{print $2}')

if [ -n "$TOP_RULE" ] && [ -n "$TOP_URI" ]; then
    echo -e "\n[3] 핀포인트 예외 처리 권장 설정 (전역 비활성화 금지):"
    echo "  -> 특정 URI(${TOP_URI})에 대해서만 해당 룰(${TOP_RULE})을 해제하여 보안 홀 방지:"
    echo "------------------------------------------------------------------"
    echo "  # ModSecurity / Nginx 예외 규칙 예시:"
    echo "  SecRule REQUEST_URI \"@beginsWith ${TOP_URI}\" \\"
    echo "      \"id:100001,phase:1,nolog,pass,ctl:ruleRemoveById=${TOP_RULE}\""
    echo "------------------------------------------------------------------"
fi

echo -e "\n=========================================="
echo " [분석 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

엔터프라이즈 웹 서비스 앞단에 웹 방화벽(WAF: Web Application Firewall)을 구축하면 SQL Injection, XSS 등의 웹 공격을 방어할 수 있지만, 초기 도입 및 운영 과정에서 **1) 정상 트래픽 차단(오탐: False Positive)**과 **2) SSL 종단(SSL Offloading) 구조로 인한 원본 클라이언트 IP/프로토콜 유실**이라는 두 가지 대표적인 트러블슈팅 과제가 발생합니다.

### 1. WAF 오탐(False Positive)의 원인과 정밀 예외 처리

* **발생 원인**:
  * OWASP CRS(Core Rule Set) 등의 표준 보안 시그니처는 특수문자(`'`, `--`, `<script>`, `SELECT`, `UNION`) 조합을 공격으로 간주합니다.
  * 따라서 개발자 커뮤니티 게시판, HTML 위지윅(WYSIWYG) 에디터, 또는 Base64 인코딩된 긴 토큰 값이 포함된 API 페이로드가 전송될 때 정상 요청임에도 403 Forbidden 에러를 내며 차단됩니다.
* **올바른 예외 처리 원칙 (전역 해제 금지)**:
  * 해당 룰 ID(예: `941100`)를 시스템 전체(Global)에서 꺼버리면 웹 사이트 전체가 XSS 공격에 무방비로 노출됩니다.
  * 반드시 **"특정 URI 경로(`/api/v1/board/write`)의 특정 파라미터(`ARGS:content`)에 한해서만 해당 룰 ID를 제거"**하는 핀포인트 예외 룰을 작성해야 합니다.

### 2. SSL 오프로딩(SSL Termination)에 따른 헤더 유실 해결

성능 최적화를 위해 WAF나 앞단 L4 로드밸런서에서 HTTPS(443) 암호화를 해제(SSL Offloading)한 뒤, 내부 백엔드 웹/WAS 서버로는 평문 HTTP(80 또는 8080)로 트래픽을 전달하는 구성이 표준입니다.

이때 백엔드 서버 설정을 보완하지 않으면 두 가지 치명적 버그가 터집니다:
1. **클라이언트 IP 왜곡**: 백엔드 접근 로그와 보안 감사 로그에 실제 해커/사용자 IP가 아닌 WAF 장비 IP만 찍힘.
2. **HTTPS 무한 리다이렉트 루프 (ERR_TOO_MANY_REDIRECTS)**: 백엔드 WAS가 자신이 받은 평문 HTTP 트래픽을 보고 "사용자가 HTTP로 들어왔으니 HTTPS로 리다이렉트 시켜야겠다"고 판단하여 `302 Redirect -> https://...`를 응답하고, WAF는 이를 다시 HTTP로 백엔드에 넘기면서 무한 루프에 빠짐.

#### 백엔드 웹 서버(Nginx) 표준 복원 설정

```nginx
# /etc/nginx/conf.d/proxy_real_ip.conf
# 1. WAF 장비의 사설 IP 대역을 신뢰할 수 있는 프록시로 등록
set_real_ip_from 10.0.1.0/24;

# 2. 실제 클라이언트 IP가 담긴 헤더 지정
real_ip_header X-Forwarded-For;
real_ip_recursive on;

server {
    listen 8080;
    server_name example.com;

    location / {
        proxy_pass http://127.0.0.1:8081;
        # WAF가 전달해 준 원본 프로토콜(https)과 호스트 정보를 WAS(Tomcat/Spring)로 계승
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
    }
}
```

#### 백엔드 WAS (Spring Boot / Tomcat) 설정 보완
Spring Boot의 경우 `application.yml`에 프록시 헤더 신뢰 옵션을 켜야 `request.isSecure()`가 정상적으로 `true`를 반환합니다.
```yaml
server:
  forward-headers-strategy: native
```

&nbsp;
&nbsp;

## 주의사항

1. **`X-Forwarded-For` 헤더 스푸핑(Spoofing) 보안 취약점 방어**:
   * 백엔드 웹 서버에서 `set_real_ip_from` 대역을 `0.0.0.0/0`(전체 허용)으로 열어두면, 악의적인 공격자가 직접 자신의 HTTP 요청 헤더에 `X-Forwarded-For: 127.0.0.1`을 위조하여 내부 관리자 페이지 인증을 우회할 수 있습니다. 반드시 **실제 WAF/로드밸런서 장비의 사설 IP 대역만 엄격하게 등록**해야 합니다.

2. **WAF 운영 전환 전 탐지 모드(Detection Only) 필수**:
   * 신규 서비스 런칭이나 보안 룰 대규모 업데이트 시 바로 차단 모드(`SecRuleEngine On`)를 켜면 정상 트래픽이 마비됩니다. 최소 1~2주간 탐지 모드(`SecRuleEngine DetectionOnly`)로 운영하면서 오탐 로그를 수집하고 예외 규칙을 모두 튜닝한 뒤 차단 모드로 전환해야 합니다.

3. **대용량 파일 업로드 시 WAF Request Body 제한 확인**:
   * WAF는 검사를 위해 HTTP 요청 본문(Body)을 메모리에 버퍼링합니다. 기본 본문 검사 제한(예: 128KB 또는 1MB)을 초과하는 첨부파일 업로드 시 413 또는 403 에러로 차단될 수 있으므로, 업로드 전용 경로는 본문 크기 상한(`SecRequestBodyLimit`)을 조정하거나 바이너리 검사를 예외 처리해야 합니다.