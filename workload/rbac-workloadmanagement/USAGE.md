# 사용자 접속 방법 가이드

ClickHouse RBAC 실습에서 다른 사용자로 접속하여 권한을 테스트하는 방법을 설명합니다.

## 목차
1. [기본 접속 방법](#기본-접속-방법)
2. [헬퍼 스크립트 사용](#헬퍼-스크립트-사용)
3. [ClickHouse Cloud 접속](#clickhouse-cloud-접속)
4. [권한 테스트 시나리오](#권한-테스트-시나리오)

---

## 기본 접속 방법

### 1. clickhouse-client를 이용한 직접 접속

각 사용자의 비밀번호:
- `demo_bi_user`: `SecurePass123!`
- `demo_analyst`: `AnalystPass456!`
- `demo_engineer`: `EngineerPass789!`
- `demo_partner`: `PartnerPass000!`

#### 로컬 ClickHouse 접속

```bash
# BI 사용자로 접속
clickhouse-client --user=demo_bi_user --password='SecurePass123!'

# 분석가로 접속
clickhouse-client --user=demo_analyst --password='AnalystPass456!'

# 엔지니어로 접속
clickhouse-client --user=demo_engineer --password='EngineerPass789!'

# 파트너로 접속
clickhouse-client --user=demo_partner --password='PartnerPass000!'
```

#### ClickHouse Cloud 접속

```bash
# 환경변수 설정 (한 번만 실행)
export CH_HOST="your-instance.clickhouse.cloud"
export CH_PORT="9440"

# 사용자로 접속
clickhouse-client \
    --host="${CH_HOST}" \
    --port="${CH_PORT}" \
    --secure \
    --user=demo_analyst \
    --password='AnalystPass456!'
```

### 2. 비밀번호를 파일로 관리 (권장)

보안을 위해 비밀번호를 파일로 관리할 수 있습니다.

```bash
# 비밀번호 파일 생성
echo 'AnalystPass456!' > ~/.clickhouse-analyst-password
chmod 600 ~/.clickhouse-analyst-password

# 파일을 이용한 접속
clickhouse-client \
    --user=demo_analyst \
    --password="$(cat ~/.clickhouse-analyst-password)"
```

---

## 헬퍼 스크립트 사용

실습 디렉토리에 제공되는 스크립트를 사용하면 더 편리합니다.

### connect-as.sh 사용법

```bash
# 대화형 모드로 접속
./connect-as.sh analyst    # 분석가로 접속
./connect-as.sh bi         # BI 사용자로 접속
./connect-as.sh engineer   # 엔지니어로 접속
./connect-as.sh partner    # 파트너로 접속

# 단일 쿼리 실행
./connect-as.sh analyst "SELECT count() FROM rbac_demo.sales"
./connect-as.sh bi "SELECT * FROM rbac_demo.customers LIMIT 5"

# 현재 설정 확인
./connect-as.sh analyst "SELECT getSetting('max_memory_usage')"
./connect-as.sh analyst "SELECT name, value FROM system.settings WHERE changed = 1"
```

### ClickHouse Cloud 환경변수 설정

```bash
# connect-as.sh가 사용할 환경변수
export CH_HOST="your-instance.clickhouse.cloud"
export CH_PORT="9440"
export CH_SECURE="--secure"

# 이제 스크립트 실행
./connect-as.sh analyst
```

### test-as.sh로 권한 자동 테스트

```bash
# 모든 사용자의 권한 테스트
./test-as.sh

# ClickHouse Cloud 환경변수 설정 후 실행
export CH_HOST="your-instance.clickhouse.cloud"
export CH_PORT="9440"
export CH_SECURE="--secure"
./test-as.sh
```

---

## ClickHouse Cloud 접속

ClickHouse Cloud를 사용하는 경우 추가 설정이 필요합니다.

### 1. 접속 정보 확인

ClickHouse Cloud 콘솔에서:
1. Services 탭 선택
2. 사용할 서비스 클릭
3. "Connect" 버튼 클릭
4. "Native" 탭에서 호스트와 포트 확인

예시:
```
Host: abc123.us-east-1.aws.clickhouse.cloud
Port: 9440
```

### 2. 환경변수 설정 스크립트 생성

편의를 위해 설정 스크립트를 만듭니다.

```bash
# set-cloud-env.sh 파일 생성
cat > set-cloud-env.sh << 'EOF'
#!/bin/bash
export CH_HOST="your-instance.clickhouse.cloud"
export CH_PORT="9440"
export CH_SECURE="--secure"
echo "ClickHouse Cloud environment set:"
echo "  Host: ${CH_HOST}"
echo "  Port: ${CH_PORT}"
EOF

chmod +x set-cloud-env.sh
```

### 3. 사용 방법

```bash
# 환경변수 로드
source ./set-cloud-env.sh

# 이제 스크립트 사용 가능
./connect-as.sh analyst
./test-as.sh
```

### 4. 직접 접속 예시

```bash
clickhouse-client \
    --host="abc123.us-east-1.aws.clickhouse.cloud" \
    --port=9440 \
    --secure \
    --user=demo_analyst \
    --password='AnalystPass456!'
```

---

## 권한 테스트 시나리오

각 사용자로 접속하여 다음 테스트를 수행합니다.

### demo_bi_user (BI 사용자)

```bash
./connect-as.sh bi
```

```sql
-- ✓ 성공: sales 테이블 읽기
SELECT count() FROM rbac_demo.sales;

-- ✓ 성공: customers 제한된 컬럼 읽기
SELECT id, name, region FROM rbac_demo.customers;

-- ✗ 실패: customers 모든 컬럼 (email, phone 없음)
SELECT * FROM rbac_demo.customers;

-- ✗ 실패: 쓰기 작업 (readonly)
INSERT INTO rbac_demo.sales VALUES (999, 'TEST', 'Test', 0, today(), 0);

-- 현재 설정 확인
SELECT getSetting('max_memory_usage');  -- 5000000000 (5GB)
SELECT getSetting('max_execution_time');  -- 60 (1분)
```

### demo_analyst (분석가)

```bash
./connect-as.sh analyst
```

```sql
-- ✓ 성공: 데이터 읽기
SELECT * FROM rbac_demo.sales;

-- ✓ 성공: 제한된 컬럼 읽기
SELECT id, name, region FROM rbac_demo.customers;

-- ✗ 실패: 민감 컬럼 접근
SELECT email, phone FROM rbac_demo.customers;

-- ✓ 성공: 임시 테이블 생성
CREATE TEMPORARY TABLE temp_test (id UInt64, value String);
INSERT INTO temp_test VALUES (1, 'test');
SELECT * FROM temp_test;

-- ✗ 실패: 영구 테이블에 쓰기 (readonly)
INSERT INTO rbac_demo.sales VALUES (999, 'TEST', 'Test', 0, today(), 0);

-- 현재 설정 확인
SELECT getSetting('max_memory_usage');  -- 10000000000 (10GB)
SELECT getSetting('max_execution_time');  -- 300 (5분)

-- Quota 확인
SELECT * FROM system.quota_usage;
```

### demo_engineer (데이터 엔지니어)

```bash
./connect-as.sh engineer
```

```sql
-- ✓ 성공: 모든 데이터 읽기
SELECT * FROM rbac_demo.sales;
SELECT * FROM rbac_demo.customers;  -- 모든 컬럼 포함

-- ✓ 성공: 데이터 쓰기
INSERT INTO rbac_demo.sales VALUES (999, 'TEST', 'Test Product', 100.00, today(), 101);

-- ✓ 성공: 데이터 삭제
DELETE FROM rbac_demo.sales WHERE id = 999;

-- ✓ 성공: 테이블 수정
ALTER TABLE rbac_demo.sales ADD COLUMN IF NOT EXISTS test_column String DEFAULT '';
ALTER TABLE rbac_demo.sales DROP COLUMN IF EXISTS test_column;

-- 현재 설정 확인
SELECT getSetting('max_memory_usage');  -- 50000000000 (50GB)
SELECT getSetting('max_execution_time');  -- 3600 (1시간)
```

### demo_partner (외부 파트너)

```bash
./connect-as.sh partner
```

```sql
-- ✓ 성공: APAC 지역 데이터만 보임
SELECT * FROM rbac_demo.sales;
-- 결과: 3개 행 (APAC만)

-- ✓ 성공: 허용된 컬럼만 조회
SELECT id, region, product, amount FROM rbac_demo.sales;

-- ✗ 실패: customer_id 컬럼 접근 불가
SELECT customer_id FROM rbac_demo.sales;

-- ✗ 실패: customers 테이블 접근 불가
SELECT * FROM rbac_demo.customers;

-- 지역별 카운트 (Row Policy 확인)
SELECT region, count() as cnt FROM rbac_demo.sales GROUP BY region;
-- 결과: APAC만 나와야 함

-- 현재 설정 확인
SELECT getSetting('max_memory_usage');  -- 2000000000 (2GB)
SELECT getSetting('max_execution_time');  -- 30 (30초)
```

---

## 리소스 제한 테스트

### Settings Profile 테스트

```bash
./connect-as.sh analyst
```

```sql
-- 시간 제한 테스트 (5분 = 300초)
SELECT sleep(1) FROM numbers(400);  -- 에러 발생 (max_execution_time 초과)

-- 메모리 제한 테스트
SELECT groupArray(number) FROM numbers(100000000);  -- 에러 발생 (max_memory_usage 초과)

-- 결과 행 제한 테스트
SELECT * FROM numbers(2000000);  -- 에러 발생 (max_result_rows 초과)
```

### Quota 테스트

```bash
./connect-as.sh analyst
```

```sql
-- 초기 Quota 확인
SELECT * FROM system.quota_usage;

-- 쿼리 여러 번 실행
SELECT count() FROM rbac_demo.sales;  -- 여러 번 실행

-- Quota 사용량 재확인
SELECT
    quota_name,
    queries,
    max_queries,
    execution_time,
    max_execution_time
FROM system.quota_usage
WHERE quota_name LIKE 'demo_%';
```

---

## 트러블슈팅

### 1. "Authentication failed" 에러

```bash
# 사용자가 생성되었는지 확인 (관리자로)
clickhouse-client --query="SELECT name FROM system.users WHERE name LIKE 'demo_%'"

# 비밀번호 확인 (올바른 비밀번호 사용 중인지)
```

### 2. "Access denied" 에러

```bash
# 해당 사용자의 권한 확인 (관리자로)
clickhouse-client --query="SHOW GRANTS FOR demo_analyst"

# 역할 할당 확인
clickhouse-client --query="SELECT * FROM system.role_grants WHERE user_name = 'demo_analyst'"
```

### 3. 접속이 안 됨 (ClickHouse Cloud)

```bash
# 연결 테스트
clickhouse-client \
    --host="your-instance.clickhouse.cloud" \
    --port=9440 \
    --secure \
    --user=default \
    --password='your-default-password' \
    --query="SELECT 1"

# IP 화이트리스트 확인 (ClickHouse Cloud 콘솔에서)
```

### 4. Row Policy가 작동하지 않음

```sql
-- Row Policy 확인 (관리자로)
SELECT * FROM system.row_policies WHERE database = 'rbac_demo';

-- 실제 적용 여부 확인
SELECT policy_name, select_filter
FROM system.row_policies
WHERE table = 'sales';
```

---

## 추가 리소스

- [README.md](README.md) - 전체 실습 가이드
- [rbac-blog-plan.md](rbac-blog-plan.md) - 상세 계획서
- ClickHouse 공식 문서:
  - [Access Rights](https://clickhouse.com/docs/operations/access-rights)
  - [Settings Profiles](https://clickhouse.com/docs/operations/settings/settings-profiles)
  - [Quotas](https://clickhouse.com/docs/operations/quotas)
