# Quick Start Guide

ClickHouse RBAC & Workload Management 실습을 빠르게 시작하는 가이드입니다.

## 🚀 5분 안에 시작하기

### 1단계: 환경 설정 (선택사항)

```bash
cd workload/rbac-workloadmanagement

# 로컬 ClickHouse를 사용하는 경우 (기본값)
# 추가 설정 불필요

# ClickHouse Cloud를 사용하는 경우
export CH_HOST="your-instance.clickhouse.cloud"
export CH_PORT="9440"
export CH_SECURE="--secure"
```

### 2단계: 전체 설정 실행

```bash
# 한 번에 모든 설정 실행
./run-all.sh
```

이 스크립트는 다음을 자동으로 실행합니다:
- ✓ 데이터베이스 및 테이블 생성
- ✓ 역할(Role) 생성
- ✓ 사용자(User) 생성
- ✓ Row Policy 설정
- ✓ Column Security 설정
- ✓ Settings Profile 설정
- ✓ Quota 설정
- ✓ Workload Scheduling (선택)

### 3단계: 테스트

```bash
# 다른 사용자로 접속해보기
./connect-as.sh analyst

# 또는 자동 테스트 실행
./test-as.sh
```

## 📝 수동 설치 (단계별)

각 단계를 개별적으로 실행하고 싶다면:

```bash
# 관리자로 접속
clickhouse-client

# 각 스크립트를 순서대로 실행
clickhouse-client < 01-setup.sql
clickhouse-client < 02-create-roles.sql
clickhouse-client < 03-create-users.sql
clickhouse-client < 04-row-policies.sql
clickhouse-client < 05-column-security.sql
clickhouse-client < 06-settings-profiles.sql
clickhouse-client < 07-quotas.sql
clickhouse-client < 08-workload-scheduling.sql  # 선택사항 (v25+)
```

## 🧪 테스트 시나리오

### 분석가로 접속

```bash
./connect-as.sh analyst
```

```sql
-- 데이터 조회 (성공)
SELECT * FROM rbac_demo.sales;

-- 민감 정보 조회 (실패)
SELECT email FROM rbac_demo.customers;

-- 설정 확인
SELECT getSetting('max_memory_usage');
```

### BI 사용자로 접속

```bash
./connect-as.sh bi
```

```sql
-- 읽기 가능
SELECT count() FROM rbac_demo.sales;

-- 쓰기 불가 (readonly)
INSERT INTO rbac_demo.sales VALUES (999, 'TEST', 'Test', 0, today(), 0);
```

### 파트너로 접속

```bash
./connect-as.sh partner
```

```sql
-- APAC 지역만 보임
SELECT region, count() FROM rbac_demo.sales GROUP BY region;

-- customer_id 컬럼 접근 불가
SELECT customer_id FROM rbac_demo.sales;
```

## 🧹 정리

실습이 끝나면:

```bash
clickhouse-client < 99-cleanup.sql
```

## 📚 더 알아보기

- [README.md](README.md) - 전체 실습 가이드
- [USAGE.md](USAGE.md) - 사용자 접속 방법 상세 가이드
- [rbac-blog-plan.md](rbac-blog-plan.md) - 블로그 계획서

## 💡 주요 명령어

```bash
# 사용자 접속
./connect-as.sh <user_type>    # analyst, bi, engineer, partner

# 권한 테스트
./test-as.sh

# 전체 설정
./run-all.sh

# 정리
clickhouse-client < 99-cleanup.sql
```

## ❓ 문제 해결

### 접속이 안 됨
```bash
# 사용자 확인
clickhouse-client --query="SELECT name FROM system.users WHERE name LIKE 'demo_%'"
```

### 권한 오류
```bash
# 권한 확인
clickhouse-client --query="SHOW GRANTS FOR demo_analyst"
```

더 자세한 내용은 [USAGE.md](USAGE.md)를 참고하세요.
