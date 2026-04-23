---
layout: article
title: Oracle Standard Edition 대용량 로그 테이블 성능 개선 및 데이터 이관 전략
tags: [Oracle, Database, SQL, Performance, DBA]
key: 20260423-oracle-db-optimization
---


- 출처 : (Oracle Standard Edition)

> 명령어: DBMS_REDEFINITION, RENAME, INSERT APPEND, CTAS  
> 키워드: 단편화(Fragmentation), Shadow Table, 인덱스 재설계, 데이터 정합성  
> 사용처: 서비스 중단 없이 대용량 테이블의 쿼리 성능을 개선하고 데이터를 안전하게 이관하고 싶을 때  

&nbsp;
&nbsp;

## **해설**  

Oracle Standard Edition(SE) 환경에서는 Enterprise Edition의 핵심 기능인 '파티셔닝'과 '온라인 재정의'를 사용할 수 없습니다. 
따라서 

`1`{:.info} 단계적 벌크 복사와  
`2`{:.info} 최종 스왑 방식을 조합한 Shadow Table 이관 전략이 가장 현실적이고 안전한 대안입니다.  
  
`1`{:.info} Shadow Table 이관 프로세스  
`1`{:.info} 신규 테이블 및 인덱스 설계 기존 테이블과 구조는 동일하되, 튜닝된 인덱스를 포함한 신규 테이블을 생성합니다.  


```sql
-- 1. 신규 테이블 생성 (인덱스 포함)
CREATE TABLE TABLE_LOG.TABLE_LOG_NEW (
    LOG_NO NUMBER,
    USER_ID VARCHAR2(20),
    ACCES_DT DATE,
    ...
);
```


`2`{:.info} 1차 데이터 복사 (Online) 서비스가 운영 중인 상태에서 APPEND 힌트를 사용하여 대량의 데이터를 미리 복사합니다.  


```sql
-- 2. 1차 벌크 데이터 복사
INSERT /*+ APPEND */ INTO TABLE_LOG.TABLE_LOG_NEW 
SELECT * FROM TABLE_LOG.TABLE_LOG;
COMMIT;
```


`3`{:.info} 최종 동기화 및 테이블 교체 (Swap) 사용량이 적은 시간에 아주 짧은 점검 시간을 확보하여 잔여 데이터를 맞추고 이름을 변경합니다.  


```sql
-- 3. 잔여 데이터 동기화 후 이름 변경
RENAME TABLE_LOG TO TABLE_LOG_OLD;
RENAME TABLE_LOG_NEW TO TABLE_LOG;
```


`2`{:.info} 성능 개선의 핵심 원리  
`1`{:.info} 데이터 고밀도 압축(Compaction): 장기간의 DML 작업으로 발생한 빈 공간(HWM 아래의 단편화)을 제거하여 물리적 I/O 효율을 높입니다.  
`2`{:.info} 인덱스 구조 최적화: 신규 생성된 인덱스는 구조적 깊이(Height)가 최소화되어 검색 속도가 비약적으로 향상됩니다.  
`3`{:.info} 통계 정보 갱신: 테이블 교체 시 최신 통계 정보가 반영되어 옵티마이저가 최적의 실행 계획을 수립합니다.  

&nbsp;
&nbsp;

## **주의사항**

`1`{:.info} 테이블스페이스 용량 확보: 전체 데이터를 복제하므로 기존 사용량의 최소 `2`{:.info}배 이상의 여유 공간이 필요합니다.  
`2`{:.info} 아카이브 로그 관리: 대량의 INSERT 작업 시 아카이브 로그가 폭증하여 디스크 장애를 유발할 수 있으므로 상시 모니터링이 필수입니다.  
`3`{:.info} 정합성 체크: 교체 직후 반드시 기존 테이블과 건수(COUNT)를 비교하고, 주요 인덱스의 유효성을 검증해야 합니다.  