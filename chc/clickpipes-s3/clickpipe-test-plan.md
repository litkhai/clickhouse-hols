# ClickPipes S3 Pause/Resume 동작 테스트 계획서

## 1. 테스트 목적

S3 Object Storage ClickPipe를 중지 후 재시작했을 때:

1. 체크포인트가 기록되어 중지 시점부터 이어서 인입하는지
2. 처음부터 다시 인입하여 중복 데이터가 발생하는지

확인하여 고객에게 명확한 답변을 제공한다.

---

## 2. 사전 준비

### 2.1 S3 버킷 및 테스트 데이터 생성

```bash
# 테스트용 S3 버킷 설정
BUCKET_NAME="your-test-bucket"
PREFIX="clickpipe-test"

# 여러 날짜에 걸친 테스트 파일 생성 (과거 데이터 시뮬레이션)
for month in 01 02 03 04 05 06; do
  for day in 01 15; do
    echo '{"id": 1, "date": "2025-'$month'-'$day'", "value": "data_'$month'_'$day'"}' > /tmp/test_${month}_${day}.json
    aws s3 cp /tmp/test_${month}_${day}.json s3://${BUCKET_NAME}/${PREFIX}/ym=2025${month}/dt=2025${month}${day}/data.json
  done
done
```

### 2.2 대상 테이블 생성 (Workbench)

```sql
CREATE TABLE test_clickpipe_checkpoint
(
    id UInt32,
    date String,
    value String,
    _file String,
    _path String,
    _time DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (date, id);
```

---

## 3. 테스트 시나리오

### 시나리오 1: 기본 Pause/Resume 동작 확인

| 단계 | 작업 | 확인 사항 |
|------|------|-----------|
| 1 | ClickPipe 생성 (S3 → test_clickpipe_checkpoint) | Pipe 정상 생성 확인 |
| 2 | 일부 데이터 인입 확인 | 몇 개 파일이 인입되었는지 확인 |
| 3 | Pipe 중지 (Pause) | 중지 시점의 인입된 파일 목록 기록 |
| 4 | 1-2분 대기 | - |
| 5 | Pipe 재시작 (Resume) | 로그 및 동작 관찰 |
| 6 | 결과 확인 | 중복 여부 체크 |

### 시나리오 2: 파일 삭제 후 Resume 동작 확인

| 단계 | 작업 | 확인 사항 |
|------|------|-----------|
| 1 | 새 Pipe 생성 | - |
| 2 | 일부 데이터 인입 후 Pause | - |
| 3 | 아직 인입되지 않은 파일 중 일부 삭제 | 라이프사이클 시뮬레이션 |
| 4 | Pipe Resume | 에러 발생 여부 및 복구 동작 확인 |

---

## 4. 검증 쿼리 (Workbench)

### 4.1 인입된 데이터 현황 확인

```sql
SELECT 
    _path,
    _file,
    min(_time) AS first_inserted,
    max(_time) AS last_inserted,
    count() AS row_count
FROM test_clickpipe_checkpoint
GROUP BY _path, _file
ORDER BY first_inserted;
```

### 4.2 중복 데이터 확인 (핵심)

```sql
-- 동일 파일이 여러 번 인입되었는지 확인
SELECT 
    _path,
    count() AS insert_count
FROM test_clickpipe_checkpoint
GROUP BY _path
HAVING insert_count > 1
ORDER BY insert_count DESC;
```

### 4.3 시간대별 인입 현황

```sql
SELECT 
    toStartOfMinute(_time) AS minute,
    count() AS rows_inserted,
    groupUniqArray(_file) AS files
FROM test_clickpipe_checkpoint
GROUP BY minute
ORDER BY minute;
```

### 4.4 Pause 전후 비교

```sql
-- Pause 시점 기준으로 before/after 비교
-- HH:MM:SS를 실제 Pause 시점으로 변경
SELECT 
    if(_time < toDateTime('2025-01-09 HH:MM:SS'), 'before_pause', 'after_resume') AS phase,
    count() AS row_count,
    countDistinct(_path) AS unique_files
FROM test_clickpipe_checkpoint
GROUP BY phase;
```

---

## 5. 예상 결과 및 판단 기준

| 결과 | 의미 | 고객 안내 |
|------|------|-----------|
| 중복 없음 | 체크포인트 기록됨, 이어서 인입 | 중지/재시작 안전하게 사용 가능 |
| 중복 발생 | 처음부터 재인입 | Dedup 설계 필요 또는 SQS 파이프 권장 |
| 삭제 파일 스킵 후 계속 진행 | 자동 복구 동작 확인 | 라이프사이클 환경에서도 사용 가능 |

---

## 6. 추가 확인 사항

- [ ] ClickPipes UI에서 ingested files count 변화 관찰
- [ ] Error logs 탭에서 에러 메시지 확인
- [ ] 재시작 후 "Starting from file X" 같은 로그 존재 여부

---

## 7. 테스트 완료 후 정리

```sql
DROP TABLE IF EXISTS test_clickpipe_checkpoint;
```

```bash
aws s3 rm s3://${BUCKET_NAME}/${PREFIX}/ --recursive
```
