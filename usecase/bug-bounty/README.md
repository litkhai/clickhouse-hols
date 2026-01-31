# Bug Bounty Packet Analysis Platform with ClickHouse

[English](#english) | [한국어](#한국어)

---

## English

A comprehensive platform for analyzing bug bounty packet data using ClickHouse, featuring real-time PII anonymization, automated attack detection, and vulnerability reproduction validation.

### 🎯 Purpose

This lab provides practical experience with ClickHouse for security operations and bug bounty management:
- HTTP packet data capture and analysis
- Real-time PII (Personally Identifiable Information) detection and anonymization
- Automated attack pattern detection (Bruteforce, Scanner, Enumeration, EDoS)
- Vulnerability reproduction validation and regression testing
- Automated triage and severity classification
- AI-ready anonymized dataset generation

Whether you're building a security operations platform or managing bug bounty programs, this lab demonstrates production-ready patterns for handling sensitive packet data at scale.

### 📊 Dataset Scale

- **Normal Traffic**: 5,000 HTTP requests
- **Attack Scenarios**: SQL Injection, JWT exposure, API key leaks
- **PII Types Detected**: JWT tokens, API keys, emails, phone numbers, credit cards
- **Time Window**: Real-time + historical (configurable TTL)
- **Demo Data**: Realistic bug bounty scenarios with before/after patch validation

### 📁 File Structure

```
bug-bounty/
├── README.md                                   # This file
├── 01-create-database.sql                      # Database setup
├── 02-create-tables.sql                        # Core tables (packets, anonymized, detection)
├── 03-create-materialized-views-realtime.sql   # Real-time MVs (anonymization, PII logging)
├── 04-create-refreshable-mvs.sql               # Refreshable MVs (attack detection, triage)
├── 05-generate-demo-data.sql                   # Demo data generation
├── 06-demo-queries.sql                         # Demo analysis queries
├── 07-utility-functions.sql                    # Utility functions and views
└── 99-cleanup.sql                              # Cleanup script
```

### 🚀 Quick Start

Execute all scripts in sequence:

```bash
cd usecase/bug-bounty

# Sequential execution
clickhouse-client --queries-file 01-create-database.sql
clickhouse-client --queries-file 02-create-tables.sql
clickhouse-client --queries-file 03-create-materialized-views-realtime.sql
clickhouse-client --queries-file 04-create-refreshable-mvs.sql
clickhouse-client --queries-file 05-generate-demo-data.sql
clickhouse-client --queries-file 07-utility-functions.sql
```

Or in a loop:

```bash
for file in 01-create-database.sql 02-create-tables.sql 03-create-materialized-views-realtime.sql 04-create-refreshable-mvs.sql 05-generate-demo-data.sql 07-utility-functions.sql; do
    echo "Executing $file..."
    clickhouse-client --queries-file "$file"
    echo ""
done
```

### 📖 Detailed Lab Steps

#### 1. Database Setup

```bash
clickhouse-client --queries-file 01-create-database.sql
```

**What it does**:
- Creates `bug_bounty` database
- Sets up USE context

**Expected time**: ~1 second

---

#### 2. Core Tables Creation

```bash
clickhouse-client --queries-file 02-create-tables.sql
```

**What it does**:
- Creates 6 core tables:
  - `http_packets`: Raw HTTP request/response packets (TTL: 90 days)
  - `http_packets_anonymized`: Anonymized packets for AI training (TTL: 365 days)
  - `attack_detection_agg`: Attack pattern aggregates (1-minute windows)
  - `triage_results`: Automated triage classification
  - `block_list`: Real-time block targets
  - `pii_exposure_log`: Detailed PII exposure events (TTL: 180 days)
- Adds secondary indexes for efficient queries

**Expected time**: ~2-3 seconds

---

#### 3. Real-time Materialized Views

```bash
clickhouse-client --queries-file 03-create-materialized-views-realtime.sql
```

**What it does**:
- Creates real-time data processing pipelines:
  - `mv_anonymize_packets`: Auto-anonymize incoming packets
    - Masks JWT tokens, API keys, emails, phone numbers, credit cards
    - Generates SHA256 hashes for IPs and participant IDs
    - Records PII types detected as metadata
  - `mv_pii_exposure_log`: Logs PII exposure incidents
    - Severity classification (CRITICAL/HIGH/MEDIUM/LOW)
    - Context snippets (masked)

**Expected time**: ~2-3 seconds

---

#### 4. Refreshable Materialized Views

```bash
clickhouse-client --queries-file 04-create-refreshable-mvs.sql
```

**What it does**:
- Creates periodically refreshed analysis views:
  - `mv_attack_detection`: Attack pattern detection (refresh: 1 minute)
    - Bruteforce: Repeated requests to same endpoint
    - Scanner: Wide endpoint exploration
    - Enumeration: Sequential ID access patterns
    - EDoS: High-cost resource consumption
  - `mv_auto_triage`: Automated severity classification (refresh: 5 minutes)
  - `mv_auto_block`: Automatic blocking for threats > 0.7 score (refresh: 1 minute)

**Expected time**: ~2-3 seconds

**Note**: Refreshable MVs require ClickHouse Cloud or recent self-managed versions

---

#### 5. Demo Data Generation

```bash
clickhouse-client --queries-file 05-generate-demo-data.sql
```

**What it does**:
- Generates 5,000 normal HTTP requests
- Creates vulnerability scenarios:
  - SQL Injection attack sequence (before patch)
  - JWT token exposure
  - API key leaks in responses
  - Post-patch validation data
- Generates various PII patterns for testing

**Expected time**: ~5-10 seconds

---

#### 6. Demo Queries

```bash
clickhouse-client --queries-file 06-demo-queries.sql
```

**Query scenarios**:
- **PART 1: Vulnerability Reproduction & Regression Testing**
  - Extract request sequences by report ID
  - Automated reproduction validation
  - Before/after patch comparison
  - Auto-triage dashboard
- **PART 2: Attack Detection**
  - Real-time threat monitoring
  - Attack type breakdown
  - Block list management
- **PART 3: PII Anonymization**
  - Original vs anonymized data comparison
  - PII exposure statistics
  - AI training dataset export

**Expected time**: ~5-30 seconds per query

---

#### 7. Utility Functions and Views

```bash
clickhouse-client --queries-file 07-utility-functions.sql
```

**What it does**:
- Creates reusable PII masking functions
  - `maskJWT`, `maskEmail`, `maskPhoneKR`, `maskCreditCard`, `maskApiKey`
  - `maskAllPII`: Comprehensive masking function
- Creates threat score calculation functions
  - `calcBruteforceScore`, `calcScannerScore`
- Creates convenience views for common queries

**Expected time**: ~2-3 seconds

---

### 🔧 Use Cases

#### 1️⃣ Vulnerability Reproduction Automation

**Goal**: Automatically validate bug reports and verify patches

| Feature | Description |
|---------|-------------|
| Sequence Extraction | Retrieve request/response sequence by report ID |
| Reproduction Validation | Analyze response patterns to confirm vulnerability |
| Regression Testing | Compare results before/after patch |
| Auto Triage | Automatic severity classification |

**Example Query**:
```sql
SELECT report_id,
       countIf(response_body LIKE '%password%') as sensitive_exposed,
       multiIf(
           countIf(response_body LIKE '%password%') > 0, 'CRITICAL',
           countIf(response_status >= 500) > 0, 'HIGH',
           'MEDIUM'
       ) as verdict
FROM http_packets
WHERE report_id = 'BUG-2024-1234'
GROUP BY report_id;
```

---

#### 2️⃣ Automated Attack Detection

**Goal**: Detect abuse and malicious activity in bug bounty traffic

| Attack Type | Detection Criteria |
|-------------|-------------------|
| Bruteforce | Repeated requests to same endpoint, high auth failure rate |
| Scanner | Wide endpoint exploration, admin path attempts |
| Enumeration | Sequential ID access patterns |
| EDoS | Repeated high-cost requests, elevated response times |

**Auto-blocking**: Threats with score > 0.7 automatically added to block list

**Example Query**:
```sql
SELECT source_ip_hash,
       participant_id,
       bruteforce_score, scanner_score,
       is_blocked, block_reason
FROM attack_detection_agg
WHERE bruteforce_score > 0.7 OR scanner_score > 0.7
ORDER BY bruteforce_score DESC;
```

---

#### 3️⃣ PII Detection and Anonymization

**Goal**: Automatically detect and mask sensitive information in responses

| PII Type | Pattern | Masked Result |
|----------|---------|---------------|
| JWT Token | `eyJ...` | `[JWT_REDACTED]` |
| API Key | `"api_key": "..."` | `"api_key":"[REDACTED]"` |
| Email | `user@example.com` | `[EMAIL_REDACTED]` |
| Phone (KR) | `010-1234-5678` | `[PHONE_REDACTED]` |
| Credit Card | `4111-1111-1111-1111` | `[CARD_REDACTED]` |

**Anonymized Data**: Safe for AI training and public disclosure

**Example Query**:
```sql
SELECT pii_type, count() as exposure_count,
       countIf(severity = 'CRITICAL') as critical_count
FROM pii_exposure_log
WHERE event_date = today()
GROUP BY pii_type
ORDER BY exposure_count DESC;
```

---

### 🛠 Prerequisites

**System Requirements**:
- **ClickHouse Version**: 23.8+ (for Refreshable MVs on Cloud, 24.1+ for self-managed)
- **Memory**: Minimum 4GB RAM (8GB+ recommended)
- **Disk Space**: 10GB for demo data
- **CPU**: 2+ cores recommended

**Software**:
- ClickHouse client installed
- Access to ClickHouse Cloud or self-managed instance
- Terminal or SQL client

**Permissions**:
- CREATE DATABASE
- CREATE TABLE
- CREATE VIEW
- INSERT data

---

### 💡 Performance Tips

1. **Index Usage**:
   - Bloom filter indexes added for `report_id`, `source_ip`, and `response_status`
   - Leverage these for fast filtering

2. **Partitioning**:
   - All tables partitioned by month (`toYYYYMM`)
   - Use partition pruning in WHERE clauses: `WHERE event_date >= today() - 30`

3. **TTL Management**:
   - Raw packets: 90 days
   - Anonymized data: 365 days
   - PII logs: 180 days
   - Adjust TTL based on compliance requirements

4. **Query Optimization**:
   - Use `FORMAT PrettyCompactMonoBlock` for readable output
   - Apply LIMIT for large result sets
   - Use materialized views instead of repeated aggregations

5. **Refreshable MVs**:
   - Adjust refresh intervals based on monitoring needs
   - Consider compute costs on ClickHouse Cloud

---

### 🔍 Troubleshooting

#### Issue: "Table already exists" error
**Solution**: Run cleanup script first
```bash
clickhouse-client --queries-file 99-cleanup.sql
```

#### Issue: Refreshable MVs not supported
**Symptom**: Error creating `mv_attack_detection`
**Solution**:
- Ensure ClickHouse version 23.8+ (Cloud) or 24.1+ (self-managed)
- Alternative: Use regular MVs with INSERT SELECT scheduled queries

#### Issue: Out of memory during data generation
**Symptom**: Query fails during `05-generate-demo-data.sql`
**Solution**:
- Reduce `numbers()` range in INSERT statements
- Generate data in smaller batches
- Increase available memory

#### Issue: Slow query performance
**Solution**:
- Check partition pruning: `EXPLAIN SELECT ...`
- Verify indexes: `SHOW CREATE TABLE http_packets`
- Use `SYSTEM RELOAD DICTIONARIES` if using dictionaries
- Check merge status: `SELECT * FROM system.merges`

#### Issue: PII not being detected
**Symptom**: `detected_pii_types` array is empty
**Solution**:
- Verify regex patterns in `mv_anonymize_packets`
- Check source data format matches patterns
- Test regex with `SELECT match(response_body, 'eyJ[A-Za-z0-9_-]{10,}...')`

---

### 🧹 Cleanup

To remove all demo data and objects:

```bash
clickhouse-client --queries-file 99-cleanup.sql
```

**What it removes**:
- All materialized views
- All regular views
- All functions
- All tables
- Database (optional - commented out by default)

**Expected time**: ~2-3 seconds

---

### 📚 Key Learning Points

1. **Real-time Data Processing**: Materialized views for instant data transformation
2. **PII Handling**: Regex-based detection and masking strategies
3. **Threat Detection**: Pattern-based scoring for different attack types
4. **Data Lifecycle**: TTL management for compliance and cost optimization
5. **Query Performance**: Partitioning, indexing, and aggregation optimization
6. **Automation**: Refreshable MVs for periodic analysis updates
7. **Audit Trail**: Comprehensive logging of security events

---

### 📝 License

MIT License - See repository root for details

---

### 👤 Author

Created: 2026-01-31
Updated: 2026-01-31

---

---

## 한국어

ClickHouse를 활용한 버그바운티 패킷 분석 플랫폼입니다. 실시간 PII 비식별화, 자동화된 공격 탐지, 취약점 재현 검증 기능을 제공합니다.

### 🎯 목적

이 랩은 보안 운영 및 버그바운티 관리를 위한 ClickHouse 실무 경험을 제공합니다:
- HTTP 패킷 데이터 캡처 및 분석
- 실시간 PII(개인식별정보) 탐지 및 비식별화
- 자동화된 공격 패턴 탐지 (Bruteforce, Scanner, Enumeration, EDoS)
- 취약점 재현 검증 및 회귀 테스트
- 자동 트리아지 및 심각도 분류
- AI 학습용 비식별화 데이터셋 생성

보안 운영 플랫폼을 구축하거나 버그바운티 프로그램을 관리하는 경우, 이 랩은 대규모 민감한 패킷 데이터 처리를 위한 프로덕션 수준의 패턴을 제시합니다.

### 📊 데이터셋 규모

- **정상 트래픽**: 5,000개 HTTP 요청
- **공격 시나리오**: SQL Injection, JWT 노출, API 키 유출
- **PII 탐지 유형**: JWT 토큰, API 키, 이메일, 전화번호, 신용카드
- **시간 윈도우**: 실시간 + 히스토리컬 (TTL 설정 가능)
- **데모 데이터**: 패치 전후 검증을 포함한 실제 버그바운티 시나리오

### 📁 파일 구조

```
bug-bounty/
├── README.md                                   # 이 파일
├── 01-create-database.sql                      # 데이터베이스 설정
├── 02-create-tables.sql                        # 핵심 테이블 (패킷, 비식별화, 탐지)
├── 03-create-materialized-views-realtime.sql   # 실시간 MV (비식별화, PII 로깅)
├── 04-create-refreshable-mvs.sql               # Refreshable MV (공격탐지, 트리아지)
├── 05-generate-demo-data.sql                   # 데모 데이터 생성
├── 06-demo-queries.sql                         # 데모 분석 쿼리
├── 07-utility-functions.sql                    # 유틸리티 함수 및 뷰
└── 99-cleanup.sql                              # 정리 스크립트
```

### 🚀 빠른 시작

모든 스크립트를 순서대로 실행:

```bash
cd usecase/bug-bounty

# 순차 실행
clickhouse-client --queries-file 01-create-database.sql
clickhouse-client --queries-file 02-create-tables.sql
clickhouse-client --queries-file 03-create-materialized-views-realtime.sql
clickhouse-client --queries-file 04-create-refreshable-mvs.sql
clickhouse-client --queries-file 05-generate-demo-data.sql
clickhouse-client --queries-file 07-utility-functions.sql
```

또는 루프로 실행:

```bash
for file in 01-create-database.sql 02-create-tables.sql 03-create-materialized-views-realtime.sql 04-create-refreshable-mvs.sql 05-generate-demo-data.sql 07-utility-functions.sql; do
    echo "Executing $file..."
    clickhouse-client --queries-file "$file"
    echo ""
done
```

### 📖 상세 랩 단계

#### 1. 데이터베이스 설정

```bash
clickhouse-client --queries-file 01-create-database.sql
```

**수행 내용**:
- `bug_bounty` 데이터베이스 생성
- USE 컨텍스트 설정

**예상 시간**: ~1초

---

#### 2. 핵심 테이블 생성

```bash
clickhouse-client --queries-file 02-create-tables.sql
```

**수행 내용**:
- 6개 핵심 테이블 생성:
  - `http_packets`: 원본 HTTP 요청/응답 패킷 (TTL: 90일)
  - `http_packets_anonymized`: AI 학습용 비식별화 패킷 (TTL: 365일)
  - `attack_detection_agg`: 공격 패턴 집계 (1분 윈도우)
  - `triage_results`: 자동 트리아지 분류
  - `block_list`: 실시간 차단 대상
  - `pii_exposure_log`: 상세 PII 노출 이벤트 (TTL: 180일)
- 효율적인 쿼리를 위한 보조 인덱스 추가

**예상 시간**: ~2-3초

---

#### 3. 실시간 Materialized Views

```bash
clickhouse-client --queries-file 03-create-materialized-views-realtime.sql
```

**수행 내용**:
- 실시간 데이터 처리 파이프라인 생성:
  - `mv_anonymize_packets`: 유입 패킷 자동 비식별화
    - JWT 토큰, API 키, 이메일, 전화번호, 신용카드 마스킹
    - IP 및 참여자 ID SHA256 해시 생성
    - 탐지된 PII 유형을 메타데이터로 기록
  - `mv_pii_exposure_log`: PII 노출 사건 로깅
    - 심각도 분류 (CRITICAL/HIGH/MEDIUM/LOW)
    - 컨텍스트 스니펫 (마스킹됨)

**예상 시간**: ~2-3초

---

#### 4. Refreshable Materialized Views

```bash
clickhouse-client --queries-file 04-create-refreshable-mvs.sql
```

**수행 내용**:
- 주기적으로 갱신되는 분석 뷰 생성:
  - `mv_attack_detection`: 공격 패턴 탐지 (갱신: 1분)
    - Bruteforce: 동일 엔드포인트 반복 요청
    - Scanner: 광범위한 엔드포인트 탐색
    - Enumeration: 순차적 ID 접근 패턴
    - EDoS: 고비용 리소스 소비
  - `mv_auto_triage`: 자동 심각도 분류 (갱신: 5분)
  - `mv_auto_block`: 위협 점수 > 0.7 자동 차단 (갱신: 1분)

**예상 시간**: ~2-3초

**참고**: Refreshable MV는 ClickHouse Cloud 또는 최신 self-managed 버전 필요

---

#### 5. 데모 데이터 생성

```bash
clickhouse-client --queries-file 05-generate-demo-data.sql
```

**수행 내용**:
- 5,000개 정상 HTTP 요청 생성
- 취약점 시나리오 생성:
  - SQL Injection 공격 시퀀스 (패치 전)
  - JWT 토큰 노출
  - 응답의 API 키 유출
  - 패치 후 검증 데이터
- 테스트용 다양한 PII 패턴 생성

**예상 시간**: ~5-10초

---

#### 6. 데모 쿼리

```bash
clickhouse-client --queries-file 06-demo-queries.sql
```

**쿼리 시나리오**:
- **PART 1: 취약점 재현 및 회귀 테스트**
  - 리포트 ID별 요청 시퀀스 추출
  - 자동 재현 검증
  - 패치 전후 비교
  - 자동 트리아지 대시보드
- **PART 2: 공격 탐지**
  - 실시간 위협 모니터링
  - 공격 유형별 분석
  - 차단 목록 관리
- **PART 3: PII 비식별화**
  - 원본 vs 비식별화 데이터 비교
  - PII 노출 통계
  - AI 학습용 데이터셋 추출

**예상 시간**: 쿼리당 ~5-30초

---

#### 7. 유틸리티 함수 및 뷰

```bash
clickhouse-client --queries-file 07-utility-functions.sql
```

**수행 내용**:
- 재사용 가능한 PII 마스킹 함수 생성
  - `maskJWT`, `maskEmail`, `maskPhoneKR`, `maskCreditCard`, `maskApiKey`
  - `maskAllPII`: 종합 마스킹 함수
- 위협 점수 계산 함수 생성
  - `calcBruteforceScore`, `calcScannerScore`
- 자주 사용하는 쿼리용 편의 뷰 생성

**예상 시간**: ~2-3초

---

### 🔧 유즈케이스

#### 1️⃣ 취약점 재현 자동화

**목표**: 버그 리포트 자동 검증 및 패치 확인

| 기능 | 설명 |
|------|------|
| 시퀀스 추출 | 리포트 ID로 요청/응답 시퀀스 조회 |
| 재현 검증 | 응답 패턴 분석으로 취약점 확인 |
| 회귀 테스트 | 패치 전후 결과 비교 |
| 자동 트리아지 | 자동 심각도 분류 |

**예제 쿼리**:
```sql
SELECT report_id,
       countIf(response_body LIKE '%password%') as sensitive_exposed,
       multiIf(
           countIf(response_body LIKE '%password%') > 0, 'CRITICAL',
           countIf(response_status >= 500) > 0, 'HIGH',
           'MEDIUM'
       ) as verdict
FROM http_packets
WHERE report_id = 'BUG-2024-1234'
GROUP BY report_id;
```

---

#### 2️⃣ 자동화 공격 탐지

**목표**: 버그바운티 트래픽에서 남용 및 악의적 활동 탐지

| 공격 유형 | 탐지 기준 |
|-----------|-----------|
| Bruteforce | 동일 엔드포인트 반복, 높은 인증 실패율 |
| Scanner | 광범위한 엔드포인트 탐색, 관리자 경로 시도 |
| Enumeration | 순차적 ID 접근 패턴 |
| EDoS | 반복적 고비용 요청, 높은 응답시간 |

**자동 차단**: 점수 > 0.7인 위협 자동 차단 목록 추가

**예제 쿼리**:
```sql
SELECT source_ip_hash,
       participant_id,
       bruteforce_score, scanner_score,
       is_blocked, block_reason
FROM attack_detection_agg
WHERE bruteforce_score > 0.7 OR scanner_score > 0.7
ORDER BY bruteforce_score DESC;
```

---

#### 3️⃣ PII 탐지 및 비식별화

**목표**: 응답의 민감정보 자동 탐지 및 마스킹

| PII 유형 | 패턴 | 마스킹 결과 |
|----------|------|-------------|
| JWT 토큰 | `eyJ...` | `[JWT_REDACTED]` |
| API 키 | `"api_key": "..."` | `"api_key":"[REDACTED]"` |
| 이메일 | `user@example.com` | `[EMAIL_REDACTED]` |
| 전화번호 | `010-1234-5678` | `[PHONE_REDACTED]` |
| 신용카드 | `4111-1111-1111-1111` | `[CARD_REDACTED]` |

**비식별화 데이터**: AI 학습 및 공개 공유 안전

**예제 쿼리**:
```sql
SELECT pii_type, count() as exposure_count,
       countIf(severity = 'CRITICAL') as critical_count
FROM pii_exposure_log
WHERE event_date = today()
GROUP BY pii_type
ORDER BY exposure_count DESC;
```

---

### 🛠 사전 요구사항

**시스템 요구사항**:
- **ClickHouse 버전**: 23.8+ (Cloud Refreshable MV), 24.1+ (self-managed)
- **메모리**: 최소 4GB RAM (8GB+ 권장)
- **디스크 공간**: 데모 데이터용 10GB
- **CPU**: 2코어 이상 권장

**소프트웨어**:
- ClickHouse 클라이언트 설치
- ClickHouse Cloud 또는 self-managed 인스턴스 접근
- 터미널 또는 SQL 클라이언트

**권한**:
- CREATE DATABASE
- CREATE TABLE
- CREATE VIEW
- INSERT 데이터

---

### 💡 성능 팁

1. **인덱스 활용**:
   - `report_id`, `source_ip`, `response_status`에 Bloom filter 인덱스 추가됨
   - 빠른 필터링을 위해 활용

2. **파티셔닝**:
   - 모든 테이블 월별 파티션 (`toYYYYMM`)
   - WHERE 절에서 파티션 프루닝 활용: `WHERE event_date >= today() - 30`

3. **TTL 관리**:
   - 원본 패킷: 90일
   - 비식별화 데이터: 365일
   - PII 로그: 180일
   - 컴플라이언스 요구사항에 따라 TTL 조정

4. **쿼리 최적화**:
   - 가독성 있는 출력을 위해 `FORMAT PrettyCompactMonoBlock` 사용
   - 대용량 결과에 LIMIT 적용
   - 반복 집계 대신 Materialized View 사용

5. **Refreshable MV**:
   - 모니터링 필요에 따라 갱신 주기 조정
   - ClickHouse Cloud에서 컴퓨트 비용 고려

---

### 🔍 트러블슈팅

#### 문제: "Table already exists" 오류
**해결방법**: 먼저 정리 스크립트 실행
```bash
clickhouse-client --queries-file 99-cleanup.sql
```

#### 문제: Refreshable MV 지원되지 않음
**증상**: `mv_attack_detection` 생성 시 오류
**해결방법**:
- ClickHouse 버전 23.8+ (Cloud) 또는 24.1+ (self-managed) 확인
- 대안: 예약된 INSERT SELECT로 일반 MV 사용

#### 문제: 데이터 생성 중 메모리 부족
**증상**: `05-generate-demo-data.sql` 실행 중 쿼리 실패
**해결방법**:
- INSERT 문의 `numbers()` 범위 줄이기
- 데이터를 더 작은 배치로 생성
- 사용 가능한 메모리 증가

#### 문제: 느린 쿼리 성능
**해결방법**:
- 파티션 프루닝 확인: `EXPLAIN SELECT ...`
- 인덱스 검증: `SHOW CREATE TABLE http_packets`
- 딕셔너리 사용 시 `SYSTEM RELOAD DICTIONARIES`
- 머지 상태 확인: `SELECT * FROM system.merges`

#### 문제: PII가 탐지되지 않음
**증상**: `detected_pii_types` 배열이 비어있음
**해결방법**:
- `mv_anonymize_packets`의 정규식 패턴 확인
- 소스 데이터 형식이 패턴과 일치하는지 확인
- 정규식 테스트: `SELECT match(response_body, 'eyJ[A-Za-z0-9_-]{10,}...')`

---

### 🧹 정리

모든 데모 데이터 및 객체 제거:

```bash
clickhouse-client --queries-file 99-cleanup.sql
```

**제거 항목**:
- 모든 Materialized View
- 모든 일반 View
- 모든 Function
- 모든 Table
- Database (선택사항 - 기본적으로 주석 처리)

**예상 시간**: ~2-3초

---

### 📚 주요 학습 포인트

1. **실시간 데이터 처리**: 즉각적인 데이터 변환을 위한 Materialized View
2. **PII 처리**: 정규식 기반 탐지 및 마스킹 전략
3. **위협 탐지**: 다양한 공격 유형에 대한 패턴 기반 점수 계산
4. **데이터 라이프사이클**: 컴플라이언스 및 비용 최적화를 위한 TTL 관리
5. **쿼리 성능**: 파티셔닝, 인덱싱, 집계 최적화
6. **자동화**: 주기적 분석 업데이트를 위한 Refreshable MV
7. **감사 추적**: 보안 이벤트의 포괄적 로깅

---

### 📝 라이선스

MIT License - 자세한 내용은 저장소 루트 참조

---

### 👤 작성자

작성일: 2026-01-31
업데이트: 2026-01-31
