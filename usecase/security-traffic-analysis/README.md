# Security Traffic Analysis Platform with ClickHouse

[English](#english) | [한국어](#한국어)

---

## English

A comprehensive platform for security traffic analysis using ClickHouse, featuring real-time PII anonymization, automated attack detection, and vulnerability reproduction validation.

### 🎯 Purpose

This lab provides practical experience with ClickHouse for security operations and traffic analysis:
- HTTP packet data capture and analysis
- Real-time PII (Personally Identifiable Information) detection and anonymization
- Automated attack pattern detection (Bruteforce, Scanner, Enumeration, EDoS)
- Vulnerability reproduction validation and regression testing
- Automated triage and severity classification
- AI-ready anonymized dataset generation

Whether you're building a security operations platform or analyzing traffic patterns, this lab demonstrates production-ready patterns for handling sensitive packet data at scale.

### 📊 Dataset Scale

- **Normal Traffic**: 5,000 HTTP requests
- **Attack Scenarios**: SQL Injection, JWT exposure, API key leaks
- **PII Types Detected**: JWT tokens, API keys, emails, phone numbers, credit cards
- **Time Window**: Real-time + historical (configurable TTL)
- **Demo Data**: Realistic security traffic analysis scenarios with before/after patch validation

### 📁 File Structure

```
security-traffic-analysis/
├── README.md                                   # This file
├── 01-create-database.sql                      # Database setup
├── 02-create-tables.sql                        # Core tables (packets, anonymized, detection)
├── 03-create-materialized-views-realtime.sql   # Real-time MVs (anonymization, PII logging)
├── 04-create-refreshable-mvs.sql               # Refreshable MVs (attack detection, triage)
├── 05-generate-demo-data.sql                   # Demo data generation
├── 06-demo-queries.sql                         # Demo analysis queries
├── 07-utility-functions.sql                    # Utility functions and views
├── 08-vector-search-setup.sql                  # Vector Search setup (attack signatures)
├── 09-vector-embeddings-tables.sql             # Embeddings tables (requests, reports)
├── 10-vector-demo-data.sql                     # Vector demo data generation
├── 11-vector-search-queries.sql                # Vector Search query practice
├── 12-vector-integration.sql                   # Python/API integration guide
└── 99-cleanup.sql                              # Cleanup script
```

### 🚀 Quick Start

Execute core labs in sequence:

```bash
cd usecase/security-traffic-analysis

# Core Lab (Required)
clickhouse-client --queries-file 01-create-database.sql
clickhouse-client --queries-file 02-create-tables.sql
clickhouse-client --queries-file 03-create-materialized-views-realtime.sql
clickhouse-client --queries-file 04-create-refreshable-mvs.sql
clickhouse-client --queries-file 05-generate-demo-data.sql
clickhouse-client --queries-file 07-utility-functions.sql

# Advanced Lab: Vector Search (Optional, requires ClickHouse 24.8+)
clickhouse-client --queries-file 08-vector-search-setup.sql
clickhouse-client --queries-file 09-vector-embeddings-tables.sql
clickhouse-client --queries-file 10-vector-demo-data.sql
clickhouse-client --queries-file 11-vector-search-queries.sql
```

Or execute core labs in a loop:

```bash
for file in 01-create-database.sql 02-create-tables.sql 03-create-materialized-views-realtime.sql 04-create-refreshable-mvs.sql 05-generate-demo-data.sql 07-utility-functions.sql; do
    echo "Executing $file..."
    clickhouse-client --queries-file "$file"
    echo ""
done
```

For Vector Search labs:

```bash
for file in 08-vector-search-setup.sql 09-vector-embeddings-tables.sql 10-vector-demo-data.sql 11-vector-search-queries.sql; do
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
- Creates `security_traffic_analysis` database
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

### 🔍 Advanced Lab: Vector Search (Optional)

**Prerequisites**: ClickHouse 24.8+ (Vector Search GA)

This advanced section demonstrates AI-powered threat detection using vector embeddings and semantic similarity search.

#### 8. Vector Search Setup

```bash
clickhouse-client --queries-file 08-vector-search-setup.sql
```

**What it does**:
- Introduces Vector Search concepts and use cases
- Creates `attack_signatures` table with vector embeddings
- Stores known attack patterns with metadata (CWE, CVSS, severity)
- Sets up HNSW index for fast similarity search
- Inserts sample attack patterns (SQLi, XSS, SSRF, etc.)

**Key concepts**:
- Vector embeddings represent attack patterns in high-dimensional space
- cosineDistance measures semantic similarity between patterns
- HNSW (Hierarchical Navigable Small World) enables fast approximate search

**Expected time**: ~2-3 seconds

---

#### 9. Embeddings Tables

```bash
clickhouse-client --queries-file 09-vector-embeddings-tables.sql
```

**What it does**:
- Creates `request_embeddings` table for HTTP request vectors
- Creates `report_knowledge_base` table for bug report semantic search
- Creates `duplicate_report_links` table for tracking duplicates
- Sets up vector similarity indexes
- Creates utility views and functions

**Use cases**:
- Similar attack pattern detection
- Duplicate report identification
- Semantic search for bug reports
- Automated triage prioritization

**Expected time**: ~2-3 seconds

---

#### 10. Vector Demo Data

```bash
clickhouse-client --queries-file 10-vector-demo-data.sql
```

**What it does**:
- Creates mock embedding functions (SQLi, XSS, SSRF patterns)
- Updates attack signatures with vector embeddings
- Generates embeddings for sample HTTP requests
- Creates sample bug reports with embeddings
- Validates embedding dimensions and quality

**Note**: Uses mock embeddings for demo. Production requires OpenAI API or Sentence Transformers.

**Expected time**: ~3-5 seconds

---

#### 11. Vector Search Queries

```bash
clickhouse-client --queries-file 11-vector-search-queries.sql
```

**Query scenarios**:
- **PART 1: Attack Pattern Detection**
  - Find similar attack patterns for suspicious requests
  - Match requests to known attack categories
  - Filter by severity and CVSS score
- **PART 2: Duplicate Report Detection**
  - Find similar bug reports
  - Calculate duplicate probability
  - Analyze duplicate rates by vulnerability type
- **PART 3: Semantic Search**
  - Natural language queries for bug reports
  - Hybrid keyword + vector search
  - Prioritize based on past high-bounty reports
- **PART 4: Clustering & Analytics**
  - Group similar attack patterns
  - Outlier detection (anomaly detection)
  - Attack trend analysis over time
- **PART 5: Production Queries**
  - Real-time threat scoring system
  - Automated triage recommendations
  - Combined heuristic + vector scoring

**Expected time**: ~5-30 seconds per query

---

#### 12. Python Integration

```bash
# View the integration guide
cat 12-vector-integration.sql
```

**What it covers**:
- **OpenAI API Integration**: Generate real embeddings using OpenAI
- **Batch Processing**: Efficient embedding generation pipelines
- **REST API Examples**: Flask-based search API endpoints
- **Sentence Transformers**: Free, local embedding generation
- **Performance Optimization**: Caching, batching, query optimization
- **Production Checklist**: Security, monitoring, cost optimization

**Key components**:
- Python scripts for embedding generation
- API endpoints for similarity search
- Duplicate detection service
- Semantic search implementation
- Best practices and deployment guide

**Expected time**: Study material (no execution required)

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

**Goal**: Detect abuse and malicious activity in security traffic analysis traffic

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
8. **Vector Search (Advanced)**: AI-powered threat detection using semantic similarity
   - Attack pattern recognition with embeddings
   - Duplicate report detection using cosine distance
   - Semantic search for bug reports
   - Hybrid traditional + AI-based threat scoring
   - Production-ready integration patterns

---

### 📝 License

MIT License - See repository root for details

---

### 👤 Author

Created: 2026-01-31
Updated: 2026-02-01

---

---

## 한국어

ClickHouse를 활용한 보안 트래픽 분석 패킷 분석 플랫폼입니다. 실시간 PII 비식별화, 자동화된 공격 탐지, 취약점 재현 검증 기능을 제공합니다.

### 🎯 목적

이 랩은 보안 운영 및 보안 트래픽 분석 관리를 위한 ClickHouse 실무 경험을 제공합니다:
- HTTP 패킷 데이터 캡처 및 분석
- 실시간 PII(개인식별정보) 탐지 및 비식별화
- 자동화된 공격 패턴 탐지 (Bruteforce, Scanner, Enumeration, EDoS)
- 취약점 재현 검증 및 회귀 테스트
- 자동 트리아지 및 심각도 분류
- AI 학습용 비식별화 데이터셋 생성

보안 운영 플랫폼을 구축하거나 보안 트래픽 분석 프로그램을 관리하는 경우, 이 랩은 대규모 민감한 패킷 데이터 처리를 위한 프로덕션 수준의 패턴을 제시합니다.

### 📊 데이터셋 규모

- **정상 트래픽**: 5,000개 HTTP 요청
- **공격 시나리오**: SQL Injection, JWT 노출, API 키 유출
- **PII 탐지 유형**: JWT 토큰, API 키, 이메일, 전화번호, 신용카드
- **시간 윈도우**: 실시간 + 히스토리컬 (TTL 설정 가능)
- **데모 데이터**: 패치 전후 검증을 포함한 실제 보안 트래픽 분석 시나리오

### 📁 파일 구조

```
security-traffic-analysis/
├── README.md                                   # 이 파일
├── 01-create-database.sql                      # 데이터베이스 설정
├── 02-create-tables.sql                        # 핵심 테이블 (패킷, 비식별화, 탐지)
├── 03-create-materialized-views-realtime.sql   # 실시간 MV (비식별화, PII 로깅)
├── 04-create-refreshable-mvs.sql               # Refreshable MV (공격탐지, 트리아지)
├── 05-generate-demo-data.sql                   # 데모 데이터 생성
├── 06-demo-queries.sql                         # 데모 분석 쿼리
├── 07-utility-functions.sql                    # 유틸리티 함수 및 뷰
├── 08-vector-search-setup.sql                  # Vector Search 설정 (공격 시그니처)
├── 09-vector-embeddings-tables.sql             # 임베딩 테이블 (요청, 리포트)
├── 10-vector-demo-data.sql                     # Vector 데모 데이터 생성
├── 11-vector-search-queries.sql                # Vector Search 쿼리 실습
├── 12-vector-integration.sql                   # Python/API 통합 가이드
└── 99-cleanup.sql                              # 정리 스크립트
```

### 🚀 빠른 시작

핵심 실습을 순서대로 실행:

```bash
cd usecase/security-traffic-analysis

# 핵심 실습 (필수)
clickhouse-client --queries-file 01-create-database.sql
clickhouse-client --queries-file 02-create-tables.sql
clickhouse-client --queries-file 03-create-materialized-views-realtime.sql
clickhouse-client --queries-file 04-create-refreshable-mvs.sql
clickhouse-client --queries-file 05-generate-demo-data.sql
clickhouse-client --queries-file 07-utility-functions.sql

# 고급 실습: Vector Search (선택, ClickHouse 24.8+ 필요)
clickhouse-client --queries-file 08-vector-search-setup.sql
clickhouse-client --queries-file 09-vector-embeddings-tables.sql
clickhouse-client --queries-file 10-vector-demo-data.sql
clickhouse-client --queries-file 11-vector-search-queries.sql
```

또는 핵심 실습을 루프로 실행:

```bash
for file in 01-create-database.sql 02-create-tables.sql 03-create-materialized-views-realtime.sql 04-create-refreshable-mvs.sql 05-generate-demo-data.sql 07-utility-functions.sql; do
    echo "Executing $file..."
    clickhouse-client --queries-file "$file"
    echo ""
done
```

Vector Search 실습용:

```bash
for file in 08-vector-search-setup.sql 09-vector-embeddings-tables.sql 10-vector-demo-data.sql 11-vector-search-queries.sql; do
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
- `security_traffic_analysis` 데이터베이스 생성
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

### 🔍 고급 실습: Vector Search (선택 사항)

**사전 요구사항**: ClickHouse 24.8+ (Vector Search GA)

이 고급 섹션에서는 벡터 임베딩과 시맨틱 유사도 검색을 활용한 AI 기반 위협 탐지를 실습합니다.

#### 8. Vector Search 설정

```bash
clickhouse-client --queries-file 08-vector-search-setup.sql
```

**수행 내용**:
- Vector Search 개념 및 활용 사례 소개
- 벡터 임베딩이 포함된 `attack_signatures` 테이블 생성
- 알려진 공격 패턴을 메타데이터와 함께 저장 (CWE, CVSS, 심각도)
- 빠른 유사도 검색을 위한 HNSW 인덱스 설정
- 샘플 공격 패턴 삽입 (SQLi, XSS, SSRF 등)

**핵심 개념**:
- 벡터 임베딩은 고차원 공간에서 공격 패턴을 표현
- cosineDistance로 패턴 간 시맨틱 유사도 측정
- HNSW (Hierarchical Navigable Small World)로 빠른 근사 검색 가능

**예상 시간**: ~2-3초

---

#### 9. 임베딩 테이블 생성

```bash
clickhouse-client --queries-file 09-vector-embeddings-tables.sql
```

**수행 내용**:
- HTTP 요청 벡터용 `request_embeddings` 테이블 생성
- 버그 리포트 시맨틱 검색용 `report_knowledge_base` 테이블 생성
- 중복 추적용 `duplicate_report_links` 테이블 생성
- 벡터 유사도 인덱스 설정
- 유틸리티 뷰 및 함수 생성

**활용 사례**:
- 유사 공격 패턴 탐지
- 중복 리포트 식별
- 버그 리포트 시맨틱 검색
- 자동 트리아지 우선순위 지정

**예상 시간**: ~2-3초

---

#### 10. Vector 데모 데이터 생성

```bash
clickhouse-client --queries-file 10-vector-demo-data.sql
```

**수행 내용**:
- Mock 임베딩 함수 생성 (SQLi, XSS, SSRF 패턴)
- 공격 시그니처에 벡터 임베딩 업데이트
- 샘플 HTTP 요청에 대한 임베딩 생성
- 임베딩이 포함된 샘플 버그 리포트 생성
- 임베딩 차원 및 품질 검증

**참고**: 데모용 Mock 임베딩 사용. 프로덕션에서는 OpenAI API 또는 Sentence Transformers 필요.

**예상 시간**: ~3-5초

---

#### 11. Vector Search 쿼리 실습

```bash
clickhouse-client --queries-file 11-vector-search-queries.sql
```

**쿼리 시나리오**:
- **PART 1: 공격 패턴 탐지**
  - 의심스러운 요청과 유사한 공격 패턴 찾기
  - 요청을 알려진 공격 카테고리에 매칭
  - 심각도 및 CVSS 점수로 필터링
- **PART 2: 중복 리포트 탐지**
  - 유사한 버그 리포트 찾기
  - 중복 확률 계산
  - 취약점 유형별 중복 비율 분석
- **PART 3: 시맨틱 검색**
  - 자연어 쿼리로 버그 리포트 검색
  - 하이브리드 키워드 + 벡터 검색
  - 과거 고액 바운티 리포트 기반 우선순위 지정
- **PART 4: 클러스터링 및 분석**
  - 유사 공격 패턴 그룹화
  - 이상치 탐지 (anomaly detection)
  - 시간별 공격 트렌드 분석
- **PART 5: 프로덕션 쿼리**
  - 실시간 위협 스코어링 시스템
  - 자동 트리아지 추천
  - 휴리스틱 + 벡터 결합 점수

**예상 시간**: 쿼리당 ~5-30초

---

#### 12. Python 통합

```bash
# 통합 가이드 확인
cat 12-vector-integration.sql
```

**포함 내용**:
- **OpenAI API 통합**: OpenAI로 실제 임베딩 생성
- **배치 처리**: 효율적인 임베딩 생성 파이프라인
- **REST API 예시**: Flask 기반 검색 API 엔드포인트
- **Sentence Transformers**: 무료 로컬 임베딩 생성
- **성능 최적화**: 캐싱, 배칭, 쿼리 최적화
- **프로덕션 체크리스트**: 보안, 모니터링, 비용 최적화

**주요 구성요소**:
- 임베딩 생성용 Python 스크립트
- 유사도 검색 API 엔드포인트
- 중복 탐지 서비스
- 시맨틱 검색 구현
- 베스트 프랙티스 및 배포 가이드

**예상 시간**: 학습 자료 (실행 불필요)

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

**목표**: 보안 트래픽 분석 트래픽에서 남용 및 악의적 활동 탐지

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
8. **Vector Search (고급)**: 시맨틱 유사도를 활용한 AI 기반 위협 탐지
   - 임베딩을 사용한 공격 패턴 인식
   - 코사인 거리를 이용한 중복 리포트 탐지
   - 버그 리포트 시맨틱 검색
   - 전통적 방법 + AI 기반 하이브리드 위협 스코어링
   - 프로덕션 준비 통합 패턴

---

### 📝 라이선스

MIT License - 자세한 내용은 저장소 루트 참조

---

### 👤 작성자

작성일: 2026-01-31
업데이트: 2026-02-01
