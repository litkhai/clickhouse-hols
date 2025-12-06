# ClickHouse Cloud API Tester

ClickHouse Cloud API를 테스트하고 상세한 리포트를 생성하는 Python 도구입니다.

## 주요 기능

- ✅ **자동 인증 관리**: .env 파일을 통한 안전한 인증 정보 관리
- 📊 **포괄적인 API 테스트**: Billing, Services, Management API 테스트
- 📝 **상세한 리포트**: Swagger 문서 기반의 상세한 API 정보 포함
- 🗂️ **자동 파일 관리**: 최신 리포트만 유지하고 이전 리포트는 old 폴더로 이동
- 🔐 **보안**: .env 파일은 .gitignore에 포함되어 Git에 커밋되지 않음

## 설치

### 필수 요구사항

- Python 3.7 이상
- pip

### 의존성 설치

```bash
pip3 install requests python-dotenv
```

## 사용 방법

### 1. 초기 설정

처음 실행 시 API 인증 정보를 입력하라는 메시지가 나타납니다:

```bash
python3 apitest.py
```

프롬프트에서 다음 정보를 입력:
- API Key
- API Secret (Password)
- Organization ID
- Service ID

입력한 정보는 `.env` 파일에 자동으로 저장되며, 다음 실행부터는 자동으로 사용됩니다.

### 2. .env 파일 수동 생성 (선택사항)

`.env.example` 파일을 복사하여 `.env`를 생성할 수도 있습니다:

```bash
cp .env.example .env
```

그 후 `.env` 파일을 편집하여 실제 값을 입력합니다:

```bash
API_KEY=your_api_key_here
API_SECRET=your_api_secret_here
ORG_ID=your_organization_id_here
SERVICE_ID=your_service_id_here
```

### 3. 테스트 실행

```bash
python3 apitest.py
```

## 출력 파일

실행 후 다음과 같은 구조로 파일이 생성됩니다:

```
chc-api-test/
├── .env                    # 인증 정보 (Git에 커밋되지 않음)
├── .env.example            # .env 템플릿
├── apitest.py              # 메인 스크립트
├── result/
│   ├── clickhouse_api_report_YYYYMMDD_HHMMSS.md    # 최신 마크다운 리포트
│   ├── clickhouse_api_results_YYYYMMDD_HHMMSS.json # 최신 JSON 결과
│   └── old/                # 이전 리포트들
│       ├── clickhouse_api_report_*.md
│       └── clickhouse_api_results_*.json
```

## 테스트되는 API 엔드포인트

### Billing API
- `GET /organizations/{organizationId}/usageCost` - 사용량 비용 조회
  - 최근 30일
  - 최근 7일
  - 어제
- `GET /organizations/{organizationId}` - 조직 정보

### Services API
- `GET /organizations/{organizationId}/services/{serviceId}` - 서비스 상세 정보
- `GET /organizations/{organizationId}/services` - 서비스 목록

### Management API
- `GET /organizations/{organizationId}/services/{serviceId}/backups` - 백업 목록
- `GET /organizations/{organizationId}/keys` - API 키 목록
- `GET /organizations/{organizationId}/members` - 멤버 목록

## 리포트 내용

생성되는 마크다운 리포트에는 다음 정보가 포함됩니다:

1. **테스트 요약**: 성공/실패 통계
2. **API 엔드포인트 상세 정보**: Swagger 문서 기반 설명
   - 메서드, 경로, 설명
   - 파라미터 정보
   - 응답 필드 설명
3. **테스트 실행 결과**: 각 API 호출의 상세 결과
   - 상태 코드, 응답 시간
   - 요청 파라미터
   - 응답 데이터 샘플
4. **활용 권장사항**: 실제 사용 예제 코드
   - 비용 모니터링 자동화
   - 서비스 헬스 체크
   - 백업 모니터링
   - Cron 스케줄링 예제

## 활용 예제

### 일일 비용 모니터링

```python
from datetime import datetime, timedelta
from apitest import ClickHouseCloudAPITester

# 테스터 초기화
tester = ClickHouseCloudAPITester(api_key, api_secret, org_id, service_id)

# 어제 비용 확인
yesterday = datetime.now() - timedelta(days=1)
result = tester.make_request(
    "GET",
    f"/organizations/{org_id}/usageCost",
    params={
        "from_date": yesterday.strftime("%Y-%m-%d"),
        "to_date": yesterday.strftime("%Y-%m-%d")
    }
)

if result['success']:
    cost = result['response']['result']['grandTotalCHC']
    print(f"어제 비용: {cost} CHC")
```

### Cron으로 자동화

```bash
# 매일 오전 9시에 API 테스트 실행
0 9 * * * cd /path/to/chc-api-test && python3 apitest.py >> /var/log/clickhouse-api-test.log 2>&1
```

## API 인증 정보 얻기

1. [ClickHouse Cloud Console](https://console.clickhouse.cloud)에 로그인
2. **Settings** > **API Keys**로 이동
3. **Create new key** 클릭하여 새 API 키 생성
4. Organization ID와 Service ID는 Console URL에서 확인 가능

## 보안 고려사항

- `.env` 파일은 절대 Git에 커밋하지 마세요
- API 키는 정기적으로 로테이션하세요
- 최소 권한 원칙을 적용하여 필요한 권한만 부여하세요
- 프로덕션 환경에서는 환경 변수나 비밀 관리 서비스를 사용하세요

## 문제 해결

### ModuleNotFoundError: No module named 'dotenv'

```bash
pip3 install python-dotenv
```

### ModuleNotFoundError: No module named 'requests'

```bash
pip3 install requests
```

### API 인증 실패 (401 Unauthorized)

- `.env` 파일의 API 키와 시크릿이 정확한지 확인
- API 키가 활성화 상태인지 ClickHouse Cloud Console에서 확인
- API 키에 필요한 권한이 부여되어 있는지 확인

## 참고 링크

- [ClickHouse Cloud API 공식 문서](https://clickhouse.com/docs/cloud/manage/api/api-overview)
- [OpenAPI Specification (Swagger)](https://clickhouse.com/docs/cloud/manage/api/swagger)
- [Billing API 가이드](https://clickhouse.com/blog/announcing-billing-api-for-clickhouse-cloud-with-vantage-support)

## 라이선스

MIT License

## 기여

이슈나 풀 리퀘스트는 언제든 환영합니다!
