# ClickHouse Hands-On Labs (HOLs)

[English](#english) | [한국어](#한국어)

---

## English

A collection of practical, hands-on laboratory exercises for learning and exploring ClickHouse — the fast open-source column-oriented database management system.

### 🎯 Purpose

These labs cover both **ClickHouse OSS** and **ClickHouse Cloud**, from a first local install to release-by-release feature testing, cloud integrations, workload benchmarks and full workshops. Each lab is self-contained: it brings up what it needs, generates its own data, and documents what to expect.

### 📁 Repository Structure

```
clickhouse-hols/
├── local/       # Local Docker environments and per-release feature labs
├── chc/         # ClickHouse Cloud integrations (API, Kafka, lakes, S3, tools)
├── tpcds/       # TPC-DS benchmark
├── usecase/     # End-to-end use cases (analytics, search, geo, LLM observability)
├── workload/    # Focused performance and behaviour experiments
└── workshop/    # Multi-service workshops and PoCs
```

### 🏠 Local Environments (`local/`)

| Lab | What it covers |
|-----|----------------|
| [local/oss-mac-setup](local/oss-mac-setup/) | ClickHouse OSS on macOS via Docker; `set.sh <version>` switches versions and every release lab builds on it |
| [local/releases](local/releases/) | **15 per-release feature labs, 25.5 → 26.7** — one directory per release, each with runnable SQL for that version's new features |
| [local/datalake-minio-catalog](local/datalake-minio-catalog/) | Local data lake: MinIO plus Iceberg / Nessie / Unity / Delta catalogs, with Jupyter notebooks |
| [local/kafka-mysql-table-engines](local/kafka-mysql-table-engines/) | Kafka and MySQL table engines, including materialized-view block-size testing |
| [local/pg-clickhouse-lab](local/pg-clickhouse-lab/) | `pg_clickhouse`: querying ClickHouse from PostgreSQL |
| [local/mcp-server-clickhouse](local/mcp-server-clickhouse/) | ClickHouse MCP server for LLM tool access |
| [local/llm-mac-librechat-with-clickhouse](local/llm-mac-librechat-with-clickhouse/) | LibreChat with a local LLM and the ClickHouse MCP server (macOS) |
| [local/llm-linux-librechat-sole](local/llm-linux-librechat-sole/) | LibreChat standalone (Linux) |

### ☁️ ClickHouse Cloud (`chc/`)

| Lab | What it covers |
|-----|----------------|
| [chc/api/chc-api-test](chc/api/chc-api-test/) | ClickHouse Cloud API tester |
| [chc/clickpipes-mysql](chc/clickpipes-mysql/) | ClickPipes CDC from a MySQL source |
| [chc/clickpipes-s3](chc/clickpipes-s3/) | ClickPipes S3 checkpoint test suite ([Terraform](chc/clickpipes-s3/terraform/)) |
| [chc/kafka/terraform-confluent-aws](chc/kafka/terraform-confluent-aws/) | Confluent Platform on AWS with Terraform |
| [chc/kafka/terraform-confluent-aws-nlb-ssl](chc/kafka/terraform-confluent-aws-nlb-ssl/) | Confluent with NLB SSL termination |
| [chc/kafka/terraform-confluent-aws-connect-sink](chc/kafka/terraform-confluent-aws-connect-sink/) | Confluent with the ClickHouse sink connector |
| [chc/lake/terraform-minio-on-aws](chc/lake/terraform-minio-on-aws/) | MinIO on AWS via Terraform |
| [chc/lake/terraform-glue-s3-chc-integration](chc/lake/terraform-glue-s3-chc-integration/) | ClickHouse Cloud with the AWS Glue catalog |
| [chc/s3/terraform-chc-secures3-aws](chc/s3/terraform-chc-secures3-aws/) | Secure S3 integration with Terraform |
| [chc/s3/terraform-chc-secures3-aws-direct-attach](chc/s3/terraform-chc-secures3-aws-direct-attach/) | S3 integration via direct bucket policy access |
| [chc/mysql-interface](chc/mysql-interface/) | Automated tests for the Cloud MySQL interface |
| [chc/tool/costkeeper](chc/tool/costkeeper/) | Service cost monitoring |
| [chc/tool/costkeeper-multi](chc/tool/costkeeper-multi/) | Cost monitoring across multiple services |
| [chc/tool/ch2otel](chc/tool/ch2otel/) | ClickHouse system metrics to OpenTelemetry |

### 📊 Benchmark (`tpcds/`)

| Lab | What it covers |
|-----|----------------|
| [tpcds](tpcds/) | TPC-DS schema, data load and the [query set](tpcds/queries/) |

### 🧪 Use Cases (`usecase/`)

| Lab | What it covers |
|-----|----------------|
| [usecase/ads-analytics](usecase/ads-analytics/) | Ad performance analytics cube |
| [usecase/customer360](usecase/customer360/) | Customer 360 modelling |
| [usecase/fulltext-search](usecase/fulltext-search/) | Bilingual (ko/en) full-text search over support tickets |
| [usecase/ch-geo-analytics](usecase/ch-geo-analytics/) | Geospatial analytics with H3 indexing |
| [usecase/korea-geo](usecase/korea-geo/) | Korean administrative boundaries with Superset |
| [usecase/gnome-variants](usecase/gnome-variants/) | Genome variant analysis |
| [usecase/security-traffic-analysis](usecase/security-traffic-analysis/) | Security traffic analysis platform |
| [usecase/json-explode-confluent-clickpipes](usecase/json-explode-confluent-clickpipes/) | Real-time JSON explode: Confluent → ClickPipes → ClickHouse |
| [usecase/langfuse-ee](usecase/langfuse-ee/) | Self-hosting Langfuse on ClickHouse (OSS + Enterprise) |
| [usecase/langfuse-eval](usecase/langfuse-eval/) | Langfuse prompts, datasets, experiments and evals |
| [usecase/mysql-prewhere](usecase/mysql-prewhere/) | `PREWHERE` behaviour over the MySQL protocol |
| [usecase/mysql-protocol-benchmark](usecase/mysql-protocol-benchmark/) | MySQL vs ClickHouse point-query performance |

### 🔬 Workloads (`workload/`)

| Lab | What it covers |
|-----|----------------|
| [workload/replacingmergetree](workload/replacingmergetree/) | `FINAL`, merge timing and the `argMax` alternative |
| [workload/dedup-engine](workload/dedup-engine/) | Deduplication engines compared |
| [workload/delete-benchmark](workload/delete-benchmark/) | DELETE mechanisms and their costs |
| [workload/mv-vs-rmv](workload/mv-vs-rmv/) | Materialized vs refreshable materialized views |
| [workload/projection](workload/projection/) | Projections for read patterns one sort key cannot serve |
| [workload/projection-customsettings](workload/projection-customsettings/) | Projection behaviour under custom settings |
| [workload/index-granularity-point-query](workload/index-granularity-point-query/) | Index granularity versus point-query latency |
| [workload/async-insert-stress](workload/async-insert-stress/) | Async insert under stress |
| [workload/json-stress-test](workload/json-stress-test/) | `JSON` type path limits: dynamic vs shared path cost |
| [workload/kafka-partitioning-ingestion](workload/kafka-partitioning-ingestion/) | Kafka partitioning aligned to the ClickHouse sort key |
| [workload/rbac-workloadmanagement](workload/rbac-workloadmanagement/) | RBAC and workload management |

### 🎓 Workshops (`workshop/`)

| Lab | What it covers |
|-----|----------------|
| [workshop/device-360](workshop/device-360/) | Device360 PoC: Cloud performance validation at billions of rows |
| [workshop/o11y-vector-ai](workshop/o11y-vector-ai/) | Observability with ClickStack, Vector and OpenTelemetry |
| [workshop/observability-waf](workshop/observability-waf/) | WAF observability across a multi-cloud MSA |

### 🛠 Prerequisites

**General**: macOS, Linux, or Windows with WSL2 · Docker and Docker Compose · basic command-line familiarity.

| Lab type | Also needs |
|----------|-----------|
| Local labs | Docker Desktop, Python 3.8+ |
| Cloud labs | Terraform, AWS CLI, an AWS account |
| ClickHouse Cloud labs | A ClickHouse Cloud account |
| Benchmarks | `clickhouse-client`, sufficient disk space |

### 🚀 Getting Started

```bash
git clone https://github.com/litkhai/clickhouse-hols.git
cd clickhouse-hols
```

Then pick a lab, read its `README.md`, and follow its Quick Start. Nothing is global: each lab documents its own setup and teardown.

### 📖 Learning Path

**Beginner** → [local/oss-mac-setup](local/oss-mac-setup/) → [local/releases](local/releases/) → [tpcds](tpcds/)

**Cloud** → [chc/api/chc-api-test](chc/api/chc-api-test/) → [chc/s3/terraform-chc-secures3-aws](chc/s3/terraform-chc-secures3-aws/) → [chc/lake/terraform-glue-s3-chc-integration](chc/lake/terraform-glue-s3-chc-integration/)

**Advanced** → [chc/kafka/terraform-confluent-aws](chc/kafka/terraform-confluent-aws/) → [workload/replacingmergetree](workload/replacingmergetree/) → [chc/tool/costkeeper](chc/tool/costkeeper/)

### 🧱 Lab Conventions

The per-release labs under [local/releases](local/releases/) are the reference layout:

| File | Role |
|------|------|
| `README.md` | Bilingual guide: overview, per-feature detail, learning points, use cases |
| `00-setup.sh` | Brings up the environment the lab needs and verifies it |
| `NN-<feature>.sh` | Thin runner that pipes the matching `.sql` into `clickhouse-client` |
| `NN-<feature>.sql` | The lab: numbered sections with banner `SELECT`s, self-generated data, cleanup left commented for inspection |

Not every lab predates this convention, so older directories vary — the SQL-only labs are run with `clickhouse-client --queries-file <file>` in numbered order, as documented in each README.

### 🔐 Credentials

This repository is **public**. Never commit real endpoints, passwords or API keys.

- Copy `*.env.example` / `*.tfvars.example` to the real filename and edit locally; `.env` and `*.tfvars` are gitignored
- Scripts read connection details from the environment and fail with instructions when they are missing
- ClickHouse Cloud **API keys are organization-wide** — scope them to the smallest role that works, and rotate them if they are ever exposed

### ✅ Repository Checks

CI runs on every push and pull request ([`.github/workflows/checks.yml`](.github/workflows/checks.yml)):

| Job | What it enforces |
|-----|------------------|
| `links` | Every relative markdown link resolves |
| `syntax` | All tracked `.sh`, `.py`, `.yml` files parse |
| `shellcheck` | Shell lint (advisory, does not block) |
| `secrets` | gitleaks with the ClickHouse rules in [`.gitleaks.toml`](.gitleaks.toml) |
| `hygiene` | No tracked file is shadowed by an ignore rule; no `/Users/...` paths in code |

Run the same checks locally, and enable the pre-commit guard once per clone:

```bash
python3 .github/scripts/check_links.py
./.github/scripts/check_syntax.sh
gitleaks detect --config .gitleaks.toml --no-banner --redact

# blocks staged secrets, host absolute paths and syntax errors
brew install gitleaks
git config core.hooksPath .githooks
```

Also enable **Settings → Code security → Push protection** on the GitHub repository, so a secret is rejected at push time even when the hook is not installed.

### 🤝 Contributing

Issues and pull requests are welcome.

### 📝 License

MIT License — see individual lab directories for specific license information.

### 🌐 Additional Resources

- [ClickHouse Documentation](https://clickhouse.com/docs)
- [ClickHouse Changelog](https://clickhouse.com/docs/whats-new/changelog)
- Korean resources: [clickhouse.kr](https://clickhouse.kr)

---

## 한국어

ClickHouse를 학습하고 탐색하기 위한 실습(Hands-On Lab) 모음입니다.

### 🎯 목적

**ClickHouse OSS**와 **ClickHouse Cloud**를 모두 다룹니다. 첫 로컬 설치부터 릴리스별 신기능 테스트, 클라우드 통합, 워크로드 벤치마크, 종합 워크숍까지 포함합니다. 각 실습은 독립적입니다 — 필요한 환경을 스스로 띄우고, 테스트 데이터를 직접 생성하며, 기대 결과를 문서화합니다.

### 📁 저장소 구조

```
clickhouse-hols/
├── local/       # 로컬 Docker 환경 및 릴리스별 기능 랩
├── chc/         # ClickHouse Cloud 통합 (API, Kafka, 레이크, S3, 도구)
├── tpcds/       # TPC-DS 벤치마크
├── usecase/     # 엔드투엔드 활용 사례 (분석, 검색, 지리, LLM 관측성)
├── workload/    # 집중 성능·동작 실험
└── workshop/    # 다중 서비스 워크숍 및 PoC
```

### 🏠 로컬 환경 (`local/`)

| 실습 | 내용 |
|------|------|
| [local/oss-mac-setup](local/oss-mac-setup/) | macOS Docker 기반 ClickHouse OSS. `set.sh <버전>`으로 버전을 전환하며, 모든 릴리스 랩이 이 환경을 사용 |
| [local/releases](local/releases/) | **릴리스별 기능 랩 15개, 25.5 → 26.7** — 릴리스마다 디렉토리 하나, 해당 버전 신기능의 실행 가능한 SQL 포함 |
| [local/datalake-minio-catalog](local/datalake-minio-catalog/) | 로컬 데이터 레이크: MinIO + Iceberg / Nessie / Unity / Delta 카탈로그, Jupyter 노트북 |
| [local/kafka-mysql-table-engines](local/kafka-mysql-table-engines/) | Kafka·MySQL 테이블 엔진, 구체화 뷰 블록 크기 테스트 포함 |
| [local/pg-clickhouse-lab](local/pg-clickhouse-lab/) | `pg_clickhouse`: PostgreSQL에서 ClickHouse 조회 |
| [local/mcp-server-clickhouse](local/mcp-server-clickhouse/) | LLM 도구 접근용 ClickHouse MCP 서버 |
| [local/llm-mac-librechat-with-clickhouse](local/llm-mac-librechat-with-clickhouse/) | 로컬 LLM + ClickHouse MCP 서버와 LibreChat (macOS) |
| [local/llm-linux-librechat-sole](local/llm-linux-librechat-sole/) | LibreChat 단독 구성 (Linux) |

### ☁️ ClickHouse Cloud (`chc/`)

| 실습 | 내용 |
|------|------|
| [chc/api/chc-api-test](chc/api/chc-api-test/) | ClickHouse Cloud API 테스터 |
| [chc/clickpipes-mysql](chc/clickpipes-mysql/) | MySQL 소스 ClickPipes CDC |
| [chc/clickpipes-s3](chc/clickpipes-s3/) | ClickPipes S3 체크포인트 테스트 ([Terraform](chc/clickpipes-s3/terraform/)) |
| [chc/kafka/terraform-confluent-aws](chc/kafka/terraform-confluent-aws/) | Terraform으로 AWS에 Confluent Platform 구성 |
| [chc/kafka/terraform-confluent-aws-nlb-ssl](chc/kafka/terraform-confluent-aws-nlb-ssl/) | NLB SSL 종료를 적용한 Confluent |
| [chc/kafka/terraform-confluent-aws-connect-sink](chc/kafka/terraform-confluent-aws-connect-sink/) | ClickHouse Sink Connector 연동 |
| [chc/lake/terraform-minio-on-aws](chc/lake/terraform-minio-on-aws/) | Terraform으로 AWS에 MinIO 구성 |
| [chc/lake/terraform-glue-s3-chc-integration](chc/lake/terraform-glue-s3-chc-integration/) | ClickHouse Cloud + AWS Glue 카탈로그 |
| [chc/s3/terraform-chc-secures3-aws](chc/s3/terraform-chc-secures3-aws/) | Terraform 기반 보안 S3 통합 |
| [chc/s3/terraform-chc-secures3-aws-direct-attach](chc/s3/terraform-chc-secures3-aws-direct-attach/) | 버킷 정책 직접 연결 방식 S3 통합 |
| [chc/mysql-interface](chc/mysql-interface/) | Cloud MySQL 인터페이스 자동 테스트 |
| [chc/tool/costkeeper](chc/tool/costkeeper/) | 서비스 비용 모니터링 |
| [chc/tool/costkeeper-multi](chc/tool/costkeeper-multi/) | 다중 서비스 비용 모니터링 |
| [chc/tool/ch2otel](chc/tool/ch2otel/) | ClickHouse 시스템 지표를 OpenTelemetry로 변환 |

### 📊 벤치마크 (`tpcds/`)

| 실습 | 내용 |
|------|------|
| [tpcds](tpcds/) | TPC-DS 스키마, 데이터 적재, [쿼리 세트](tpcds/queries/) |

### 🧪 활용 사례 (`usecase/`)

| 실습 | 내용 |
|------|------|
| [usecase/ads-analytics](usecase/ads-analytics/) | 광고 성과 분석 큐브 |
| [usecase/customer360](usecase/customer360/) | Customer 360 모델링 |
| [usecase/fulltext-search](usecase/fulltext-search/) | 한/영 이중 언어 지원 티켓 전문 검색 |
| [usecase/ch-geo-analytics](usecase/ch-geo-analytics/) | H3 인덱싱 기반 공간 분석 |
| [usecase/korea-geo](usecase/korea-geo/) | 한국 행정경계(시군구) + Superset |
| [usecase/gnome-variants](usecase/gnome-variants/) | 유전체 변이 분석 |
| [usecase/security-traffic-analysis](usecase/security-traffic-analysis/) | 보안 트래픽 분석 플랫폼 |
| [usecase/json-explode-confluent-clickpipes](usecase/json-explode-confluent-clickpipes/) | 실시간 JSON explode: Confluent → ClickPipes → ClickHouse |
| [usecase/langfuse-ee](usecase/langfuse-ee/) | ClickHouse 기반 Langfuse 자체 호스팅 (OSS + Enterprise) |
| [usecase/langfuse-eval](usecase/langfuse-eval/) | Langfuse 프롬프트·데이터셋·실험·평가 |
| [usecase/mysql-prewhere](usecase/mysql-prewhere/) | MySQL 프로토콜에서의 `PREWHERE` 동작 |
| [usecase/mysql-protocol-benchmark](usecase/mysql-protocol-benchmark/) | MySQL vs ClickHouse 포인트 쿼리 성능 |

### 🔬 워크로드 (`workload/`)

| 실습 | 내용 |
|------|------|
| [workload/replacingmergetree](workload/replacingmergetree/) | `FINAL`, 머지 시점, `argMax` 대안 |
| [workload/dedup-engine](workload/dedup-engine/) | 중복 제거 엔진 비교 |
| [workload/delete-benchmark](workload/delete-benchmark/) | DELETE 메커니즘과 비용 |
| [workload/mv-vs-rmv](workload/mv-vs-rmv/) | MV vs RMV(갱신 구체화 뷰) |
| [workload/projection](workload/projection/) | 단일 정렬 키로 커버되지 않는 읽기 패턴용 프로젝션 |
| [workload/projection-customsettings](workload/projection-customsettings/) | 커스텀 설정에서의 프로젝션 동작 |
| [workload/index-granularity-point-query](workload/index-granularity-point-query/) | 인덱스 granularity와 포인트 쿼리 지연 |
| [workload/async-insert-stress](workload/async-insert-stress/) | 비동기 삽입 스트레스 테스트 |
| [workload/json-stress-test](workload/json-stress-test/) | `JSON` 타입 경로 한계: dynamic vs shared path 비용 |
| [workload/kafka-partitioning-ingestion](workload/kafka-partitioning-ingestion/) | Kafka 파티셔닝과 ClickHouse 정렬 키 정합 |
| [workload/rbac-workloadmanagement](workload/rbac-workloadmanagement/) | RBAC 및 워크로드 관리 |

### 🎓 워크숍 (`workshop/`)

| 실습 | 내용 |
|------|------|
| [workshop/device-360](workshop/device-360/) | Device360 PoC: 수십억 행 규모 Cloud 성능 검증 |
| [workshop/o11y-vector-ai](workshop/o11y-vector-ai/) | ClickStack·Vector·OpenTelemetry 기반 관측성 |
| [workshop/observability-waf](workshop/observability-waf/) | 멀티 클라우드 MSA 환경의 WAF 관측성 |

### 🛠 사전 요구사항

**공통**: macOS, Linux, 또는 WSL2 환경의 Windows · Docker 및 Docker Compose · 기본적인 커맨드라인 사용 경험

| 실습 유형 | 추가 요구사항 |
|-----------|---------------|
| 로컬 실습 | Docker Desktop, Python 3.8+ |
| 클라우드 실습 | Terraform, AWS CLI, AWS 계정 |
| ClickHouse Cloud 실습 | ClickHouse Cloud 계정 |
| 벤치마크 | `clickhouse-client`, 충분한 디스크 공간 |

### 🚀 시작하기

```bash
git clone https://github.com/litkhai/clickhouse-hols.git
cd clickhouse-hols
```

이후 실습을 하나 골라 해당 `README.md`를 읽고 빠른 시작을 따라가면 됩니다. 전역 설정은 없습니다 — 각 실습이 자체 설정과 정리 방법을 문서화합니다.

### 📖 학습 경로

**초급** → [local/oss-mac-setup](local/oss-mac-setup/) → [local/releases](local/releases/) → [tpcds](tpcds/)

**클라우드** → [chc/api/chc-api-test](chc/api/chc-api-test/) → [chc/s3/terraform-chc-secures3-aws](chc/s3/terraform-chc-secures3-aws/) → [chc/lake/terraform-glue-s3-chc-integration](chc/lake/terraform-glue-s3-chc-integration/)

**고급** → [chc/kafka/terraform-confluent-aws](chc/kafka/terraform-confluent-aws/) → [workload/replacingmergetree](workload/replacingmergetree/) → [chc/tool/costkeeper](chc/tool/costkeeper/)

### 🧱 실습 구성 관례

[local/releases](local/releases/)의 릴리스별 랩이 기준 레이아웃입니다.

| 파일 | 역할 |
|------|------|
| `README.md` | 영/한 가이드: 개요, 기능별 상세, 학습 포인트, 활용 사례 |
| `00-setup.sh` | 실습에 필요한 환경을 띄우고 검증 |
| `NN-<기능>.sh` | 대응 `.sql`을 `clickhouse-client`로 전달하는 얇은 실행 스크립트 |
| `NN-<기능>.sql` | 랩 본문: 배너 `SELECT`로 구분된 번호 섹션, 자체 생성 데이터, 확인을 위해 주석 처리된 정리 구문 |

이 관례보다 앞서 만들어진 실습들도 있어 구버전 디렉토리는 형태가 다릅니다. SQL만 있는 실습은 각 README에 안내된 순서대로 `clickhouse-client --queries-file <파일>`로 실행합니다.

### 🔐 자격증명

이 저장소는 **공개**입니다. 실제 엔드포인트·비밀번호·API 키를 커밋하지 마세요.

- `*.env.example` / `*.tfvars.example`을 실제 파일명으로 복사해 로컬에서 수정하세요. `.env`와 `*.tfvars`는 gitignore 처리돼 있습니다
- 스크립트는 접속 정보를 환경변수에서 읽고, 없으면 안내와 함께 종료합니다
- ClickHouse Cloud **API 키는 조직 전체 범위**입니다 — 최소 권한으로 제한하고, 노출된 적이 있다면 반드시 교체하세요

### ✅ 저장소 검사

push와 pull request마다 CI가 실행됩니다 ([`.github/workflows/checks.yml`](.github/workflows/checks.yml)).

| Job | 검사 내용 |
|-----|-----------|
| `links` | 모든 마크다운 상대 링크가 실제로 존재하는지 |
| `syntax` | 추적 중인 `.sh`, `.py`, `.yml` 전체 구문 |
| `shellcheck` | 셸 린트 (참고용, 차단하지 않음) |
| `secrets` | [`.gitleaks.toml`](.gitleaks.toml)의 ClickHouse 규칙으로 gitleaks 스캔 |
| `hygiene` | ignore 규칙에 가려진 추적 파일 없음, 코드에 `/Users/...` 경로 없음 |

동일한 검사를 로컬에서 실행하고, 클론마다 한 번 pre-commit 가드를 활성화하세요.

```bash
python3 .github/scripts/check_links.py
./.github/scripts/check_syntax.sh
gitleaks detect --config .gitleaks.toml --no-banner --redact

# 스테이징된 시크릿·호스트 절대경로·구문 오류를 차단
brew install gitleaks
git config core.hooksPath .githooks
```

GitHub 저장소의 **Settings → Code security → Push protection**도 켜두면, 훅이 설치되지 않은 환경에서도 push 시점에 시크릿이 차단됩니다.

### 🤝 기여

이슈와 풀 리퀘스트를 환영합니다.

### 📝 라이선스

MIT License — 실습별 라이선스 정보는 각 디렉토리를 참조하세요.

### 🌐 추가 자료

- [ClickHouse 공식 문서](https://clickhouse.com/docs)
- [ClickHouse Changelog](https://clickhouse.com/docs/whats-new/changelog)
- 한국어 자료: [clickhouse.kr](https://clickhouse.kr)
