# ClickHouse 25.10 New Features Lab

ClickHouse 25.10 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 ClickHouse 25.10에서 새롭게 추가된 기능들을 실습하고 반복 학습할 수 있도록 구성되어 있습니다.

## 📋 Overview

ClickHouse 25.10은 JOIN 성능 개선, 벡터 검색을 위한 새로운 데이터 타입, 그리고 쿼리 편의성을 높이는 여러 기능들을 포함합니다.

### 🎯 Key Features

1. **QBit Data Type** - 벡터 검색을 위한 새로운 데이터 타입
2. **Negative LIMIT/OFFSET** - 음수 값을 사용한 역방향 조회
3. **JOIN Improvements** - Lazy materialization, filter push-down, 자동 조건 유도
4. **LIMIT BY ALL** - 그룹별 레코드 제한을 위한 새로운 문법
5. **Auto Statistics** - 자동 통계 수집 및 JOIN 최적화

## 🚀 Quick Start

### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../oss-mac-setup/) 환경 구성

### Setup and Run

```bash
# 1. ClickHouse 25.10 설치 및 시작
cd local/25.10
./00-setup.sh

# 2. 각 기능별 테스트 실행
./01-qbit-vector-search.sh
./02-negative-limit-offset.sh
./03-join-improvements.sh
./04-limit-by-all.sh
./05-auto-statistics.sh
```

### Manual Execution (SQL only)

SQL 파일을 직접 실행하려면:

```bash
# ClickHouse 클라이언트 접속
cd ../oss-mac-setup
./client.sh 2510

# SQL 파일 실행
cd ../25.10
source 01-qbit-vector-search.sql
```

## 📚 Feature Details

### 1. QBit Vector Search (01-qbit-vector-search)

**새로운 기능:** QBit 데이터 타입을 통한 효율적인 벡터 검색

**테스트 내용:**
- QBit 데이터 타입 생성 및 사용
- L2 Distance (유클리드 거리) 계산
- Cosine Distance 계산
- 유사도 검색 및 벡터 연산

**실행:**
```bash
./01-qbit-vector-search.sh
# 또는
cat 01-qbit-vector-search.sql | docker exec -i clickhouse-25-10 clickhouse-client --multiline --multiquery
```

**주요 학습 포인트:**
- 벡터 임베딩 저장 및 검색
- 거리 함수를 이용한 유사도 계산
- 메모리 효율적인 벡터 저장

---

### 2. Negative LIMIT/OFFSET (02-negative-limit-offset)

**새로운 기능:** LIMIT과 OFFSET에 음수 값 사용 지원

**테스트 내용:**
- 음수 LIMIT으로 마지막 N개 레코드 조회
- 음수 OFFSET으로 끝에서부터 건너뛰기
- 양수/음수 조합 사용
- 페이지네이션 응용

**실행:**
```bash
./02-negative-limit-offset.sh
```

**주요 학습 포인트:**
- `LIMIT -3`: 마지막 3개 레코드
- `OFFSET -2`: 끝에서 2개 건너뛰기
- 역방향 페이지네이션 구현
- 서브쿼리 없이 tail 쿼리 작성

---

### 3. JOIN Improvements (03-join-improvements)

**새로운 기능:** JOIN 성능 최적화 - Lazy materialization, Filter push-down, 자동 조건 유도

**테스트 내용:**
- Lazy materialization을 통한 메모리/CPU 최적화
- Filter push-down (PREWHERE-like optimization)
- 복잡한 WHERE 절의 자동 조건 유도
- 다중 테이블 JOIN 최적화

**실행:**
```bash
./03-join-improvements.sh
```

**주요 학습 포인트:**
- JOIN 시 블록 복제의 지연 수행 (lazy)
- 작은 필터를 다른 테이블 읽기에 활용
- 자동 조건 전파로 쿼리 최적화
- EXPLAIN으로 실행 계획 확인

---

### 4. LIMIT BY ALL (04-limit-by-all)

**새로운 기능:** 그룹별 레코드 제한을 위한 새로운 문법

**테스트 내용:**
- `LIMIT BY ALL` 문법 사용
- 다중 컬럼 조합으로 그룹핑
- 데이터 샘플링 및 중복 제거
- 세션 분석 응용

**실행:**
```bash
./04-limit-by-all.sh
```

**주요 학습 포인트:**
- `LIMIT 2 BY ALL user_id`: 각 사용자별 2개씩
- 윈도우 함수 대신 간단한 문법 사용
- 데이터 품질 체크 및 샘플링
- 그룹별 첫/마지막 레코드 조회

---

### 5. Auto Statistics (05-auto-statistics)

**새로운 기능:** 테이블 수준 자동 통계 수집 설정

**테스트 내용:**
- `auto_collect_statistics` 설정
- minmax, uniq, countmin 통계 타입
- 통계 기반 JOIN 순서 자동 최적화
- system.statistics 테이블 조회

**실행:**
```bash
./05-auto-statistics.sh
```

**주요 학습 포인트:**
- 테이블 생성 시 자동 통계 활성화
- 통계를 활용한 쿼리 최적화
- JOIN 순서 자동 재배치
- 통계 메타데이터 확인

## 🔧 Management

### ClickHouse Connection Info

- **Web UI**: http://localhost:2510/play
- **HTTP API**: http://localhost:2510
- **TCP**: localhost:25101
- **User**: default (no password)

### Useful Commands

```bash
# ClickHouse 상태 확인
cd ../oss-mac-setup
./status.sh

# CLI 접속
./client.sh 2510

# 로그 확인
docker logs clickhouse-25-10

# 중지
./stop.sh

# 완전 삭제
./stop.sh --cleanup
```

## 📂 File Structure

```
25.10/
├── README.md                      # 이 문서
├── 00-setup.sh                    # ClickHouse 25.10 설치 스크립트
├── 01-qbit-vector-search.sh       # QBit 벡터 검색 테스트 실행
├── 01-qbit-vector-search.sql      # QBit 벡터 검색 SQL
├── 02-negative-limit-offset.sh    # Negative LIMIT/OFFSET 테스트 실행
├── 02-negative-limit-offset.sql   # Negative LIMIT/OFFSET SQL
├── 03-join-improvements.sh        # JOIN 개선 테스트 실행
├── 03-join-improvements.sql       # JOIN 개선 SQL
├── 04-limit-by-all.sh             # LIMIT BY ALL 테스트 실행
├── 04-limit-by-all.sql            # LIMIT BY ALL SQL
├── 05-auto-statistics.sh          # Auto Statistics 테스트 실행
└── 05-auto-statistics.sql         # Auto Statistics SQL
```

## 🎓 Learning Path

### 초급 사용자
1. **00-setup.sh** - 환경 구성 이해
2. **02-negative-limit-offset** - 간단한 문법부터 시작
3. **04-limit-by-all** - 데이터 그룹핑 이해

### 중급 사용자
1. **01-qbit-vector-search** - 벡터 검색 개념 학습
2. **03-join-improvements** - JOIN 최적화 이해
3. **05-auto-statistics** - 통계 기반 최적화

### 고급 사용자
- 모든 기능을 조합하여 실제 프로덕션 시나리오 구현
- EXPLAIN 명령으로 쿼리 실행 계획 분석
- 성능 벤치마킹 및 비교

## 🔍 Additional Resources

- **Official Release Blog**: [ClickHouse 25.10 Release](https://clickhouse.com/blog/clickhouse-release-25-10)
- **Release Presentation**: [25.10 Feature Deck](https://presentations.clickhouse.com/2025-release-25.10/)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)

## 📝 Notes

- 각 스크립트는 독립적으로 실행 가능합니다
- SQL 파일을 직접 읽고 수정하여 실험해보세요
- 테스트 데이터는 각 SQL 파일 내에서 생성됩니다
- 정리(cleanup)는 기본적으로 주석 처리되어 있습니다

## 🤝 Contributing

이 랩에 대한 개선 사항이나 추가 예제가 있다면:
1. 이슈 등록
2. Pull Request 제출
3. 피드백 공유

## 📄 License

MIT License - 자유롭게 학습 및 수정 가능

---

**Happy Learning! 🚀**

For questions or issues, please refer to the main [clickhouse-hols README](../../README.md).
