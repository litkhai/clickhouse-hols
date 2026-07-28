# MinIO와 다중 카탈로그를 사용한 데이터 레이크

[English](README.md) | **한국어**

MinIO 객체 스토리지와 5가지 데이터 카탈로그(Nessie, Hive Metastore, Iceberg REST, Polaris, Unity Catalog)를 사용한 로컬 데이터 레이크 환경 구축.

**🔗 통합 지원:** [ClickHouse 25.8+ Labs](../releases/25.8/) - ClickHouse 25.10 및 25.11과 완전 테스트 완료

---

## 🚀 빠른 시작

### 방법 1: 단일 카탈로그 사용 (setup.sh)

하나의 카탈로그만 집중적으로 사용할 때 권장

```bash
# 1. 설정 (카탈로그 1개 선택)
./setup.sh --configure

# 2. 시작
./setup.sh --start

# 3. 예제 실행
./examples/basic-s3-read-write.sh
```

### 방법 2: 다중 카탈로그 사용 (setup-multi-catalog.sh)

여러 카탈로그를 동시에 비교/테스트할 때 권장

```bash
# 1. 모든 카탈로그 시작
./setup-multi-catalog.sh --start

# 또는 특정 카탈로그만
./setup-multi-catalog.sh --start nessie unity hive

# 2. 예제 실행
./examples/basic-s3-read-write.sh
```

---

## 📖 주요 기능

- **MinIO 객체 스토리지**: S3 호환 스토리지 (포트 19000 API, 19001 콘솔)
- **5가지 데이터 카탈로그**:
  - **Nessie** (기본값): Git과 유사한 버전 관리 (포트 19120)
  - **Hive Metastore**: 전통적이고 널리 사용됨 (포트 9083)
  - **Iceberg REST**: 표준 REST API (포트 8181)
  - **Polaris**: Apache Polaris (포트 8182, 8183)
  - **Unity Catalog**: Databricks 호환 (포트 8080)
- **Apache Iceberg**: 대용량 분석 데이터셋을 위한 테이블 포맷
- **Jupyter Notebooks**: 인터랙티브 데이터 탐색 (포트 8888)
- **ClickHouse 통합**: 25.10 및 25.11과 완전 테스트 완료

---

## 🎯 사용 시나리오별 권장 방식

### 시나리오 1: 하나의 카탈로그에 집중
**권장**: `setup.sh` 사용

```bash
./setup.sh --configure  # Unity Catalog 선택
./setup.sh --start
```

**장점**:
- 리소스 효율적
- 하나의 카탈로그에 집중
- 간단한 설정

### 시나리오 2: 카탈로그 비교 및 테스트
**권장**: `setup-multi-catalog.sh` 사용

```bash
./setup-multi-catalog.sh --start nessie unity hive
```

**장점**:
- 여러 카탈로그 동시 실행
- 기능 비교 용이
- 통합 테스트

### 시나리오 3: 개발 및 실험
**권장**: 두 가지 병행 사용

```bash
# 주 작업: setup.sh로 Unity Catalog 사용
./setup.sh --start  # Unity only

# 비교 테스트: setup-multi-catalog.sh로 다중 실행
./setup-multi-catalog.sh --start nessie unity
```

---

## 📁 프로젝트 구조

```
datalake-minio-catalog/
│
├── 🔧 핵심 설정 스크립트
│   ├── setup.sh                    # 단일 카탈로그 설정
│   ├── setup-multi-catalog.sh      # 다중 카탈로그 설정
│   ├── config.env                  # 단일 카탈로그 설정 파일
│   ├── config-multi-catalog.env    # 다중 카탈로그 설정 파일
│   └── docker-compose.yml          # Docker 서비스 정의
│
├── 📚 문서
│   ├── README.ko.md (이 파일)     # 한글 문서
│   ├── README.md                   # 영문 문서
│   └── docs/                       # 상세 문서
│
├── 🧪 테스트
│   └── tests/
│       ├── test-catalogs.sh        # 카탈로그 통합 테스트
│       └── test-unity-deltalake.sh # Unity + Delta Lake 테스트
│
├── 💡 예제
│   └── examples/
│       ├── basic-s3-read-write.sh  # 기본 S3 작업
│       └── delta-lake-simple.sh    # Delta Lake 예제
│
└── 📓 Jupyter 노트북
    └── notebooks/
```

---

## 🎮 명령어 가이드

### setup.sh (단일 카탈로그)

```bash
# 설정 (필수)
./setup.sh --configure

# 시작
./setup.sh --start

# 중지
./setup.sh --stop

# 상태 확인
./setup.sh --status

# 데이터 삭제
./setup.sh --clean
```

### setup-multi-catalog.sh (다중 카탈로그)

```bash
# 모든 카탈로그 시작
./setup-multi-catalog.sh --start

# 특정 카탈로그만
./setup-multi-catalog.sh --start nessie unity

# 중지
./setup-multi-catalog.sh --stop

# 상태 확인
./setup-multi-catalog.sh --status

# 설정 (선택사항 - 기본값 제공)
./setup-multi-catalog.sh --configure
```

---

## 🔍 서비스 엔드포인트

서비스 시작 후 다음 URL로 접근 가능:

### MinIO
- **콘솔 UI**: http://localhost:19001
- **API 엔드포인트**: http://localhost:19000
- **로그인**: admin / password123

### 데이터 카탈로그

| 카탈로그 | 엔드포인트 | 포트 |
|----------|-----------|------|
| **Nessie** | http://localhost:19120 | 19120 |
| **Hive** | thrift://localhost:9083 | 9083 |
| **Iceberg REST** | http://localhost:8181 | 8181 |
| **Polaris** | http://localhost:8182 | 8182, 8183 |
| **Unity** | http://localhost:8080 | 8080 |

### Jupyter Notebook
- **URL**: http://localhost:8888 (비밀번호 불필요)

---

## 💡 활용 예제

### 예제 1: 기본 S3 읽기/쓰기

```bash
# MinIO + 카탈로그 시작
./setup.sh --start

# 예제 실행
./examples/basic-s3-read-write.sh
```

### 예제 2: Delta Lake 작업

```bash
# Unity Catalog 시작
./setup.sh --configure  # Unity 선택
./setup.sh --start

# Delta Lake 예제
./examples/delta-lake-simple.sh
```

### 예제 3: 카탈로그 비교

```bash
# 3개 카탈로그 동시 시작
./setup-multi-catalog.sh --start nessie unity hive

# 비교 테스트
./tests/test-catalogs.sh
```

---

## 🧪 ClickHouse 통합 테스트

### 테스트된 버전

| 버전 | Unity Catalog | Delta Lake | 상태 | 권장사항 |
|------|--------------|------------|------|----------|
| **25.11.2.24** | ✅ 완전 지원 | ✅ 완전 지원 | ✅ 모든 테스트 통과 | **권장** |
| **25.10.3.100** | ✅ 기본 지원 | ⚠️ 제한적 지원 | ⚠️ 80% 테스트 통과 | 주의해서 사용 |

### Unity Catalog + Delta Lake 테스트

```bash
# 1. Unity Catalog 시작
./setup.sh --configure  # Unity 선택
./setup.sh --start

# 2. ClickHouse 시작
cd ../oss-mac-setup
./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog

# 3. 통합 테스트 실행
./tests/test-unity-deltalake.sh

# 4. 결과 확인
cat docs/test-results/test-results-*.md
```

상세 비교: [docs/COMPARISON-25.10-vs-25.11.md](docs/COMPARISON-25.10-vs-25.11.md)

---

## 📊 카탈로그 비교

| 기능 | Nessie | Hive | Iceberg REST | Polaris | Unity |
|------|--------|------|--------------|---------|-------|
| **버전 관리** | ✅ Git 방식 | ❌ | 제한적 | ✅ | ✅ |
| **시간 여행** | ✅ | ❌ | ✅ | ✅ | ✅ |
| **브랜칭** | ✅ | ❌ | ❌ | ✅ | ❌ |
| **ACID** | ✅ | 제한적 | ✅ | ✅ | ✅ |
| **성숙도** | 최신 | 매우 성숙 | 최신 | 신규 | 최신 |
| **적합한 용도** | 버전 제어 | 레거시 시스템 | 표준 API | Iceberg 중심 | Databricks 호환 |

---

## 🔄 워크플로우 예제

### 워크플로우 1: 빠른 테스트

```bash
# 방법 A: 단일 카탈로그
./setup.sh --configure && ./setup.sh --start
./examples/basic-s3-read-write.sh

# 방법 B: 다중 카탈로그
./setup-multi-catalog.sh --start
./examples/basic-s3-read-write.sh
```

### 워크플로우 2: Unity Catalog 심화

```bash
# Unity만 시작
./setup.sh --configure  # Unity 선택
./setup.sh --start

# ClickHouse 시작 및 테스트
cd ../oss-mac-setup && ./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog
./tests/test-unity-deltalake.sh
```

### 워크플로우 3: 카탈로그 비교 분석

```bash
# 모든 카탈로그 시작
./setup-multi-catalog.sh --start

# ClickHouse 시작
cd ../oss-mac-setup && ./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog

# 통합 테스트
./tests/test-catalogs.sh
```

---

## 🐛 문제 해결

### 서비스가 시작되지 않음

```bash
# Docker 확인
docker ps

# 로그 확인
docker logs minio
docker logs unity-catalog

# 상태 확인
./setup.sh --status
./setup-multi-catalog.sh --status
```

### 포트 충돌

```bash
# 포트 사용 확인
lsof -i :19000

# 포트 변경
./setup.sh --configure
# 또는
./setup-multi-catalog.sh --configure
```

### ClickHouse 연결 문제

```sql
-- Docker 내부에서: host.docker.internal 사용
SELECT * FROM s3(
    'http://host.docker.internal:19000/warehouse/data.parquet',
    'admin', 'password123', 'Parquet'
);

-- 외부에서: localhost 사용
SELECT * FROM s3(
    'http://localhost:19000/warehouse/data.parquet',
    'admin', 'password123', 'Parquet'
);
```

---

## 📚 문서

### 한글 문서
- **[README.ko.md](README.ko.md)** (이 파일) - 메인 문서
- **[docs/NAVIGATION_GUIDE.md](docs/NAVIGATION_GUIDE.md)** - 프로젝트 탐색
- **[docs/UNITY_DELTALAKE_TEST_GUIDE.md](docs/UNITY_DELTALAKE_TEST_GUIDE.md)** - Unity 테스트 가이드
- **[docs/COMPARISON-25.10-vs-25.11.md](docs/COMPARISON-25.10-vs-25.11.md)** - ClickHouse 버전 비교

### English Documentation
- **[README.md](README.md)** - Main documentation
- **[docs/QUICKSTART_GUIDE.md](docs/QUICKSTART_GUIDE.md)** - Quick start
- **[docs/SPARK_SETUP.md](docs/SPARK_SETUP.md)** - Spark integration

---

## 🎯 권장 사항 요약

| 사용 목적 | 권장 도구 | 이유 |
|----------|----------|------|
| **단일 카탈로그 사용** | `setup.sh` | 리소스 효율적, 집중적 작업 |
| **카탈로그 비교** | `setup-multi-catalog.sh` | 동시 실행, 기능 비교 |
| **Unity 심화 테스트** | `setup.sh` + Unity | 집중적 테스트 환경 |
| **종합 테스트** | `setup-multi-catalog.sh` | 모든 카탈로그 한번에 |
| **개발/실험** | 두 가지 병행 | 유연한 환경 전환 |

---

## ✨ 버전 히스토리

### v3.1 (2025-12-13) - 다중 카탈로그 지원
- ✨ `setup-multi-catalog.sh` 추가 - 여러 카탈로그 동시 실행
- 📚 한글/영문 병행 문서화
- 🎯 목적별 사용 가이드 제공

### v3.0 (2025-12-13) - 구조 개선
- 📁 테스트, 예제, 문서 분리
- 🧹 프로젝트 구조 정리

### v2.0 (2025-12)
- Polaris 및 Unity Catalog 추가
- ClickHouse 25.10/25.11 테스트

### v1.0
- 3개 카탈로그로 첫 출시

---

## 📖 참고 자료

- [MinIO 문서](https://min.io/docs/minio/linux/index.html)
- [Apache Iceberg](https://iceberg.apache.org/)
- [Project Nessie](https://projectnessie.org/)
- [Apache Polaris](https://polaris.apache.org/)
- [Unity Catalog](https://github.com/unitycatalog/unitycatalog)
- [ClickHouse S3 통합](https://clickhouse.com/docs/en/engines/table-engines/integrations/s3)

---

## 📝 라이선스

교육 목적 데모 프로젝트

---

## 🆘 도움말

- **빠른 시작**: `./setup.sh --help` 또는 `./setup-multi-catalog.sh --help`
- **문서**: [docs/](docs/) 디렉토리 참조
- **테스트**: `./tests/test-catalogs.sh` 실행
- **로그**: `docker logs <service-name>`
