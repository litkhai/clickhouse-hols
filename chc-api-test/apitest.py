import requests
import json
import time
import os
import shutil
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Any
import base64
from dotenv import load_dotenv

class ClickHouseCloudAPITester:
    """ClickHouse Cloud API 테스터 클래스"""

    # API 엔드포인트 상세 정보 (Swagger 문서 기반)
    API_ENDPOINTS = {
        "billing": {
            "usageCost": {
                "method": "GET",
                "path": "/organizations/{organizationId}/usageCost",
                "description": "조직의 사용량 및 비용 데이터를 조회합니다. 최대 31일 기간의 일별 비용 정보를 반환합니다.",
                "parameters": {
                    "from_date": "시작 날짜 (YYYY-MM-DD 형식, 필수)",
                    "to_date": "종료 날짜 (YYYY-MM-DD 형식, 필수, from_date로부터 최대 30일)"
                },
                "response": {
                    "grandTotalCHC": "전체 비용 (ClickHouse Credits)",
                    "costs": "일별/엔티티별 비용 상세 정보 배열"
                }
            },
            "organization": {
                "method": "GET",
                "path": "/organizations/{organizationId}",
                "description": "조직의 기본 정보를 조회합니다.",
                "parameters": {},
                "response": {
                    "id": "조직 ID",
                    "name": "조직 이름",
                    "createdAt": "생성 일시",
                    "privateEndpoints": "프라이빗 엔드포인트 목록"
                }
            }
        },
        "services": {
            "getService": {
                "method": "GET",
                "path": "/organizations/{organizationId}/services/{serviceId}",
                "description": "특정 서비스의 상세 정보를 조회합니다.",
                "parameters": {},
                "response": {
                    "id": "서비스 ID",
                    "name": "서비스 이름",
                    "provider": "클라우드 제공자 (aws, gcp, azure)",
                    "region": "리전",
                    "state": "서비스 상태 (running, stopped, idle 등)",
                    "endpoints": "엔드포인트 정보 배열"
                }
            },
            "listServices": {
                "method": "GET",
                "path": "/organizations/{organizationId}/services",
                "description": "조직의 모든 서비스 목록을 조회합니다.",
                "parameters": {},
                "response": "서비스 객체 배열"
            }
        },
        "management": {
            "backups": {
                "method": "GET",
                "path": "/organizations/{organizationId}/services/{serviceId}/backups",
                "description": "서비스의 백업 목록을 조회합니다.",
                "parameters": {},
                "response": {
                    "id": "백업 ID",
                    "status": "백업 상태 (done, in_progress, failed 등)",
                    "startedAt": "백업 시작 시간",
                    "finishedAt": "백업 완료 시간",
                    "sizeInBytes": "백업 크기"
                }
            },
            "keys": {
                "method": "GET",
                "path": "/organizations/{organizationId}/keys",
                "description": "조직의 API 키 목록을 조회합니다.",
                "parameters": {},
                "response": {
                    "id": "키 ID",
                    "name": "키 이름",
                    "keySuffix": "키의 마지막 4자리",
                    "roles": "권한 역할 배열",
                    "state": "키 상태 (enabled, disabled)",
                    "createdAt": "생성 일시",
                    "usedAt": "마지막 사용 일시"
                }
            },
            "members": {
                "method": "GET",
                "path": "/organizations/{organizationId}/members",
                "description": "조직의 멤버 목록을 조회합니다.",
                "parameters": {},
                "response": {
                    "userId": "사용자 ID",
                    "name": "사용자 이름",
                    "email": "이메일",
                    "role": "역할 (admin, developer 등)",
                    "joinedAt": "가입 일시"
                }
            }
        }
    }

    def __init__(self, api_key: str, password: str, org_id: str, service_id: str):
        self.api_key = api_key
        self.password = password
        self.org_id = org_id
        self.service_id = service_id
        self.base_url = "https://api.clickhouse.cloud/v1"
        # ClickHouse Cloud는 Basic Auth 사용
        credentials = base64.b64encode(f"{api_key}:{password}".encode()).decode()
        self.headers = {
            "Authorization": f"Basic {credentials}",
            "Content-Type": "application/json"
        }
        self.test_results = []
        self.start_time = datetime.now()

    def make_request(self, method: str, endpoint: str, params: Dict = None) -> Dict[str, Any]:
        """API 요청 실행 및 결과 수집"""
        url = f"{self.base_url}{endpoint}"
        start = time.time()

        try:
            if method.upper() == "GET":
                response = requests.get(url, headers=self.headers, params=params, timeout=30)
            elif method.upper() == "POST":
                response = requests.post(url, headers=self.headers, json=params, timeout=30)
            else:
                raise ValueError(f"Unsupported method: {method}")

            elapsed = time.time() - start

            result = {
                "endpoint": endpoint,
                "method": method,
                "status_code": response.status_code,
                "response_time": f"{elapsed:.2f}s",
                "success": response.status_code == 200,
                "params": params,
                "response": response.json() if response.status_code == 200 else response.text,
                "timestamp": datetime.now().isoformat()
            }

        except Exception as e:
            elapsed = time.time() - start
            result = {
                "endpoint": endpoint,
                "method": method,
                "status_code": "ERROR",
                "response_time": f"{elapsed:.2f}s",
                "success": False,
                "params": params,
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }

        self.test_results.append(result)
        return result

    def test_billing_apis(self):
        """빌링 관련 API 테스트"""
        print("\n=== 빌링 API 테스트 시작 ===\n")

        # 1. 최근 30일 사용량 비용 조회
        print("1. 최근 30일 사용량 비용 조회...")
        end_date = datetime.now()
        start_date = end_date - timedelta(days=30)
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/usageCost",
            params={
                "from_date": start_date.strftime("%Y-%m-%d"),
                "to_date": end_date.strftime("%Y-%m-%d")
            }
        )
        self._print_result(result)

        # 2. 최근 7일 사용량 비용 조회
        print("\n2. 최근 7일 사용량 비용 조회...")
        start_date = end_date - timedelta(days=7)
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/usageCost",
            params={
                "from_date": start_date.strftime("%Y-%m-%d"),
                "to_date": end_date.strftime("%Y-%m-%d")
            }
        )
        self._print_result(result)

        # 3. 어제 하루 사용량 비용 조회
        print("\n3. 어제 하루 사용량 비용 조회...")
        yesterday = end_date - timedelta(days=1)
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/usageCost",
            params={
                "from_date": yesterday.strftime("%Y-%m-%d"),
                "to_date": yesterday.strftime("%Y-%m-%d")
            }
        )
        self._print_result(result)

        # 4. 조직 정보 조회
        print("\n4. 조직 정보 조회...")
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}"
        )
        self._print_result(result)

    def test_monitoring_apis(self):
        """모니터링 관련 API 테스트"""
        print("\n=== 모니터링 API 테스트 시작 ===\n")

        # 1. 서비스 상태 조회
        print("1. 서비스 상태 조회...")
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/services/{self.service_id}"
        )
        self._print_result(result)

        # 2. 서비스 목록 조회
        print("\n2. 조직의 모든 서비스 조회...")
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/services"
        )
        self._print_result(result)

    def test_service_management_apis(self):
        """서비스 관리 관련 API 테스트"""
        print("\n=== 서비스 관리 API 테스트 시작 ===\n")

        # 1. 백업 목록 조회
        print("1. 백업 목록 조회...")
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/services/{self.service_id}/backups"
        )
        self._print_result(result)

        # 2. 조직 API 키 목록 조회
        print("\n2. 조직 API 키 목록 조회...")
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/keys"
        )
        self._print_result(result)

        # 3. 조직 멤버 목록 조회
        print("\n3. 조직 멤버 목록 조회...")
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/members"
        )
        self._print_result(result)

    def _print_result(self, result: Dict[str, Any]):
        """결과 출력"""
        status = "✓ SUCCESS" if result["success"] else "✗ FAILED"
        print(f"{status} [{result['status_code']}] - {result['response_time']}")

        if result["success"]:
            response = result["response"]
            if isinstance(response, dict):
                print(f"Response keys: {list(response.keys())}")
                # 주요 정보만 출력
                if "result" in response:
                    print(f"Result preview: {str(response['result'])[:200]}...")
            else:
                print(f"Response: {str(response)[:200]}...")
        else:
            print(f"Error: {result.get('error', result.get('response', 'Unknown error'))}")

    def _get_endpoint_info(self, endpoint: str) -> Dict[str, Any]:
        """엔드포인트 정보 조회"""
        for category, endpoints in self.API_ENDPOINTS.items():
            for name, info in endpoints.items():
                if info["path"].replace("{organizationId}", self.org_id).replace("{serviceId}", self.service_id) in endpoint:
                    return {
                        "category": category,
                        "name": name,
                        "info": info
                    }
        return None

    def generate_report(self) -> str:
        """상세 종합 리포트 생성"""
        end_time = datetime.now()
        total_time = (end_time - self.start_time).total_seconds()

        successful_tests = sum(1 for r in self.test_results if r["success"])
        failed_tests = len(self.test_results) - successful_tests

        report = f"""# ClickHouse Cloud API 테스트 상세 리포트

**생성 일시:** {end_time.strftime("%Y-%m-%d %H:%M:%S")}
**총 소요 시간:** {total_time:.2f}초
**Organization ID:** `{self.org_id}`
**Service ID:** `{self.service_id}`

---

## 📊 테스트 요약

| 항목 | 값 |
|------|-----|
| **총 테스트 수** | {len(self.test_results)} |
| **성공** | {successful_tests} ✓ |
| **실패** | {failed_tests} ✗ |
| **성공률** | {(successful_tests/len(self.test_results)*100):.1f}% |

---

## 🔍 API 엔드포인트 상세 정보

### Billing API

"""

        # Billing API 설명
        for name, info in self.API_ENDPOINTS["billing"].items():
            report += f"""
#### {name}

- **메서드:** `{info['method']}`
- **경로:** `{info['path']}`
- **설명:** {info['description']}
- **파라미터:**
"""
            if info['parameters']:
                for param, desc in info['parameters'].items():
                    report += f"  - `{param}`: {desc}\n"
            else:
                report += "  - 없음\n"

            report += "- **응답 필드:**\n"
            if isinstance(info['response'], dict):
                for field, desc in info['response'].items():
                    report += f"  - `{field}`: {desc}\n"
            else:
                report += f"  - {info['response']}\n"

        report += "\n### Services API\n"
        for name, info in self.API_ENDPOINTS["services"].items():
            report += f"""
#### {name}

- **메서드:** `{info['method']}`
- **경로:** `{info['path']}`
- **설명:** {info['description']}
- **응답 필드:**
"""
            if isinstance(info['response'], dict):
                for field, desc in info['response'].items():
                    report += f"  - `{field}`: {desc}\n"
            else:
                report += f"  - {info['response']}\n"

        report += "\n### Management API\n"
        for name, info in self.API_ENDPOINTS["management"].items():
            report += f"""
#### {name}

- **메서드:** `{info['method']}`
- **경로:** `{info['path']}`
- **설명:** {info['description']}
- **응답 필드:**
"""
            if isinstance(info['response'], dict):
                for field, desc in info['response'].items():
                    report += f"  - `{field}`: {desc}\n"
            else:
                report += f"  - {info['response']}\n"

        report += """
---

## 📝 테스트 실행 결과

"""

        # 카테고리별로 그룹화
        categories = {
            "빌링 API": [],
            "모니터링 API": [],
            "서비스 관리 API": []
        }

        for result in self.test_results:
            if "usageCost" in result["endpoint"] or (result["endpoint"].endswith(self.org_id)):
                categories["빌링 API"].append(result)
            elif "services" in result["endpoint"] and "backups" not in result["endpoint"]:
                categories["모니터링 API"].append(result)
            else:
                categories["서비스 관리 API"].append(result)

        for category, results in categories.items():
            if not results:
                continue

            report += f"\n### {category}\n\n"

            for i, result in enumerate(results, 1):
                status = "✓" if result["success"] else "✗"
                report += f"""
#### {i}. {result['method']} `{result['endpoint']}`

| 항목 | 값 |
|------|-----|
| **상태** | {status} {result['status_code']} |
| **응답 시간** | {result['response_time']} |
| **실행 시각** | {result['timestamp']} |
"""

                if result.get("params"):
                    report += f"\n**파라미터:**\n```json\n{json.dumps(result['params'], indent=2, ensure_ascii=False)}\n```\n"

                if result["success"]:
                    response = result["response"]
                    if isinstance(response, dict):
                        report += f"\n**응답 키:** `{list(response.keys())}`\n"
                        if "result" in response:
                            result_data = response['result']
                            if isinstance(result_data, dict):
                                report += f"\n**응답 데이터 샘플:**\n```json\n{json.dumps(result_data, indent=2, ensure_ascii=False)[:500]}...\n```\n"
                            elif isinstance(result_data, list) and len(result_data) > 0:
                                report += f"\n**응답 데이터 샘플 (첫 번째 항목):**\n```json\n{json.dumps(result_data[0], indent=2, ensure_ascii=False)[:500]}...\n```\n"
                                report += f"\n**총 항목 수:** {len(result_data)}\n"
                else:
                    error_msg = result.get('error', result.get('response', 'Unknown'))
                    report += f"\n**에러 메시지:**\n```\n{error_msg}\n```\n"

                report += "\n---\n"

        # 권장사항 추가
        report += """
## 💡 활용 권장사항

### 1. 비용 모니터링 자동화

```python
# 일일 비용 체크 스크립트 예제
from datetime import datetime, timedelta

def check_daily_cost():
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
        if cost > THRESHOLD:
            send_alert(f"비용 초과 경고: {cost} CHC")
```

### 2. 서비스 헬스 체크

```python
def health_check():
    result = tester.make_request(
        "GET",
        f"/organizations/{org_id}/services/{service_id}"
    )

    if result['success']:
        state = result['response']['result']['state']
        if state != 'running':
            send_alert(f"서비스 상태 이상: {state}")
```

### 3. 백업 모니터링

```python
def check_backups():
    result = tester.make_request(
        "GET",
        f"/organizations/{org_id}/services/{service_id}/backups"
    )

    if result['success']:
        backups = result['response']['result']
        recent_backup = backups[0] if backups else None
        if recent_backup:
            backup_time = datetime.fromisoformat(recent_backup['startedAt'].replace('Z', '+00:00'))
            if (datetime.now(timezone.utc) - backup_time).days > 1:
                send_alert("최근 백업이 24시간 이상 경과")
```

### 4. 스케줄링 예제 (cron)

```bash
# 매일 오전 9시에 일일 비용 체크
0 9 * * * cd /path/to/script && python3 apitest.py --daily-cost

# 매 시간마다 서비스 헬스 체크
0 * * * * cd /path/to/script && python3 apitest.py --health-check
```

---

## 🔗 참고 링크

- [ClickHouse Cloud API 공식 문서](https://clickhouse.com/docs/cloud/manage/api/api-overview)
- [OpenAPI Specification (Swagger)](https://clickhouse.com/docs/cloud/manage/api/swagger)
- [Billing API 가이드](https://clickhouse.com/blog/announcing-billing-api-for-clickhouse-cloud-with-vantage-support)

---

**리포트 생성 완료** - {end_time.strftime("%Y-%m-%d %H:%M:%S")}
"""

        return report

    def run_all_tests(self):
        """모든 테스트 실행"""
        print("=" * 60)
        print("ClickHouse Cloud API 종합 테스트 시작")
        print("=" * 60)

        self.test_billing_apis()
        self.test_monitoring_apis()
        self.test_service_management_apis()

        print("\n" + "=" * 60)
        print("모든 테스트 완료")
        print("=" * 60)

        return self.generate_report()

    def save_report(self, output_dir: str = "result"):
        """리포트를 디렉토리에 저장하고 이전 리포트는 old로 이동"""
        # 디렉토리 생성
        result_dir = Path(output_dir)
        old_dir = result_dir / "old"
        result_dir.mkdir(exist_ok=True)
        old_dir.mkdir(exist_ok=True)

        # 기존 파일들을 old로 이동
        for file in result_dir.glob("*.md"):
            if file.name != "README.md":
                shutil.move(str(file), str(old_dir / file.name))

        for file in result_dir.glob("*.json"):
            shutil.move(str(file), str(old_dir / file.name))

        # 새 리포트 생성
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        md_filename = result_dir / f"clickhouse_api_report_{timestamp}.md"
        json_filename = result_dir / f"clickhouse_api_results_{timestamp}.json"

        # 마크다운 리포트 저장
        report = self.generate_report()
        with open(md_filename, 'w', encoding='utf-8') as f:
            f.write(report)

        # JSON 결과 저장
        with open(json_filename, 'w', encoding='utf-8') as f:
            json.dump(self.test_results, f, indent=2, ensure_ascii=False)

        print(f"\n✓ 리포트가 저장되었습니다: {md_filename}")
        print(f"✓ JSON 결과가 저장되었습니다: {json_filename}")
        print(f"✓ 이전 리포트는 {old_dir}로 이동되었습니다.")

        return str(md_filename), str(json_filename)


def load_or_create_env():
    """환경 변수 로드 또는 생성"""
    env_path = Path(".env")

    # .env 파일이 존재하면 로드
    if env_path.exists():
        load_dotenv()
        print("✓ .env 파일을 찾았습니다. 기존 설정을 사용합니다.\n")

        api_key = os.getenv("API_KEY")
        api_secret = os.getenv("API_SECRET")
        org_id = os.getenv("ORG_ID")
        service_id = os.getenv("SERVICE_ID")

        if all([api_key, api_secret, org_id, service_id]):
            return api_key, api_secret, org_id, service_id
        else:
            print("⚠ .env 파일에 일부 값이 누락되었습니다. 새로 입력받습니다.\n")

    # .env 파일이 없거나 값이 누락된 경우 새로 입력받음
    print("=" * 60)
    print("ClickHouse Cloud API 설정")
    print("=" * 60)
    print("API 인증 정보를 입력해주세요.")
    print("(입력한 정보는 .env 파일에 저장됩니다)\n")

    api_key = input("API Key: ").strip()
    api_secret = input("API Secret (Password): ").strip()
    org_id = input("Organization ID: ").strip()
    service_id = input("Service ID: ").strip()

    # .env 파일에 저장
    with open(env_path, 'w') as f:
        f.write(f"# ClickHouse Cloud API Credentials\n")
        f.write(f"API_KEY={api_key}\n")
        f.write(f"API_SECRET={api_secret}\n")
        f.write(f"ORG_ID={org_id}\n")
        f.write(f"SERVICE_ID={service_id}\n")

    print(f"\n✓ 설정이 .env 파일에 저장되었습니다.")
    print("✓ 다음 실행부터는 저장된 설정을 자동으로 사용합니다.\n")

    return api_key, api_secret, org_id, service_id


# 실행 예제
if __name__ == "__main__":
    # 환경 변수 로드 또는 생성
    api_key, api_secret, org_id, service_id = load_or_create_env()

    # 테스터 생성 및 실행
    tester = ClickHouseCloudAPITester(api_key, api_secret, org_id, service_id)

    # 모든 테스트 실행
    report = tester.run_all_tests()

    # 리포트 파일 저장 (result 디렉토리에, 이전 파일은 old로 이동)
    tester.save_report()
