# ClickPipes S3 Checkpoint Test Suite

S3 ClickPipe의 Pause/Resume 시 체크포인트 동작을 검증하기 위한 자동화된 테스트 스위트입니다.

## 테스트 목적

S3 Object Storage ClickPipe를 중지(Pause) 후 재시작(Resume)했을 때:
- ✅ 체크포인트가 기록되어 중지 시점부터 이어서 인입하는지
- ❌ 처음부터 다시 인입하여 중복 데이터가 발생하는지

를 확인하여 고객에게 명확한 답변을 제공합니다.

## 필수 요구사항

### 1. 환경 준비
- AWS CLI 설치 및 설정
- ClickHouse CLI 설치 (`clickhouse-client`)
- `jq` 설치 (JSON 파싱용)
- ClickHouse Cloud 서비스 (실행 중)
- (선택) Terraform 설치 (Terraform으로 ClickPipe를 생성하려는 경우)

### 2. 필요한 정보

#### AWS 정보
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` (optional)
- `AWS_REGION`
- S3 버킷 이름

#### ClickHouse Cloud 정보
- Organization ID
- Service ID
- API Key
- 호스트 주소 (예: `xxx.clickhouse.cloud`)
- 사용자 이름
- 비밀번호

## 설치 및 설정

### 1. .env 파일 생성

```bash
cp .env.template .env
```

### 2. .env 파일 편집

```bash
# .env 파일을 열어 실제 값으로 채우기
nano .env  # 또는 vi, code 등 원하는 에디터 사용
```

필수 항목:
```bash
# AWS Configuration
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here
AWS_REGION=us-east-1
AWS_S3_BUCKET=your-test-bucket-name

# ClickHouse Cloud Configuration
CHC_ORGANIZATION_ID=your_organization_id
CHC_SERVICE_ID=your_service_id
CHC_API_KEY=your_api_key_here
CHC_HOST=your-service.clickhouse.cloud
CHC_USER=default
CHC_PASSWORD=your_password_here
```

### 3. 요구사항 확인

```bash
./00-check-requirements.sh
```

이 스크립트는 다음을 확인합니다:
- 필수 도구 설치 여부 (AWS CLI, ClickHouse Client, jq)
- .env 파일 존재 및 필수 변수 설정
- AWS 자격증명 유효성
- S3 버킷 접근 권한
- ClickHouse 연결
- ClickPipes API 접근

### 4. 스크립트 실행 권한 부여

```bash
chmod +x *.sh
```

## 사용 방법

### 옵션 1: 전체 자동화 테스트 실행

```bash
./run-full-test.sh
```

이 스크립트는 전체 테스트 프로세스를 안내하며, 각 단계마다 확인을 요청합니다.

### 옵션 2: 단계별 수동 실행

#### Step 1: S3 테스트 데이터 생성
```bash
./01-setup-s3-data.sh
```
- 12개의 JSON 파일 생성 (6개월 × 2일)
- S3에 업로드 (파티션 구조 포함)

#### Step 2: ClickHouse 테이블 생성
```bash
./02-setup-clickhouse-table.sh
```
- `test_clickpipe_checkpoint` 테이블 생성
- `_file`, `_path`, `_time` 컬럼 포함 (추적용)

#### Step 3: ClickPipe 생성

**방법 A: ClickPipes API 사용 (기본)**
```bash
./03-create-clickpipe.sh
```

**방법 B: Terraform 사용 (선택)**
```bash
./03-create-clickpipe-terraform.sh
```

두 방법 모두:
- S3 → ClickHouse 파이프 생성
- 자동으로 데이터 인입 시작
- `.pipe_id` 파일에 Pipe ID 저장

#### Step 4: 상태 확인
```bash
./04-check-pipe-status.sh
```
- 파이프 상태 및 인입 통계 확인

#### Step 5: 데이터 조회
```bash
# 요약 보기
./05-query-data.sh summary

# 중복 확인
./05-query-data.sh duplicates

# 타임라인 보기
./05-query-data.sh timeline

# 전체 카운트
./05-query-data.sh count

# 모든 데이터
./05-query-data.sh all
```

#### Step 6: 파이프 일시정지
```bash
./06-pause-pipe.sh
```
- 파이프를 일시정지하고 현재 상태 기록

#### Step 7: 파이프 재시작
```bash
# 1-2분 대기 후 실행
./07-resume-pipe.sh
```
- 파이프를 재시작하고 인입 재개

#### Step 8: 체크포인트 검증
```bash
# 모든 데이터 인입이 완료된 후 실행
./08-validate-checkpoint.sh
```
- 중복 데이터 검사
- 파일 인입 완전성 확인
- Pause/Resume 타임라인 분석
- 최종 결과 리포트

#### Step 9: 정리
```bash
./09-cleanup.sh
```
- ClickPipe 삭제
- 테이블 삭제
- S3 데이터 삭제
- 로컬 임시 파일 정리

## 파일 구조

```
clickpipes-s3/
├── .env.template                    # 환경 변수 템플릿
├── .env                              # 실제 환경 변수 (생성 필요, git ignore됨)
├── .gitignore                        # Git ignore 설정
├── README.md                         # 이 파일
├── QUICKSTART.md                     # 빠른 시작 가이드
├── clickpipe-test-plan.md            # 원본 테스트 계획서
├── 00-check-requirements.sh          # 요구사항 확인
├── 01-setup-s3-data.sh               # S3 테스트 데이터 생성
├── 02-setup-clickhouse-table.sh      # ClickHouse 테이블 생성
├── 03-create-clickpipe.sh            # ClickPipe 생성 (API)
├── 03-create-clickpipe-terraform.sh  # ClickPipe 생성 (Terraform)
├── 04-check-pipe-status.sh           # 파이프 상태 확인
├── 05-query-data.sh                  # 데이터 조회 (여러 쿼리 타입 지원)
├── 06-pause-pipe.sh                  # 파이프 일시정지
├── 07-resume-pipe.sh                 # 파이프 재시작
├── 08-validate-checkpoint.sh         # 체크포인트 동작 검증
├── 09-cleanup.sh                     # 리소스 정리
├── run-full-test.sh                  # 전체 자동화 테스트
└── terraform/                        # Terraform 설정 파일들
    ├── main.tf
    ├── variables.tf
    ├── terraform.tfvars.example
    └── README.md
```

## 생성되는 임시 파일

테스트 실행 중 다음 파일들이 생성됩니다 (모두 .gitignore에 포함):
- `.pipe_id` - 생성된 ClickPipe의 ID
- `.pause_time` - 파이프 일시정지 시간 (UTC)
- `.resume_time` - 파이프 재시작 시간 (UTC)
- `.pipe_status_last.json` - 마지막 파이프 상태 (디버깅용)

## 예상 결과

### ✅ 체크포인트가 작동하는 경우
```
🎉 ✅ ALL TESTS PASSED!

Conclusion:
  - ClickPipes S3 successfully maintains checkpoints
  - Pause/Resume works without data duplication
  - All files were ingested exactly once

Customer Guidance:
  ✅ Safe to pause and resume S3 ClickPipes
  ✅ No deduplication logic needed in the table
  ✅ Checkpoint mechanism is reliable
```

### ❌ 체크포인트가 작동하지 않는 경우
```
⚠️  TESTS FAILED - Issues Detected

  ❌ Checkpointing does not work - duplicates found
     Customer must implement deduplication logic
     Consider using ReplacingMergeTree or similar
```

## 트러블슈팅

### AWS 권한 오류
- S3 버킷에 대한 읽기/쓰기 권한 확인
- IAM 정책에 `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` 권한 포함 필요

### ClickHouse 연결 오류
- 호스트 주소가 올바른지 확인 (`*.clickhouse.cloud` 형식)
- 비밀번호에 특수문자가 있다면 따옴표로 감싸기
- 방화벽에서 8443 포트가 열려있는지 확인

### ClickPipes API 오류
- API Key가 유효한지 확인
- Organization ID와 Service ID가 정확한지 확인
- [ClickHouse Cloud Console](https://clickhouse.cloud)에서 확인 가능

### jq 명령어 없음
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

## ClickPipes API 엔드포인트

테스트에서 사용하는 API 엔드포인트:

- **생성**: `POST /v1/organizations/{org_id}/services/{service_id}/clickpipes`
- **조회**: `GET /v1/organizations/{org_id}/services/{service_id}/clickpipes/{pipe_id}`
- **일시정지**: `POST /v1/organizations/{org_id}/services/{service_id}/clickpipes/{pipe_id}/pause`
- **재시작**: `POST /v1/organizations/{org_id}/services/{service_id}/clickpipes/{pipe_id}/resume`
- **삭제**: `DELETE /v1/organizations/{org_id}/services/{service_id}/clickpipes/{pipe_id}`

API 문서: https://clickhouse.com/docs/integrations/clickpipes

## 주의사항

1. **비용**: 테스트 실행 시 AWS S3 및 ClickHouse Cloud 사용료가 발생할 수 있습니다
2. **정리**: 테스트 완료 후 반드시 `./09-cleanup.sh`를 실행하여 리소스를 정리하세요
3. **동시 실행**: 같은 환경에서 여러 테스트를 동시에 실행하지 마세요
4. **데이터 보존**: 실제 프로덕션 환경에서는 테스트하지 마세요

## 라이센스

이 테스트 스위트는 ClickHouse Cloud 기능 검증을 위한 내부 도구입니다.

## 지원

문제가 발생하면 다음을 확인하세요:
1. `.env` 파일의 모든 값이 정확한지 확인
2. `04-check-pipe-status.sh`로 파이프 상태 확인
3. `.pipe_status_last.json` 파일에서 상세 에러 메시지 확인
4. ClickHouse Cloud Console에서 파이프 로그 확인

## License

[MIT](../../LICENSE) — same as the rest of the repository.
