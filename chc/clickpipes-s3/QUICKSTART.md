# ClickPipes S3 Checkpoint Test - Quick Start Guide

## 🚀 빠른 시작 (5분)

### 1단계: 환경 설정 (1분)

```bash
# 1. .env 파일 생성
cp .env.template .env

# 2. .env 파일 편집 (필수 정보 입력)
nano .env
```

**최소 필수 정보:**
```bash
# AWS
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
AWS_REGION=us-east-1
AWS_S3_BUCKET=your-bucket

# ClickHouse Cloud
CHC_ORGANIZATION_ID=your_org_id
CHC_SERVICE_ID=your_service_id
CHC_API_KEY=your_api_key
CHC_HOST=xxx.clickhouse.cloud
CHC_USER=default
CHC_PASSWORD=your_password
```

### 2단계: 전체 자동화 테스트 실행 (4분)

```bash
./run-full-test.sh
```

이 스크립트는 다음을 자동으로 수행합니다:
1. ✅ S3에 12개의 테스트 파일 업로드
2. ✅ ClickHouse 테이블 생성
3. ✅ ClickPipe 생성 및 데이터 인입 시작
4. ⏸️  일부 파일 인입 후 Pause
5. ▶️  1-2분 대기 후 Resume
6. 🔍 중복 데이터 여부 검증

### 3단계: 결과 확인

스크립트가 완료되면 다음과 같은 결과를 확인할 수 있습니다:

**✅ 성공 케이스:**
```
🎉 ✅ ALL TESTS PASSED!
  - ClickPipes S3 successfully maintains checkpoints
  - Pause/Resume works without data duplication
```

**❌ 실패 케이스:**
```
⚠️  TESTS FAILED - Issues Detected
  - Checkpointing does not work - duplicates found
```

### 4단계: 리소스 정리

```bash
./09-cleanup.sh
```

---

## 📋 수동 실행 (상세 제어가 필요한 경우)

### 기본 흐름

```bash
# 1. S3 데이터 준비
./01-setup-s3-data.sh

# 2. 테이블 생성
./02-setup-clickhouse-table.sh

# 3. ClickPipe 생성
./03-create-clickpipe.sh

# 4. 상태 모니터링
./04-check-pipe-status.sh

# 5. 데이터 확인
./05-query-data.sh count

# 6. 일시정지
./06-pause-pipe.sh

# 7. 재시작 (1-2분 후)
./07-resume-pipe.sh

# 8. 검증
./08-validate-checkpoint.sh

# 9. 정리
./09-cleanup.sh
```

### 유용한 명령어

```bash
# 다양한 쿼리 실행
./05-query-data.sh summary      # 파일별 인입 현황
./05-query-data.sh duplicates   # 중복 확인
./05-query-data.sh timeline     # 시간대별 인입
./05-query-data.sh count        # 전체 카운트
./05-query-data.sh all          # 모든 데이터

# 파이프 상태 실시간 확인
watch -n 5 ./04-check-pipe-status.sh
```

---

## 🔧 트러블슈팅

### "Command not found: jq"
```bash
# macOS
brew install jq

# Linux
sudo apt-get install jq  # Debian/Ubuntu
sudo yum install jq      # CentOS/RHEL
```

### "Command not found: clickhouse-client"
```bash
# macOS
brew install clickhouse

# Linux
curl https://clickhouse.com/ | sh
```

### AWS 권한 오류
- S3 버킷에 대한 읽기/쓰기 권한 확인
- IAM 정책에 `s3:*` 또는 최소한 `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` 필요

### ClickHouse 연결 오류
- 호스트 주소 형식: `xxx.clickhouse.cloud` (https:// 제외)
- 포트 8443이 방화벽에서 열려있는지 확인
- 비밀번호에 특수문자가 있으면 `.env` 파일에서 따옴표로 감싸기

---

## 📊 예상 테스트 시간

| 단계 | 예상 시간 |
|------|-----------|
| S3 데이터 업로드 | 30초 |
| 테이블 생성 | 5초 |
| ClickPipe 생성 | 10초 |
| 초기 인입 대기 | 30초 |
| Pause 후 대기 | 1-2분 |
| Resume 후 인입 완료 | 1분 |
| 검증 | 10초 |
| **전체 소요 시간** | **약 4-5분** |

---

## 💡 팁

1. **첫 실행**: `run-full-test.sh`를 사용하여 전체 프로세스를 먼저 경험해보세요
2. **반복 테스트**: 각 단계를 수동으로 실행하면 더 세밀한 제어가 가능합니다
3. **로그 확인**: `.pipe_status_last.json` 파일에서 API 응답 상세 정보를 확인할 수 있습니다
4. **비용 절약**: 테스트 완료 후 반드시 `./09-cleanup.sh`를 실행하세요

---

## 📞 도움이 필요하신가요?

- 📖 상세 문서: [README.md](README.md)
- 📝 원본 계획서: [clickpipe-test-plan.md](clickpipe-test-plan.md)
- 🔍 API 문서: https://clickhouse.com/docs/integrations/clickpipes

---

**준비 완료!** 이제 `./run-full-test.sh`를 실행하여 테스트를 시작하세요! 🚀
