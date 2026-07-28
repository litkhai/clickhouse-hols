# ClickPipes S3 Checkpoint Test - 프로젝트 요약

## 📋 개요

이 프로젝트는 **ClickHouse Cloud ClickPipes의 S3 소스에 대한 Pause/Resume 기능의 체크포인트 동작**을 검증하기 위한 완전 자동화된 테스트 스위트입니다.

### 핵심 질문
> S3 ClickPipe를 Pause한 후 Resume하면, 중지 시점부터 이어서 인입하는가? 아니면 처음부터 다시 인입하는가?

## 🎯 제공하는 기능

### 1. 완전 자동화된 테스트
- S3 테스트 데이터 자동 생성 및 업로드 (12개 파일)
- ClickHouse 테이블 자동 생성
- ClickPipe 자동 생성 (API 또는 Terraform)
- Pause/Resume 테스트
- 자동 검증 및 리포트

### 2. 두 가지 ClickPipe 생성 방법
- **방법 A**: ClickHouse Cloud API (curl)
- **방법 B**: Terraform (Infrastructure as Code)

### 3. 상세한 검증 기능
- 중복 데이터 탐지
- 파일 인입 완전성 확인
- 시간대별 인입 분석
- Pause/Resume 전후 비교

## 📁 프로젝트 구조

```
clickpipes-s3/
├── 설정 파일
│   ├── .env.template                # 환경변수 템플릿
│   └── .gitignore                   # Git ignore
│
├── 문서
│   ├── README.md                    # 상세 문서
│   ├── QUICKSTART.md                # 빠른 시작 가이드
│   ├── SUMMARY.md                   # 이 파일
│   └── clickpipe-test-plan.md       # 원본 테스트 계획
│
├── 테스트 스크립트 (순서대로)
│   ├── 00-check-requirements.sh     # ✅ 환경 체크
│   ├── 01-setup-s3-data.sh          # 📦 S3 데이터 준비
│   ├── 02-setup-clickhouse-table.sh # 🗃️  테이블 생성
│   ├── 03-create-clickpipe.sh       # 🔗 Pipe 생성 (API)
│   ├── 03-create-clickpipe-terraform.sh # 🔗 Pipe 생성 (Terraform)
│   ├── 04-check-pipe-status.sh      # 📊 상태 확인
│   ├── 05-query-data.sh             # 🔍 데이터 조회
│   ├── 06-pause-pipe.sh             # ⏸️  일시정지
│   ├── 07-resume-pipe.sh            # ▶️  재시작
│   ├── 08-validate-checkpoint.sh    # ✔️  검증
│   └── 09-cleanup.sh                # 🧹 정리
│
├── 자동화
│   └── run-full-test.sh             # 🚀 전체 자동 실행
│
└── Terraform (IaC)
    ├── terraform/main.tf
    ├── terraform/variables.tf
    ├── terraform/terraform.tfvars.example
    └── terraform/README.md
```

## 🚀 사용 시나리오

### 시나리오 1: 빠른 검증 (5분)
```bash
# 1. 환경 설정
cp .env.template .env
nano .env  # 정보 입력

# 2. 요구사항 확인
./00-check-requirements.sh

# 3. 전체 자동 실행
./run-full-test.sh

# 4. 결과 확인 (자동)
# → ✅ 또는 ❌ 리포트 출력
```

### 시나리오 2: 단계별 실행 (제어 필요시)
```bash
# 각 스크립트를 순서대로 수동 실행
./01-setup-s3-data.sh
./02-setup-clickhouse-table.sh
./03-create-clickpipe.sh  # 또는 03-create-clickpipe-terraform.sh
# ... 이하 생략
```

### 시나리오 3: Terraform으로 인프라 관리
```bash
# 데이터 및 테이블 준비
./01-setup-s3-data.sh
./02-setup-clickhouse-table.sh

# Terraform으로 Pipe 생성
cd terraform
terraform init
terraform apply

# 기존 스크립트로 테스트
cd ..
./04-check-pipe-status.sh
./06-pause-pipe.sh
./07-resume-pipe.sh
./08-validate-checkpoint.sh

# Terraform으로 정리
cd terraform
terraform destroy
```

## 📊 검증 항목

### 1. 중복 데이터 확인
- 같은 파일이 여러 번 인입되었는지 검사
- 예상: 각 파일당 정확히 3행

### 2. 파일 완전성
- 12개 파일 모두 인입되었는지 확인
- 예상: 총 36행 (12 × 3)

### 3. 시간대별 분석
- Pause 전후 인입 패턴 분석
- 재시작 후 중복 없이 이어서 인입하는지 확인

## 🎯 예상 결과

### ✅ 성공 케이스
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

### ❌ 실패 케이스
```
⚠️  TESTS FAILED - Issues Detected

  ❌ Checkpointing does not work - duplicates found
     Customer must implement deduplication logic
     Consider using ReplacingMergeTree or similar
```

## 🔧 필수 도구

| 도구 | 용도 | 설치 방법 |
|------|------|-----------|
| AWS CLI | S3 접근 | `brew install awscli` |
| clickhouse-client | CH 접근 | `brew install clickhouse` |
| jq | JSON 파싱 | `brew install jq` |
| curl | API 호출 | 기본 설치 |
| terraform | IaC (선택) | `brew install terraform` |

## 📝 필요한 정보

### AWS
- Access Key ID / Secret Access Key
- S3 버킷 이름
- 리전

### ClickHouse Cloud
- Organization ID
- Service ID
- API Key
- 호스트 주소
- 사용자 이름 / 비밀번호

## ⏱️ 예상 소요 시간

| 단계 | 시간 |
|------|------|
| 환경 설정 | 2분 |
| S3 데이터 업로드 | 30초 |
| 테이블 생성 | 5초 |
| Pipe 생성 | 10초 |
| 초기 인입 대기 | 30초 |
| Pause 후 대기 | 1-2분 |
| Resume 후 완료 | 1분 |
| 검증 | 10초 |
| **총 소요 시간** | **약 4-5분** |

## 🎓 학습 포인트

### 이 프로젝트로 배울 수 있는 것:

1. **ClickPipes API 사용법**
   - REST API를 통한 Pipe 생성/관리
   - 상태 모니터링 및 제어

2. **Terraform + ClickHouse**
   - IaC로 ClickPipes 관리
   - 선언적 인프라 구성

3. **데이터 파이프라인 검증**
   - 체크포인트 메커니즘 이해
   - 중복 데이터 탐지 방법
   - 시계열 데이터 분석

4. **자동화 스크립트 작성**
   - Bash 스크립트 패턴
   - 에러 핸들링
   - 환경 변수 관리

## 💡 Pro Tips

1. **첫 실행**: 항상 `./00-check-requirements.sh`부터 시작
2. **반복 테스트**: `./09-cleanup.sh` 후 재실행 가능
3. **디버깅**: `.pipe_status_last.json` 파일 확인
4. **비용 절약**: 테스트 완료 후 반드시 리소스 정리
5. **실시간 모니터링**: `watch -n 5 ./04-check-pipe-status.sh`

## 📞 지원

- 📖 [README.md](README.md) - 상세 문서
- 🚀 [QUICKSTART.md](QUICKSTART.md) - 빠른 시작
- 🔧 [terraform/README.md](terraform/README.md) - Terraform 가이드
- 🌐 [ClickPipes API 문서](https://clickhouse.com/docs/integrations/clickpipes)

## 📄 라이센스

ClickHouse Cloud 기능 검증을 위한 내부 테스트 도구

---

**Ready to test?** → `./run-full-test.sh` 🚀
