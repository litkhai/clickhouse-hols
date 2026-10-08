# ClickHouse RBAC & Workload Management Lab

[English](#english) | [한국어](#한국어)

---

## English

> **Related notes** (Korean): [Basic Tuning 의 이해](https://clickhouse.litkhai.dev/articles/core-architecture/basic-tuning/)

*English translation of the Korean original, LLM-assisted (2026-10-06).*

A hands-on environment for practicing ClickHouse RBAC (Role-Based Access Control) and workload management.

### 📋 Lab Overview

In this lab you will learn:

1. **RBAC (Role-Based Access Control)**
   - Creating roles and granting privileges
   - Creating users and assigning roles
   - Row-Level Security
   - Column-Level Security

2. **Workload Management**
   - Settings Profile (query resource limits)
   - Quota (time-based usage limits)
   - Workload Scheduling (v25+)

### 🗂️ File Structure

```
rbac-workloadmanagement/
├── README.md                      # This file
├── rbac-blog-plan.md              # Detailed plan
│
├── 01-setup.sql                   # Create test environment and data
├── 02-create-roles.sql            # Create roles and grant privileges
├── 03-create-users.sql            # Create users and assign roles
├── 04-row-policies.sql            # Row Policy (row-level security)
├── 05-column-security.sql         # Column-Level Security
├── 06-settings-profiles.sql       # Create Settings Profiles
├── 07-quotas.sql                  # Create Quotas
├── 08-workload-scheduling.sql     # Workload Scheduling (v25+)
├── 09-monitoring.sql              # Monitoring and verification queries
├── 99-cleanup.sql                 # Cleanup script
│
├── connect-as.sh                  # Helper script to connect as a user
└── test-as.sh                     # Privilege test script
```

### 🚀 Getting Started

#### Prerequisites

1. A ClickHouse server (local or cloud)
2. The `clickhouse-client` CLI tool
3. An account with administrator privileges

#### Environment Variables (optional)

```bash
# When using ClickHouse Cloud
export CH_HOST="your-host.clickhouse.cloud"
export CH_PORT="9440"
export CH_SECURE="--secure"

# When using a local ClickHouse
export CH_HOST="localhost"
export CH_PORT="9000"
export CH_SECURE=""
```

### 📚 Lab Steps

#### Step 1: Create the test environment

Connect with the administrator account and create the test database and tables.

```bash
clickhouse-client < 01-setup.sql
```

What gets created:
- The `rbac_demo` database
- The `sales` table (sales data)
- The `customers` table (customer data, including sensitive information)

#### Step 2: Create roles

Create four roles and grant each the appropriate privileges.

```bash
clickhouse-client < 02-create-roles.sql
```

Roles created:
- `rbac_demo_readonly` - Read-only (BI developer)
- `rbac_demo_analyst` - Analyst (read + temporary tables)
- `rbac_demo_engineer` - Data engineer (full privileges)
- `rbac_demo_partner` - External partner (restricted read)

#### Step 3: Create users

Create a user for each role.

```bash
clickhouse-client < 03-create-users.sql
```

Users created:
- `demo_bi_user` (password: `SecurePass123!`)
- `demo_analyst` (password: `AnalystPass456!`)
- `demo_engineer` (password: `EngineerPass789!`)
- `demo_partner` (password: `PartnerPass000!`)

#### Step 4: Set up the Row Policy

Set up row-level security. The partner is restricted to seeing only APAC region data.

```bash
clickhouse-client < 04-row-policies.sql
```

#### Step 5: Set up column-level security

Restrict access to sensitive information (email, phone).

```bash
clickhouse-client < 05-column-security.sql
```

#### Step 6: Create Settings Profiles

Set query resource limits.

```bash
clickhouse-client < 06-settings-profiles.sql
```

Limits per role:
- BI: 5GB memory, 1 minute execution, 2 threads
- Analyst: 10GB memory, 5 minutes execution, 4 threads
- Engineer: 50GB memory, 1 hour execution, 16 threads
- Partner: 2GB memory, 30 seconds execution, 2 threads

#### Step 7: Create Quotas

Set time-based usage limits.

```bash
clickhouse-client < 07-quotas.sql
```

#### Step 8: Workload Scheduling (ClickHouse 25+)

Set up workload scheduling. (Requires ClickHouse 25.4 or later)

```bash
clickhouse-client < 08-workload-scheduling.sql
```

#### Step 9: Monitoring

Review and monitor what has been configured.

```bash
clickhouse-client < 09-monitoring.sql
```

### 🔧 User Connection Tools

#### connect-as.sh - Interactive connection

Connect to ClickHouse as a specific user.

```bash
# Connect as analyst
./connect-as.sh analyst

# Connect as BI user
./connect-as.sh bi

# Connect as engineer
./connect-as.sh engineer

# Connect as partner
./connect-as.sh partner
```

#### Running queries directly

```bash
# Run a single query
./connect-as.sh analyst "SELECT count() FROM rbac_demo.sales"

# Check a setting
./connect-as.sh analyst "SELECT getSetting('max_memory_usage')"
```

#### test-as.sh - Privilege test

Automatically tests the privileges of every user.

```bash
./test-as.sh
```

### 🧪 Test Scenarios

#### 1. Row Policy test

**Connect as demo_partner:**
```sql
-- Only APAC data is visible (3 rows)
SELECT region, count() FROM rbac_demo.sales GROUP BY region;
```

**Connect as demo_analyst:**
```sql
-- Data for all regions is visible (8 rows)
SELECT region, count() FROM rbac_demo.sales GROUP BY region;
```

#### 2. Column Security test

**Connect as demo_analyst:**
```sql
-- ✗ Error (no privilege on email, phone)
SELECT * FROM rbac_demo.customers;

-- ✓ Succeeds (allowed columns only)
SELECT id, name, region FROM rbac_demo.customers;

-- ✗ Error
SELECT email FROM rbac_demo.customers;
```

**Connect as demo_engineer:**
```sql
-- ✓ Succeeds (all columns accessible)
SELECT * FROM rbac_demo.customers;
```

#### 3. Settings Profile test

**Connect as demo_analyst:**
```sql
-- Check current settings
SELECT getSetting('max_memory_usage');  -- 10000000000 (10GB)
SELECT getSetting('max_execution_time');  -- 300 (5 minutes)

-- Time limit test (error after 5 minutes)
SELECT sleep(1) FROM numbers(400);

-- readonly test (error)
INSERT INTO rbac_demo.sales VALUES (999, 'TEST', 'Test', 0, today(), 0);
```

#### 4. Quota test

**Connect as demo_analyst:**
```sql
-- Check current Quota usage
SELECT * FROM system.quota_usage;

-- Run queries several times, then check usage
SELECT count() FROM rbac_demo.sales;  -- Run several times
SELECT * FROM system.quota_usage;  -- Confirm the queries count increases
```

#### 5. Workload Scheduling test

**Run queries with different workloads:**
```sql
-- High priority (analytics)
SELECT count() FROM rbac_demo.sales
SETTINGS workload = 'demo_analytics';

-- Low priority (adhoc)
SELECT * FROM numbers(1000000)
SETTINGS workload = 'demo_adhoc';

-- Check scheduler state
SELECT * FROM system.scheduler ORDER BY path;
```

### 📊 Monitoring Queries

#### Per-user query statistics (last hour)

```sql
SELECT
    user,
    count() as query_count,
    countIf(type = 'QueryFinish') as successful,
    countIf(type = 'ExceptionWhileProcessing') as failed,
    round(avg(query_duration_ms), 2) as avg_duration_ms
FROM system.query_log
WHERE event_time > now() - INTERVAL 1 HOUR
  AND user LIKE 'demo_%'
GROUP BY user;
```

#### Currently running queries

```sql
SELECT
    query_id,
    user,
    elapsed,
    formatReadableSize(memory_usage) as memory,
    substring(query, 1, 100) as query_preview
FROM system.processes
WHERE user LIKE 'demo_%';
```

#### Check Quota usage

```sql
SELECT
    quota_name,
    queries,
    max_queries,
    execution_time,
    max_execution_time,
    formatReadableSize(read_bytes) as read_bytes,
    formatReadableSize(max_read_bytes) as max_read_bytes
FROM system.quota_usage
WHERE quota_name LIKE 'demo_%';
```

### 🧹 Cleanup

When the lab is over, clean up all resources.

```bash
clickhouse-client < 99-cleanup.sql
```

Items cleaned up:
- Row Policies
- Quotas
- Settings Profiles
- Users
- Roles
- Workloads
- Resources
- Database (rbac_demo)

### 📖 References

#### Official Documentation
- [ClickHouse Access Rights](https://clickhouse.com/docs/operations/access-rights)
- [Settings Profiles](https://clickhouse.com/docs/operations/settings/settings-profiles)
- [Quotas](https://clickhouse.com/docs/operations/quotas)
- [Workload Scheduling](https://clickhouse.com/docs/operations/workload-scheduling)

#### System Tables
- `system.users` - User list
- `system.roles` - Role list
- `system.grants` - Grant history
- `system.row_policies` - Row Policy list
- `system.settings_profiles` - Settings Profile list
- `system.quotas` - Quota settings
- `system.quota_usage` - Quota usage
- `system.workloads` - Workload settings
- `system.scheduler` - Scheduler state
- `system.query_log` - Query log

### 💡 Best Practices

#### RBAC
1. **Principle of least privilege**: Grant only the minimum privileges needed
2. **Role-based management**: Use Roles instead of granting privileges directly to users
3. **Naming convention**: Use a clear naming rule (`{env}_{team}_{access_level}`)
4. **Regular audits**: Review privileges quarterly and remove unnecessary ones
5. **Use Row Policy**: Apply row-level security to sensitive data

#### Workload Management
1. **Tiered profiles**: Design profiles to fit real-time / interactive / batch jobs
2. **Dual limits**: Apply hourly and daily Quotas together
3. **Workload separation**: Separate jobs with different priorities into separate workloads
4. **Monitoring**: Check resource usage periodically

### ❗ Cautions

1. **Password security**: Do not use the lab passwords in production
2. **HOST restriction**: In production, always restrict to specific IPs
3. **Workload Scheduling**: Available only on ClickHouse 25.4 or later
4. **Cleanup script**: 99-cleanup.sql deletes all data, so be careful

### 🆘 Troubleshooting

#### "Access Denied" error
```sql
-- Check privileges
SHOW GRANTS FOR demo_analyst;
SELECT * FROM system.grants WHERE user_name = 'demo_analyst';
```

#### Queries are slow (Profile/Quota limits)
```sql
-- Check current settings
SELECT name, value FROM system.settings WHERE changed = 1;
SELECT * FROM system.quota_usage;
```

#### Row Policy is not applied
```sql
-- Check Row Policy
SELECT * FROM system.row_policies WHERE table = 'sales';
```

### 📝 License

[MIT](../../LICENSE) — same as the rest of the repository.

---

## 한국어

> **관련 글**: [Basic Tuning 의 이해](https://clickhouse.litkhai.dev/articles/core-architecture/basic-tuning/)

ClickHouse의 RBAC(Role-Based Access Control)와 워크로드 매니지먼트를 실습하는 환경입니다.

### 📋 실습 개요

이 실습에서는 다음을 배울 수 있습니다:

1. **RBAC (Role-Based Access Control)**
   - 역할(Role) 생성 및 권한 부여
   - 사용자(User) 생성 및 역할 할당
   - Row-Level Security (행 수준 보안)
   - Column-Level Security (컬럼 수준 보안)

2. **Workload Management**
   - Settings Profile (쿼리 리소스 제한)
   - Quota (시간 기반 사용량 제한)
   - Workload Scheduling (워크로드 스케줄링, v25+)

### 🗂️ 파일 구조

```
rbac-workloadmanagement/
├── README.md                      # 이 파일
├── rbac-blog-plan.md              # 상세 계획서
│
├── 01-setup.sql                   # 테스트 환경 및 데이터 생성
├── 02-create-roles.sql            # 역할 생성 및 권한 부여
├── 03-create-users.sql            # 사용자 생성 및 역할 할당
├── 04-row-policies.sql            # Row Policy (행 수준 보안)
├── 05-column-security.sql         # Column-Level Security
├── 06-settings-profiles.sql       # Settings Profile 생성
├── 07-quotas.sql                  # Quota 생성
├── 08-workload-scheduling.sql     # Workload Scheduling (v25+)
├── 09-monitoring.sql              # 모니터링 및 검증 쿼리
├── 99-cleanup.sql                 # 정리 스크립트
│
├── connect-as.sh                  # 사용자 접속 헬퍼 스크립트
└── test-as.sh                     # 권한 테스트 스크립트
```

### 🚀 시작하기

#### 사전 준비

1. ClickHouse 서버 (로컬 또는 클라우드)
2. `clickhouse-client` CLI 도구
3. 관리자 권한을 가진 계정

#### 환경 변수 설정 (선택사항)

```bash
# ClickHouse Cloud를 사용하는 경우
export CH_HOST="your-host.clickhouse.cloud"
export CH_PORT="9440"
export CH_SECURE="--secure"

# 로컬 ClickHouse를 사용하는 경우
export CH_HOST="localhost"
export CH_PORT="9000"
export CH_SECURE=""
```

### 📚 실습 단계

#### Step 1: 테스트 환경 생성

관리자 계정으로 접속하여 테스트 데이터베이스와 테이블을 생성합니다.

```bash
clickhouse-client < 01-setup.sql
```

생성되는 것들:
- `rbac_demo` 데이터베이스
- `sales` 테이블 (판매 데이터)
- `customers` 테이블 (고객 데이터, 민감 정보 포함)

#### Step 2: 역할(Role) 생성

4가지 역할을 생성하고 각각에 적절한 권한을 부여합니다.

```bash
clickhouse-client < 02-create-roles.sql
```

생성되는 역할:
- `rbac_demo_readonly` - 읽기 전용 (BI 개발자)
- `rbac_demo_analyst` - 분석가 (읽기 + 임시 테이블)
- `rbac_demo_engineer` - 데이터 엔지니어 (전체 권한)
- `rbac_demo_partner` - 외부 파트너 (제한된 읽기)

#### Step 3: 사용자(User) 생성

각 역할에 맞는 사용자를 생성합니다.

```bash
clickhouse-client < 03-create-users.sql
```

생성되는 사용자:
- `demo_bi_user` (비밀번호: `SecurePass123!`)
- `demo_analyst` (비밀번호: `AnalystPass456!`)
- `demo_engineer` (비밀번호: `EngineerPass789!`)
- `demo_partner` (비밀번호: `PartnerPass000!`)

#### Step 4: Row Policy 설정

행 수준 보안을 설정합니다. 파트너는 APAC 지역 데이터만 볼 수 있도록 제한됩니다.

```bash
clickhouse-client < 04-row-policies.sql
```

#### Step 5: 컬럼 수준 보안 설정

민감한 정보(email, phone)에 대한 접근을 제한합니다.

```bash
clickhouse-client < 05-column-security.sql
```

#### Step 6: Settings Profile 생성

쿼리 리소스 제한을 설정합니다.

```bash
clickhouse-client < 06-settings-profiles.sql
```

각 역할별 제한:
- BI: 5GB 메모리, 1분 실행, 2 스레드
- Analyst: 10GB 메모리, 5분 실행, 4 스레드
- Engineer: 50GB 메모리, 1시간 실행, 16 스레드
- Partner: 2GB 메모리, 30초 실행, 2 스레드

#### Step 7: Quota 생성

시간 기반 사용량 제한을 설정합니다.

```bash
clickhouse-client < 07-quotas.sql
```

#### Step 8: Workload Scheduling (ClickHouse 25+)

워크로드 스케줄링을 설정합니다. (ClickHouse 25.4 이상 필요)

```bash
clickhouse-client < 08-workload-scheduling.sql
```

#### Step 9: 모니터링

설정된 내용을 확인하고 모니터링합니다.

```bash
clickhouse-client < 09-monitoring.sql
```

### 🔧 사용자 접속 도구

#### connect-as.sh - 대화형 접속

특정 사용자로 ClickHouse에 접속합니다.

```bash
# 분석가로 접속
./connect-as.sh analyst

# BI 사용자로 접속
./connect-as.sh bi

# 엔지니어로 접속
./connect-as.sh engineer

# 파트너로 접속
./connect-as.sh partner
```

#### 쿼리 직접 실행

```bash
# 단일 쿼리 실행
./connect-as.sh analyst "SELECT count() FROM rbac_demo.sales"

# 설정 확인
./connect-as.sh analyst "SELECT getSetting('max_memory_usage')"
```

#### test-as.sh - 권한 테스트

모든 사용자의 권한을 자동으로 테스트합니다.

```bash
./test-as.sh
```

### 🧪 테스트 시나리오

#### 1. Row Policy 테스트

**demo_partner로 접속:**
```sql
-- APAC 데이터만 보임 (3개 행)
SELECT region, count() FROM rbac_demo.sales GROUP BY region;
```

**demo_analyst로 접속:**
```sql
-- 모든 지역 데이터 보임 (8개 행)
SELECT region, count() FROM rbac_demo.sales GROUP BY region;
```

#### 2. Column Security 테스트

**demo_analyst로 접속:**
```sql
-- ✗ 에러 발생 (email, phone 권한 없음)
SELECT * FROM rbac_demo.customers;

-- ✓ 성공 (허용된 컬럼만)
SELECT id, name, region FROM rbac_demo.customers;

-- ✗ 에러 발생
SELECT email FROM rbac_demo.customers;
```

**demo_engineer로 접속:**
```sql
-- ✓ 성공 (모든 컬럼 접근 가능)
SELECT * FROM rbac_demo.customers;
```

#### 3. Settings Profile 테스트

**demo_analyst로 접속:**
```sql
-- 현재 설정 확인
SELECT getSetting('max_memory_usage');  -- 10000000000 (10GB)
SELECT getSetting('max_execution_time');  -- 300 (5분)

-- 시간 제한 테스트 (5분 초과 시 에러)
SELECT sleep(1) FROM numbers(400);

-- readonly 테스트 (에러 발생)
INSERT INTO rbac_demo.sales VALUES (999, 'TEST', 'Test', 0, today(), 0);
```

#### 4. Quota 테스트

**demo_analyst로 접속:**
```sql
-- 현재 Quota 사용량 확인
SELECT * FROM system.quota_usage;

-- 쿼리 여러 번 실행 후 사용량 확인
SELECT count() FROM rbac_demo.sales;  -- 여러 번 실행
SELECT * FROM system.quota_usage;  -- queries 카운트 증가 확인
```

#### 5. Workload Scheduling 테스트

**서로 다른 워크로드로 쿼리 실행:**
```sql
-- 높은 우선순위 (analytics)
SELECT count() FROM rbac_demo.sales
SETTINGS workload = 'demo_analytics';

-- 낮은 우선순위 (adhoc)
SELECT * FROM numbers(1000000)
SETTINGS workload = 'demo_adhoc';

-- 스케줄러 상태 확인
SELECT * FROM system.scheduler ORDER BY path;
```

### 📊 모니터링 쿼리

#### 사용자별 쿼리 통계 (최근 1시간)

```sql
SELECT
    user,
    count() as query_count,
    countIf(type = 'QueryFinish') as successful,
    countIf(type = 'ExceptionWhileProcessing') as failed,
    round(avg(query_duration_ms), 2) as avg_duration_ms
FROM system.query_log
WHERE event_time > now() - INTERVAL 1 HOUR
  AND user LIKE 'demo_%'
GROUP BY user;
```

#### 현재 실행 중인 쿼리

```sql
SELECT
    query_id,
    user,
    elapsed,
    formatReadableSize(memory_usage) as memory,
    substring(query, 1, 100) as query_preview
FROM system.processes
WHERE user LIKE 'demo_%';
```

#### Quota 사용량 확인

```sql
SELECT
    quota_name,
    queries,
    max_queries,
    execution_time,
    max_execution_time,
    formatReadableSize(read_bytes) as read_bytes,
    formatReadableSize(max_read_bytes) as max_read_bytes
FROM system.quota_usage
WHERE quota_name LIKE 'demo_%';
```

### 🧹 정리

실습이 끝나면 모든 리소스를 정리합니다.

```bash
clickhouse-client < 99-cleanup.sql
```

정리되는 항목:
- Row Policies
- Quotas
- Settings Profiles
- Users
- Roles
- Workloads
- Resources
- Database (rbac_demo)

### 📖 참고 자료

#### 공식 문서
- [ClickHouse Access Rights](https://clickhouse.com/docs/operations/access-rights)
- [Settings Profiles](https://clickhouse.com/docs/operations/settings/settings-profiles)
- [Quotas](https://clickhouse.com/docs/operations/quotas)
- [Workload Scheduling](https://clickhouse.com/docs/operations/workload-scheduling)

#### 시스템 테이블
- `system.users` - 사용자 목록
- `system.roles` - 역할 목록
- `system.grants` - 권한 부여 내역
- `system.row_policies` - Row Policy 목록
- `system.settings_profiles` - Settings Profile 목록
- `system.quotas` - Quota 설정
- `system.quota_usage` - Quota 사용량
- `system.workloads` - Workload 설정
- `system.scheduler` - 스케줄러 상태
- `system.query_log` - 쿼리 로그

### 💡 Best Practices

#### RBAC
1. **최소 권한 원칙**: 필요한 최소한의 권한만 부여
2. **Role 기반 관리**: 사용자에게 직접 권한 부여 대신 Role 사용
3. **네이밍 컨벤션**: 명확한 이름 규칙 사용 (`{env}_{team}_{access_level}`)
4. **정기 감사**: 분기별 권한 리뷰 및 불필요한 권한 제거
5. **Row Policy 활용**: 민감 데이터는 행 수준 보안 적용

#### Workload Management
1. **티어별 프로필**: 실시간/대화형/배치 작업에 맞는 프로필 설계
2. **이중 제한**: 시간당 + 일당 Quota 동시 적용
3. **워크로드 분리**: 우선순위가 다른 작업은 별도 워크로드로 분리
4. **모니터링**: 주기적으로 리소스 사용량 확인

### ❗ 주의사항

1. **비밀번호 보안**: 실습용 비밀번호를 프로덕션에 사용하지 마세요
2. **HOST 제한**: 프로덕션 환경에서는 반드시 특정 IP로 제한
3. **Workload Scheduling**: ClickHouse 25.4 이상에서만 사용 가능
4. **정리 스크립트**: 99-cleanup.sql은 모든 데이터를 삭제하므로 주의

### 🆘 트러블슈팅

#### "Access Denied" 에러
```sql
-- 권한 확인
SHOW GRANTS FOR demo_analyst;
SELECT * FROM system.grants WHERE user_name = 'demo_analyst';
```

#### 쿼리가 느림 (Profile/Quota 제한)
```sql
-- 현재 설정 확인
SELECT name, value FROM system.settings WHERE changed = 1;
SELECT * FROM system.quota_usage;
```

#### Row Policy가 적용 안 됨
```sql
-- Row Policy 확인
SELECT * FROM system.row_policies WHERE table = 'sales';
```

### 📝 라이선스

[MIT](../../LICENSE) — 저장소 전체와 동일합니다.
