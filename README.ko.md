# ClickHouse 실습 랩 (HOLs)

빠른 오픈소스 컬럼 지향 데이터베이스 관리 시스템인 ClickHouse를 학습하고 탐구하기 위한 실용적인 실습 과정 모음입니다.

[English](README.md) | **한국어**

## 🎯 목적

이 실습 랩들은 다음과 같은 실무 경험을 제공하도록 설계되었습니다:
- **ClickHouse OSS** (오픈소스 소프트웨어)
- **ClickHouse Cloud** (관리형 서비스)

ClickHouse 기초를 배우는 초보자든, 고급 기능을 탐구하는 숙련된 사용자든, 이 랩들은 실제 시나리오를 통해 기술을 구축할 수 있는 구조화된 단계별 연습을 제공합니다.

## 📁 저장소 구조

```
clickhouse-hols/
├── local/          # 로컬 환경 설정
│   ├── oss-mac-setup/           # macOS용 ClickHouse OSS
│   └── datalake-minio-catalog/  # MinIO를 사용한 로컬 데이터 레이크
├── chc/            # ClickHouse Cloud 통합
│   ├── api/        # API 테스트 및 통합
│   ├── kafka/      # Kafka/Confluent 통합
│   ├── lake/       # 데이터 레이크 통합 (Glue, MinIO)
│   └── s3/         # S3 통합 예제
├── tpcds/          # TPC-DS 벤치마크
└── workload/       # 성능 테스트 워크로드
    ├── sql-lab-delete-benchmark/  # DELETE 연산 벤치마크
    └── sql-lab-gnome-variants/    # 유전체 데이터 워크로드
```

## 📚 사용 가능한 랩

### 🏠 로컬 환경 (`local/`)

#### 1. [local/oss-mac-setup](local/oss-mac-setup/)
**목적:** macOS에서 ClickHouse OSS(오픈소스) 실행을 위한 빠른 설정

Docker를 사용한 macOS 최적화 개발 환경:
- macOS의 `get_mempolicy` 오류를 수정하는 커스텀 seccomp 보안 프로필
- 특정 ClickHouse 버전 또는 최신 버전 지원
- 영구 데이터 저장을 위한 Docker named volumes
- 시작/중지/정리를 위한 간편한 관리 스크립트
- 다양한 접근 인터페이스 (Web UI, HTTP API, TCP)

**빠른 시작:**
```bash
cd local/oss-mac-setup
./set.sh        # 최신 버전으로 설정
./start.sh      # ClickHouse 시작
./client.sh     # CLI 연결
```

---

#### 2. [local/25.6](local/25.6/) - ClickHouse 25.6 신기능
**목적:** ClickHouse 25.6 신기능 학습 및 테스트

테스트 기능:
- CoalescingMergeTree 테이블 엔진
- Time 및 Time64 데이터 타입
- Bech32 인코딩 함수
- lag/lead 윈도우 함수
- 일관된 스냅샷 기능

**빠른 시작:**
```bash
cd local/25.6
./00-setup.sh  # ClickHouse 25.6 배포
./01-coalescingmergetree.sh
./02-time-datatypes.sh
```

---

#### 3. [local/25.7](local/25.7/) - ClickHouse 25.7 신기능
**목적:** ClickHouse 25.7 신기능 학습 및 테스트

테스트 기능:
- SQL UPDATE/DELETE 연산 (최대 1000배 빠름)
- count() 집계 최적화 (20-30% 빠름)
- JOIN 성능 개선 (최대 1.8배 빠름)
- 대량 UPDATE 성능

**빠른 시작:**
```bash
cd local/25.7
./00-setup.sh  # ClickHouse 25.7 배포
./01-sql-update-delete.sh
```

---

#### 4. [local/25.8](local/25.8/) - ClickHouse 25.8 신기능
**목적:** MinIO Data Lake 통합을 통한 ClickHouse 25.8 신기능 학습 및 테스트

테스트 기능:
- **새로운 Parquet Reader** (1.81배 빠름, 99.98% 적은 데이터 스캔)
- **MinIO 통합** (S3 호환 스토리지)
- 컬럼 프루닝 최적화
- 와일드카드를 이용한 다중 파일 쿼리
- 데이터 레이크 기반 이커머스 분석
- Data Lake 개선 (Iceberg, Delta Lake 개념)

**빠른 시작:**
```bash
cd local/25.8
./00-setup.sh              # ClickHouse 25.8 + MinIO + Nessie 배포
./06-minio-integration.sh  # MinIO S3 호환 스토리지 테스트
```

**포함 내용:**
- MinIO 및 Nessie 자동 배포
- 50,000개 샘플 이커머스 주문 데이터
- Parquet 내보내기/가져오기 테스트
- 일일 매출 분석
- 고객 세분화 분석

---

#### 5. [local/25.10](local/25.10/) - ClickHouse 25.10 신기능
**목적:** ClickHouse 25.10 신기능 학습 및 테스트

테스트 기능:
- 벡터 검색을 위한 QBit 데이터 타입
- 음수 LIMIT/OFFSET
- JOIN 개선
- LIMIT BY ALL
- 자동 통계 수집

---

#### 6. [local/datalake-minio-catalog](local/datalake-minio-catalog/)
**목적:** MinIO와 다양한 카탈로그 옵션을 갖춘 로컬 데이터 레이크 환경

Docker로 로컬에서 실행되는 완전한 데이터 레이크 스택:
- **MinIO**: 데이터 레이크 저장소용 S3 호환 객체 스토리지
- **다양한 카탈로그 옵션**: Nessie (Git 스타일), Hive Metastore, Iceberg REST
- **Apache Iceberg**: ACID 보장을 제공하는 현대적인 테이블 포맷
- **Jupyter Notebooks**: 사전 구성된 예제가 있는 대화형 데이터 탐색
- **샘플 데이터**: 사전 로드된 JSON 및 Parquet 데이터셋

**빠른 시작:**
```bash
cd local/datalake-minio-catalog
./setup.sh --configure  # 카탈로그 유형 선택
./setup.sh --start      # 모든 서비스 시작
# Jupyter: http://localhost:8888
# MinIO Console: http://localhost:9001
```

---

### ☁️ ClickHouse Cloud 통합 (`chc/`)

#### API 테스트

##### [chc/api/chc-api-test](chc/api/chc-api-test/)
**목적:** ClickHouse Cloud API 테스트 및 통합 예제

ClickHouse Cloud용 포괄적인 API 테스트 스위트:
- Python을 사용한 REST API 예제
- 인증 및 연결 처리
- 쿼리 실행 및 결과 처리
- 성능 테스트 및 모니터링

**빠른 시작:**
```bash
cd chc/api/chc-api-test
cp .env.example .env
# .env에 CHC 자격증명 입력
python3 apitest.py
```

---

#### Kafka/Confluent 통합

##### [chc/kafka/terraform-confluent-aws](chc/kafka/terraform-confluent-aws/)
**목적:** ClickHouse Cloud와 Confluent Cloud Kafka 통합

##### [chc/kafka/terraform-confluent-aws-nlb-ssl](chc/kafka/terraform-confluent-aws-nlb-ssl/)
**목적:** AWS NLB를 사용한 SSL/TLS 기반 보안 Kafka 연결

##### [chc/kafka/terraform-confluent-aws-connect-sink](chc/kafka/terraform-confluent-aws-connect-sink/)
**목적:** ClickHouse Cloud로 데이터 스트리밍을 위한 Kafka Connect Sink 커넥터

---

#### 데이터 레이크 통합

##### [chc/lake/terraform-minio-on-aws](chc/lake/terraform-minio-on-aws/)
**목적:** Terraform으로 AWS EC2에 단일 노드 MinIO 서버 배포

AWS 인프라의 프로덕션 수준 MinIO 배포:
- 자동 배포를 지원하는 Ubuntu 22.04 LTS
- 구성 가능한 인스턴스 유형 및 EBS 볼륨 크기
- 보안 그룹 및 선택적 Elastic IP
- 상태 모니터링 및 설치 로그

**빠른 시작:**
```bash
cd chc/lake/terraform-minio-on-aws
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
./deploy.sh   # 자동 배포
```

---

##### [chc/lake/terraform-glue-s3-chc-integration](chc/lake/terraform-glue-s3-chc-integration/)
**목적:** Apache Iceberg를 사용한 ClickHouse Cloud와 AWS Glue Catalog 통합

**⚠️ 중요:** 이 랩은 ClickHouse Cloud 25.8의 현재 DataLakeCatalog 기능과 알려진 제한사항을 보여줍니다.

ClickHouse Cloud + AWS Glue + Iceberg 통합을 위한 자동화된 인프라:
- **S3 Storage**: Apache Iceberg 데이터용 암호화된 버킷
- **AWS Glue Database**: Iceberg 테이블용 메타데이터 카탈로그
- **PyIceberg**: Glue 카탈로그 지원을 통한 적절한 Iceberg v2 테이블 생성
- **샘플 데이터**: 파티셔닝이 적용된 사전 구성 `sales_orders` 테이블
- **원클릭 배포**: `deploy.sh`를 통한 자동화된 설정

**현재 제한사항 (ClickHouse Cloud 25.8):**
- ❌ DataLakeCatalog에서 `glue_database` 매개변수 미지원
- ❌ IAM 역할 기반 인증 미지원 (액세스 키 필수)
- ✅ DataLakeCatalog는 리전의 모든 Glue 데이터베이스를 자동 검색

**빠른 시작:**
```bash
cd chc/lake/terraform-glue-s3-chc-integration
./deploy.sh  # AWS 자격증명 입력 후 모두 배포
```

**기술 아키텍처:**
```
ClickHouse Cloud (DataLakeCatalog)
    ↓ (AWS 자격증명)
AWS Glue Catalog (clickhouse_iceberg_db)
    ↓ (테이블 메타데이터)
S3 Bucket (Apache Iceberg 데이터)
    ↓ (Parquet 파일)
샘플 테이블: sales_orders (10 레코드, 날짜별 파티션)
```

---

#### S3 통합

##### [chc/s3/terraform-chc-secures3-aws](chc/s3/terraform-chc-secures3-aws/)
**목적:** IAM 역할 기반 인증을 사용한 보안 ClickHouse Cloud S3 통합

ClickHouse Cloud를 위한 프로덕션 수준 S3 액세스:
- IAM 역할 기반 인증 (액세스 키 불필요)
- SELECT, INSERT, export를 위한 읽기 및 쓰기 권한
- S3 Table Engine 지원
- 다양한 포맷 지원 (Parquet, CSV, JSON)
- 암호화, 버전 관리, 보안

**빠른 시작:**
```bash
cd chc/s3/terraform-chc-secures3-aws
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
./deploy.sh   # 대화형 배포
```

---

##### [chc/s3/terraform-chc-secures3-aws-direct-attach](chc/s3/terraform-chc-secures3-aws-direct-attach/)
**목적:** ClickHouse Cloud S3 액세스를 위한 직접 IAM 정책 연결

ClickHouse Cloud IAM 역할에 정책을 직접 연결하는 대안적 접근 방식.

---

### 📊 벤치마크 & 워크로드

#### [tpcds/](tpcds/)
**목적:** ClickHouse 성능 테스트를 위한 TPC-DS 벤치마크

산업 표준 의사결정 지원 벤치마크:
- 24개 테이블로 구성된 완전한 TPC-DS 스키마
- 99개의 분석 쿼리 템플릿
- 자동화된 데이터 생성 및 로딩
- 순차 및 병렬 쿼리 실행
- 성능 메트릭 및 분석

**빠른 시작:**
```bash
cd tpcds
./00-set.sh --interactive
./01-create-schema.sh
./03-load-data.sh --source s3
./04-run-queries-sequential.sh
```

---

### 🔬 성능 테스트 (`workload/`)

#### [workload/sql-lab-delete-benchmark](workload/sql-lab-delete-benchmark/)
**목적:** DELETE 연산 성능 벤치마크

포괄적인 DELETE 연산 테스트:
- 다양한 DELETE 패턴 및 시나리오
- 성능 메트릭 수집
- 다양한 삭제 전략 비교
- 쿼리 성능에 미치는 영향 분석

**빠른 시작:**
```bash
cd workload/sql-lab-delete-benchmark
# SQL 스크립트를 순서대로 실행: 01부터 05까지
```

---

#### [workload/sql-lab-gnome-variants](workload/sql-lab-gnome-variants/)
**목적:** 유전체 데이터 워크로드 테스트

실제 유전체 데이터 처리 시나리오:
- 유전체 변이 분석
- 대규모 유전체 데이터 처리
- 과학 워크로드를 위한 성능 최적화

**빠른 시작:**
```bash
cd workload/sql-lab-gnome-variants
# SQL 스크립트를 순서대로 실행: 01부터 05까지
```

---

## 🛠 사전 요구사항

### 일반 요구사항
- macOS, Linux, 또는 WSL2가 있는 Windows
- Docker 및 Docker Compose
- 기본적인 커맨드라인 지식

### 특정 요구사항
- **로컬 랩**: Docker Desktop, Python 3.8+
- **클라우드 랩**: Terraform, AWS CLI, AWS 계정
- **ClickHouse Cloud 랩**: ClickHouse Cloud 계정
- **벤치마크**: ClickHouse 클라이언트, 충분한 디스크 공간

## 🚀 시작하기

1. **이 저장소를 클론합니다:**
   ```bash
   git clone https://github.com/yourusername/clickhouse-hols.git
   cd clickhouse-hols
   ```

2. **학습 목표에 따라 위 목록에서 랩을 선택합니다**

3. **각 랩 디렉토리의 빠른 시작 지침을 따릅니다**

4. **포괄적인 문서를 위해 각 랩의 상세 README를 읽습니다**

## 📖 학습 경로

### 초보자용
1. **[local/oss-mac-setup](local/oss-mac-setup/)** - 로컬에서 ClickHouse 기초 학습
2. **[local/datalake-minio-catalog](local/datalake-minio-catalog/)** - 데이터 레이크 개념 탐구
3. **[tpcds](tpcds/)** - 성능 및 벤치마킹 이해

### 클라우드 사용자용
1. **[chc/api/chc-api-test](chc/api/chc-api-test/)** - ClickHouse Cloud API 학습
2. **[chc/s3/terraform-chc-secures3-aws](chc/s3/terraform-chc-secures3-aws/)** - 보안 S3 통합
3. **[chc/lake/terraform-glue-s3-chc-integration](chc/lake/terraform-glue-s3-chc-integration/)** - AWS Glue 통합

### 고급 사용자용
1. **[chc/kafka](chc/kafka/)** - 실시간 데이터 스트리밍
2. **[workload](workload/)** - 성능 테스트 및 최적화

## 🌐 추가 리소스

ClickHouse에 대한 더 많은 정보와 한국어 리소스는 [clickhouse.kr](https://clickhouse.kr)에서 확인하실 수 있습니다.

## 🤝 기여하기

기여를 환영합니다! 이슈나 풀 리퀘스트를 자유롭게 제출해 주세요.

## 📝 라이선스

MIT License - 특정 라이선스 정보는 각 랩 디렉토리를 참조하세요.
