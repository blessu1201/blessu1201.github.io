---
layout: article
title: 시스템 관리_34 SQL Server Error 18456 Login failed for user 로그인 실패 오류 원인 분석 및 State 코드별 해결 가이드
tags: [Linux, Windows, SQL-Server, MSSQL, Error-18456, Login-Failed, State-Code, sqlcmd, DBA, Troubleshooting]
keys: 261016-linux-db-infra-034
---

- 출처 / 참고: Microsoft Learn (Troubleshoot Error 18456 - Login failed for user), Microsoft Documentation (SQL Server Error Log)

> 명령어: `sqlcmd`, `grep`, `tail`, `journalctl`, `systemctl`  
> 키워드: Error 18456, Login failed for user, State Code, SQL Server Authentication, Mixed Mode, sys.server_principals, ERRORLOG  
> 사용처: 애플리케이션 및 DBA 클라이언트(SSMS, DBeaver)에서 MSSQL 접속 거부 시 정확한 실패 원인(비밀번호, 비활성화, 인증 모드 등) 규명 및 계정 복구

---

> 실행예제

클라이언트(SSMS, DBeaver, 애플리케이션)에서 접속을 시도할 때 보안상 세부 정보가 숨겨진 채 `Login failed for user '...'. (Microsoft SQL Server, Error: 18456)` 메시지만 반환되므로, SQL Server의 `ERRORLOG` 파일을 확인하여 실제 실패 원인을 나타내는 **State 코드**를 확인합니다.

```bash
# 1. 클라이언트 관점: sqlcmd 명령어로 접속 시도 및 오류 메시지 확인
$ sqlcmd -S 192.168.1.100 -U appuser -P "WrongPassword123!"
# Msg 18456, Level 14, State 1, Server SQLSRV01, Line 1
# Login failed for user 'appuser'.
# -> 클라이언트에는 보안상 항상 'State 1'로만 표시됨 (실제 State는 서버 에러로그에 기록됨)

# 2. 리눅스 환경: SQL Server ERRORLOG 파일 경로 확인 및 최근 로그인 실패 로그 추적
$ sudo tail -n 50 /var/opt/mssql/log/errorlog | grep -E "18456|Login failed"
# [출력 예시 - 암호 불일치 (State 8)]
# 2026-10-16 10:14:22.15 Logon       Error: 18456, Severity: 14, State: 8.
# 2026-10-16 10:14:22.15 Logon       Login failed for user 'appuser'. Reason: Password did not match that for the login provided. [CLIENT: 192.168.1.50]

# [출력 예시 - 계정 없음 (State 5)]
# 2026-10-16 10:15:01.32 Logon       Error: 18456, Severity: 14, State: 5.
# 2026-10-16 10:15:01.32 Logon       Login failed for user 'guest_user'. Reason: Could not find a login matching the name provided. [CLIENT: 192.168.1.50]

# [출력 예시 - 혼합 인증 모드(Mixed Mode) 미활성화 (State 58)]
# 2026-10-16 10:16:11.89 Logon       Error: 18456, Severity: 14, State: 58.
# 2026-10-16 10:16:11.89 Logon       Login failed for user 'sa'. Reason: An attempt to login using SQL authentication failed. Server is configured for Integrated authentication only. [CLIENT: 192.168.1.50]

# 3. 윈도우 환경: PowerShell을 통해 ERRORLOG 내 18456 오류 필터링
# Get-Content "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Log\ERRORLOG" | Select-String "18456" -Context 0,1

# 4. 관리자 계정으로 sys.server_principals를 조회하여 계정 활성 및 잠금 상태 점검
$ sqlcmd -S localhost -U sa -P 'MyStrongPass!' -Q "
SELECT name, is_disabled, create_date, modify_date 
FROM sys.server_principals 
WHERE name = 'appuser';
"
```

&nbsp;
&nbsp;

## 스크립트

리눅스 상에서 동작하는 SQL Server(`mssql-server`)의 `ERRORLOG`를 분석하여 발생한 Error 18456의 **State 코드**를 자동으로 추출하고, Microsoft 공식 State 명세에 따른 원인 및 해결 조치 가이드를 즉시 매핑해 주는 진단 쉘 스크립트입니다.

```bash
#!/bin/bash
# diagnose_mssql_18456.sh - Parse SQL Server ERRORLOG and explain Error 18456 State Codes

ERRORLOG_PATH=${1:-"/var/opt/mssql/log/errorlog"}

echo "=========================================="
echo " [SQL Server Error 18456 State 진단기]"
echo " 대상 로그 경로: ${ERRORLOG_PATH}"
echo "=========================================="

if [ ! -f "$ERRORLOG_PATH" ]; then
    echo "  [오류] ERRORLOG 파일을 찾을 수 없습니다: ${ERRORLOG_PATH}"
    echo "  -> 사용법: sudo $0 [ERRORLOG 경로]"
    exit 1
fi

echo -e "\n[1] 최근 감지된 Error 18456 로그인 실패 내역 (최근 5건):"
RECENT_ERRORS=$(grep -n "Error: 18456" "$ERRORLOG_PATH" | tail -n 5)

if [ -z "$RECENT_ERRORS" ]; then
    echo "  [정상] 로그 파일 내에 Error 18456 기록이 없습니다."
    exit 0
fi

while read -r LINE; do
    LINE_NO=$(echo "$LINE" | cut -d':' -f1)
    LOG_TEXT=$(echo "$LINE" | cut -d':' -f2-)
    
    # State 코드 추출
    STATE_CODE=$(echo "$LOG_TEXT" | grep -oE "State: [0-9]+" | awk '{print $2}')
    # 다음 줄(이유 및 계정/클라이언트 IP 정보) 추출
    NEXT_LINE=$(sed -n "$((LINE_NO + 1))p" "$ERRORLOG_PATH")
    USER_NAME=$(echo "$NEXT_LINE" | grep -oE "user '[^']+'" | cut -d"'" -f2)
    CLIENT_IP=$(echo "$NEXT_LINE" | grep -oE "\[CLIENT: [^]]+\]")

    echo "------------------------------------------------------------------"
    echo "  발생 시각 및 로그 : $LOG_TEXT"
    echo "  대상 계정 / 클라이언트 : ${USER_NAME:-"알 수 없음"} / ${CLIENT_IP:-"[Local]"}"
    echo "  검출된 State 코드     : State ${STATE_CODE}"
    echo "  [원인 및 해결 가이드]:"

    case "$STATE_CODE" in
        2)
            echo "    -> [원인] 유효하지 않은 사용자 ID (User ID is not valid)."
            echo "    -> [조치] 로그인 계정 철자 오타를 확인하거나 계정을 새로 생성하십시오."
            ;;
        5)
            echo "    -> [원인] 존재하지 않는 로그인 계정 (User ID doesn't exist)."
            echo "    -> [조치] sys.server_principals 목록에서 계정 존재 여부를 확인하십시오."
            ;;
        6)
            echo "    -> [원인] Windows 도메인 로그인 이름 해석 실패."
            echo "    -> [조치] Active Directory 도메인 컨트롤러 연결 상태 및 계정명을 확인하십시오."
            ;;
        7)
            echo "    -> [원인] 계정이 비활성화(Disabled) 상태입니다."
            echo "    -> [조치] ALTER LOGIN [계정명] ENABLE; 명령으로 활성화하십시오."
            ;;
        8)
            echo "    -> [원인] 비밀번호 불일치 (Password did not match)."
            echo "    -> [조치] 입력한 패스워드를 재확인하거나 ALTER LOGIN으로 재설정하십시오."
            ;;
        11|12)
            echo "    -> [원인] 기본 데이터베이스(Default Database) 접근 권한 없음 또는 오프라인 상태."
            echo "    -> [조치] 계정의 Default DB 상태(ONLINE)를 확인하거나 ALTER LOGIN [계정명] WITH DEFAULT_DATABASE = [master]; 로 변경하십시오."
            ;;
        16)
            echo "    -> [원인] 로그인 계정에 DB 엔진 접속 권한이 거부됨 (CONNECT SQL Denied)."
            echo "    -> [조치] GRANT CONNECT SQL TO [계정명]; 명령을 실행하십시오."
            ;;
        38)
            echo "    -> [원인] 데이터베이스가 단일 사용자 모드(SINGLE_USER)로 설정되어 있어 이미 다른 세션이 선점함."
            echo "    -> [조치] DB를 MULTI_USER 모드로 변경하거나 선점 중인 세션을 정리하십시오."
            ;;
        58)
            echo "    -> [원인] 서버가 Windows 인증 전용으로 설정되어 SQL Server 인증을 거부함."
            echo "    -> [조치] 서버 인증 모드를 'SQL Server 및 Windows 인증 모드(Mixed Mode)'로 변경 후 서비스를 재기동하십시오."
            ;;
        *)
            echo "    -> [안내] 세부 원인 로그를 참조하십시오: $NEXT_LINE"
            ;;
    esac
done <<< "$RECENT_ERRORS"

echo -e "\n=========================================="
echo " [진단 완료]"
echo "=========================================="
```

&nbsp;
&nbsp;

## 해설

`Error 18456: Login failed for user`는 클라이언트가 데이터베이스 엔진에 로그인 인증을 요청했으나 거부되었을 때 반환되는 가장 포괄적인 인증 실패 오류입니다.

### 1. 왜 클라이언트에는 항상 `State 1`로만 표시되는가

* 악의적인 공격자가 무차별 대입 공격(Brute-Force)을 수행할 때 "아이디가 틀렸는지", "비밀번호가 틀렸는지", "계정이 잠겼는지"를 알 수 없도록 방어하기 위한 보안 규격(Information Disclosure 방지) 때문입니다.
* 따라서 클라이언트에 찍히는 `State: 1`은 "구체적인 이유는 서버 관리자만 확인할 수 있음"을 뜻하며, **진짜 실패 원인은 반드시 데이터베이스 서버의 `ERRORLOG`에 기록된 내부 State 코드**를 통해서만 파악할 수 있습니다.

### 2. 핵심 State 코드별 상세 분석표

| State 코드 | 서버 ERRORLOG에 기록되는 사유 | 발생 원인 및 복구 쿼리 |
| :--- | :--- | :--- |
| **State 2, 5** | `Could not find a login matching the name provided.` | 계정명이 없거나 오타 발생. 계정 생성 필요. |
| **State 7** | `Login is disabled.` | 계정이 비활성화됨.<br>`ALTER LOGIN [appuser] ENABLE;` |
| **State 8** | `Password did not match that for the login provided.` | 비밀번호 불일치.<br>`ALTER LOGIN [appuser] WITH PASSWORD = 'NewPassword!';` |
| **State 11, 12** | `Cannot open user default database.` | 로그인 시 기본 지정된 DB가 삭제/오프라인이거나 권한 없음.<br>`ALTER LOGIN [appuser] WITH DEFAULT_DATABASE = master;` |
| **State 16** | `Login has not been granted CONNECT SQL permission.` | 엔진 접속 권한 거절.<br>`GRANT CONNECT SQL TO [appuser];` |
| **State 58** | `Server is configured for Integrated authentication only.` | **혼합 인증 모드 미설정**. SQL Server 인증을 거부함. |

### 3. 주요 복구 가이드

#### 1) 혼합 인증 모드(Mixed Mode) 전환 (State 58 조치)
SQL Server 설치 초기 기본값이 "Windows 인증 전용"으로 되어 있는 경우 `sa`나 일반 SQL 계정 인증이 일절 불가능합니다.

* **Linux 환경 (`mssql-conf`)**:
  ```bash
  sudo /opt/mssql/bin/mssql-conf set network.enable-mixed-mode true
  sudo systemctl restart mssql-server
  ```
* **Windows 환경 (T-SQL)**:
  ```sql
  -- 인증 모드를 Mixed Mode(2)로 변경
  EXEC xp_instance_regwrite 
      N'HKEY_LOCAL_MACHINE', 
      N'Software\Microsoft\MSSQLServer\MSSQLServer', 
      N'LoginMode', 
      REG_DWORD, 2;
  -- 적용 후 SQL Server 서비스 재시작 필요
  ```

#### 2) 계정 잠금 해제 및 비밀번호 정책 완화 (State 7, 8 조치)
운영체제의 암호 정책(복잡도, 만료, 잠금)으로 인해 계정이 잠긴 경우 잠금을 해제합니다.

```sql
ALTER LOGIN [appuser] WITH 
    PASSWORD = 'SafeStrongPassword2026!' UNLOCK,
    CHECK_POLICY = OFF,      -- 정책 강제 검사 비활성화 (필요 시)
    CHECK_EXPIRATION = OFF;  -- 만료 주기 비활성화
```

&nbsp;
&nbsp;

## 주의사항

1. **클라이언트 화면만 보고 트러블슈팅 금지**:
   * 웹 애플리케이션의 콘솔이나 SSMS 팝업에 나타나는 `State 1` 문자열은 유효한 단서가 아닙니다. 반드시 DB 서버의 `ERRORLOG` 위치를 확인하고 실제 서버 측 State 번호를 수집해야 엉뚱한 설정 변경으로 인한 2차 장애를 막을 수 있습니다.

2. **반복적인 비밀번호 실패에 따른 계정 잠금(Lockout)**:
   * `CHECK_POLICY = ON`으로 설정된 계정은 Windows 또는 Linux PAM의 보안 정책에 따라 비밀번호를 일정 횟수 이상 틀릴 경우 계정이 잠겨 State 8 대신 State 7이 발생할 수 있습니다. 애플리케이션의 커넥션 풀 설정 파일(예: 암호화된 패스워드 설정 등)이 최신화되어 있는지 확인해야 합니다.

3. **기본 데이터베이스(Default DB) 변경 시 주의**:
   * 계정의 기본 DB(`DEFAULT_DATABASE`)로 특정 업무 DB를 지정해 둔 상태에서 해당 DB를 백업 복원을 위해 오프라인으로 전환하거나 삭제하면, 계정 암호가 맞아도 State 11/12 에러를 내며 접속이 완전히 거부됩니다. 항상 기본 DB 접근 실패 시에는 `master` 데이터베이스로 접속 경로를 우회 지정하여 진단해야 합니다.