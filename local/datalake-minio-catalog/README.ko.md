# MinIO와 다중 카탈로그를 사용한 데이터 레이크

> **관련 글**: [Data Lake Catalog (25.10+)](https://clickhouse.litkhai.dev/articles/feature/data-lake-catalog-25-10/)

[English](README.md) | **한국어**

MinIO 객체 스토리지와 5가지 데이터 카탈로그(Nessie, Hive Metastore, Iceberg REST, Polaris, Unity Catalog)를 사용한 로컬 데이터 레이크 환경 구축.

**🔗 통합 지원:** [ClickHouse 25.8+ Labs](../releases/25.8/) - ClickHouse 26.10.3.7에서 카탈로그 연동 검증(아래 "카탈로그 연동 테스트" 참고)

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
- **ClickHouse 통합**: 26.10.3.7에서 5개 카탈로그 모두 `DataLakeCatalog` 읽기 테스트(아래). 이전 상태 점검은 그렇게 표기

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
│       ├── test-datalakecatalog.sh # 실제 테스트: 카탈로그로 시드, DataLakeCatalog로 읽기
│       ├── seed_catalogs.py        # 버전 고정 시드 작성기 (pyiceberg / deltalake)
│       ├── requirements-seed.txt   # 작성기 버전 고정
│       ├── test-catalogs.sh        # 상태/스토리지 점검 (카탈로그 연동 아님)
│       └── test-unity-deltalake.sh # Unity API + s3() Parquet 점검 (Delta 엔진 아님)
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

### 카탈로그 연동 테스트 (`DataLakeCatalog`)

`tests/test-datalakecatalog.sh`가 ClickHouse를 카탈로그에 실제로 붙여 보는 테스트입니다. 카탈로그마다

1. `lab.events`(5행: `id` Int64, `name` String, `amount` Float64, `ts` timestamp)를 **카탈로그를 통해** 버전 고정 작성기로 넣고(`seed_catalogs.py`, digest 고정 `python:3.12-slim` 컨테이너: Nessie·Hive Metastore·Iceberg REST·Polaris는 pyiceberg 0.12.0, Unity Catalog는 `deltalake` 1.6.6과 Unity REST API로 Delta 테이블 등록),
2. 랩 네트워크의 ClickHouse 컨테이너에서 `CREATE DATABASE ... ENGINE = DataLakeCatalog(...)`를 실행하고,
3. `SHOW TABLES`, `count()` = 5, `sum(id)`/`sum(amount)` = 15/152, 필터 쿼리(`amount > 25`는 charlie, delta, echo), 타임스탬프 값을 확인합니다.

ClickHouse가 카탈로그를 통해 시드한 행을 읽어야만 통과입니다. 스크립트가 스택과 ClickHouse 컨테이너를 직접 띄우고 지웁니다(compose 프로젝트 `dlfix`, `KEEP=1`이면 남김). 호스트 포트는 `config.env` 기본값이며 환경변수로 덮어쓸 수 있습니다(`MINIO_PORT`, `MINIO_CONSOLE_PORT`, `POSTGRES_PORT`, `JUPYTER_PORT` 등).

```bash
tests/test-datalakecatalog.sh                       # 5개 전부
tests/test-datalakecatalog.sh nessie polaris        # 일부만
FAULT=stop-catalog tests/test-datalakecatalog.sh    # 시드 후 각 카탈로그를 멈춤: 실패해야 정상
CH_IMAGE=clickhouse/clickhouse-server:26.10.3.7 tests/test-datalakecatalog.sh
```

사용한 DDL(엔진 설정은 `system.settings`, 서버 오류 메시지, [DataLakeCatalog 문서](https://clickhouse.com/docs/engines/database-engines/datalakecatalog)(2026-11-04 확인)에서 읽음). MinIO 기반 REST/Hive 카탈로그 공통 설정: `vended_credentials = 0, aws_access_key_id, aws_secret_access_key, region = 'us-east-1', storage_endpoint = 'http://minio:9000/warehouse'`.

| 카탈로그 | 엔진 엔드포인트 | `catalog_type` | 필요한 `SET` | 그 밖의 설정 |
|---|---|---|---|---|
| Nessie | `http://nessie:19120/iceberg` | `rest` | `allow_database_iceberg` | `warehouse = 'warehouse'` |
| Iceberg REST (tabulario) | `http://iceberg-rest:8181` | `rest` | `allow_database_iceberg` | `warehouse = 'warehouse'` (ClickHouse가 요구, 서버는 무시) |
| Polaris | `http://polaris:8181/api/catalog` | `rest` | `allow_database_iceberg` | `warehouse = '<카탈로그>'`, `catalog_credential = 'root:<secret>'`, `auth_scope = 'PRINCIPAL_ROLE:ALL'`, `oauth_server_uri = '.../v1/oauth/tokens'` |
| Hive Metastore | `thrift://hive-metastore:9083` | `hive` | `allow_experimental_database_hms_catalog` | `warehouse = 'hive'` |
| Unity Catalog OSS | `http://unity-catalog:8080/api/2.1/unity-catalog` | `unity` | `allow_database_unity_catalog` | `use_unity_catalog_v2 = 1`, `warehouse = 'lab'`, `catalog_credential`, `storage_endpoint = 'http://minio:9000'`, `region` |

실행 중 알게 된 점:

- `vended_credentials = 0`이 없으면 REST 카탈로그 읽기가 `ACCESS_DENIED`("S3 access from user queries is not allowed to use the server's own credentials ...")로 실패했습니다. 기본값이 카탈로그가 발급한 자격 증명을 요청하는 것인데, 여기 Nessie는 발급하도록 설정돼 있지 않습니다.
- Unity: Unity OSS에는 엔드포인트 설정이 없어서 테스트가 `server.properties`(`UNITY_SERVER_PROPERTIES`)로 단기 MinIO STS 자격 증명을 줍니다. ClickHouse에는 MinIO로 가도록 `storage_endpoint`가 필요합니다. 없으면 발급된 키로 `https://s3.eu-central-1.amazonaws.com/warehouse/...`를 요청해 `403 InvalidAccessKeyId`가 났습니다(`UNITY_STORAGE_ENDPOINT= tests/test-datalakecatalog.sh unity`로 재현, 이때 임시 MinIO 키가 AWS로 전송됨). `use_unity_catalog_v2 = 0`(`UNITY_V2=0`)에서도 통과했습니다. 테스트 기본값은 문서가 Delta와 Iceberg 모두를 다룬다고 설명하는 `1`입니다.
- Hive Metastore: `s3a://` 테이블 위치를 해석하려면 이미지에 `hadoop-aws` 클래스패스와 `conf/hive-core-site.xml`이 필요합니다(둘 다 `docker-compose.yml`에 설정). 시드는 `s3a://` 위치를 명시해 테이블을 등록합니다. `apache/hive:3.1.3` 이미지는 amd64 전용이라 arm64에서는 에뮬레이션으로 돕니다. 기존 Postgres 볼륨에 메타스토어 컨테이너만 다시 만들면 실패합니다(시작할 때마다 `initSchema` 실행). `down -v`를 쓰세요.

### 버전 고정

이미지는 고정했습니다(`:latest` 없음). digest는 2026-11-04에 읽은 레지스트리 인덱스 digest입니다.

| 구성 요소 | 이미지 | digest / 버전 |
|---|---|---|
| MinIO | `cgr.dev/chainguard/minio@sha256:3c60a2a8...` | `RELEASE.2026-10-23T20-06-51Z` (`minio/minio`는 더 이상 pull 불가, Chainguard는 버전 태그가 없어 digest로 고정) |
| MinIO 클라이언트(버킷 생성) | `cgr.dev/chainguard/minio-client@sha256:1dccd2a6...` | 셸 없음: `MC_HOST_myminio`와 `mc mb` 한 번 |
| Nessie | `ghcr.io/projectnessie/nessie:0.109.0` | `sha256:61a1a14e...` (Docker Hub `projectnessie/nessie`는 2024-01에서 멈춤) |
| Iceberg REST | `tabulario/iceberg-rest:1.6.0` | `sha256:3b7d31bd...` |
| Polaris | `apache/polaris:1.8.0` | `sha256:347615e7...` |
| Unity Catalog | `unitycatalog/unitycatalog:v0.7.0` | `sha256:cdacdc5e...` |
| Hive Metastore | `apache/hive:3.1.3` | `sha256:d102ba29...` |
| Hive 백엔드 DB | `postgres:11.16` | `sha256:5d2aa4a7...` |
| Jupyter 베이스 (`Dockerfile.jupyter`) | `jupyter/pyspark-notebook@sha256:58377aaa...` | Docker Hub 마지막 게시 2023-10-20(2026-11-04에 `latest`가 가리키던 것). 이미지가 빌드되고 `pyarrow`가 import되도록 `boto3==1.43.117`, `pyarrow<26` 고정 |
| 시드 작성기 | `python@sha256:b18b261e...` (`python:3.12-slim`) | `tests/requirements-seed.txt` |
| ClickHouse | `clickhouse/clickhouse-server:26.10.3.7` | `sha256:739e099a...` |

**ClickHouse 26.10.3.7에서 검증, 2026-11-04** (Docker Desktop, arm64 호스트): `tests/test-datalakecatalog.sh`를 5개 카탈로그 모두에 대해 끝까지 실행해, 모든 카탈로그에서 시드한 5행을 읽었습니다(`count()`, 합계, 필터 쿼리, 타임스탬프 값 일치). 시드 후 각 카탈로그 컨테이너를 멈추면 같은 테스트가 5개 모두 실패했고(통과 0, 실패 5), `storage_endpoint` 없는 Unity도 실패했습니다(위). 이 실행들의 원본 출력은 커밋하지 않았습니다. 검증한 것은 `DataLakeCatalog` 읽기 경로뿐이며, ClickHouse를 통한 쓰기, ClickPipes, 다른 버전은 검증하지 않았습니다.

### 상태/스토리지 점검 (카탈로그 연동 아님)

`tests/test-catalogs.sh`는 MinIO(`s3()` Parquet 쓰기/읽기)와, 활성 카탈로그에 대해서는 헬스 엔드포인트 응답(Hive는 9083 포트 열림)과 ClickHouse `ENGINE = Memory` 테이블만 확인하며, ClickHouse가 카탈로그에 연결하지 않습니다. `tests/test-unity-deltalake.sh`도 Unity에 대해 같습니다(API 응답, `s3()` Parquet). Delta 엔진도 `DataLakeCatalog`도 쓰지 않습니다. `CATALOG_TYPE`과 `CLICKHOUSE_CONTAINER`는 환경변수로 지정할 수 있습니다. 예전의 "25.11 모든 테스트 통과 / 25.10 80% 통과" 표는 이 점검에서 나온 것이고 다시 실행하지 않았으며 카탈로그 지원의 근거가 아니어서 삭제했습니다. [docs/COMPARISON-25.10-vs-25.11.md](docs/COMPARISON-25.10-vs-25.11.md)는 새 테스트보다 앞선 문서이며 다시 확인하지 않았습니다.

### Unity Catalog 상태/스토리지 점검

```bash
# 1. Unity Catalog 시작
./setup.sh --configure  # Unity 선택
./setup.sh --start

# 2. ClickHouse 시작
cd ../oss-docker
./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog

# 3. Unity 상태/스토리지 점검 실행 (카탈로그 읽기 테스트 아님)
./tests/test-unity-deltalake.sh

# 4. 결과 확인
cat tests/test-results-*.md   # 스크립트 옆에 생성되는 보고서 (git 무시)
```

과거 비교(2025-12-13, 다시 실행하지 않음): [docs/COMPARISON-25.10-vs-25.11.md](docs/COMPARISON-25.10-vs-25.11.md)

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
cd ../oss-docker && ./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog
./tests/test-unity-deltalake.sh
```

### 워크플로우 3: 카탈로그 비교 분석

```bash
# 모든 카탈로그 시작
./setup-multi-catalog.sh --start

# ClickHouse 시작
cd ../oss-docker && ./set.sh 25.11 && ./start.sh
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
- **테스트**: `./tests/test-datalakecatalog.sh`(카탈로그 연동) 또는 `./tests/test-catalogs.sh`(상태 점검) 실행
- **로그**: `docker logs <service-name>`
