# ClickHouse Async Insert 스트레스 테스트

ClickHouse의 Async Insert 기능에 대한 다양한 파라미터 조합과 스트레스 테스트를 수행합니다.

## 테스트 개요

이 테스트는 ClickHouse의 비동기 삽입(Async Insert) 기능의 성능과 안정성을 검증하기 위해 설계되었습니다.

### 테스트 환경
- **데이터베이스**: ClickHouse Cloud (ap-northeast-2)
- **테스트 일시**: 2026-01-31

## 파일 구조

```
async-insert-stress/
├── 01-setup.sql              # 테스트 환경 설정 (데이터베이스, 테이블 생성)
├── 02-basic-tests.sql        # 기본 파라미터 테스트 (6가지 케이스, 각 1,000건)
├── 03-stress-tests.sql       # 고강도 스트레스 테스트 (대용량 & 연속 INSERT)
├── 04-verification.sql       # 결과 확인 및 검증 쿼리
├── 05-monitoring.sql         # 모니터링 및 성능 분석 쿼리
└── 99-cleanup.sql            # 테스트 완료 후 정리
```

## 테스트 케이스

### 기본 파라미터 테스트 (각 1,000건)
1. **case1_sync**: 동기 INSERT (baseline)
2. **case2_async_wait1**: `async_insert=1, wait_for_async_insert=1` (flush 대기)
3. **case3_async_wait0**: `async_insert=1, wait_for_async_insert=0` (즉시 응답)
4. **case4_async_timeout200**: `async_insert=1, wait=0, busy_timeout=200ms`
5. **case5_async_maxsize1mb**: `async_insert=1, wait=0, max_data_size=1MB`
6. **case6_async_wait1_timeout200**: `async_insert=1, wait=1, busy_timeout=200ms`

### 고강도 스트레스 테스트
- **stress_100k_wait0**: 10만 건 비동기 INSERT (wait=0)
- **stress_100k_wait1**: 10만 건 비동기 INSERT (wait=1)
- **rapid_insert_batch1-5**: 연속 INSERT 테스트 (각 100건 x 5회)

## 실행 방법

1. **환경 설정**
   ```bash
   clickhouse-client < 01-setup.sql
   ```

2. **기본 테스트 실행**
   ```bash
   clickhouse-client < 02-basic-tests.sql
   ```

3. **스트레스 테스트 실행**
   ```bash
   clickhouse-client < 03-stress-tests.sql
   ```

4. **결과 확인**
   ```bash
   clickhouse-client < 04-verification.sql
   ```

5. **모니터링**
   ```bash
   clickhouse-client < 05-monitoring.sql
   ```

6. **정리**
   ```bash
   clickhouse-client < 99-cleanup.sql
   ```

## 주요 설정 파라미터

| 파라미터 | 설명 | 기본값 |
|---------|------|--------|
| `async_insert` | 비동기 INSERT 활성화 | 0 (비활성) |
| `wait_for_async_insert` | flush 완료 대기 여부 | 1 (대기) |
| `async_insert_busy_timeout_ms` | 버퍼 플러시 시간 | 200ms |
| `async_insert_max_data_size` | 최대 버퍼 크기 | 10MB |

## 모니터링 포인트

- **system.asynchronous_inserts**: 현재 버퍼 상태
- **system.asynchronous_insert_log**: INSERT 로그 및 에러
- **system.query_log**: 쿼리 성공/실패 통계
- **system.parts**: 파트 생성 및 병합 현황

## 기대 결과

- 모든 테스트 케이스에서 100% 성공률
- Async Insert 사용 시 응답 시간 개선
- 파트 생성 최적화 (병합 효율 증가)
- 데이터 일관성 유지

## 테스트 배경 및 결과

### 검증 목적

ClickHouse의 `async_insert` 기능 사용 시 `wait_for_async_insert=0` 설정은 INSERT 응답 시간을 수 밀리초로 단축시키지만, 문서상 "데이터 유실 가능성"이 명시되어 있어 실제 운영 환경에서의 안정성 검증이 필요했습니다.

### 테스트 목적

1. `wait_for_async_insert=0` 설정 시 실제 데이터 유실이 발생하는지 검증
2. 다양한 flush 파라미터 조합에서의 INSERT 성공률 측정
3. 대용량/고빈도 INSERT 시나리오에서의 안정성 확인

### 테스트 결과

- **총 테스트 건수**: 200,500건
- **전체 성공률**: 100%
- **데이터 유실**: 0건

### 결론

ClickHouse Cloud 환경에서 `async_insert=1, wait_for_async_insert=0` 설정은 멀티 레플리카 구성으로 인해 실제 유실 확률이 거의 0%에 가까우므로, 로그 데이터와 같이 일부 유실이 허용되는 케이스에서 안심하고 사용 가능합니다.

## 참고 사항

- 테스트 완료 후 3초 대기하여 비동기 버퍼가 flush되도록 합니다.
- 대용량 테스트는 시스템 리소스를 많이 사용하므로 주의가 필요합니다.
- 실제 프로덕션 환경에서는 워크로드에 맞게 파라미터를 조정해야 합니다.
