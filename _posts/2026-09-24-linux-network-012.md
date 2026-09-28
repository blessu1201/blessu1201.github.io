---
layout: article
title: 시스템 관리_12 "리눅스 DNS 장애 해결 가이드 'Temporary failure in name resolution' 원인 및 복구 방법"
tags: [Linux, Network, DNS, Resolv.conf, Systemd-resolved, Troubleshooting, Dig]
keys: 260924-linux-network-012
---

- 출처 / 참고: Linux man-pages (resolv.conf(5), systemd-resolved(8)), RFC 1035 (Domain Names)

> 명령어: `dig`, `nslookup`, `resolvectl`, `systemctl`, `ping`, `ip route`  
> 키워드: Temporary failure in name resolution, DNS timeout, resolv.conf, systemd-resolved, 네임서버, 53 포트  
> 사용처: `apt`/`yum` 패키지 설치 실패, `curl`/`wget` 도메인 호출 에러, 리눅스 서버 초기 네트워크 구축 장애 대응  

---

> 실행예제

도메인 해석 실패 시 원인이 로컬 DNS 서비스인지, 설정 파일 누락인지, 외부 53번 포트 통신 차단인지를 분리하여 파악합니다.

```bash
# 1. 장애 현상 확인: ping 또는 curl 호출 시 오류 발생
$ ping -c 2 google.com
ping: google.com: Temporary failure in name resolution

# 2. IP 직통 통신 여부 확인 (게이트웨이/외부 라우팅 정상 여부 분리)
$ ping -c 2 8.8.8.8
64 bytes from 8.8.8.8: icmp_seq=1 ttl=116 time=12.4 ms
# -> IP 핑이 성공한다면 네트워크 라우팅은 정상이지만 순수 DNS 해석 문제임을 확정

# 3. 현재 등록된 DNS 네임서버 설정 확인
$ cat /etc/resolv.conf
# 만약 파일이 비어있거나 올바른 nameserver IP가 없다면 에러 발생

# 4. systemd-resolved 상태 및 바인딩된 업스트림 DNS 점검
$ resolvectl status
# 또는
$ systemctl status systemd-resolved

# 5. 특정 네임서버를 직접 지정하여 질의 테스트 (53번 포트 통신 가능 여부)
$ dig @8.8.8.8 google.com +time=3
```

&nbsp;
&nbsp;

## 스크립트

현재 시스템의 DNS 해석 경로(`resolv.conf`, `systemd-resolved`, 외부 53번 UDP/TCP 통신, 게이트웨이)를 순차 점검하고 문제를 진단하는 쉘 스크립트입니다.

```bash
#!/bin/bash
# dns_troubleshoot.sh - Diagnose Linux DNS resolution failures

TARGET_DOMAIN=${1:-"google.com"}
TEST_DNS="8.8.8.8"

echo "=========================================="
echo " [DNS 진단 시작] 대상 도메인: ${TARGET_DOMAIN}"
echo "=========================================="

# 1. 기본 라우팅 및 게이트웨이 확인
echo -e "\n[1] 기본 네트워크 경로 및 IP 라우팅 점검:"
DEFAULT_GW=$(ip route | grep default | awk '{print $3}')
if [ -z "$DEFAULT_GW" ]; then
    echo "  [오류] 기본 게이트웨이(Default Gateway)가 설정되어 있지 않습니다."
    echo "  -> 네트워크 인터페이스 설정을 먼저 확인하십시오."
else
    echo "  [정상] 기본 게이트웨이 감지: ${DEFAULT_GW}"
fi

# 2. 공용 IP 핑 테스트 (순수 네트워크 계층 정상 여부)
echo -e "\n[2] 외부 공용 IP(8.8.8.8) 도달 가능 여부:"
if ping -c 2 -W 2 "$TEST_DNS" &>/dev/null; then
    echo "  [정상] 외부 IP 직통 연결 정상 (네트워크 계층 이상 없음)"
else
    echo "  [경고] 외부 IP로 패킷이 나가지 못하고 있습니다. 게이트웨이 또는 방화벽 문제일 수 있습니다."
fi

# 3. /etc/resolv.conf 점검
echo -e "\n[3] /etc/resolv.conf 상태 점검:"
if [ ! -f /etc/resolv.conf ]; then
    echo "  [오류] /etc/resolv.conf 파일이 존재하지 않습니다."
else
    NAMESERVERS=$(grep -E "^nameserver" /etc/resolv.conf | awk '{print $2}')
    if [ -z "$NAMESERVERS" ]; then
        echo "  [오류] resolv.conf 내에 등록된 nameserver가 없습니다."
    else
        echo "  [정상] 등록된 네임서버:"
        echo "$NAMESERVERS" | sed 's/^/    - /'
    fi
    
    # 심볼릭 링크 여부 확인 (Ubuntu/systemd 계열)
    if [ -L /etc/resolv.conf ]; then
        echo "  [안내] /etc/resolv.conf 는 심볼릭 링크입니다 -> $(readlink -f /etc/resolv.conf)"
    fi
fi

# 4. systemd-resolved 데몬 상태 점검
echo -e "\n[4] systemd-resolved 상태 점검:"
if systemctl is-active --quiet systemd-resolved; then
    echo "  [정상] systemd-resolved 서비스가 활성화되어 있습니다."
else
    echo "  [참고] systemd-resolved 서비스가 비활성 상태이거나 설치되지 않았습니다."
fi

# 5. 실제 도메인 질의 테스트
echo -e "\n[5] 도메인 해석 테스트:"
if getent hosts "$TARGET_DOMAIN" &>/dev/null; then
    echo "  [성공] '${TARGET_DOMAIN}' 이름 해석 성공:"
    getent hosts "$TARGET_DOMAIN" | sed 's/^/    /'
else
    echo "  [실패] '${TARGET_DOMAIN}' 이름 해석 실패 (Temporary failure in name resolution)"
    echo "  -> 외부 DNS(${TEST_DNS}) 직접 질의 테스트 시도..."
    if command -v dig &>/dev/null; then
        dig @"$TEST_DNS" "$TARGET_DOMAIN" +short
    fi
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

`Temporary failure in name resolution` 오류는 운영체제 리졸버(NSS, glibc resolver)가 특정 도메인을 IP로 변환하려고 시도했으나, 유효한 네임서버로부터 응답을 받지 못해 일시적인 실패 상태를 반환할 때 발생합니다.

### 1. 주요 원인

1. **`/etc/resolv.conf` 설정 누락 또는 잘못된 IP**:
   * 시스템이 질의할 `nameserver <IP>` 항목이 비어 있거나, 설정된 IP의 DNS 서버가 다운된 경우.
2. **`systemd-resolved` 심볼릭 링크 깨짐**:
   * Ubuntu 18.04/20.04/22.04+ 환경에서 `/etc/resolv.conf`가 잘못된 스텁 리졸버 경로(`../run/systemd/resolve/stub-resolv.conf`)를 가리키거나 링크가 깨진 경우.
3. **네트워크 매니저(NetworkManager, Netplan) 덮어쓰기**:
   * 사용자가 `/etc/resolv.conf`를 수동으로 수정했으나, DHCP 리스 갱신 또는 서버 재부팅 시 설정이 초기화되는 현상.
4. **53번 포트(UDP/TCP) 방화벽 차단**:
   * 아웃바운드 방화벽(iptables, 클라우드 보안 그룹 등)에서 외부 네임서버로의 `UDP/TCP 53`번 포트 통신을 차단한 경우.

### 2. 단계별 복구 및 해결 방법

1. **임시 즉각 조치 (긴급 복구)**:
   * `/etc/resolv.conf`에 안정적인 퍼블릭 네임서버를 직접 추가:
     ```bash
     echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
     echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf
     ```

2. **Ubuntu (`systemd-resolved`) 환경 영구 복구**:
   * 스텁 리졸버 링크를 복구하고 데몬 재시작:
     ```bash
     sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
     sudo systemctl restart systemd-resolved
     ```
   * `/etc/systemd/resolved.conf` 파일에서 글로벌 DNS 지정:
     ```ini
     [Resolve]
     DNS=8.8.8.8 1.1.1.1
     FallbackDNS=8.8.4.4
     ```

3. **Netplan 환경 영구 반영 (`/etc/netplan/*.yaml`)**:
   ```yaml
   network:
     version: 2
     ethernets:
       eth0:
         nameservers:
           addresses: [8.8.8.8, 1.1.1.1]
   ```
   수정 후 `sudo netplan apply` 적용.

&nbsp;
&nbsp;

## 주의사항

1. **`/etc/resolv.conf` 직접 수정 시 덮어쓰기 주의**:
   * 최신 배포판(Ubuntu, RHEL 8/9 등)에서 `/etc/resolv.conf`는 `systemd-resolved`나 `NetworkManager`에 의해 동적으로 자동 생성됩니다. 직접 파일을 수정하더라도 네트워크 재시작이나 재부팅 시 원복되므로, 반드시 `netplan`, `nmcli`, 또는 `resolved.conf`를 통해 영구 반영해야 합니다.
2. **`chattr +i` 사용 지양**:
   * 덮어쓰기를 막기 위해 `chattr +i /etc/resolv.conf`(불변 속성)를 설정하는 임시 방편이 자주 공유되지만, 이는 네트워크 서비스 재시작 시 비정상 종료(Crash)를 유발할 수 있으므로 권장되지 않습니다.
3. **사내망 및 사설 VPC(AWS Route 53 등) 환경**:
   * 클라우드 내부 인스턴스에서 외부 공용 DNS(8.8.8.8 등)만 지정할 경우 사내 도메인이나 VPC 내부 엔드포인트(예: RDS 엔드포인트, 내부 API)를 해석하지 못할 수 있습니다. VPC 기본 제공 DNS(예: AWS VPC CIDR + 2)를 최우선 순위로 유지해야 합니다.