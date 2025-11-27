import requests
import json
import time
from datetime import datetime, timedelta
from typing import Dict, List, Any
import base64

class ClickHouseCloudAPITester:
    def __init__(self, api_key: str, password: str, org_id: str, service_id: str):
        self.api_key = api_key
        self.password = password
        self.org_id = org_id
        self.service_id = service_id
        self.base_url = "https://api.clickhouse.cloud/v1"
        self.headers = {
            "Authorization": f"Bearer {api_key}:{password}",
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
        
        # 1. 전체 사용량 비용 조회
        print("1. 전체 사용량 비용 조회...")
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/usageCost"
        )
        self._print_result(result)
        
        # 2. 특정 기간 사용량 비용 조회 (최근 30일)
        print("\n2. 최근 30일 사용량 비용 조회...")
        end_date = datetime.now()
        start_date = end_date - timedelta(days=30)
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/usageCost",
            params={
                "startDate": start_date.strftime("%Y-%m-%d"),
                "endDate": end_date.strftime("%Y-%m-%d")
            }
        )
        self._print_result(result)
        
        # 3. 최근 7일 사용량 비용 조회
        print("\n3. 최근 7일 사용량 비용 조회...")
        start_date = end_date - timedelta(days=7)
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/usageCost",
            params={
                "startDate": start_date.strftime("%Y-%m-%d"),
                "endDate": end_date.strftime("%Y-%m-%d")
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
        
        # 1. Prometheus 메트릭 조회
        print("1. Prometheus 메트릭 조회...")
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/services/{self.service_id}/prometheus"
        )
        self._print_result(result)
        
        # 2. 서비스 상태 조회
        print("\n2. 서비스 상태 조회...")
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/services/{self.service_id}"
        )
        self._print_result(result)
        
        # 3. 서비스 목록 조회
        print("\n3. 조직의 모든 서비스 조회...")
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/services"
        )
        self._print_result(result)
        
        # 4. 특정 Prometheus 쿼리 테스트
        prometheus_queries = [
            "up",
            "clickhouse_query_total",
            "clickhouse_query_duration_seconds",
            "clickhouse_connection_total"
        ]
        
        for query in prometheus_queries:
            print(f"\n4.{prometheus_queries.index(query)+1}. Prometheus 쿼리 테스트: {query}...")
            result = self.make_request(
                "GET",
                f"/organizations/{self.org_id}/services/{self.service_id}/prometheus",
                params={"query": query}
            )
            self._print_result(result)
    
    def test_service_management_apis(self):
        """서비스 관리 관련 API 테스트"""
        print("\n=== 서비스 관리 API 테스트 시작 ===\n")
        
        # 1. 서비스 활동 로그 조회
        print("1. 서비스 활동 로그 조회...")
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/services/{self.service_id}/activity"
        )
        self._print_result(result)
        
        # 2. 백업 목록 조회
        print("\n2. 백업 목록 조회...")
        result = self.make_request(
            "GET",
            f"/organizations/{self.org_id}/services/{self.service_id}/backups"
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
    
    def generate_report(self) -> str:
        """종합 리포트 생성"""
        end_time = datetime.now()
        total_time = (end_time - self.start_time).total_seconds()
        
        successful_tests = sum(1 for r in self.test_results if r["success"])
        failed_tests = len(self.test_results) - successful_tests
        
        report = f"""
# ClickHouse Cloud API 테스트 리포트

**생성 일시:** {end_time.strftime("%Y-%m-%d %H:%M:%S")}
**총 소요 시간:** {total_time:.2f}초
**Organization ID:** {self.org_id}
**Service ID:** {self.service_id}

---

## 📊 테스트 요약

- **총 테스트 수:** {len(self.test_results)}
- **성공:** {successful_tests} ✓
- **실패:** {failed_tests} ✗
- **성공률:** {(successful_tests/len(self.test_results)*100):.1f}%

---

## 🔍 상세 테스트 결과

"""
        
        # 카테고리별로 그룹화
        categories = {
            "빌링 API": [],
            "모니터링 API": [],
            "서비스 관리 API": []
        }
        
        for result in self.test_results:
            if "usageCost" in result["endpoint"] or "organizations" in result["endpoint"]:
                categories["빌링 API"].append(result)
            elif "prometheus" in result["endpoint"] or "services" in result["endpoint"]:
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
**{i}. {result['method']} {result['endpoint']}**

- **상태:** {status} {result['status_code']}
- **응답 시간:** {result['response_time']}
- **실행 시각:** {result['timestamp']}
"""
                
                if result.get("params"):
                    report += f"- **파라미터:** {json.dumps(result['params'], indent=2)}\n"
                
                if result["success"]:
                    response = result["response"]
                    if isinstance(response, dict):
                        report += f"- **응답 키:** {list(response.keys())}\n"
                        if "result" in response:
                            report += f"- **결과 미리보기:** `{str(response['result'])[:150]}...`\n"
                else:
                    report += f"- **에러:** {result.get('error', result.get('response', 'Unknown'))}\n"
                
                report += "\n---\n"
        
        # 권장사항 추가
        report += """
## 💡 권장사항 및 실행 방안

### 빌링 모니터링
1. **일일 비용 추적**: 매일 `usageCost` API를 호출하여 비용 추이를 모니터링
2. **예산 알림**: 특정 임계값 초과 시 알림 설정 권장
3. **비용 최적화**: 주기적으로 사용 패턴 분석 후 리소스 조정

### 성능 모니터링
1. **Prometheus 메트릭**: 
   - `clickhouse_query_total`: 쿼리 처리량 모니터링
   - `clickhouse_query_duration_seconds`: 쿼리 성능 추적
   - `up`: 서비스 가용성 체크
2. **알림 설정**: Grafana 또는 자체 모니터링 시스템과 연동
3. **정기 점검**: 시간당 또는 일일 단위로 메트릭 수집

### 자동화 방안
1. **스케줄링**: cron 또는 Task Scheduler로 주기적 실행
2. **대시보드**: Grafana, Streamlit 등으로 실시간 대시보드 구축
3. **알림 통합**: Slack, 이메일, PagerDuty 등과 연동

### 보안 고려사항
1. API 키는 환경 변수로 관리
2. 정기적인 키 로테이션 수행
3. 최소 권한 원칙 적용

---

## 📝 참고 문서

- [ClickHouse Cloud API 문서](https://clickhouse.com/docs/cloud/manage/api/api-overview)
- [Billing API 상세](https://clickhouse.com/docs/cloud/manage/api/swagger#tag/Billing)
- [Prometheus API 상세](https://clickhouse.com/docs/cloud/manage/api/swagger#tag/Prometheus)

---

**리포트 생성 완료**
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
    
    def save_report(self, filename: str = None):
        """리포트 파일로 저장"""
        if filename is None:
            filename = f"clickhouse_api_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.md"
        
        report = self.generate_report()
        
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(report)
        
        print(f"\n✓ 리포트가 저장되었습니다: {filename}")
        return filename


# 실행 예제
if __name__ == "__main__":
    # 설정
    API_KEY = "mMyJAi9HVaIS90Y04AMv"
    PASSWORD = "your_password_here"  # 실제 패스워드로 교체 필요
    ORG_ID = "9142daed-a43f-455a-a112-f721d02b80af"
    SERVICE_ID = "c5ccc996-e105-4f61-aa12-4769ea485f7f"
    
    # 테스터 생성 및 실행
    tester = ClickHouseCloudAPITester(API_KEY, PASSWORD, ORG_ID, SERVICE_ID)
    
    # 모든 테스트 실행
    report = tester.run_all_tests()
    
    # 리포트 출력
    print("\n" + "=" * 60)
    print("생성된 리포트:")
    print("=" * 60)
    print(report)
    
    # 리포트 파일 저장
    tester.save_report()
    
    # JSON 형태로도 저장
    json_filename = f"clickhouse_api_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(json_filename, 'w', encoding='utf-8') as f:
        json.dump(tester.test_results, f, indent=2, ensure_ascii=False)
    print(f"✓ JSON 결과가 저장되었습니다: {json_filename}")