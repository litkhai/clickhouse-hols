# ClickHouse Agentic AI & Vector Search in Observability

ClickHouse Vector Search와 Agentic AI를 활용한 Observability 데모 프로젝트입니다.

## 빠른 시작 🚀

```bash
# 1. .env 파일 생성 및 ClickHouse 정보 입력
cp .env.example .env
nano .env  # CLICKHOUSE_HOST, PASSWORD 등 수정

# 2. 스키마 생성 및 서비스 시작
python3 scripts/setup-clickhouse.py  # 스키마 생성
docker-compose up -d                  # 서비스 시작

# 3. 접속
open http://localhost:8000/docs
```

---

## 개요

이 프로젝트는 다음 기능을 제공합니다:

- **유사 에러 로그 검색**: Vector Index를 사용하여 과거 유사 에러 패턴 탐색
- **이상 트레이스 탐지**: Embedding 기반 정상/비정상 패턴 분류
- **OpenTelemetry 기반 데이터 수집**: Logs, Traces, Metrics 자동 수집

## 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS EC2 Instance                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │  Sample App     │  │  Data Generator │  │  Embedding      │ │
│  │  (FastAPI)      │  │  (Traffic Gen)  │  │  Pipeline       │ │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘ │
│           │                    │                    │           │
│           └────────────────────┼────────────────────┘           │
│                                ▼                                │
│                    ┌─────────────────────┐                      │
│                    │  OTEL Collector     │                      │
│                    └──────────┬──────────┘                      │
└───────────────────────────────┼─────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────┐
│                      ClickHouse Cloud                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐│
│  │ otel_logs    │  │ otel_traces  │  │ logs_with_embeddings     ││
│  └──────────────┘  └──────────────┘  └──────────────────────────┘│
│                                                                   │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │  traces_with_embeddings + Vector Index (usearch)             ││
│  └──────────────────────────────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────────┘
```

## 사전 요구사항

### 로컬 개발 환경
- Docker & Docker Compose
- Python 3.11+
- ClickHouse CLI (선택사항)

### 클라우드 리소스
- AWS 계정 (EC2 배포용)
- ClickHouse Cloud 인스턴스

## 빠른 시작 (로컬)

### 방법 1: 자동 설정 스크립트 (추천) ⚡

```bash
./quick-start.sh
```

스크립트가 다음을 자동으로 수행합니다:
1. ClickHouse Cloud 연결 정보 입력 받기
2. 연결 테스트
3. `.env` 파일 자동 생성
4. 다음 단계 안내

### 방법 2: 전체 자동 배포

Quick Start 후 바로 배포:
```bash
./quick-start.sh    # 1단계: 환경 설정
./scripts/deploy.sh # 2단계: 자동 배포
```

`deploy.sh`가 자동으로:
- ClickHouse 스키마 생성
- Docker 컨테이너 빌드 및 시작
- 서비스 상태 확인

### 방법 3: 수동 설정 (고급)

<details>
<summary>수동으로 단계별 설정하기 (클릭하여 펼치기)</summary>

#### 1. 환경 변수 설정

```bash
cp .env.example .env
nano .env  # 또는 원하는 에디터
```

`.env` 파일에 ClickHouse Cloud 정보 입력:
```bash
CLICKHOUSE_HOST=your-instance.clickhouse.cloud
CLICKHOUSE_PORT=8443
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=your-password
CLICKHOUSE_DB=o11y
CLICKHOUSE_SECURE=true
```

#### 2. ClickHouse 스키마 생성

```bash
cd scripts
./setup-clickhouse.sh
cd ..
```

#### 3. 서비스 시작

```bash
docker-compose up -d
```

</details>

### 서비스 확인

배포 완료 후 다음 URL로 접속:
- **Sample App**: http://localhost:8000
- **Sample App API Docs**: http://localhost:8000/docs
- **Sample App Health**: http://localhost:8000/health

로그 확인:
```bash
docker-compose logs -f                # 전체 로그
docker-compose logs -f sample-app     # Sample App만
docker-compose logs -f otel-collector # OTEL Collector만
```

## AWS EC2 배포

### 1. Terraform 설정

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` 파일 수정:
```hcl
aws_region = "ap-northeast-2"
environment = "demo"

# User-defined Tags
user_name    = "Your Name"
user_contact = "your.email@example.com"
application  = "o11y-vector-ai-demo"
end_date     = "2025-12-31"

# Network Configuration
vpc_id    = "vpc-xxxxxxxxx"
subnet_id = "subnet-xxxxxxxxx"

# EC2 Configuration
ami_id        = "ami-086cae3329a3f7d75"  # Ubuntu 22.04 in Seoul
instance_type = "t3.large"

# SSH Configuration
ssh_public_key = "ssh-rsa AAAAB3Nza... your-key"

# ClickHouse Cloud Configuration
clickhouse_host = "your-instance.clickhouse.cloud"
clickhouse_user = "default"
clickhouse_db   = "o11y"
```

### 2. 환경 변수 설정

민감한 정보는 환경 변수로 설정:
```bash
export TF_VAR_clickhouse_password="your-clickhouse-password"
export TF_VAR_openai_api_key="your-openai-api-key"
```

### 3. AWS 인증

```bash
# AWS Configure 사용
aws configure

# 또는 환경 변수
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_SESSION_TOKEN="your-session-token"  # 필요시
```

### 4. Terraform 배포

```bash
cd scripts
./terraform-deploy.sh
```

### 5. EC2 인스턴스 접속 및 설정

```bash
# Terraform output에서 표시된 SSH 명령어 사용
ssh -i your-private-key.pem ubuntu@<EC2-PUBLIC-IP>

# EC2에서 설정 스크립트 실행
cd /home/ubuntu/o11y-vector-ai
./scripts/setup-ec2.sh
```

## 프로젝트 구조

```
o11y-vector-ai/
├── README.md
├── .env.example                    # 환경 변수 템플릿
├── .gitignore
├── docker-compose.yml              # 로컬 Docker Compose 설정
│
├── terraform/                      # AWS 인프라 코드
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── user-data.sh
│   └── terraform.tfvars.example
│
├── clickhouse/                     # ClickHouse 스키마 및 쿼리
│   ├── schemas/
│   │   ├── 01_otel_tables.sql     # OTEL 기본 테이블
│   │   └── 02_vector_tables.sql   # Vector Search 테이블
│   └── queries/
│       ├── similar_error_search.sql
│       └── anomaly_detection.sql
│
├── sample-app/                     # FastAPI E-commerce 샘플 앱
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py
│   └── otel_config.py
│
├── data-generator/                 # 트래픽 생성기
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── generator.py
│   └── config.yaml
│
├── embedding-pipeline/             # Embedding 처리 파이프라인
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── batch_processor.py
│   └── config.yaml
│
├── hyperdx/                        # HyperDX 및 OTEL Collector 설정
│   └── otel-collector-config.yaml
│
└── scripts/                        # 배포 및 설정 스크립트
    ├── setup-clickhouse.sh
    ├── deploy.sh
    ├── terraform-deploy.sh
    └── setup-ec2.sh
```

## Vector Search 쿼리 예시

### 유사 에러 검색

```sql
WITH current_error AS (
    SELECT embedding
    FROM o11y.logs_with_embeddings
    WHERE TraceId = 'your-trace-id'
    LIMIT 1
)
SELECT
    l.Timestamp,
    l.ServiceName,
    l.Body,
    cosineDistance(l.embedding, ce.embedding) AS distance
FROM o11y.logs_with_embeddings l
CROSS JOIN current_error ce
WHERE l.SeverityText = 'ERROR'
    AND cosineDistance(l.embedding, ce.embedding) < 0.3
ORDER BY distance ASC
LIMIT 10;
```

### 이상 트레이스 탐지

```sql
WITH normal_centroid AS (
    SELECT arrayMap(i -> avg(embedding[i]), range(1, 1537)) AS centroid
    FROM o11y.traces_with_embeddings
    WHERE is_anomaly = 0
)
SELECT
    TraceId,
    span_sequence,
    total_duration,
    error_count,
    cosineDistance(embedding, nc.centroid) AS anomaly_score
FROM o11y.traces_with_embeddings t, normal_centroid nc
WHERE Timestamp > now() - INTERVAL 10 MINUTE
ORDER BY anomaly_score DESC
LIMIT 20;
```


## 문제 해결

### ClickHouse 연결 오류

```bash
# 연결 테스트
clickhouse client \
    --host="your-instance.clickhouse.cloud" \
    --port=8443 \
    --user=default \
    --password="your-password" \
    --secure \
    --query="SELECT 1"
```

### Docker 컨테이너 로그 확인

```bash
# 모든 서비스 로그
docker-compose logs -f

# 특정 서비스 로그
docker-compose logs -f sample-app
docker-compose logs -f data-generator
docker-compose logs -f embedding-pipeline
```

### OTEL Collector 상태 확인

```bash
# Metrics 확인
curl http://localhost:8888/metrics
```

## 정리

### 로컬 환경

```bash
docker-compose down -v
```

### AWS 리소스

```bash
cd terraform
terraform destroy
```

## 예상 비용

- **AWS EC2 (t3.large)**: ~$60/월
- **ClickHouse Cloud (Development)**: ~$200/월 (데모 기간만 사용)
- **OpenAI Embeddings (ada-002)**: ~$10-20 (데모 데이터 기준)

**데모 기간(1-2주) 총 예상 비용**: ~$100 이내

## 보안 고려사항

- `.env` 파일은 절대 Git에 커밋하지 마세요
- Terraform 상태 파일에 민감한 정보가 포함될 수 있으므로 주의
- EC2 보안 그룹에서 SSH 접근을 특정 IP로 제한하세요
- 사용 후 모든 리소스를 정리하세요

## 라이선스

이 프로젝트는 데모 목적으로 제공됩니다.

## 참고 자료

- [ClickHouse Vector Search Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/annindexes)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [HyperDX](https://www.hyperdx.io/)
