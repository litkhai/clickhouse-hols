#!/bin/bash
# 테스트 결과 리포트 생성 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
RESULTS_DIR="${BASE_DIR}/test-results"
TIMESTAMP=${1:-$(date +"%Y%m%d_%H%M%S")}
REPORT_FILE="${RESULTS_DIR}/report_${TIMESTAMP}.md"

echo "테스트 리포트 생성 중..."
echo ""

python3 << EOF
import json
import os
from datetime import datetime
from pathlib import Path

results_dir = Path("${RESULTS_DIR}")
report_file = "${REPORT_FILE}"
timestamp = "${TIMESTAMP}"

# 결과 파일 목록
result_files = [
    "basic-compatibility.json",
    "sql-syntax.json",
    "datatype.json",
    "function.json",
    "tpcds.json",
    "python-driver.json",
    "performance.json"
]

# 각 테스트 결과 로드
all_results = {}
for result_file in result_files:
    file_path = results_dir / result_file
    if file_path.exists():
        with open(file_path, 'r') as f:
            try:
                all_results[result_file] = json.load(f)
            except:
                all_results[result_file] = {"error": "Failed to load"}

# 마크다운 리포트 생성
report = []
report.append("# ClickHouse Cloud MySQL Interface 호환성 테스트 보고서\n")
report.append(f"**생성일시**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
report.append(f"**테스트 ID**: {timestamp}\n")
report.append("\n---\n")

# 전체 요약
report.append("\n## 📊 전체 요약\n")

total_tests = 0
total_passed = 0
category_results = {}

for result_file, data in all_results.items():
    if "tests" in data:
        tests = data["tests"]
        passed = sum(1 for t in tests if t.get("passed", False))
        total = len(tests)
        total_tests += total
        total_passed += passed

        category_name = data.get("test_name", result_file)
        category_results[category_name] = {
            "total": total,
            "passed": passed,
            "pass_rate": (passed / total * 100) if total > 0 else 0
        }

overall_pass_rate = (total_passed / total_tests * 100) if total_tests > 0 else 0

report.append(f"- **전체 테스트**: {total_tests}개\n")
report.append(f"- **성공**: {total_passed}개 ({overall_pass_rate:.1f}%)\n")
report.append(f"- **실패**: {total_tests - total_passed}개\n")
report.append("\n")

# 등급 판정
if overall_pass_rate >= 90:
    grade = "A (Excellent)"
    grade_emoji = "🌟"
elif overall_pass_rate >= 80:
    grade = "B (Good)"
    grade_emoji = "✅"
elif overall_pass_rate >= 70:
    grade = "C (Acceptable)"
    grade_emoji = "⚠️"
else:
    grade = "D (Needs Improvement)"
    grade_emoji = "❌"

report.append(f"### 종합 등급: {grade_emoji} {grade}\n")
report.append("\n---\n")

# 카테고리별 결과
report.append("\n## 📋 카테고리별 결과\n")

for category_name, stats in category_results.items():
    status_emoji = "✅" if stats["pass_rate"] >= 80 else "⚠️" if stats["pass_rate"] >= 60 else "❌"
    report.append(f"\n### {status_emoji} {category_name}\n")
    report.append(f"- 성공률: {stats['pass_rate']:.1f}% ({stats['passed']}/{stats['total']})\n")

report.append("\n---\n")

# 상세 테스트 결과
report.append("\n## 📝 상세 테스트 결과\n")

for result_file, data in all_results.items():
    if "tests" not in data:
        continue

    category_name = data.get("test_name", result_file)
    report.append(f"\n### {category_name}\n")
    report.append(f"*실행 시간: {data.get('timestamp', 'N/A')}*\n")
    report.append("\n")

    # 테이블 헤더
    report.append("| 테스트 | 결과 | 메시지 |\n")
    report.append("|--------|------|--------|\n")

    for test in data["tests"]:
        test_name = test.get("name", "Unknown")
        passed = test.get("passed", False)
        status = "✅ 성공" if passed else "❌ 실패"
        message = test.get("message", test.get("error", ""))

        # 메시지 길이 제한
        if len(message) > 100:
            message = message[:97] + "..."

        # 성능 메트릭 추가
        if "duration_ms" in test:
            message += f" ({test['duration_ms']:.2f}ms)"
        if "throughput" in test and test["throughput"] > 0:
            message += f" ({test['throughput']:.0f} ops/sec)"

        report.append(f"| {test_name} | {status} | {message} |\n")

    report.append("\n")

report.append("\n---\n")

# 성능 요약
report.append("\n## ⚡ 성능 요약\n")

if "performance.json" in all_results and "tests" in all_results["performance.json"]:
    perf_tests = all_results["performance.json"]["tests"]
    report.append("\n| 테스트 | 실행 시간 | 처리량 |\n")
    report.append("|--------|----------|--------|\n")

    for test in perf_tests:
        name = test.get("name", "Unknown")
        duration = test.get("duration_ms", 0)
        throughput = test.get("throughput", 0)
        report.append(f"| {name} | {duration:.2f}ms | {throughput:.0f} ops/sec |\n")

    report.append("\n")

report.append("\n---\n")

# 권장 사항
report.append("\n## 💡 권장 사항\n")

if overall_pass_rate >= 90:
    report.append("\n✅ **프로덕션 사용 권장**\n")
    report.append("- MySQL interface가 대부분의 워크로드에서 안정적으로 작동합니다.\n")
    report.append("- 분석 쿼리 및 OLAP 워크로드에 적합합니다.\n")
elif overall_pass_rate >= 80:
    report.append("\n✅ **제한적 프로덕션 사용 가능**\n")
    report.append("- 기본 기능은 잘 작동하나 일부 고급 기능에 제한이 있을 수 있습니다.\n")
    report.append("- 실제 워크로드로 추가 테스트를 권장합니다.\n")
elif overall_pass_rate >= 70:
    report.append("\n⚠️ **주의가 필요**\n")
    report.append("- 일부 호환성 문제가 있습니다.\n")
    report.append("- 실패한 테스트를 검토하고 워크로드에 영향이 있는지 확인하세요.\n")
else:
    report.append("\n❌ **추가 조사 필요**\n")
    report.append("- 여러 호환성 문제가 발견되었습니다.\n")
    report.append("- ClickHouse 네이티브 인터페이스 사용을 고려하세요.\n")

report.append("\n")

# 알려진 제한사항
report.append("\n## ⚠️ 알려진 제한사항\n")
report.append("\n")
report.append("- **AUTO_INCREMENT**: 제한적 지원 (대안: generateUUIDv4() 사용)\n")
report.append("- **FOREIGN KEY**: 구문만 허용, 실제 제약조건 미적용\n")
report.append("- **TRIGGER**: 미지원\n")
report.append("- **STORED PROCEDURE**: 미지원\n")
report.append("- **TRANSACTION**: INSERT만 부분 지원\n")
report.append("\n")

# 참고 자료
report.append("\n---\n")
report.append("\n## 📚 참고 자료\n")
report.append("\n")
report.append("- [ClickHouse MySQL Interface 문서](https://clickhouse.com/docs/en/interfaces/mysql/)\n")
report.append("- [ClickHouse SQL Reference](https://clickhouse.com/docs/en/sql-reference/)\n")
report.append("- [MySQL 호환성 가이드](https://clickhouse.com/docs/en/interfaces/mysql#mysql-compatibility)\n")
report.append("\n")

# 파일에 저장
with open(report_file, 'w', encoding='utf-8') as f:
    f.writelines(report)

print(f"✓ 리포트 생성 완료: {report_file}")
print(f"  전체 테스트: {total_tests}개")
print(f"  성공: {total_passed}개 ({overall_pass_rate:.1f}%)")
print(f"  등급: {grade}")
EOF

exit $?
