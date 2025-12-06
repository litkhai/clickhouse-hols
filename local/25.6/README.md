# ClickHouse 25.6 New Features Lab

ClickHouse 25.6 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 ClickHouse 25.6에서 새롭게 추가된 기능들을 실습하고 반복 학습할 수 있도록 구성되어 있습니다.

## 📋 Overview

ClickHouse 25.6은 CoalescingMergeTree 테이블 엔진, 새로운 Time 데이터 타입, Bech32 인코딩 함수, lag/lead 윈도우 함수, 그리고 일관된 스냅샷 기능을 포함합니다.

### 🎯 Key Features

1. **CoalescingMergeTree** - 희소 업데이트에 최적화된 새로운 테이블 엔진
2. **Time and Time64 Data Types** - 시간 표현을 위한 새로운 데이터 타입
3. **Bech32 Encoding Functions** - 암호화폐 주소 등에 사용되는 Bech32 인코딩/디코딩
4. **lag/lead Window Functions** - SQL 호환성을 위한 윈도우 함수
5. **Consistent Snapshot** - 여러 쿼리에 걸친 일관된 데이터 스냅샷

## 🚀 Quick Start

### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../oss-mac-setup/) 환경 구성

### Setup and Run

```bash
# 1. ClickHouse 25.6 설치 및 시작
cd local/25.6
./00-setup.sh

# 2. 각 기능별 테스트 실행
./01-coalescingmergetree.sh
./02-time-datatypes.sh
./03-bech32-encoding.sh
./04-lag-lead-functions.sh
./05-consistent-snapshot.sh
```

### Manual Execution (SQL only)

SQL 파일을 직접 실행하려면:

```bash
# ClickHouse 클라이언트 접속
cd ../oss-mac-setup
./client.sh 2506

# SQL 파일 실행
cd ../25.6
source 01-coalescingmergetree.sql
```

## 📚 Feature Details

### 1. CoalescingMergeTree (01-coalescingmergetree)

**새로운 기능:** 희소 업데이트에 최적화된 CoalescingMergeTree 테이블 엔진

**테스트 내용:**
- CoalescingMergeTree 엔진을 사용한 테이블 생성
- Sign 컬럼을 이용한 업데이트/삭제 처리
- 머지 시 자동 병합 동작 확인
- 센서 데이터 및 메트릭 추적 사용 사례
- 실시간 데이터 수정 시나리오

**실행:**
```bash
./01-coalescingmergetree.sh
# 또는
cat 01-coalescingmergetree.sql | docker exec -i clickhouse-25-6 clickhouse-client --multiline --multiquery
```

**주요 학습 포인트:**
- Sign 컬럼: 1은 삽입, -1은 삭제/업데이트(이전 값)
- 머지 시 Sign 값을 기반으로 자동 병합
- ReplacingMergeTree보다 빈번한 업데이트에 효율적
- CDC(Change Data Capture) 시나리오에 적합

**실무 활용:**
- 메트릭 및 모니터링 시스템
- 센서 데이터 수정 및 보정
- 사용자 상태 추적
- 실시간 대시보드 업데이트

---

### 2. Time and Time64 Data Types (02-time-datatypes)

**새로운 기능:** 시간(time-of-day) 표현을 위한 Time 및 Time64 데이터 타입

**테스트 내용:**
- Time 데이터 타입 (초 정밀도)
- Time64 데이터 타입 (마이크로초 정밀도)
- 시간 연산 및 계산
- 비즈니스 시간 스케줄링
- API 성능 모니터링

**실행:**
```bash
./02-time-datatypes.sh
```

**주요 학습 포인트:**
- `Time`: 자정 이후 초 단위로 저장
- `Time64(precision)`: 마이크로초 정밀도 지원
- 시간 산술 연산: 더하기, 빼기, 차이 계산
- 날짜 없이 시간만 저장하여 효율적인 스토리지
- 비즈니스 운영 시간 및 근무 시간 관리

**실무 활용:**
- 영업 시간 및 운영 스케줄
- 직원 교대 근무 관리
- API 응답 시간 모니터링 (마이크로초 단위)
- 서비스 가용성 및 SLA 추적
- 시간 기반 접근 제어

---

### 3. Bech32 Encoding Functions (03-bech32-encoding)

**새로운 기능:** Bech32 인코딩/디코딩 함수 (`bech32Encode`, `bech32Decode`)

**테스트 내용:**
- bech32Encode() 함수를 이용한 데이터 인코딩
- bech32Decode() 함수를 이용한 디코딩
- HRP(Human Readable Prefix) 처리
- 암호화폐 주소 인코딩
- 체크섬 검증 및 오류 감지

**실행:**
```bash
./03-bech32-encoding.sh
```

**주요 학습 포인트:**
- Bech32는 Base32 변형으로 체크섬 포함
- HRP로 인코딩된 데이터의 용도 식별
- 대소문자 구분 없음 (입력 오류 감소)
- 혼동 가능한 문자 제외 (0, O, I, l)
- 비트코인 Segwit 주소 등에 사용

**실무 활용:**
- 암호화폐 주소 인코딩
- 공개 API 키 생성
- URL 단축 및 난독화
- 인보이스 및 결제 식별자
- 보안을 위한 외부 ID 매핑
- QR 코드 데이터 인코딩

---

### 4. lag/lead Window Functions (04-lag-lead-functions)

**새로운 기능:** 이전/다음 행 접근을 위한 `lag()` 및 `lead()` 윈도우 함수

**테스트 내용:**
- lag() 함수로 이전 행 데이터 접근
- lead() 함수로 다음 행 데이터 접근
- 윈도우 파티셔닝 및 정렬
- 시계열 분석 및 추세 감지
- 고객 행동 및 전환 추적

**실행:**
```bash
./04-lag-lead-functions.sh
```

**주요 학습 포인트:**
- `lag(column, offset, default)`: 이전 offset번째 행
- `lead(column, offset, default)`: 다음 offset번째 행
- PARTITION BY로 그룹별 독립적인 윈도우
- 셀프 조인 없이 인접 행 비교 가능
- 시계열 데이터의 변화율 계산

**실무 활용:**
- 주식 가격 분석 및 일일 수익률 계산
- 사용자 행동 분석 및 전환 퍼널
- 매출 추세 감지 및 예측
- 이동 평균 및 시계열 스무딩
- 세션 분석 및 사용자 여정 매핑
- 이전 기간 대비 이상 감지

---

### 5. Consistent Snapshot (05-consistent-snapshot)

**새로운 기능:** 여러 쿼리에 걸친 일관된 스냅샷 보장

**테스트 내용:**
- 읽기 일관성을 위한 스냅샷 격리
- snapshot_id를 사용한 다중 쿼리 트랜잭션
- 장시간 작업 중 팬텀 읽기 방지
- 일관된 데이터로 리포트 생성
- 감사 및 규정 준수 시나리오

**실행:**
```bash
./05-consistent-snapshot.sh
```

**주요 학습 포인트:**
- 여러 쿼리가 동일한 데이터 상태를 보도록 보장
- 리포트 생성 중 데이터 일관성 유지
- 스냅샷 테이블을 통한 특정 시점 분석
- 감사 추적을 위한 체크섬 생성
- 규제 보고를 위한 히스토리컬 스냅샷

**실무 활용:**
- 재무 일일 마감 리포트 및 정산
- 규제 준수 및 감사 추적
- 일관성 있는 다중 테이블 대시보드 생성
- 외부 시스템으로 데이터 내보내기
- 히스토리컬 특정 시점 분석
- 백업 검증 및 데이터 무결성 검사

## 🔧 Management

### ClickHouse Connection Info

- **Web UI**: http://localhost:2506/play
- **HTTP API**: http://localhost:2506
- **TCP**: localhost:25061
- **User**: default (no password)

### Useful Commands

```bash
# ClickHouse 상태 확인
cd ../oss-mac-setup
./status.sh

# CLI 접속
./client.sh 2506

# 로그 확인
docker logs clickhouse-25-6

# 중지
./stop.sh

# 완전 삭제
./stop.sh --cleanup
```

## 📂 File Structure

```
25.6/
├── README.md                      # 이 문서
├── 00-setup.sh                    # ClickHouse 25.6 설치 스크립트
├── 01-coalescingmergetree.sh      # CoalescingMergeTree 테스트 실행
├── 01-coalescingmergetree.sql     # CoalescingMergeTree SQL
├── 02-time-datatypes.sh           # Time 데이터 타입 테스트 실행
├── 02-time-datatypes.sql          # Time 데이터 타입 SQL
├── 03-bech32-encoding.sh          # Bech32 인코딩 테스트 실행
├── 03-bech32-encoding.sql         # Bech32 인코딩 SQL
├── 04-lag-lead-functions.sh       # lag/lead 함수 테스트 실행
├── 04-lag-lead-functions.sql      # lag/lead 함수 SQL
├── 05-consistent-snapshot.sh      # Consistent Snapshot 테스트 실행
└── 05-consistent-snapshot.sql     # Consistent Snapshot SQL
```

## 🎓 Learning Path

### 초급 사용자
1. **00-setup.sh** - 환경 구성 이해
2. **02-time-datatypes** - 간단한 데이터 타입부터 시작
3. **04-lag-lead-functions** - 윈도우 함수 기초 학습

### 중급 사용자
1. **01-coalescingmergetree** - 테이블 엔진 최적화 이해
2. **03-bech32-encoding** - 인코딩 및 보안 개념
3. **05-consistent-snapshot** - 트랜잭션 및 일관성

### 고급 사용자
- 모든 기능을 조합하여 실제 프로덕션 시나리오 구현
- EXPLAIN 명령으로 쿼리 실행 계획 분석
- 성능 벤치마킹 및 비교
- 실시간 데이터 파이프라인 설계

## 💡 Feature Comparison

### CoalescingMergeTree vs ReplacingMergeTree

| Feature | CoalescingMergeTree | ReplacingMergeTree |
|---------|---------------------|-------------------|
| 업데이트 방식 | Sign 컬럼 (-1, +1) | 버전 컬럼 |
| 병합 시점 | 자동 병합 | FINAL 쿼리 필요 |
| 성능 | 빈번한 업데이트에 적합 | 드문 업데이트에 적합 |
| 용도 | 메트릭, CDC | 마스터 데이터, 차원 테이블 |

### Time vs DateTime

| Feature | Time/Time64 | DateTime |
|---------|-------------|----------|
| 저장 내용 | 시간만 (자정 기준) | 날짜 + 시간 |
| 정밀도 | 초 or 마이크로초 | 초 |
| 용도 | 업무 시간, 일정 | 타임스탬프, 이벤트 |
| 저장 크기 | 작음 | 큰 |

## 🔍 Additional Resources

- **Official Release Blog**: [ClickHouse 25.6 Release](https://clickhouse.com/blog/clickhouse-release-25-06)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **GitHub Repository**: [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)

## 📝 Notes

- 각 스크립트는 독립적으로 실행 가능합니다
- SQL 파일을 직접 읽고 수정하여 실험해보세요
- 테스트 데이터는 각 SQL 파일 내에서 생성됩니다
- 정리(cleanup)는 기본적으로 주석 처리되어 있습니다
- 프로덕션 환경 적용 전 충분한 테스트를 권장합니다

## 🔒 Security Considerations

**Bech32 인코딩 사용 시:**
- 체크섬이 포함되어 있지만 암호화는 아님
- 민감한 데이터는 추가 암호화 필요
- 공개 식별자로만 사용 권장

**CoalescingMergeTree 사용 시:**
- Sign 컬럼 관리에 주의
- 애플리케이션 레벨에서 일관성 보장 필요
- 동시성 제어 메커니즘 고려

## ⚡ Performance Tips

**CoalescingMergeTree:**
- 적절한 ORDER BY 키 설정으로 머지 효율 향상
- 파티션 전략으로 과거 데이터 관리
- Sign 필터링으로 읽기 성능 최적화

**Time64 데이터 타입:**
- 높은 정밀도가 필요한 경우만 Time64 사용
- 대부분의 경우 Time으로 충분
- 인덱스 및 파티션 키로 사용 가능

**lag/lead 함수:**
- 적절한 PARTITION BY로 윈도우 크기 제한
- ORDER BY 최적화로 정렬 비용 감소
- 큰 offset 값은 성능에 영향

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
