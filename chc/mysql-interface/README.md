# ClickHouse Cloud MySQL Interface 자동 테스트 도구

ClickHouse Cloud의 MySQL Wire Protocol 호환성을 자동으로 검증하는 종합 테스트 도구입니다.

## 📋 목차

- [개요](#개요)
- [기능](#기능)
- [설치 및 설정](#설치-및-설정)
- [사용 방법](#사용-방법)
- [테스트 항목](#테스트-항목)
- [결과 리포트](#결과-리포트)
- [문제 해결](#문제-해결)

## 개요

이 도구는 [chc-mysql-interface-test-plan.md](chc-mysql-interface-test-plan.md)에 정의된 테스트 플랜을 자동으로 실행하여 ClickHouse Cloud의 MySQL interface 호환성을 검증합니다.

### 주요 특징

- ✅ MySQL 클라이언트 자동 설치 및 확인
- ✅ ClickHouse Cloud 접속 정보 관리
- ✅ 7가지 카테고리별 호환성 테스트
- ✅ 성능 벤치마크
- ✅ 자동 리포트 생성 (Markdown)
- ✅ JSON 형식 결과 저장

## 기능

### 테스트 카테고리

1. **환경 설정**: Python, MySQL 클라이언트 확인
2. **MySQL 클라이언트 설치**: 버전 5.7 및 8.0 지원
3. **접속 정보 확인**: CHC MySQL interface 연결 테스트
4. **기본 호환성 테스트**: 기본 SQL 작업 (CREATE, INSERT, SELECT 등)
5. **SQL 구문 호환성**: WHERE, JOIN, GROUP BY, HAVING 등
6. **데이터 타입 호환성**: INT, VARCHAR, DATE, DECIMAL 등
7. **함수 호환성**: 문자열, 날짜, 집계 함수
8. **TPC-DS 벤치마크**: 복잡한 분석 쿼리
9. **Python 드라이버**: mysql-connector-python, PyMySQL
10. **성능 테스트**: 처리량 및 응답 시간 측정

## 설치 및 설정

### 사전 요구사항

- Python 3.7 이상
- pip3
- macOS, Linux 또는 WSL (Windows)
- ClickHouse Cloud 인스턴스 (MySQL interface 활성화)

### 1단계: 저장소 클론

```bash
git clone <repository-url>
cd clickhouse-hols/chc/mysql-interface
```

### 2단계: 접속 정보 설정

```bash
# 템플릿 복사
cp config/chc-config.template config/chc-config.sh

# 설정 파일 편집
vim config/chc-config.sh
```

**config/chc-config.sh 예시:**

```bash
export CHC_HOST="abc123.us-east-1.aws.clickhouse.cloud"
export CHC_MYSQL_PORT="9004"
export CHC_USER="default"
export CHC_PASSWORD="your-secure-password"
export CHC_DATABASE="mysql_interface"
export CHC_SSL_MODE="REQUIRED"
```

⚠️ **중요**: `config/chc-config.sh` 파일은 민감한 정보를 포함하므로 Git에 커밋하지 마세요!

## 사용 방법

### 전체 테스트 실행

```bash
./run-mysql-test.sh
```

### 개별 테스트 실행

```bash
# 1. 환경 설정
./scripts/01-setup-environment.sh

# 2. MySQL 클라이언트 설치
./scripts/02-install-mysql-clients.sh

# 3. 접속 확인
./scripts/03-verify-connection.sh

# 4. 기본 호환성 테스트
./scripts/04-basic-compatibility-tests.sh

# 5. SQL 구문 테스트
./scripts/05-sql-syntax-tests.sh

# 6. 데이터 타입 테스트
./scripts/06-datatype-tests.sh

# 7. 함수 테스트
./scripts/07-function-tests.sh

# 8. TPC-DS 테스트
./scripts/08-tpcds-tests.sh

# 9. Python 드라이버 테스트
./scripts/09-python-driver-tests.sh

# 10. 성능 테스트
./scripts/10-performance-tests.sh

# 11. 리포트 생성
./scripts/11-generate-report.sh
```

## 테스트 항목

### 기본 호환성 테스트
- SELECT 기본 쿼리
- 버전 조회
- 데이터베이스 생성/사용
- 테이블 생성/삭제
- 데이터 삽입/조회
- COUNT 집계
- Prepared Statement

### SQL 구문 호환성
- Single/Multiple INSERT
- WHERE 절
- ORDER BY
- LIMIT
- GROUP BY
- HAVING
- DISTINCT
- IN 절
- BETWEEN
- LIKE 패턴
- CASE WHEN

### 데이터 타입 호환성
- 숫자형: TINYINT, SMALLINT, INT, BIGINT, FLOAT, DOUBLE, DECIMAL
- 문자열: CHAR, VARCHAR, TEXT
- 날짜/시간: DATE, DATETIME, TIMESTAMP

### 함수 호환성
- 문자열: CONCAT, UPPER, LOWER, LENGTH, SUBSTRING
- 날짜: NOW, CURDATE, YEAR, MONTH
- 집계: COUNT, SUM, AVG, MIN, MAX

### 성능 테스트
- 단순 쿼리 처리량
- 집계 쿼리 성능
- 배치 삽입 성능
- 테이블 스캔 성능

## 결과 리포트

### 출력 디렉토리

```
test-results/
├── basic-compatibility.json    # 기본 호환성 결과
├── sql-syntax.json             # SQL 구문 결과
├── datatype.json               # 데이터 타입 결과
├── function.json               # 함수 결과
├── tpcds.json                  # TPC-DS 결과
├── python-driver.json          # Python 드라이버 결과
├── performance.json            # 성능 결과
└── report_YYYYMMDD_HHMMSS.md  # 종합 리포트
```

### 리포트 내용

자동 생성되는 리포트에는 다음이 포함됩니다:

- 📊 전체 요약 (성공률, 등급)
- 📋 카테고리별 결과
- 📝 상세 테스트 결과
- ⚡ 성능 요약
- 💡 권장 사항
- ⚠️ 알려진 제한사항

### 등급 기준

- **A (Excellent)**: 90% 이상 🌟
- **B (Good)**: 80-89% ✅
- **C (Acceptable)**: 70-79% ⚠️
- **D (Needs Improvement)**: 70% 미만 ❌

## 문제 해결

### MySQL 클라이언트 설치 오류

**macOS:**
```bash
brew install mysql-client
echo 'export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install mysql-client
```

**CentOS/RHEL:**
```bash
sudo yum install mysql
```

### Python 패키지 설치 오류

```bash
pip3 install --upgrade pip
pip3 install mysql-connector-python pymysql
```

### 연결 실패

1. ClickHouse Cloud 인스턴스가 실행 중인지 확인
2. MySQL interface 포트(9004)가 열려 있는지 확인
3. 방화벽 규칙 확인
4. 접속 정보가 올바른지 확인

```bash
# 연결 테스트
mysql --host=<your-host> --port=9004 --user=default --password=<password> --ssl-mode=REQUIRED
```

### SSL 인증서 오류

```bash
# SSL 모드 확인
export CHC_SSL_MODE="REQUIRED"

# 또는 Python 스크립트에서
ssl_disabled=False
```

## 디렉토리 구조

```
chc/mysql-interface/
├── run-mysql-test.sh              # 메인 실행 스크립트
├── chc-mysql-interface-test-plan.md  # 테스트 플랜 문서
├── README.md                       # 이 파일
├── config/
│   ├── chc-config.template        # 설정 템플릿
│   └── chc-config.sh              # 실제 설정 (gitignore)
├── scripts/
│   ├── 01-setup-environment.sh    # 환경 설정
│   ├── 02-install-mysql-clients.sh # MySQL 클라이언트 설치
│   ├── 03-verify-connection.sh    # 접속 확인
│   ├── 04-basic-compatibility-tests.sh  # 기본 호환성
│   ├── 05-sql-syntax-tests.sh     # SQL 구문
│   ├── 06-datatype-tests.sh       # 데이터 타입
│   ├── 07-function-tests.sh       # 함수
│   ├── 08-tpcds-tests.sh          # TPC-DS
│   ├── 09-python-driver-tests.sh  # Python 드라이버
│   ├── 10-performance-tests.sh    # 성능
│   └── 11-generate-report.sh      # 리포트 생성
├── test-results/                  # 테스트 결과 (자동 생성)
└── logs/                          # 로그 파일 (자동 생성)
```

## 기여

버그 리포트, 기능 제안, 풀 리퀘스트를 환영합니다!

## 라이선스

[MIT](../../LICENSE) — 저장소 전체와 동일합니다. 이 랩의 스크립트는 모두 직접 작성한 것으로,
가져다 쓴 상류 코드가 없습니다. (이전에 Apache 2.0으로 표기돼 있었으나 근거가 없어 정정했습니다.)

## 연락처

- **작성자**: Ken (Solution Architect, ClickHouse Inc.)
- **이메일**: support@clickhouse.com
- **문서**: https://clickhouse.com/docs

## 참고 자료

- [ClickHouse MySQL Interface 문서](https://clickhouse.com/docs/en/interfaces/mysql/)
- [ClickHouse SQL Reference](https://clickhouse.com/docs/en/sql-reference/)
- [TPC-DS 벤치마크](http://www.tpc.org/tpcds/)
