# ClickHouse RBAC & Workload Management 기술 블로그 상세 계획서

## 📋 프로젝트 개요

**제목 (안)**: "ClickHouse 권한 제어와 워크로드 매니지먼트 완벽 가이드"

**목표**: ClickHouse의 RBAC(Role-Based Access Control)와 워크로드 매니지먼트에 대한 실습 중심 기술 블로그 작성

**대상 독자**: ClickHouse를 운영 중이거나 도입을 검토하는 DBA, 데이터 엔지니어, 플랫폼 엔지니어

**예상 분량**: 약 4,000~5,000 단어 (한글 기준)

---

## 🔍 테스트 환경 정보

### ClickHouse Cloud 환경
| 항목 | 값 |
|------|-----|
| **버전** | 25.8.1.8909 |
| **환경** | ClickHouse Cloud (AWS) |
| **테스트 사용자** | default (admin 권한) |

### 현재 환경 상태
| 리소스 | 개수 | 설명 |
|--------|------|------|
| Users | 11개 | 시스템 내부용 + sql-console 사용자 |
| Roles | 5개 | sql_console_read_only, sql_console_admin, default_role, clickpipes_system, hdx_alert_role |
| Settings Profiles | 9개 | default, admin, readonly, backup, operator 등 |
| Quotas | 2개 | default, observability-internal-quota |
| Row Policies | 0개 | 없음 |
| Workloads | 0개 | 없음 (신규 생성 필요) |
| Resources | 0개 | 없음 (신규 생성 필요) |

### 테스트 진행 방식
- **DDL/DCL 실행**: SQL Workbench (워크벤치)에서 직접 실행
- **결과 검증**: MCP 연결로 system 테이블 조회하여 확인
- **중간 기록**: 각 단계별 체크포인트 기록

---

## 📚 블로그 상세 구성

### 1. 도입부: 왜 권한 제어와 워크로드 관리가 필요한가? (300단어)

#### 1.1 문제 상황 제시
- **시나리오 A**: 분석가의 무거운 ad-hoc 쿼리가 실시간 대시보드 성능에 영향
- **시나리오 B**: 개발팀이 실수로 운영 테이블 삭제
- **시나리오 C**: 특정 사용자가 민감한 고객 데이터에 무단 접근

#### 1.2 ClickHouse의 해결책
- RBAC: 세분화된 권한 제어
- Settings Profile: 쿼리 리소스 제한
- Quota: 사용량 제한
- Workload Scheduling: CPU/IO 리소스 분배

#### 1.3 블로그에서 다룰 내용 미리보기

---

### 2. RBAC 기본 개념 (600단어)

#### 2.1 ClickHouse Access Control 구성요소

```
┌─────────────────────────────────────────────────────────────┐
│                    ClickHouse RBAC 구조                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────┐     ┌─────────┐     ┌──────────────────┐     │
│   │  USER   │────▶│  ROLE   │────▶│    PRIVILEGES    │     │
│   └─────────┘     └─────────┘     └──────────────────┘     │
│        │               │                                    │
│        │               │          ┌──────────────────┐     │
│        │               └─────────▶│  ROW POLICIES    │     │
│        │                          └──────────────────┘     │
│        │                                                    │
│        ▼                                                    │
│   ┌─────────────────┐     ┌─────────┐                      │
│   │ SETTINGS PROFILE│     │  QUOTA  │                      │
│   └─────────────────┘     └─────────┘                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 2.2 핵심 개념 설명

**Users (사용자)**
- 개별 사용자 또는 애플리케이션 계정
- 인증 방식: 비밀번호, SHA256, SSL 인증서, LDAP, Kerberos
- HOST 제한으로 접속 IP 제어 가능

**Roles (역할)**
- 권한의 논리적 그룹
- 역할 상속 가능 (계층 구조)
- Best Practice: 권한은 Role에, Role을 User에게 부여

**Privileges (권한)**
- 세분화된 작업 권한: SELECT, INSERT, ALTER, DROP, CREATE 등
- 데이터베이스/테이블/컬럼 수준으로 제어 가능
- GRANT OPTION으로 권한 위임 가능

**Row Policies (행 수준 보안)**
- 특정 조건에 맞는 행만 접근 가능
- 멀티 테넌트 환경에서 데이터 격리
- USING 절로 필터 조건 정의

**Settings Profiles**
- 쿼리 실행 관련 설정 그룹
- max_memory_usage, max_execution_time 등 제한
- 사용자 또는 역할에 적용

**Quotas**
- 시간 기반 사용량 제한
- 쿼리 수, 결과 행 수, 읽기 바이트 등 제한
- 리소스 남용 방지

#### 2.3 XML vs SQL 방식 비교

| 항목 | XML 방식 | SQL 방식 |
|------|----------|----------|
| 설정 위치 | users.xml, config.xml | SQL 명령어 |
| 동적 변경 | 서버 재시작/reload 필요 | 즉시 적용 |
| 권장 여부 | Legacy | **권장** |
| 관리 편의성 | 파일 편집 | SQL 클라이언트 |

> ⚠️ **권장사항**: SQL 기반 워크플로우 사용 (ClickHouse Cloud 기본)

---

### 3. RBAC 실습 - 권한 제어 구현 (800단어)

#### 3.1 실습 시나리오

**가상의 데이터 분석 조직**:
```
데이터팀
├── Data Engineers    → 전체 접근 권한
├── Data Analysts     → 읽기 + 제한된 쓰기
├── BI Developers     → 읽기 전용
└── External Partners → 특정 데이터만 접근
```

#### 3.2 Step 1: 테스트 데이터베이스 및 테이블 생성

```sql
-- 실습용 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS rbac_demo;

-- 판매 데이터 테이블
CREATE TABLE rbac_demo.sales (
    id UInt64,
    region String,
    product String,
    amount Decimal(18,2),
    sale_date Date,
    customer_id UInt64
) ENGINE = MergeTree()
ORDER BY (region, sale_date);

-- 고객 데이터 테이블 (민감 정보 포함)
CREATE TABLE rbac_demo.customers (
    id UInt64,
    name String,
    email String,           -- 민감 정보
    phone String,           -- 민감 정보
    region String,
    created_at DateTime
) ENGINE = MergeTree()
ORDER BY id;

-- 샘플 데이터 삽입
INSERT INTO rbac_demo.sales VALUES
    (1, 'APAC', 'Product A', 1000.00, '2024-01-15', 101),
    (2, 'APAC', 'Product B', 2500.00, '2024-01-16', 102),
    (3, 'EMEA', 'Product A', 1500.00, '2024-01-15', 103),
    (4, 'AMERICAS', 'Product C', 3000.00, '2024-01-17', 104);

INSERT INTO rbac_demo.customers VALUES
    (101, 'Kim Corp', 'contact@kimcorp.com', '+82-10-1234-5678', 'APAC', now()),
    (102, 'Lee Inc', 'info@leeinc.com', '+82-10-2345-6789', 'APAC', now()),
    (103, 'Euro GmbH', 'hello@eurogmbh.de', '+49-123-456789', 'EMEA', now()),
    (104, 'US Corp', 'sales@uscorp.com', '+1-555-123-4567', 'AMERICAS', now());
```

**검증 쿼리** (MCP로 실행):
```sql
SELECT database, name, engine FROM system.tables WHERE database = 'rbac_demo';
SELECT count() FROM rbac_demo.sales;
SELECT count() FROM rbac_demo.customers;
```

#### 3.3 Step 2: Role 생성 및 권한 부여

```sql
-- 1) 읽기 전용 역할 (BI Developers용)
CREATE ROLE IF NOT EXISTS rbac_demo_readonly;
GRANT SELECT ON rbac_demo.* TO rbac_demo_readonly;

-- 2) 분석가 역할 (읽기 + 임시 테이블)
CREATE ROLE IF NOT EXISTS rbac_demo_analyst;
GRANT SELECT ON rbac_demo.* TO rbac_demo_analyst;
GRANT CREATE TEMPORARY TABLE ON *.* TO rbac_demo_analyst;

-- 3) 데이터 엔지니어 역할 (전체 권한)
CREATE ROLE IF NOT EXISTS rbac_demo_engineer;
GRANT ALL ON rbac_demo.* TO rbac_demo_engineer;

-- 4) 외부 파트너 역할 (특정 테이블, 특정 컬럼만)
CREATE ROLE IF NOT EXISTS rbac_demo_partner;
GRANT SELECT(id, region, product, amount, sale_date) ON rbac_demo.sales TO rbac_demo_partner;
-- customer_id는 제외!
```

**검증 쿼리** (MCP로 실행):
```sql
SELECT * FROM system.roles WHERE name LIKE 'rbac_demo%';
SELECT role_name, access_type, database, table, column 
FROM system.grants WHERE role_name LIKE 'rbac_demo%';
```

#### 3.4 Step 3: 사용자 생성 및 역할 할당

```sql
-- 사용자 생성 (다양한 인증 방식)
CREATE USER IF NOT EXISTS demo_bi_user 
    IDENTIFIED BY 'SecurePass123!'
    DEFAULT ROLE rbac_demo_readonly;

CREATE USER IF NOT EXISTS demo_analyst 
    IDENTIFIED WITH sha256_password BY 'AnalystPass456!'
    DEFAULT ROLE rbac_demo_analyst;

CREATE USER IF NOT EXISTS demo_engineer 
    IDENTIFIED BY 'EngineerPass789!'
    DEFAULT ROLE rbac_demo_engineer;

CREATE USER IF NOT EXISTS demo_partner 
    IDENTIFIED BY 'PartnerPass000!'
    HOST IP '0.0.0.0/0'  -- 실제 환경에서는 특정 IP로 제한
    DEFAULT ROLE rbac_demo_partner;

-- 역할 할당 확인
GRANT rbac_demo_readonly TO demo_bi_user;
GRANT rbac_demo_analyst TO demo_analyst;
GRANT rbac_demo_engineer TO demo_engineer;
GRANT rbac_demo_partner TO demo_partner;
```

**검증 쿼리** (MCP로 실행):
```sql
SELECT name, auth_type, default_roles_list FROM system.users WHERE name LIKE 'demo_%';
SELECT * FROM system.role_grants WHERE user_name LIKE 'demo_%';
```

#### 3.5 Step 4: Row Policy (행 수준 보안) 구현

```sql
-- APAC 지역 데이터만 접근 가능한 정책
CREATE ROW POLICY IF NOT EXISTS apac_only_policy 
ON rbac_demo.sales 
FOR SELECT
USING region = 'APAC'
TO rbac_demo_partner;

-- 분석가는 모든 지역 접근 가능 (명시적 허용)
CREATE ROW POLICY IF NOT EXISTS all_regions_policy 
ON rbac_demo.sales 
FOR SELECT
USING 1=1
TO rbac_demo_analyst, rbac_demo_engineer, rbac_demo_readonly;
```

**검증 쿼리** (MCP로 실행):
```sql
SELECT * FROM system.row_policies WHERE database = 'rbac_demo';
```

**테스트 시나리오** (워크벤치에서 각 사용자로 로그인):
```sql
-- demo_partner로 로그인 후 실행
SELECT * FROM rbac_demo.sales;  -- APAC 데이터만 반환되어야 함

-- demo_analyst로 로그인 후 실행
SELECT * FROM rbac_demo.sales;  -- 모든 데이터 반환
```

#### 3.6 Step 5: Column-Level Security (컬럼 수준 보안)

```sql
-- 분석가에게 고객 테이블의 민감 컬럼 제외하고 부여
REVOKE SELECT ON rbac_demo.customers FROM rbac_demo_analyst;
GRANT SELECT(id, name, region, created_at) ON rbac_demo.customers TO rbac_demo_analyst;
-- email, phone 컬럼은 접근 불가
```

**테스트** (워크벤치에서 demo_analyst로 로그인):
```sql
SELECT * FROM rbac_demo.customers;  -- 에러 발생
SELECT id, name, region FROM rbac_demo.customers;  -- 성공
SELECT email FROM rbac_demo.customers;  -- 에러: 권한 없음
```

---

### 4. 워크로드 매니지먼트 개념 (600단어)

#### 4.1 워크로드 관리의 필요성

**문제 상황**:
- Heavy ad-hoc 쿼리가 실시간 대시보드를 느리게 함
- 배치 작업이 온라인 서비스에 영향
- 특정 사용자가 리소스 독점

**해결 방향**:
```
┌─────────────────────────────────────────────────────────────┐
│                워크로드 관리 계층 구조                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Level 1: Settings Profile                                  │
│  ├── max_memory_usage (쿼리당 메모리 제한)                   │
│  ├── max_execution_time (실행 시간 제한)                     │
│  └── max_threads (쓰레드 수 제한)                            │
│                                                             │
│  Level 2: Quotas                                            │
│  ├── 시간당 쿼리 수 제한                                     │
│  ├── 읽기 행/바이트 제한                                     │
│  └── 결과 크기 제한                                          │
│                                                             │
│  Level 3: Workload Scheduling (v25+)                        │
│  ├── CPU 스케줄링                                            │
│  ├── IO 스케줄링                                             │
│  └── 워크로드 간 리소스 분배                                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 4.2 Settings Profile 주요 설정

| 설정 | 설명 | 권장값 (분석가) |
|------|------|----------------|
| `max_memory_usage` | 쿼리당 최대 메모리 | 10GB |
| `max_execution_time` | 쿼리 타임아웃 (초) | 300 |
| `max_threads` | 병렬 처리 쓰레드 수 | 4 |
| `max_rows_to_read` | 읽을 수 있는 최대 행 수 | 1억 |
| `max_result_rows` | 결과 최대 행 수 | 100만 |
| `readonly` | 읽기 전용 모드 | 1 (분석가) |

#### 4.3 Quota 제한 항목

| 항목 | 설명 |
|------|------|
| `max_queries` | 기간당 최대 쿼리 수 |
| `max_query_selects` | 기간당 SELECT 쿼리 수 |
| `max_query_inserts` | 기간당 INSERT 쿼리 수 |
| `max_errors` | 허용 에러 수 |
| `max_result_rows` | 결과 총 행 수 |
| `max_read_rows` | 읽은 총 행 수 |
| `max_read_bytes` | 읽은 총 바이트 |
| `max_execution_time` | 총 실행 시간 |

#### 4.4 Workload Scheduling (v25+ 신기능)

ClickHouse 25.4부터 CPU 슬롯 스케줄링 지원:

```sql
-- CPU 리소스 정의
CREATE RESOURCE cpu (MASTER THREAD, WORKER THREAD);

-- 워크로드 계층 정의
CREATE WORKLOAD all;

CREATE WORKLOAD production IN all 
SETTINGS max_concurrent_threads = 100;

CREATE WORKLOAD analytics IN production 
SETTINGS max_concurrent_threads = 60, weight = 9;

CREATE WORKLOAD adhoc IN production 
SETTINGS max_concurrent_threads = 20, weight = 1;
```

**워크로드 계층 예시**:
```
all (root)
├── admin (max_concurrent_threads = 10)
└── production (max_concurrent_threads = 100)
    ├── analytics (weight=9) - 높은 우선순위
    └── adhoc (weight=1) - 낮은 우선순위
```

---

### 5. 워크로드 매니지먼트 실습 (700단어)

#### 5.1 Step 1: Settings Profile 생성

```sql
-- 1) 분석가용 프로필 (제한적)
CREATE SETTINGS PROFILE IF NOT EXISTS demo_analyst_profile
SETTINGS 
    max_memory_usage = 10000000000,       -- 10GB
    max_execution_time = 300,              -- 5분
    max_threads = 4,
    max_rows_to_read = 100000000,          -- 1억 행
    max_result_rows = 1000000,             -- 100만 행
    readonly = 1;

-- 2) BI 사용자용 프로필 (더 제한적)
CREATE SETTINGS PROFILE IF NOT EXISTS demo_bi_profile
SETTINGS 
    max_memory_usage = 5000000000,         -- 5GB
    max_execution_time = 60,               -- 1분
    max_threads = 2,
    max_result_rows = 100000,              -- 10만 행
    readonly = 1;

-- 3) 데이터 엔지니어용 프로필 (관대함)
CREATE SETTINGS PROFILE IF NOT EXISTS demo_engineer_profile
SETTINGS 
    max_memory_usage = 50000000000,        -- 50GB
    max_execution_time = 3600,             -- 1시간
    max_threads = 16;
```

**검증 쿼리** (MCP로 실행):
```sql
SELECT * FROM system.settings_profiles WHERE name LIKE 'demo_%';
SELECT * FROM system.settings_profile_elements WHERE profile_name LIKE 'demo_%';
```

#### 5.2 Step 2: Profile을 User/Role에 적용

```sql
-- 역할에 프로필 적용
ALTER ROLE rbac_demo_analyst SETTINGS PROFILE demo_analyst_profile;
ALTER ROLE rbac_demo_readonly SETTINGS PROFILE demo_bi_profile;
ALTER ROLE rbac_demo_engineer SETTINGS PROFILE demo_engineer_profile;

-- 또는 사용자에게 직접 적용
ALTER USER demo_analyst SETTINGS PROFILE demo_analyst_profile;
ALTER USER demo_bi_user SETTINGS PROFILE demo_bi_profile;
```

**테스트** (워크벤치에서 demo_analyst로 로그인):
```sql
SELECT getSetting('max_memory_usage');  -- 10000000000 반환 확인
SELECT getSetting('max_execution_time');  -- 300 반환 확인

-- 제한 초과 테스트 (의도적으로 큰 쿼리)
SELECT count() FROM system.numbers LIMIT 1000000000;  -- 메모리/시간 제한에 걸림
```

#### 5.3 Step 3: Quota 생성 및 적용

```sql
-- 분석가용 Quota (시간당 제한)
CREATE QUOTA IF NOT EXISTS demo_analyst_quota
FOR INTERVAL 1 hour
MAX queries = 100,
    query_selects = 80,
    result_rows = 10000000,      -- 1000만 행
    read_rows = 1000000000,      -- 10억 행
    execution_time = 1800        -- 30분
TO rbac_demo_analyst;

-- BI 사용자용 Quota (더 제한적)
CREATE QUOTA IF NOT EXISTS demo_bi_quota
FOR INTERVAL 1 hour
MAX queries = 200,
    result_rows = 1000000,       -- 100만 행
    execution_time = 600         -- 10분
TO rbac_demo_readonly;

-- 일 단위 Quota 추가
CREATE QUOTA IF NOT EXISTS demo_daily_quota
FOR INTERVAL 1 day
MAX queries = 1000,
    read_bytes = 100000000000    -- 100GB/일
TO rbac_demo_analyst;
```

**검증 쿼리** (MCP로 실행):
```sql
SELECT * FROM system.quotas WHERE name LIKE 'demo_%';
SELECT * FROM system.quota_limits WHERE quota_name LIKE 'demo_%';
SELECT * FROM system.quota_usage;
```

#### 5.4 Step 4: Workload Scheduling 구성 (v25+)

```sql
-- CPU 리소스 정의
CREATE RESOURCE IF NOT EXISTS cpu (MASTER THREAD, WORKER THREAD);

-- 워크로드 계층 생성
CREATE WORKLOAD IF NOT EXISTS all;

CREATE WORKLOAD IF NOT EXISTS demo_production IN all 
SETTINGS max_concurrent_threads = 80;

CREATE WORKLOAD IF NOT EXISTS demo_analytics IN demo_production 
SETTINGS max_concurrent_threads = 50, weight = 9;

CREATE WORKLOAD IF NOT EXISTS demo_adhoc IN demo_production 
SETTINGS max_concurrent_threads = 20, weight = 1;
```

**워크로드 사용**:
```sql
-- 쿼리 실행 시 워크로드 지정
SELECT count() FROM rbac_demo.sales SETTINGS workload = 'demo_analytics';

-- 무거운 ad-hoc 쿼리는 낮은 우선순위로
SELECT * FROM large_table WHERE complex_condition SETTINGS workload = 'demo_adhoc';
```

**검증 쿼리** (MCP로 실행):
```sql
SELECT * FROM system.workloads;
SELECT * FROM system.resources;
SELECT * FROM system.scheduler;
```

---

### 6. Best Practices (500단어)

#### 6.1 RBAC Best Practices

**✅ DO (권장)**:
1. **최소 권한 원칙 (Least Privilege)**: 필요한 최소한의 권한만 부여
2. **Role 기반 관리**: 사용자에게 직접 권한 부여 대신 Role 사용
3. **네이밍 컨벤션**: 명확한 이름 규칙 (`{env}_{team}_{access_level}`)
4. **정기 감사**: 분기별 권한 리뷰 및 불필요한 권한 제거
5. **Row Policy 활용**: 민감 데이터는 행 수준 보안 적용

**❌ DON'T (피해야 할 것)**:
1. default 사용자에 운영 권한 부여
2. `GRANT ALL ON *.*` 남발
3. 비밀번호 없는 사용자 생성
4. Row Policy 없이 멀티 테넌트 운영

#### 6.2 Workload Management Best Practices

**Settings Profile 설계**:
```sql
-- 티어별 프로필 권장 설정
-- Tier 1: Real-time (대시보드, API)
max_memory_usage = 5GB, max_execution_time = 30초, max_threads = 4

-- Tier 2: Interactive (분석가 쿼리)
max_memory_usage = 20GB, max_execution_time = 300초, max_threads = 8

-- Tier 3: Batch (ETL, 리포트)
max_memory_usage = 100GB, max_execution_time = 3600초, max_threads = 32
```

**Quota 설계**:
- 시간당 + 일당 이중 제한 권장
- 에러 수 제한으로 버그 있는 쿼리 조기 차단
- 피크 시간대 별도 Quota 고려

#### 6.3 모니터링 권장 쿼리

```sql
-- 사용자별 쿼리 통계
SELECT 
    user,
    count() as query_count,
    sum(read_rows) as total_read_rows,
    sum(memory_usage) as total_memory,
    avg(query_duration_ms) as avg_duration_ms
FROM system.query_log
WHERE event_time > now() - INTERVAL 1 HOUR
GROUP BY user
ORDER BY query_count DESC;

-- Quota 사용량 확인
SELECT * FROM system.quota_usage;

-- 현재 실행 중인 쿼리
SELECT 
    query_id, user, elapsed, read_rows, memory_usage, query
FROM system.processes
ORDER BY elapsed DESC;
```

---

### 7. 모니터링 및 트러블슈팅 (400단어)

#### 7.1 주요 시스템 테이블

| 테이블 | 용도 |
|--------|------|
| `system.users` | 사용자 목록 |
| `system.roles` | 역할 목록 |
| `system.grants` | 권한 부여 내역 |
| `system.row_policies` | Row Policy 목록 |
| `system.settings_profiles` | 프로필 목록 |
| `system.quotas` | Quota 설정 |
| `system.quota_usage` | Quota 사용량 |
| `system.query_log` | 쿼리 로그 |
| `system.workloads` | 워크로드 설정 |

#### 7.2 일반적인 문제와 해결

**문제 1: "Access Denied" 에러**
```sql
-- 원인 파악
SHOW GRANTS FOR username;
SELECT * FROM system.grants WHERE user_name = 'username';
```

**문제 2: 쿼리가 느림 (Quota/Profile 제한)**
```sql
-- 현재 적용된 설정 확인
SELECT name, value FROM system.settings WHERE changed = 1;
SELECT * FROM system.quota_usage WHERE quota_key = 'username';
```

**문제 3: Row Policy가 적용 안 됨**
```sql
-- Row Policy 확인
SELECT * FROM system.row_policies WHERE table = 'table_name';
-- USING 조건의 컬럼이 실제로 존재하는지 확인
```

---

### 8. 정리 및 리소스 정리 (200단어)

#### 8.1 핵심 요약

1. **RBAC**: User → Role → Privilege 계층으로 권한 관리
2. **Row Policy**: 행 수준 보안으로 멀티 테넌트 지원
3. **Settings Profile**: 쿼리 리소스 제한
4. **Quota**: 시간 기반 사용량 제한
5. **Workload Scheduling**: CPU/IO 리소스 분배 (v25+)

#### 8.2 실습 리소스 정리 스크립트

```sql
-- 테스트 리소스 정리 (순서 중요!)
DROP ROW POLICY IF EXISTS apac_only_policy ON rbac_demo.sales;
DROP ROW POLICY IF EXISTS all_regions_policy ON rbac_demo.sales;

DROP QUOTA IF EXISTS demo_analyst_quota;
DROP QUOTA IF EXISTS demo_bi_quota;
DROP QUOTA IF EXISTS demo_daily_quota;

DROP SETTINGS PROFILE IF EXISTS demo_analyst_profile;
DROP SETTINGS PROFILE IF EXISTS demo_bi_profile;
DROP SETTINGS PROFILE IF EXISTS demo_engineer_profile;

DROP USER IF EXISTS demo_bi_user;
DROP USER IF EXISTS demo_analyst;
DROP USER IF EXISTS demo_engineer;
DROP USER IF EXISTS demo_partner;

DROP ROLE IF EXISTS rbac_demo_readonly;
DROP ROLE IF EXISTS rbac_demo_analyst;
DROP ROLE IF EXISTS rbac_demo_engineer;
DROP ROLE IF EXISTS rbac_demo_partner;

DROP WORKLOAD IF EXISTS demo_adhoc;
DROP WORKLOAD IF EXISTS demo_analytics;
DROP WORKLOAD IF EXISTS demo_production;

DROP DATABASE IF EXISTS rbac_demo;
```

#### 8.3 추가 학습 리소스

- [ClickHouse 공식 문서 - Access Rights](https://clickhouse.com/docs/operations/access-rights)
- [ClickHouse 공식 문서 - Quotas](https://clickhouse.com/docs/en/operations/quotas)
- [ClickHouse 공식 문서 - Workload Scheduling](https://clickhouse.com/docs/operations/workload-scheduling)
- [ClickHouse 25.4 Release Notes - CPU Scheduling](https://clickhouse.com/blog/clickhouse-release-25-04)

---

## 📅 작업 체크포인트

### Checkpoint 템플릿

```markdown
## Checkpoint #N - [YYYY-MM-DD HH:MM]

### ✅ 완료된 작업
- [ ] 항목 1
- [ ] 항목 2

### 📝 실행한 SQL 및 결과
```sql
-- 실행한 쿼리
```

### 🔍 MCP 검증 결과
(시스템 테이블 조회 결과)

### ⚠️ 이슈/메모
- 발생한 문제나 특이사항

### ➡️ 다음 단계
- 다음에 진행할 작업
```

---

## 📌 체크리스트

### Phase 1: 환경 준비 ✅
- [x] MCP 접속 확인
- [x] 권한 확인
- [x] 기존 설정 확인
- [x] 계획서 작성

### Phase 2: RBAC 실습
- [ ] 테스트 DB/테이블 생성
- [ ] Role 생성
- [ ] User 생성
- [ ] Row Policy 생성
- [ ] Column-level 권한 테스트
- [ ] 각 사용자로 로그인 테스트

### Phase 3: Workload Management 실습
- [ ] Settings Profile 생성
- [ ] Profile 적용 및 테스트
- [ ] Quota 생성
- [ ] Quota 적용 및 테스트
- [ ] Workload Scheduling 구성 (선택)

### Phase 4: 문서화 및 정리
- [ ] 블로그 본문 작성
- [ ] 스크린샷 추가
- [ ] 리소스 정리
- [ ] 최종 검토
