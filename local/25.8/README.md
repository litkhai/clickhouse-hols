# ClickHouse 25.8 New Features Lab

ClickHouse 25.8 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 ClickHouse 25.8에서 새롭게 추가된 기능들을 실습하고 반복 학습할 수 있도록 구성되어 있으며, **MinIO 기반 Data Lake 환경이 통합**되어 있습니다.

## 📋 Overview

ClickHouse 25.8은 새로운 Parquet Reader (1.81배 빠른 성능), Data Lake 통합 강화, Hive-style 파티셔닝, S3 임시 데이터 저장, 그리고 향상된 UNION ALL 기능을 포함합니다.

### 🎯 Key Features

1. **New Parquet Reader** - 1.81배 빠른 성능, 99.98% 적은 데이터 스캔
2. **MinIO Integration** - S3 호환 스토리지를 통한 Data Lake 구현
3. **Data Lake Enhancements** - Iceberg CREATE/DROP, Delta Lake 쓰기, 시간 여행
4. **Hive-Style Partitioning** - partition_strategy 파라미터, 디렉토리 기반 파티셔닝
5. **Temporary Data on S3** - 로컬 디스크 대신 S3를 임시 데이터 저장소로 활용
6. **Enhanced UNION ALL** - _table 가상 컬럼 지원

## 🚀 Quick Start

### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../oss-mac-setup/) 환경 구성
- [datalake-minio-catalog](../datalake-minio-catalog/) 자동 배포 (setup 스크립트가 처리)

### Setup and Run

```bash
# 1. ClickHouse 25.8 + MinIO Data Lake 설치 및 시작
cd local/25.8
./00-setup.sh   # ClickHouse 25.8, MinIO, Nessie를 모두 배포합니다

# 2. 각 기능별 테스트 실행
./01-new-parquet-reader.sh      # 로컬 파일 기반 Parquet Reader 테스트
./06-minio-integration.sh       # MinIO S3 통합 테스트 (★ 추천)
./02-hive-partitioning.sh
./03-temp-data-s3.sh
./04-union-all-table.sh
./05-data-lake-features.sh
```

### What Gets Deployed

`./00-setup.sh` 실행 시 다음이 자동으로 배포됩니다:

1. **MinIO** (포트 19000, 19001)
   - S3 호환 객체 스토리지
   - 웹 콘솔: http://localhost:19001
   - 자격증명: admin / password123

2. **Nessie** (포트 19120)
   - Git-like 데이터 카탈로그
   - REST API: http://localhost:19120

3. **ClickHouse 25.8** (포트 2508, 25081)
   - 웹 UI: http://localhost:2508/play
   - TCP 포트: 25081

### Manual Execution (SQL only)

SQL 파일을 직접 실행하려면:

```bash
# ClickHouse 클라이언트 접속
cd ../oss-mac-setup
./client.sh 2508

# SQL 파일 실행
cd ../25.8
source 01-new-parquet-reader.sql
```

## 📚 Feature Details

### 0. MinIO Integration (06-minio-integration) ★ 추천

**새로운 기능:** ClickHouse 25.8 + MinIO S3 호환 스토리지를 통한 실전 Data Lake 구현

**테스트 내용:**
- 50,000개 이커머스 주문 데이터 생성
- MinIO로 Parquet 형식 데이터 내보내기
- S3 함수로 MinIO에서 데이터 읽기
- 컬럼 프루닝 최적화 (99.98% 적은 데이터 스캔)
- 국가별 파일 분할 및 와일드카드 쿼리
- 일일 매출 분석 (14일)
- 제품 카테고리 성능 분석
- 고객 세분화 분석 (VIP, Premium)

**실행:**
```bash
./06-minio-integration.sh
```

**주요 학습 포인트:**
- S3 호환 스토리지 (MinIO)와 ClickHouse 통합
- `s3()` 함수를 통한 데이터 읽기/쓰기
- 새로운 Parquet Reader의 실제 성능 (1.81배 빠름)
- 컬럼 프루닝을 통한 최소 데이터 스캔
- 와일드카드를 사용한 다중 파일 쿼리
- 로컬 개발 환경에서의 Data Lake 구현

**실무 활용:**
- 로컬 Data Lake 개발 및 테스트
- S3 마이그레이션 전 로컬 검증
- 비용 효율적인 데이터 저장소
- 데이터 분석 파이프라인 프로토타입
- 이커머스 매출 분석 대시보드
- 고객 행동 분석 및 세분화

**데이터셋:**
- 50,000개 주문 (8개 국가, 5,000명 고객)
- 8개 제품 카테고리
- 4가지 주문 상태
- 38M+ 총 매출

### 1. New Parquet Reader (01-new-parquet-reader)

**새로운 기능:** 1.81배 빠른 성능과 99.98% 적은 데이터 스캔을 제공하는 새로운 Parquet Reader

**테스트 내용:**
- E-commerce 이벤트 데이터셋 생성 (100,000 행)
- Parquet 파일 내보내기
- 새로운 Parquet Reader로 읽기
- Column pruning 최적화 (필요한 컬럼만 읽기)
- 복잡한 분석 쿼리 성능
- 변환율 퍼널 분석
- 사용자 행동 분석
- 디바이스 및 채널 성능 분석
- 지리적 분석
- 제품 카테고리 성능
- 시간대별 활동 패턴

**실행:**
```bash
./01-new-parquet-reader.sh
# 또는
cat 01-new-parquet-reader.sql | docker exec -i clickhouse-25-8 clickhouse-client --multiline --multiquery
```

**주요 학습 포인트:**
- 새로운 Parquet Reader는 기존 대비 1.81배 빠른 성능
- Column pruning으로 99.98% 적은 데이터 스캔
- 필요한 컬럼만 읽어 메모리 효율성 향상
- Parquet v2 포맷 완전 지원
- 대규모 Parquet 파일의 메모리 사용량 감소
- 중첩된 구조체 및 배열 지원 개선

**실무 활용:**
- Data Lake 쿼리 가속화
- S3/GCS/Azure의 Parquet 파일 직접 분석
- ETL 파이프라인 최적화
- 대용량 로그 파일 분석
- 데이터 웨어하우스 연합 쿼리
- 기계 학습 특성 엔지니어링
- 실시간 분석 대시보드
- 비용 효율적인 cold storage 쿼리

**성능 비교:**
| 작업 | 이전 버전 | ClickHouse 25.8 | 개선 |
|------|----------|-----------------|------|
| 전체 Parquet 스캔 | 기준 | 1.81배 빠름 | 81% 향상 |
| 선택적 컬럼 읽기 | 많은 데이터 스캔 | 99.98% 적은 스캔 | 거의 0.02%만 스캔 |
| 메모리 사용량 | 높음 | 대폭 감소 | 효율성 향상 |

---

### 2. Hive-Style Partitioning (02-hive-partitioning)

**새로운 기능:** partition_strategy 파라미터로 Hive-style 디렉토리 구조 지원

**테스트 내용:**
- 판매 트랜잭션 데이터 생성 (100,000 행)
- Hive-style 파티셔닝으로 데이터 내보내기 (year=YYYY/month=MM/)
- 파티션된 데이터 읽기
- 파티션 프루닝 (특정 파티션만 스캔)
- 지역별 판매 분석
- 제품 카테고리 성능
- 매장 성능 순위
- 결제 방법 분석
- 일별 판매 트렌드
- 고가치 고객 분석
- 파티션 효율성 비교
- 월별 성장률 분석

**실행:**
```bash
./02-hive-partitioning.sh
```

**주요 학습 포인트:**
- Hive partitioning: key=value 디렉토리 구조
- 파티션 프루닝으로 불필요한 디렉토리 스캔 회피
- Spark, Presto, Athena와 호환되는 표준 방식
- 다단계 파티셔닝 지원 (year/month/day)
- 자동 파티션 컬럼 감지
- 스키마 변경 없이 파티션 추가 가능
- 데이터 조직화 및 쿼리 최적화

**실무 활용:**
- Data Lake 조직화 (S3, HDFS, GCS)
- 다중 엔진 데이터 공유 (Spark + ClickHouse)
- 시계열 데이터 관리
- 지리적 데이터 파티셔닝
- 멀티 테넌트 데이터 격리
- ETL 파이프라인 최적화
- 규정 준수 데이터 보관
- 비용 효율적인 데이터 아카이빙

**파티션 패턴 예시:**
```
/data/year=2024/month=12/day=01/
/data/country=US/region=West/
/data/tenant_id=123/date=2024-12-01/
/data/event_type=purchase/hour=14/
```

**성능 이점:**
- **I/O 감소:** 관련 없는 파티션 건너뛰기
- **쿼리 속도:** 필요한 데이터만 읽기
- **조직화:** 직관적인 디렉토리 구조
- **확장성:** 페타바이트급 데이터 효율적 처리

---

### 3. Temporary Data on S3 (03-temp-data-s3)

**새로운 기능:** 로컬 디스크 대신 S3를 임시 데이터 저장소로 사용 가능

**테스트 내용:**
- 임시 데이터 개념 이해
- S3 임시 데이터 구성 방법
- 대규모 데이터셋 생성 (500,000 이벤트)
- 대규모 JOIN 연산 (임시 저장소 사용)
- 높은 카디널리티 GROUP BY 집계
- 대규모 DISTINCT 연산
- 복잡한 윈도우 함수
- 대규모 ORDER BY 정렬
- 세션 분석 (복잡한 쿼리)
- 제품 성능 분석 (다중 JOIN)
- 사용자 코호트 분석

**실행:**
```bash
./03-temp-data-s3.sh
```

**주요 학습 포인트:**
- 임시 데이터는 쿼리 실행 중 생성됨 (JOIN, GROUP BY, ORDER BY 등)
- 25.8 이전: 로컬 디스크만 사용, 공간 제약
- 25.8 이후: S3 사용 가능, 무제한 용량
- 메모리 초과 시 자동 spillover
- 쿼리에 투명하게 동작
- S3에 최적화된 I/O 패턴
- 임시 데이터 자동 정리

**임시 데이터가 필요한 작업:**
1. 대규모 JOIN (해시 테이블)
2. 높은 카디널리티 GROUP BY
3. 대용량 데이터 정렬 (ORDER BY)
4. 윈도우 함수
5. DISTINCT 연산
6. 메모리 제한 초과 집계

**설정 예시:**
```xml
<storage_configuration>
    <disks>
        <s3_disk>
            <type>s3</type>
            <endpoint>https://bucket.s3.amazonaws.com/temp/</endpoint>
        </s3_disk>
    </disks>
</storage_configuration>
```

```sql
SET max_bytes_before_external_group_by = 10000000000;  -- 10GB
SET max_bytes_before_external_sort = 10000000000;       -- 10GB
SET temporary_data_policy = 'temp_policy';
```

**실무 활용:**
- 대규모 데이터셋 애드혹 분석
- 복잡한 다중 테이블 JOIN
- 높은 카디널리티 집계
- 데이터 탐색 및 발견
- 기계 학습 특성 엔지니어링
- 전체 데이터셋 품질 검사
- 로컬 디스크 제약 극복
- 비용 효율적인 대용량 처리

**이점:**
- 로컬 디스크 한계 초과 가능
- 더 나은 리소스 활용
- 비용 효율성 (S3가 로컬 SSD보다 저렴)
- 수동 임시 데이터 관리 불필요
- 쿼리 성공률 향상

---

### 4. Enhanced UNION ALL with _table Virtual Column (04-union-all-table)

**새로운 기능:** UNION ALL에서 _table 가상 컬럼으로 소스 테이블 식별 가능

**테스트 내용:**
- 다중 지역 판매 테이블 생성 (US, EU, Asia, LATAM)
- 지역별 판매 데이터 삽입
- UNION ALL과 _table 컬럼 사용
- 글로벌 판매 분석
- 지역별 일별 판매 트렌드
- 지역별 제품 성능
- 고객 분포 분석
- 소스 테이블별 필터링
- 지역 간 성능 비교
- 주간 트렌드 분석
- 데이터 계보 추적
- 다중 통화 집계

**실행:**
```bash
./04-union-all-table.sh
```

**주요 학습 포인트:**
- _table 가상 컬럼이 UNION ALL 결과에서 소스 테이블 식별
- WHERE, GROUP BY, ORDER BY에서 _table 사용 가능
- 데이터 계보 추적 가능
- 소스별 집계 및 필터링
- 다중 테이블 쿼리 감사 추적
- 최소한의 오버헤드

**구문 예시:**
```sql
SELECT *, 'table1' AS _table FROM table1
UNION ALL
SELECT *, 'table2' AS _table FROM table2

-- _table로 필터링
WHERE _table = 'table1'

-- _table로 그룹화
GROUP BY _table

-- _table로 정렬
ORDER BY _table, revenue DESC
```

**실무 활용:**
- 다중 지역 데이터 통합
- 연도별 테이블 union (히스토리컬 데이터)
- 멀티 테넌트 데이터 쿼리
- 연합 쿼리 결과
- 데이터 마이그레이션 검증
- 샤드 간 분석
- 감사 및 규정 준수
- 데이터 거버넌스

**주요 이점:**
- 데이터 계보 추적
- 병합된 결과에서 소스 식별
- 소스 테이블별 필터링
- 소스별 집계
- 다중 테이블 쿼리 감사 추적
- 디버깅 및 문제 해결

---

### 5. Data Lake Enhancements (05-data-lake-features)

**새로운 기능:** Iceberg CREATE/DROP, Delta Lake 쓰기, 시간 여행 (time travel)

**테스트 내용:**
- Data Lake 개요 및 기능 설명
- 제품 카탈로그 데이터 생성 (10,000 제품)
- Parquet 형식으로 Data Lake 내보내기
- Data Lake에서 데이터 읽기
- 버전 관리 시뮬레이션 (v1, v2, v3)
- 시간 여행 - 버전 비교
- Delta Lake 스타일 증분 업데이트
- Iceberg 스타일 파티셔닝
- 스키마 진화 시뮬레이션
- 다중 버전 쿼리
- Data Lake 메타데이터 쿼리
- 특정 시점 쿼리 (Point-in-Time)
- 버전별 감사 추적

**실행:**
```bash
./05-data-lake-features.sh
```

**주요 학습 포인트:**
- Apache Iceberg 테이블 생성/삭제
- Delta Lake 쓰기 지원
- ACID 트랜잭션 보장
- 스키마 진화 (재작성 없이)
- 시간 여행로 히스토리컬 버전 쿼리
- 버전 비교 및 감사
- 메타데이터 최적화
- 다중 포맷 통합 (Parquet, Iceberg, Delta)

**시간 여행 예시:**
```sql
-- Iceberg: 특정 시점 쿼리
SELECT * FROM iceberg_table
FOR SYSTEM_TIME AS OF '2024-12-01';

-- Delta Lake: 특정 버전 쿼리
SELECT * FROM delta_table
VERSION AS OF 42;

-- 타임스탬프 기반 쿼리
SELECT * FROM delta_table
TIMESTAMP AS OF '2024-12-01 00:00:00';
```

**실무 활용:**
- Data Lake 분석
  - S3/HDFS 직접 쿼리
  - 다중 포맷 지원
  - 파티션 프루닝

- 데이터 엔지니어링:
  - ETL 파이프라인
  - 데이터 품질 검사
  - 스키마 진화

- 데이터 과학:
  - 특성 엔지니어링
  - 히스토리컬 분석
  - 실험 추적

- 규정 준수 및 감사:
  - 시간 여행로 규정 준수
  - 감사 추적
  - 데이터 계보

- 실시간 분석:
  - 스트리밍 + 배치
  - 증분 업데이트
  - ACID 보장

**통합 예시:**
- **ClickHouse + Spark:** Iceberg 테이블 공유
- **ClickHouse + Presto:** 연합 쿼리
- **ClickHouse + Airflow:** ETL 오케스트레이션
- **ClickHouse + dbt:** 데이터 변환
- **ClickHouse + Kafka:** 스트리밍 수집

**성능 팁:**
- 대규모 데이터셋에 파티셔닝 사용
- 시간 여행을 디버깅에 활용
- 스키마 진화를 신중하게 구현
- 메타데이터 작업 모니터링
- 파티션 전략 최적화
- 압축으로 저장 효율성 향상
- 파일 크기 최적화 (128MB-1GB)

---

## 🔧 Management

### ClickHouse Connection Info

- **Web UI**: http://localhost:2508/play
- **HTTP API**: http://localhost:2508
- **TCP**: localhost:25081
- **User**: default (no password)

### Useful Commands

```bash
# ClickHouse 상태 확인
cd ../oss-mac-setup
./status.sh

# CLI 접속
./client.sh 2508

# 로그 확인
docker logs clickhouse-25-8

# 중지
./stop.sh

# 완전 삭제
./stop.sh --cleanup
```

## 📂 File Structure

```
25.8/
├── README.md                      # 이 문서
├── 00-setup.sh                    # ClickHouse 25.8 설치 스크립트
├── 01-new-parquet-reader.sh       # New Parquet Reader 테스트 실행
├── 01-new-parquet-reader.sql      # New Parquet Reader SQL
├── 02-hive-partitioning.sh        # Hive-style 파티셔닝 테스트 실행
├── 02-hive-partitioning.sql       # Hive-style 파티셔닝 SQL
├── 03-temp-data-s3.sh             # S3 임시 데이터 테스트 실행
├── 03-temp-data-s3.sql            # S3 임시 데이터 SQL
├── 04-union-all-table.sh          # UNION ALL 테스트 실행
├── 04-union-all-table.sql         # UNION ALL SQL
├── 05-data-lake-features.sh       # Data Lake 기능 테스트 실행
└── 05-data-lake-features.sql      # Data Lake 기능 SQL
```

## 🎓 Learning Path

### 초급 사용자
1. **00-setup.sh** - 환경 구성 이해
2. **01-new-parquet-reader** - Parquet 파일 읽기와 성능 개선 학습
3. **04-union-all-table** - 다중 테이블 통합 기초

### 중급 사용자
1. **02-hive-partitioning** - 파티셔닝 전략 이해
2. **03-temp-data-s3** - 대용량 쿼리 최적화 학습
3. **05-data-lake-features** - Data Lake 통합 탐색

### 고급 사용자
- 모든 기능을 조합하여 엔드투엔드 Data Lake 파이프라인 구현
- 실제 프로덕션 시나리오 설계
- 성능 벤치마킹 및 최적화
- 다중 엔진 통합 (Spark, Presto, ClickHouse)

## 💡 Feature Comparison

### ClickHouse 25.8 vs Previous Versions

| Feature | Before 25.8 | ClickHouse 25.8 | Improvement |
|---------|-------------|-----------------|-------------|
| Parquet Reader | Standard | 1.81x faster | 81% faster |
| Parquet Column Pruning | Basic | 99.98% less scan | Drastically reduced I/O |
| Hive Partitioning | Manual | Native support | Standard compatibility |
| Temporary Data | Local disk only | S3 support | Unlimited capacity |
| UNION ALL | Basic | _table column | Source tracking |
| Iceberg Tables | Read-only | CREATE/DROP | Full management |
| Delta Lake | Read-only | Write support | Bidirectional |
| Time Travel | Limited | Full support | Historical queries |

### Performance Comparison

| Operation | Previous | ClickHouse 25.8 | Benefit |
|-----------|----------|-----------------|---------|
| Parquet full scan | Baseline | 1.81x faster | Speed |
| Parquet selective columns | Many bytes | 0.02% of data | I/O efficiency |
| Hive partition query | Full scan | Partition pruning | Reduced scanning |
| Large JOIN | Memory limited | S3 spillover | Unlimited capacity |
| Multi-table union | No tracking | Source identification | Data lineage |
| Data Lake writes | Limited | Full ACID | Data integrity |

## 🔍 Additional Resources

- **Official Release Blog**: [ClickHouse 25.8 Release](https://clickhouse.com/blog/clickhouse-release-25-08)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **GitHub Repository**: [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)
- **Data Lake Formats**:
  - [Apache Iceberg](https://iceberg.apache.org/)
  - [Delta Lake](https://delta.io/)
  - [Apache Parquet](https://parquet.apache.org/)

## 📝 Notes

- 각 스크립트는 독립적으로 실행 가능합니다
- SQL 파일을 직접 읽고 수정하여 실험해보세요
- 테스트 데이터는 각 SQL 파일 내에서 생성됩니다
- 정리(cleanup)는 기본적으로 주석 처리되어 있습니다
- 프로덕션 환경 적용 전 충분한 테스트를 권장합니다
- Data Lake 기능은 적절한 스토리지 구성이 필요할 수 있습니다

## 🔒 Security Considerations

**Data Lake 접근 시:**
- S3/GCS/Azure 자격 증명을 안전하게 관리
- 환경 변수 또는 IAM 역할 사용
- 데이터 암호화 (전송 중 및 저장 시)
- 접근 제어 및 권한 관리
- 감사 로깅 활성화

**임시 데이터 사용 시:**
- S3 버킷 액세스 제어
- 임시 데이터 자동 정리 설정
- 비용 모니터링
- 네트워크 대역폭 고려

## ⚡ Performance Tips

**Parquet Reader 최적화:**
- 필요한 컬럼만 SELECT
- WHERE 조건으로 행 필터링
- 적절한 파일 크기 유지 (128MB-1GB)
- 압축 알고리즘 선택 (Snappy, ZSTD)

**Hive Partitioning 최적화:**
- 쿼리 패턴에 맞는 파티션 키 선택
- 파티션 수를 적절히 유지 (너무 많거나 적지 않게)
- 파티션 키를 WHERE 조건에 포함
- 파티션 프루닝 활용

**임시 데이터 최적화:**
- 적절한 메모리 임계값 설정
- 오프피크 시간에 대용량 작업 수행
- S3 사용 비용 모니터링
- 로컬 캐시 활용

**UNION ALL 최적화:**
- _table 컬럼으로 파티션 프루닝
- 불필요한 테이블 제외
- 인덱스 키 활용

**Data Lake 최적화:**
- 시계열 데이터는 날짜로 파티셔닝
- 메타데이터 캐싱 활용
- 파일 크기 최적화
- Predicate pushdown 활용

## 🚀 Production Deployment

### Best Practices

```sql
-- 파티션 정보 확인
SELECT
    partition,
    name,
    rows,
    bytes_on_disk
FROM system.parts
WHERE table = 'your_table'
  AND active = 1;

-- 실행 중인 쿼리 모니터링
SELECT
    query_id,
    user,
    query,
    elapsed,
    memory_usage
FROM system.processes
WHERE query NOT LIKE '%system.processes%';

-- 디스크 사용량 확인
SELECT
    name,
    path,
    formatReadableSize(free_space) AS free,
    formatReadableSize(total_space) AS total
FROM system.disks;
```

## 🛠 Management Commands

### ClickHouse 관리

```bash
# ClickHouse 상태 확인
cd ../oss-mac-setup
./status.sh

# ClickHouse CLI 접속
./client.sh 2508

# ClickHouse 중지
./stop.sh

# ClickHouse 재시작
./start.sh
```

### Data Lake (MinIO + Nessie) 관리

```bash
# MinIO 웹 콘솔 접속
# 브라우저에서: http://localhost:19001
# 자격증명: admin / password123

# MinIO 및 Nessie 중지
cd ../datalake-minio-catalog
docker-compose down

# MinIO 및 Nessie 재시작
docker-compose up -d minio nessie minio-setup

# MinIO 데이터 완전 삭제
docker-compose down -v

# 컨테이너 로그 확인
docker-compose logs -f minio
docker-compose logs -f nessie
```

### 전체 환경 재구성

```bash
# 1. 모든 서비스 중지 및 정리
cd ../oss-mac-setup
./stop.sh

cd ../datalake-minio-catalog
docker-compose down -v

# 2. 전체 재시작
cd ../25.8
./00-setup.sh
```

### 데이터 확인

```bash
# MinIO에 저장된 파일 확인
docker exec -it minio mc ls myminio/warehouse/

# ClickHouse 테이블 확인
docker exec -it clickhouse-25-8 clickhouse-client -q "SHOW TABLES"

# ClickHouse 데이터베이스 크기 확인
docker exec -it clickhouse-25-8 clickhouse-client -q "SELECT database, formatReadableSize(sum(bytes)) as size FROM system.parts GROUP BY database"
```

---

### Migration Strategy

1. **테스트 환경에서 검증**
   - 모든 새 기능 테스트
   - 성능 벤치마킹
   - 롤백 계획 수립

2. **점진적 롤아웃**
   - 작은 데이터셋부터 시작
   - 모니터링 및 성능 측정
   - 문제 발생 시 즉시 대응

3. **모니터링**
   - 쿼리 성능 추적
   - 리소스 사용량 모니터링
   - 에러 및 경고 확인

## 🤝 Contributing

이 랩에 대한 개선 사항이나 추가 예제가 있다면:
1. 이슈 등록
2. Pull Request 제출
3. 피드백 공유

## 📄 License

MIT License - 자유롭게 학습 및 수정 가능

---

**Happy Learning! 🚀**

For questions or issues, please refer to the main [clickhouse-hols README](../../README.md).
