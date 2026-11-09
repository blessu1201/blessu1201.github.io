---
layout: article
title: 시스템 관리_54 Linux 및 ESXi iSCSI 타겟 마운트 지연과 Discovery 실패 원인 분석 및 완벽 복구 가이드
tags: [Linux, ESXi, Storage, iSCSI, iscsiadm, Discovery, MTU, Jumbo-Frame, IQN, CHAP, Troubleshooting]
keys: 261106-linux-storage-054
---

- 출처 / 참고: Linux man-pages (iscsiadm(8), iscsid.conf(5)), VMware Broadcom Knowledge Base (Troubleshooting iSCSI LUN connectivity - KB 1003952), IETF RFC 3720 (Internet Small Computer Systems Interface)

> 명령어: `iscsiadm`, `ping`, `traceroute`, `ip`, `systemctl`, `esxcli`  
> 키워드: iSCSI, iscsiadm, Discovery failed, Connection refused, IQN, Jumbo Frame, MTU 9000, node.session.timeo.replacement_timeout, CHAP  
> 사용처: SAN 스토리지의 iSCSI LUN 탐색(Discovery) 불가, 로그인 타임아웃, 대용량 I/O 시 패킷 드롭 및 마운트 지연 장애 해결

---

> 실행예제

리눅스 및 ESXi 환경에서 `iscsiadm` 명령어로 스토리지 포털 탐색(SendTargets) 또는 로그인 시도시 타임아웃이 발생하거나, 점보 프레임(MTU 9000) 불일치로 세션이 끊기는 현상을 진단합니다.

```bash
# 1. iSCSI 타겟 포털 Discovery 시도 및 타임아웃 오류 확인
$ sudo iscsiadm -m discovery -t sendtargets -p 192.168.10.50:3260
# iscsiadm: cannot make connection to 192.168.10.50: Connection timed out
# iscsiadm: connection login retries (reopen_max) 5 exceeded
# -> TCP 3260번 통신 두절 또는 IP 라우팅 경로 문제 확인

# 2. 로컬 iSCSI Initiator Name(IQN) 확인 및 스토리지 매핑 검증
$ cat /etc/iscsi/initiatorname.iscsi
# InitiatorName=iqn.1994-05.com.redhat:srv01-node1
# -> 스토리지 관리자 콘솔의 마스킹/LUN 매핑 목록에 등록된 IQN과 대조

# 3. iSCSI 전용 NIC의 MTU 설정 및 점보 프레임(9000) 패킷 단편화 금지(DF) 테스트
$ ip link show eth2
# 4: eth2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
# -> 호스트 인터페이스는 MTU 1500인데 스위치나 스토리지가 MTU 9000으로 잡혀 있으면 대용량 I/O 패킷이 드롭됨
$ ping -M do -s 8972 -c 3 192.168.10.50
# PING 192.168.10.50 (192.168.10.50) 8972(9000) bytes of data.
# From 192.168.10.100 icmp_seq=1 Frag needed and DF set (mtu = 1500)
# -> DF(Don't Fragment) 설정 패킷이 통과하지 못하고 차단됨 확인

# 4. 활성 세션 상태 및 커널 iSCSI 에러 확인
$ sudo iscsiadm -m session -P 1
$ sudo dmesg -T | grep -iE "iscsi|connection failed"
# [Fri Nov  6 09:30:11 2026] iscsi: host3: session recovery timed out after 120 secs
# [Fri Nov  6 09:30:11 2026] sd 3:0:0:1: rejecting I/O to offline device
```

&nbsp;
&nbsp;

## 스크립트

iSCSI 서비스 상태, Initiator IQN 유효성, 타겟 포털 3260 포트 통신 상태 및 점보 프레임(MTU 9000) 전송 가능 여부를 단계별로 검증하고 자동 로그인 명령어를 제시하는 쉘 스크립트입니다.

```bash
#!/bin/bash
# diagnose_iscsi_connectivity.sh - Diagnose iSCSI Discovery, TCP 3260, and Jumbo Frame MTU issues

TARGET_IP=${1:-"192.168.10.50"}
TARGET_PORT=${2:-3260}

echo "=========================================="
echo " [iSCSI 타겟 연결 및 MTU 점보프레임 진단기]"
echo " 대상 타겟 포털: ${TARGET_IP}:${TARGET_PORT}"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
    echo "  [오류] iSCSI 관리를 위해 루트(root) 권한이 필요합니다."
    exit 1
fi

# 1. iscsid 데몬 구동 여부
echo -e "\n[1] iscsid 서비스 상태 점검:"
if systemctl is-active --quiet iscsid; then
    echo "  [정상] iscsid 데몬 구동 중"
else
    echo "  [경고] iscsid 데몬이 비활성 상태입니다. 시작 시도..."
    systemctl start iscsid
fi

# 2. InitiatorName 점검
echo -e "\n[2] 로컬 InitiatorName(IQN) 확인:"
INITIATOR_FILE="/etc/iscsi/initiatorname.iscsi"
if [ -f "$INITIATOR_FILE" ]; then
    IQN_VAL=$(grep -E "^InitiatorName=" "$INITIATOR_FILE" | cut -d'=' -f2)
    echo "  - 로컬 IQN: ${IQN_VAL}"
else
    echo "  [치명적 오류] ${INITIATOR_FILE} 파일이 없습니다!"
fi

# 3. 네트워크 및 TCP 3260 포트 확인
echo -e "\n[3] 타겟 포털 네트워크 및 3260 포트 검사:"
if ping -c 2 -w 2 "$TARGET_IP" >/dev/null 2>&1; then
    echo "  - ICMP Ping 통신: [성공]"
else
    echo "  - ICMP Ping 통신: [실패] (방화벽 차단 또는 라우팅 문제 가능성)"
fi

if nc -zv -w 3 "$TARGET_IP" "$TARGET_PORT" >/dev/null 2>&1; then
    echo "  - TCP ${TARGET_PORT} 포트: [열림] 스토리지 데몬 응답 정상"
else
    echo "  - TCP ${TARGET_PORT} 포트: [차단/응답없음] 스토리지 네트워크 ACL 또는 스위치 방화벽 점검 필요"
fi

# 4. 점보 프레임 (MTU 9000) 단편화 검증
echo -e "\n[4] 점보 프레임(MTU 9000) 전송 가능 여부 검사 (8972 바이트 ICMP):"
PING_DF=$(ping -M do -s 8972 -c 2 -w 2 "$TARGET_IP" 2>&1)
if echo "$PING_DF" | grep -q "Frag needed"; then
    echo "  [경고] 경로 상에 MTU 1500 스위치/NIC가 있어 9000 바이트 패킷이 차단됩니다!"
    echo "  -> 조치: 호스트 NIC, 스위치 포트, 스토리지 포트 전체를 MTU 9000으로 통일해야 합니다."
elif echo "$PING_DF" | grep -q "0% packet loss"; then
    echo "  [정상] 전 구간 MTU 9000 점보 프레임이 손실 없이 통과합니다."
else
    echo "  [안내] 점보 프레임 핑 응답 없음 (단편화 불가 또는 ICMP 거부)"
fi

# 5. Discovery 시도
echo -e "\n[5] iscsiadm SendTargets Discovery 실행:"
DISC_OUT=$(iscsiadm -m discovery -t sendtargets -p "${TARGET_IP}:${TARGET_PORT}" 2>&1)
if echo "$DISC_OUT" | grep -q "iqn\."; then
    echo "  [성공] 발견된 타겟 목록:"
    echo "$DISC_OUT" | sed 's/^/    /'
    echo "  -> 전체 로그인 명령: iscsiadm -m node -p ${TARGET_IP}:${TARGET_PORT} --login"
else
    echo "  [실패] 타겟을 찾을 수 없습니다:"
    echo "  $DISC_OUT"
fi

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

iSCSI(Internet Small Computer Systems Interface)는 IP 네트워크망(TCP 3260)을 통해 SCSI 블록 스토리지를 연결하는 엔터프라이즈 기술입니다. 파이버 채널(FC)과 달리 표준 이더넷을 이용하므로 구축 비용이 저렴하지만, **IP 계층의 MTU 불일치**와 **IQN 마스킹 오류**, **네트워크 타임아웃 파라미터 미조율**로 인한 연결 장애가 가장 많이 발생합니다.

### 1. 주요 장애 원인 분석

1. **점보 프레임(Jumbo Frame) 부분 불일치 (Mismatched MTU)**:
   * iSCSI 성능 향상을 위해 보통 MTU를 9000으로 설정합니다. 그러나 호스트 NIC, 물리 스위치(Access/Core), 스토리지 포트 중 **단 하나라도 MTU 1500으로 남아있으면**, 초기 3-way 핸드셰이크는 정상 체결되나 이후 대용량 데이터 블록 전송 시 패킷이 드롭되어 세션 리셋이 반복됩니다.
2. **IQN 불일치 및 스토리지 LUN 매핑 누락**:
   * 클라이언트의 `/etc/iscsi/initiatorname.iscsi`에 정의된 IQN이 스토리지 LUN 마스킹에 등록된 문자열과 글자 하나라도 다르면 `Discovery`는 성공하더라도 세션 로그인(`--login`) 단계에서 인증 거부(`Authorization failed`)가 발생합니다.
3. **기본 복구 타임아웃(`replacement_timeout`) 과다**:
   * `/etc/iscsi/iscsid.conf`의 기본 세션 교체 타임아웃(`node.session.timeo.replacement_timeout`)은 보통 120초입니다. 네트워크 스위치 절체나 일시적인 패킷 유실 시 120초 동안 I/O를 정지(Blocked)시킨 채 대기하므로 파일시스템 커널 패닉이나 애플리케이션 행을 유발합니다.

### 2. 단계별 튜닝 및 복구 절차

#### 1) 전 구간 점보 프레임 통일 (MTU 9000)
호스트 인터페이스의 MTU를 9000으로 변경합니다.
```bash
# NetworkManager 환경
sudo nmcli connection modify eth2 802-3-ethernet.mtu 9000
sudo nmcli connection up eth2
```

#### 2) iSCSI 타임아웃 최적화 (`/etc/iscsi/iscsid.conf`)
다중 경로(Multipath) 환경에서는 빠른 페일오버를 위해 타임아웃을 5~15초 수준으로 단축합니다.
```ini
# /etc/iscsi/iscsid.conf
node.session.timeo.replacement_timeout = 15
node.conn[0].timeo.login_timeout = 15
node.conn[0].timeo.logout_timeout = 15
```

#### 3) 자동 로그인 등록
시스템 재부팅 시 LUN이 자동으로 마운트되도록 노드 모드를 자동(`automatic`)으로 설정합니다.
```bash
sudo iscsiadm -m node -T iqn.target.name -p 192.168.10.50:3260 -o update -n node.startup -v automatic
```

&nbsp;
&nbsp;

## 주의사항

1. **iSCSI 볼륨에 `/etc/fstab` 등록 시 `_netdev` 옵션 누락 금지**:
   * `/etc/fstab`에 iSCSI 파티션을 등록할 때 `_netdev` 옵션을 빠뜨리면 부팅 과정에서 네트워크가 올라오기 전에 파일시스템 마운트를 시도하다 시스템 부팅이 멈추고 이머전시 모드(Emergency Mode)로 떨어집니다.
   * 올바른 구문: `UUID=... /data ext4 defaults,_netdev 0 0`

2. **단일 NIC에 다중 서브넷 iSCSI 바인딩 금지**:
   * 소프트웨어 iSCSI 멀티패스를 구성할 때 서로 다른 서브넷의 스토리지를 동일한 물리 NIC 포트에 혼용하여 바인딩하면 ARP 충돌 및 비대칭 라우팅으로 인해 패킷 손실이 발생합니다. iSCSI 전용 격리 VLAN을 분리해야 합니다.

3. **스토리지 세션 제거 시 언마운트 선행 필수**:
   * `iscsiadm -m node -u` (로그아웃)를 실행하기 전에 반드시 해당 디바이스의 파일시스템을 먼저 `umount`해야 합니다. 마운트된 상태에서 iSCSI 세션을 끊으면 디바이스가 비정상 제거(Dead LUN)되어 커널 메모리 누수와 I/O 에러가 발생합니다.