---
layout: article
title: 시스템 관리_10 "트래픽이 집중되는 리눅스 서버의 'Too many open files' (ulimit) 오류 해결 방법"
tags: [Linux, Performance, Troubleshooting, ulimit, Systemd, Nginx]
keys: 260922-linux-storage-010
---

- 출처 / 참고: 리눅스 파일시스템 마운트 관리 및 스토리지 복구 가이드
> 명령어: `ulimit -n`, `sysctl -p`, `systemctl daemon-reload`, `lsof -p <PID>`  
> 키워드: File Descriptor, ulimit, nofile, systemd LimitNOFILE, fs.file-max, Socket Exhaustion  
> 사용처: 웹 서버(Nginx, Apache), 데이터베이스(MySQL, Redis), Node.js/Java 백엔드 등에서 동시 접속 급증 시 소켓 및 파일 핸들 고갈 장애 해결  

---

> 실행예제

```bash
# 1. 애플리케이션 로그에서 오류 확인 (Nginx/DB/App 공통)
# [alert] 12345#12345: *67890 socket() failed (24: Too many open files) while connecting to upstream
# java.io.IOException: Too many open files

# 2. 현재 시스템 전체 파일 디스크립터(FD) 사용량 및 최대 한도 점검
$ cat /proc/sys/fs/file-nr
18240   0   65536
# 출력 설명: [할당된 FD 수] [미사용 할당 FD 수] [시스템 전역 최대 한도] (현재 한도에 근접한 상태)

# 3. 현재 셸 및 사용자 세션의 FD 제한 확인 (Soft / Hard Limit)
$ ulimit -Sn
1024
$ ulimit -Hn
4096

# 4. 대상 프로세스(예: PID 12345)의 실제 런타임 적용 한도 및 현재 열린 FD 개수 확인
$ cat /proc/12345/limits | grep "Max open files"
Max open files            1024                 4096                 files

$ ls /proc/12345/fd | wc -l
1024
```

&nbsp;
&nbsp;

## 스크립트

```bash
#!/usr/bin/env bash
#
# 고트래픽 환경 대응: 커널 파라미터, PAM limits, systemd 파일 디스크립터(FD) 일괄 상향 스크립트
#

set -euo pipefail

TARGET_NOFILE=1048576  # 1M (고트래픽 서버 권장 표준 한도)

echo "=== [1] 시스템 전체 커널 파라미터 (/etc/sysctl.d/99-file-max.conf) 설정 ==="
cat <<EOF > /etc/sysctl.d/99-file-max.conf
fs.file-max = 2097152
fs.nr_open = ${TARGET_NOFILE}
EOF

sysctl -p /etc/sysctl.d/99-file-max.conf

echo "=== [2] 사용자 및 세션 레벨 제한 설정 (/etc/security/limits.d/99-nofile.conf) ==="
cat <<EOF > /etc/security/limits.d/99-nofile.conf
*          soft    nofile    ${TARGET_NOFILE}
*          hard    nofile    ${TARGET_NOFILE}
root       soft    nofile    ${TARGET_NOFILE}
root       hard    nofile    ${TARGET_NOFILE}
EOF

echo "=== [3] systemd 글로벌 서비스 기본값 설정 (/etc/systemd/system.conf & user.conf) ==="
# systemd 데몬 관리 서비스 전체에 대한 디폴트 LimitNOFILE 반영
mkdir -p /etc/systemd/system.conf.d
cat <<EOF > /etc/systemd/system.conf.d/30-nofile.conf
[Manager]
DefaultLimitNOFILE=${TARGET_NOFILE}:${TARGET_NOFILE}
EOF

systemctl daemon-reexec

echo "=== [4] 특정 서비스(예: nginx) systemd 오버라이드 단독 적용 ==="
if systemctl is-active --quiet nginx 2>/dev/null; then
    mkdir -p /etc/systemd/system/nginx.service.d
    cat <<EOF > /etc/systemd/system/nginx.service.d/override.conf
[Service]
LimitNOFILE=${TARGET_NOFILE}
EOF
    systemctl daemon-reload
    systemctl restart nginx
    echo "Nginx 서비스의 LimitNOFILE이 성공적으로 갱신되었습니다."
fi

echo "=== [완료] 파일 디스크립터 한도 확장 설정이 완료되었습니다. ==="
```

&nbsp;
&nbsp;

## 해설

1. **에러 원인 분석:**
   * 리눅스는 네트워크 소켓, 파일, 파이프, 디렉터리 등을 모두 **파일 디스크립터(FD, File Descriptor)**로 취급합니다.
   * 트래픽이 폭증할 때 프로세스가 동시에 열어야 하는 TCP 연결 소켓 수가 배정된 FD 제한(`Soft Limit`)을 초과하면 커널은 `EMFILE (24: Too many open files)` 에러를 반환하며 새로운 연결 수립을 거부합니다.

2. **계층별 적용 체계 및 스크립트 핵심 로직:**
   * **커널 전역 레벨 (`fs.file-max`, `fs.nr_open`):**
     * `fs.file-max`: 시스템 전체에서 모든 프로세스가 합산하여 열 수 있는 절대 최대 FD 수입니다.
     * `fs.nr_open`: 개별 프로세스가 요청할 수 있는 단일 프로세스 최대 상한선입니다. `limits.conf`의 값보다 이 값이 항상 크거나 같아야 적용 오류가 발생하지 않습니다.
   * **사용자 세션 레벨 (`/etc/security/limits.d/`):**
     * PAM(`pam_limits.so`)을 통과하는 로그인 셸, SSH 세션, cron 등의 상한선을 제어합니다.
     * `soft`: 프로세스가 기본으로 사용하는 현재 한도값입니다.
     * `hard`: root 권한 없이 사용자가 `ulimit -n`으로 올릴 수 있는 최대 상한선입니다.
   * **데몬/서비스 레벨 (`systemd`):**
     * 최신 배포판(RHEL 7+, Ubuntu 16.04+)의 백그라운드 서비스(Nginx, MySQL, Redis 등)는 PAM을 거치지 않고 `systemd`에 의해 직접 기동됩니다.
     * 따라서 `limits.conf`를 수정해도 systemd 유닛에는 적용되지 않으므로, 유닛 파일 내 `LimitNOFILE=` 또는 `DefaultLimitNOFILE=`을 반드시 설정해야 합니다.

&nbsp;
&nbsp;

## 주의사항

1. **systemd 기반 서비스의 `limits.conf` 무시 현상:**
   * `systemctl`로 기동하는 서비스는 `/etc/security/limits.conf` 설정을 완전히 무시합니다. 반드시 `systemctl edit <서비스명>`을 통해 `[Service]` 섹션 아래에 `LimitNOFILE=...`을 선언해야 합니다.

2. **`fs.nr_open`을 초과하는 ulimit 설정 시 로그인 불가 장애:**
   * `limits.conf`의 `nofile` 값을 커널의 `fs.nr_open`(기본값 1,048,576)보다 크게 설정하면, SSH 로그인 시 PAM 모듈 오류로 인해 사용자가 시스템에 접속하지 못하는 장애가 발생할 수 있습니다. 상향 시 항상 `fs.nr_open`을 먼저 검토해야 합니다.

3. **애플리케이션 자체 설정과의 동기화:**
   * Nginx의 경우 OS 한도 외에도 `nginx.conf` 상단의 `worker_rlimit_nofile` 지시어가 별도로 존재합니다. OS 레벨만 늘리고 웹 서버 설정값을 누락하면 동일한 에러가 계속 발생하므로 양쪽 설정을 맞춰주어야 합니다.

4. **리소스 누수(FD Leak) 감별:**
   * 정상적인 트래픽 증가가 아닌, 애플리케이션 버그로 소켓(`CLOSE_WAIT`)이나 파일 핸들을 닫지 않아 FD가 계속 누적되는 상황일 수도 있습니다. `lsof -p <PID>`를 주기적으로 모니터링하여 특정 유형의 파일/소켓이 비정상적으로 누적되는지 사전 확인해야 합니다.