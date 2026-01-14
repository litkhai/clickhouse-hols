# Terraform으로 ClickPipe 생성하기

이 디렉토리는 Terraform을 사용하여 ClickPipe를 생성하는 방법을 제공합니다.

## 필수 요구사항

- Terraform >= 1.0
- ClickHouse Terraform Provider

## 설정 방법

### 1. Terraform 설치

```bash
# macOS
brew install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

### 2. 변수 파일 생성

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 3. terraform.tfvars 편집

```bash
nano terraform.tfvars
```

필수 값 입력:
```hcl
organization_id = "your-org-id"
service_id      = "your-service-id"
api_key         = "your-api-key"
s3_bucket       = "your-bucket"
aws_region      = "us-east-1"
aws_access_key_id     = "AKIA..."
aws_secret_access_key = "..."
```

## 사용 방법

### 초기화

```bash
terraform init
```

### 계획 확인

```bash
terraform plan
```

### ClickPipe 생성

```bash
terraform apply
```

출력 예시:
```
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

pipe_id = "12345678-1234-1234-1234-123456789abc"
pipe_status = "running"
```

### Pipe ID 저장 (부모 디렉토리 스크립트와 연동)

```bash
terraform output -raw pipe_id > ../.pipe_id
```

이제 부모 디렉토리의 스크립트들을 사용할 수 있습니다:
```bash
cd ..
./04-check-pipe-status.sh
./05-query-data.sh summary
./06-pause-pipe.sh
./07-resume-pipe.sh
./08-validate-checkpoint.sh
```

### ClickPipe 삭제

```bash
terraform destroy
```

## 통합 워크플로우

Terraform으로 Pipe를 생성하고 기존 스크립트로 테스트:

```bash
# 1. S3 데이터 생성 (부모 디렉토리에서)
cd ..
./01-setup-s3-data.sh
./02-setup-clickhouse-table.sh

# 2. Terraform으로 Pipe 생성
cd terraform
terraform init
terraform apply
terraform output -raw pipe_id > ../.pipe_id

# 3. 기존 테스트 스크립트 사용
cd ..
./04-check-pipe-status.sh
./05-query-data.sh count

# 4. Pause/Resume 테스트
./06-pause-pipe.sh
# (1-2분 대기)
./07-resume-pipe.sh

# 5. 검증
./08-validate-checkpoint.sh

# 6. 정리
cd terraform
terraform destroy
cd ..
./09-cleanup.sh
```

## 파일 구조

```
terraform/
├── main.tf                    # Terraform 리소스 정의
├── variables.tf               # 변수 정의
├── terraform.tfvars.example   # 변수 예시 파일
├── .gitignore                 # Git ignore 설정
└── README.md                  # 이 파일
```

## 트러블슈팅

### Provider 설치 오류

```bash
terraform init -upgrade
```

### 인증 오류

- Organization ID와 Service ID가 정확한지 확인
- API Key가 유효한지 확인 (ClickHouse Cloud Console에서 생성)

### State 파일 관리

로컬에서 테스트 중이므로 state 파일은 로컬에 저장됩니다.
프로덕션에서는 S3 backend 사용을 권장합니다.

## 참고

- ClickHouse Terraform Provider: https://registry.terraform.io/providers/ClickHouse/clickhouse
- ClickHouse Cloud API: https://clickhouse.com/docs/en/cloud/manage/api/clickpipes
