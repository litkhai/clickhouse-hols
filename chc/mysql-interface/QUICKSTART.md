# ClickHouse MySQL Interface 테스트 - 빠른 시작 가이드

## 🚀 5분 안에 시작하기

### 1단계: 설정 파일 생성 (1분)

```bash
# 설정 템플릿 복사
cd chc/mysql-interface
cp config/chc-config.template config/chc-config.sh

# 설정 파일 편집
nano config/chc-config.sh
```

**필수 수정 항목:**
```bash
export CHC_HOST="your-instance.clickhouse.cloud"    # ClickHouse Cloud 호스트
export CHC_PASSWORD="your-password"                  # 비밀번호
```

### 2단계: 테스트 실행 (3분)

```bash
./run-mysql-test.sh
```

### 3단계: 결과 확인 (1분)

```bash
# 최신 리포트 보기
ls -lt test-results/report_*.md | head -1 | awk '{print $9}' | xargs cat
```

---

## 📊 예상 출력

```
==========================================================================
  ClickHouse Cloud MySQL Interface 호환성 자동 테스트
==========================================================================

실행 시간: 2025-12-13 15:30:00
결과 저장: /path/to/test-results

[INFO] 1단계: 환경 설정 시작...
✓ Python3: Python 3.11.0
✓ pip3: pip 23.0.1
✓ mysql-connector-python 설치 완료
✓ pymysql 설치 완료
✓ 환경 설정 완료

[INFO] 2단계: MySQL 클라이언트 설치 확인...
✓ MySQL 클라이언트가 이미 설치되어 있습니다:
  mysql  Ver 8.0.33 for macos13.3 on arm64
✓ MySQL 클라이언트 확인 완료

[INFO] 3단계: ClickHouse Cloud 접속 정보 확인...
설정 정보:
  호스트: abc123.us-east-1.aws.clickhouse.cloud
  포트: 9004
  사용자: default
  데이터베이스: mysql_interface
  SSL 모드: REQUIRED

연결 테스트 중...
✓ 연결 성공!
  ClickHouse 버전: 24.11.1.123
  현재 데이터베이스: default
✓ 접속 정보 확인 완료

[INFO] 4단계: 기본 호환성 테스트 실행...
✓ Basic SELECT: SELECT 1 returned 1
✓ Version Query: Version: 24.11.1.123
✓ Create Database: Database created successfully
✓ Use Database: Database switched successfully
✓ Create Table: Table created successfully
✓ Insert Data: Data inserted successfully
✓ Select Data: Retrieved: (1, 'test1', 100.5, datetime(...))
✓ Aggregate COUNT: Count: 2
✓ Prepared Statement: Retrieved: (2, 'test2', 200.75, datetime(...))
✓ Cleanup: Table dropped successfully

통계: 10/10 테스트 통과

[SUCCESS] 기본 호환성 테스트 완료

... (추가 테스트 계속) ...

==========================================================================
  테스트 결과 요약
==========================================================================

전체 테스트: 7
성공: 7
실패: 0

성공률: 100%

[SUCCESS] 전체 테스트 성공!

상세 리포트: /path/to/test-results/report_20251213_153000.md
```

---

## 🎯 다음 단계

### 개별 테스트 실행

특정 테스트만 실행하고 싶다면:

```bash
# SQL 구문 테스트만 실행
./scripts/05-sql-syntax-tests.sh

# 성능 테스트만 실행
./scripts/10-performance-tests.sh
```

### 결과 분석

```bash
# JSON 결과 보기
cat test-results/basic-compatibility.json | python3 -m json.tool

# 성능 메트릭 추출
cat test-results/performance.json | jq '.tests[] | {name: .name, throughput: .throughput}'
```

### 실제 워크로드 테스트

테스트 플랜의 TPC-DS 섹션을 참고하여 실제 데이터로 테스트:

```bash
# TPC-DS 스키마 생성 및 데이터 로드
# (chc-mysql-interface-test-plan.md 참조)
```

---

## ⚠️ 문제 해결

### "ERROR: CHC_HOST가 설정되지 않았습니다"

➜ `config/chc-config.sh` 파일을 확인하고 실제 값으로 수정하세요.

### "ERROR: 연결 중 오류 발생"

➜ 다음을 확인하세요:
1. ClickHouse Cloud 인스턴스가 실행 중인가?
2. MySQL interface 포트(9004)가 열려 있는가?
3. 비밀번호가 올바른가?

```bash
# 직접 연결 테스트
mysql --host=<your-host> --port=9004 --user=default --password --ssl-mode=REQUIRED
```

### Python 패키지 오류

```bash
# 패키지 재설치
pip3 install --upgrade --force-reinstall mysql-connector-python pymysql
```

---

## 💡 팁

### CI/CD 통합

```bash
# Jenkins/GitHub Actions에서 사용
./run-mysql-test.sh
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ All tests passed"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
```

### 자동 스케줄링

```bash
# cron으로 매일 실행
0 2 * * * cd /path/to/mysql-interface && ./run-mysql-test.sh >> logs/cron.log 2>&1
```

### 결과 알림

```bash
# Slack 알림 예시
./run-mysql-test.sh
REPORT=$(ls -t test-results/report_*.md | head -1)
curl -X POST -H 'Content-type: application/json' \
  --data "{\"text\":\"MySQL Interface Test Report: $(cat $REPORT | head -20)\"}" \
  YOUR_SLACK_WEBHOOK_URL
```

---

## 📚 더 알아보기

- [상세 테스트 플랜](chc-mysql-interface-test-plan.md)
- [전체 README](README.md)
- [ClickHouse 문서](https://clickhouse.com/docs)

---

**문의**: support@clickhouse.com
