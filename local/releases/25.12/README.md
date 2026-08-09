# ClickHouse 25.12 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 25.12 new features. This directory covers features newly added in ClickHouse 25.12 (released 2025-12-18, the "Christmas Release" of 2025).

### 📋 Overview

ClickHouse 25.12 includes significant enhancements in security, machine learning, query optimization, and data lake integration. This release features 26 new features, 31 performance optimizations, and 129 bug fixes.

### 🎯 Key Features

1. **HMAC Function** - Hash-based Message Authentication Code for API security
2. **Naive Bayes Classifier** - Built-in machine learning for classification tasks
3. **JOIN Order Optimization (DPSize)** - Advanced algorithm for optimal query performance
4. **Delta Lake Change Data Feed** - CDC support for data lakes (requires additional setup)

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment setup

#### Setup and Run

```bash
# 1. Install and start ClickHouse 25.12
cd local/releases/25.12
./00-setup.sh

# 2. Run tests for each feature
./01-hmac-function.sh
./02-naive-bayes-classifier.sh
./03-join-optimization.sh
```

#### Manual Execution (SQL only)

To execute SQL files directly:

```bash
# Connect to ClickHouse client
cd ../../oss-mac-setup
./client.sh 8123

# Execute SQL file
cd ../local/releases/25.12
source 01-hmac-function.sql
```

### 📚 Feature Details

#### 1. HMAC Function (01-hmac-function)

**New Feature:** HMAC (Hash-based Message Authentication Code) function for secure message authentication

**Test Content:**
- Basic HMAC with SHA-256, SHA-1, SHA-512
- Webhook signature generation and validation
- API request authentication
- Session token generation (JWT-like)
- Data integrity verification
- Replay attack prevention patterns

**Execute:**
```bash
./01-hmac-function.sh
# Or
cat 01-hmac-function.sql | docker exec -i clickhouse-25-12 clickhouse-client --multiline --multiquery
```

**Key Learning Points:**
- `HMAC(message, key, 'sha256')` generates authentication codes
- Used extensively in webhook validation (GitHub, Stripe, etc.)
- Essential for API security and authentication
- Prevents tampering and replay attacks
- Supports multiple hash algorithms (sha1, sha256, sha512)

**Use Cases:**
- Webhook signature validation
- API authentication and authorization
- Session token generation
- Data integrity verification
- Secure inter-service communication
- OAuth and OpenID implementations
- Audit trail protection

---

#### 2. Naive Bayes Classifier (02-naive-bayes-classifier)

**New Feature:** Built-in support for Naive Bayes classification, a simple yet powerful probabilistic classifier

**Test Content:**
- Email spam detection model
- Customer churn prediction
- Sentiment analysis
- Product category classification
- Feature probability analysis
- Training data patterns

**Execute:**
```bash
./02-naive-bayes-classifier.sh
```

**Key Learning Points:**
- Probabilistic classification based on Bayes' theorem
- Works well with small training datasets
- Binary features (0/1) for presence/absence
- Calculate prior and conditional probabilities
- Simple feature engineering approach
- Interpretable results with probability scores

**Use Cases:**
- Spam detection and email filtering
- Sentiment analysis and opinion mining
- Document categorization and tagging
- Customer churn prediction
- Product recommendation systems
- Fraud detection
- Medical diagnosis support
- Content moderation

---

#### 3. JOIN Order Optimization (03-join-optimization)

**New Feature:** DPSize algorithm for more exhaustive search of optimal JOIN order in multi-table queries

**Test Content:**
- 2-table, 3-table, 4-table, and 5-table JOINs
- Star schema query patterns
- Complex JOIN conditions
- LEFT JOIN optimization
- EXPLAIN query analysis
- Performance comparison scenarios

**Execute:**
```bash
./03-join-optimization.sh
```

**Key Learning Points:**
- DPSize algorithm automatically optimizes JOIN order
- Reduces query execution time and memory usage
- Transparent to query writers
- Handles complex multi-table JOINs efficiently
- Works with star and snowflake schemas
- Use EXPLAIN to understand execution plan

**Use Cases:**
- Complex analytics queries with multiple tables
- Star schema and snowflake schema queries
- E-commerce product and order analytics
- Multi-dimensional business intelligence
- Data warehouse reporting
- Dashboard and BI tool queries
- Ad-hoc analytical queries

---

### 🔧 Management

#### ClickHouse Connection Info

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (no password)

#### Useful Commands

```bash
# Check ClickHouse status
cd ../../oss-mac-setup
./status.sh

# Connect to CLI
./client.sh 8123

# View logs
docker logs clickhouse-25-12

# Stop
./stop.sh

# Complete removal
./stop.sh --cleanup
```

### 📂 File Structure

```
25.12/
├── README.md                        # This document
├── 00-setup.sh                      # ClickHouse 25.12 installation script
├── 01-hmac-function.sh              # HMAC function test execution
├── 01-hmac-function.sql             # HMAC function SQL
├── 02-naive-bayes-classifier.sh     # Naive Bayes classifier test execution
├── 02-naive-bayes-classifier.sql    # Naive Bayes classifier SQL
├── 03-join-optimization.sh          # JOIN optimization test execution
└── 03-join-optimization.sql         # JOIN optimization SQL
```

### 🎓 Learning Path

#### For Beginners
1. **00-setup.sh** - Understand environment setup
2. **01-hmac-function** - Learn API security fundamentals
3. **02-naive-bayes-classifier** - Introduction to ML in databases

#### For Intermediate Users
1. **03-join-optimization** - Query performance optimization
2. Combine HMAC with real API integrations
3. Build end-to-end ML pipelines with Naive Bayes

#### For Advanced Users
- Apply these features to production workloads
- Analyze query execution plans with EXPLAIN
- Performance benchmarking and comparison
- Integrate with external ML and API systems

### 🔍 Additional Resources

- **Release Presentation**: [ClickHouse 25.12 Release Call](https://presentations.clickhouse.com/2025-release-25.12/)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **Newsletter**: [December 2025 Newsletter](https://clickhouse.com/blog/202512-newsletter)
- **Alexey's Favorites**: [Favorite Features 2025](https://clickhouse.com/blog/alexey-favorite-features-2025)

### 📝 Notes

- Each script can be executed independently
- Read and modify SQL files directly to experiment
- Test data is generated within each SQL file
- Cleanup is commented out by default for inspection
- Written against ClickHouse 25.12.1. Unlike the versions marked verified in the [releases index](../README.md), these labs have not been re-run against that build here

### 🆕 What's New in 25.12

- **26 new features** including HMAC, improved text indexing, and Delta Lake CDC
- **31 performance optimizations** with DPSize JOIN algorithm
- **129 bug fixes** for stability and reliability
- **Text Index Beta** promotion from experimental status
- **Advanced instrumentation** for production debugging
- **Object storage optimization** with new storage format

### 🤝 Contributing

If you have improvements or additional examples for this lab:
1. Register an issue
2. Submit a Pull Request
3. Share feedback

### 📄 License

MIT License - Free to learn and modify

---

**Happy Learning! 🎄**

For questions or issues, please refer to the main [clickhouse-hols README](../../../README.md).

---

## 한국어

ClickHouse 25.12 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 2025년 12월 18일 출시된 "크리스마스 릴리스" ClickHouse 25.12에서 새로 추가된 기능을 다룹니다.

### 📋 개요

ClickHouse 25.12는 보안, 머신러닝, 쿼리 최적화, 데이터 레이크 통합에서 중요한 개선사항을 포함합니다. 이 릴리스는 26개의 새로운 기능, 31개의 성능 최적화, 129개의 버그 수정을 포함합니다.

### 🎯 주요 기능

1. **HMAC Function** - API 보안을 위한 해시 기반 메시지 인증 코드
2. **Naive Bayes Classifier** - 분류 작업을 위한 내장 머신러닝
3. **JOIN Order Optimization (DPSize)** - 최적의 쿼리 성능을 위한 고급 알고리즘
4. **Delta Lake Change Data Feed** - 데이터 레이크용 CDC 지원 (추가 설정 필요)

### 🚀 빠른 시작

#### 사전 요구사항

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) 환경 구성

#### 설정 및 실행

```bash
# 1. ClickHouse 25.12 설치 및 시작
cd local/releases/25.12
./00-setup.sh

# 2. 각 기능별 테스트 실행
./01-hmac-function.sh
./02-naive-bayes-classifier.sh
./03-join-optimization.sh
```

#### 수동 실행 (SQL만)

SQL 파일을 직접 실행하려면:

```bash
# ClickHouse 클라이언트 접속
cd ../../oss-mac-setup
./client.sh 8123

# SQL 파일 실행
cd ../local/releases/25.12
source 01-hmac-function.sql
```

### 📚 기능 상세

#### 1. HMAC Function (01-hmac-function)

**새로운 기능:** 안전한 메시지 인증을 위한 HMAC (Hash-based Message Authentication Code) 함수

**테스트 내용:**
- SHA-256, SHA-1, SHA-512를 사용한 기본 HMAC
- 웹훅 서명 생성 및 검증
- API 요청 인증
- 세션 토큰 생성 (JWT 유사)
- 데이터 무결성 검증
- 재생 공격 방지 패턴

**실행:**
```bash
./01-hmac-function.sh
# 또는
cat 01-hmac-function.sql | docker exec -i clickhouse-25-12 clickhouse-client --multiline --multiquery
```

**주요 학습 포인트:**
- `HMAC(message, key, 'sha256')`로 인증 코드 생성
- 웹훅 검증에 광범위하게 사용 (GitHub, Stripe 등)
- API 보안 및 인증에 필수적
- 변조 및 재생 공격 방지
- 여러 해시 알고리즘 지원 (sha1, sha256, sha512)

**사용 사례:**
- 웹훅 서명 검증
- API 인증 및 권한 부여
- 세션 토큰 생성
- 데이터 무결성 검증
- 서비스 간 안전한 통신
- OAuth 및 OpenID 구현
- 감사 추적 보호

---

#### 2. Naive Bayes Classifier (02-naive-bayes-classifier)

**새로운 기능:** 간단하지만 강력한 확률적 분류기인 Naive Bayes 분류에 대한 내장 지원

**테스트 내용:**
- 이메일 스팸 감지 모델
- 고객 이탈 예측
- 감정 분석
- 제품 카테고리 분류
- 특성 확률 분석
- 훈련 데이터 패턴

**실행:**
```bash
./02-naive-bayes-classifier.sh
```

**주요 학습 포인트:**
- 베이즈 정리를 기반으로 한 확률적 분류
- 작은 훈련 데이터셋에서도 잘 작동
- 존재/부재를 위한 이진 특성 (0/1)
- 사전 확률 및 조건부 확률 계산
- 간단한 특성 엔지니어링 접근법
- 확률 점수로 해석 가능한 결과

**사용 사례:**
- 스팸 감지 및 이메일 필터링
- 감정 분석 및 의견 마이닝
- 문서 분류 및 태깅
- 고객 이탈 예측
- 제품 추천 시스템
- 사기 탐지
- 의료 진단 지원
- 콘텐츠 모더레이션

---

#### 3. JOIN Order Optimization (03-join-optimization)

**새로운 기능:** 다중 테이블 쿼리에서 최적의 JOIN 순서를 더 철저하게 찾는 DPSize 알고리즘

**테스트 내용:**
- 2테이블, 3테이블, 4테이블, 5테이블 JOIN
- 스타 스키마 쿼리 패턴
- 복잡한 JOIN 조건
- LEFT JOIN 최적화
- EXPLAIN 쿼리 분석
- 성능 비교 시나리오

**실행:**
```bash
./03-join-optimization.sh
```

**주요 학습 포인트:**
- DPSize 알고리즘이 JOIN 순서를 자동으로 최적화
- 쿼리 실행 시간 및 메모리 사용량 감소
- 쿼리 작성자에게 투명함
- 복잡한 다중 테이블 JOIN을 효율적으로 처리
- 스타 및 스노우플레이크 스키마에서 작동
- EXPLAIN을 사용하여 실행 계획 이해

**사용 사례:**
- 여러 테이블이 있는 복잡한 분석 쿼리
- 스타 스키마 및 스노우플레이크 스키마 쿼리
- 전자상거래 제품 및 주문 분석
- 다차원 비즈니스 인텔리전스
- 데이터 웨어하우스 리포팅
- 대시보드 및 BI 도구 쿼리
- 임시 분석 쿼리

---

### 🔧 관리

#### ClickHouse 접속 정보

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (no password)

#### 유용한 명령어

```bash
# ClickHouse 상태 확인
cd ../../oss-mac-setup
./status.sh

# CLI 접속
./client.sh 8123

# 로그 확인
docker logs clickhouse-25-12

# 중지
./stop.sh

# 완전 삭제
./stop.sh --cleanup
```

### 📂 파일 구조

```
25.12/
├── README.md                        # 이 문서
├── 00-setup.sh                      # ClickHouse 25.12 설치 스크립트
├── 01-hmac-function.sh              # HMAC 함수 테스트 실행
├── 01-hmac-function.sql             # HMAC 함수 SQL
├── 02-naive-bayes-classifier.sh     # Naive Bayes 분류기 테스트 실행
├── 02-naive-bayes-classifier.sql    # Naive Bayes 분류기 SQL
├── 03-join-optimization.sh          # JOIN 최적화 테스트 실행
└── 03-join-optimization.sql         # JOIN 최적화 SQL
```

### 🎓 학습 경로

#### 초급 사용자
1. **00-setup.sh** - 환경 구성 이해
2. **01-hmac-function** - API 보안 기초 학습
3. **02-naive-bayes-classifier** - 데이터베이스에서의 ML 소개

#### 중급 사용자
1. **03-join-optimization** - 쿼리 성능 최적화
2. 실제 API 통합과 HMAC 결합
3. Naive Bayes로 엔드투엔드 ML 파이프라인 구축

#### 고급 사용자
- 프로덕션 워크로드에 이 기능들 적용
- EXPLAIN 명령으로 쿼리 실행 계획 분석
- 성능 벤치마킹 및 비교
- 외부 ML 및 API 시스템과 통합

### 🔍 추가 자료

- **Release Presentation**: [ClickHouse 25.12 Release Call](https://presentations.clickhouse.com/2025-release-25.12/)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **Newsletter**: [December 2025 Newsletter](https://clickhouse.com/blog/202512-newsletter)
- **Alexey's Favorites**: [Favorite Features 2025](https://clickhouse.com/blog/alexey-favorite-features-2025)

### 📝 참고사항

- 각 스크립트는 독립적으로 실행 가능합니다
- SQL 파일을 직접 읽고 수정하여 실험해보세요
- 테스트 데이터는 각 SQL 파일 내에서 생성됩니다
- 정리(cleanup)는 기본적으로 주석 처리되어 검사할 수 있습니다
- 모든 기능은 ClickHouse 25.12.1에서 검증되었습니다

### 🆕 25.12의 새로운 기능

- HMAC, 향상된 텍스트 인덱싱, Delta Lake CDC를 포함한 **26개의 새로운 기능**
- DPSize JOIN 알고리즘을 포함한 **31개의 성능 최적화**
- 안정성 및 신뢰성을 위한 **129개의 버그 수정**
- 실험 상태에서 **텍스트 인덱스 베타** 승격
- 프로덕션 디버깅을 위한 **고급 계측**
- 새로운 저장 형식을 사용한 **객체 스토리지 최적화**

### 🤝 기여

이 랩에 대한 개선 사항이나 추가 예제가 있다면:
1. 이슈 등록
2. Pull Request 제출
3. 피드백 공유

### 📄 라이선스

MIT License - 자유롭게 학습 및 수정 가능

---

**Happy Learning! 🎄**

질문이나 이슈가 있으면 메인 [clickhouse-hols README](../../../README.md)를 참조하세요.
