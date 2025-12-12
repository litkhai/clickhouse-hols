# Device360 PoC 실행 체크리스트

## 📋 사전 준비 체크리스트

### 1. 계정 및 인프라
- [ ] AWS 계정 준비
  - [ ] IAM 사용자 생성 (또는 기존 사용자)
  - [ ] S3 권한 확인 (create bucket, put object, get object)
  - [ ] Access Key ID 발급
  - [ ] Secret Access Key 발급

- [ ] ClickHouse Cloud 계정 준비
  - [ ] 인스턴스 생성 (최소 16GB RAM 권장)
  - [ ] 호스트 주소 확인 (예: xxx.clickhouse.cloud)
  - [ ] 패스워드 확인
  - [ ] 포트 확인 (기본: 8443)

### 2. 로컬 환경
- [ ] Python 3.8 이상 설치 확인
  ```bash
  python3 --version
  ```

- [ ] Pip 업그레이드
  ```bash
  pip3 install --upgrade pip
  ```

- [ ] 디스크 공간 확인
  - [ ] 1GB 테스트: 최소 5GB 여유
  - [ ] 50GB 테스트: 최소 100GB 여유
  - [ ] 300GB 테스트: 최소 500GB 여유

- [ ] Git repository clone
  ```bash
  git pull origin main
  cd workshop/device-360
  ```

### 3. 프로젝트 설정
- [ ] `.env` 파일 생성
  ```bash
  cp .env.template .env
  ```

- [ ] `.env` 파일 편집 - AWS 섹션
  ```bash
  AWS_ACCESS_KEY_ID=AKIA...
  AWS_SECRET_ACCESS_KEY=...
  AWS_REGION=us-east-1
  S3_BUCKET_NAME=device360-test-data-YOURNAME
  ```

- [ ] `.env` 파일 편집 - ClickHouse 섹션
  ```bash
  CLICKHOUSE_HOST=xxx.clickhouse.cloud
  CLICKHOUSE_PORT=8443
  CLICKHOUSE_USER=default
  CLICKHOUSE_PASSWORD=...
  CLICKHOUSE_DATABASE=device360
  ```

- [ ] `.env` 파일 편집 - 데이터 파라미터
  ```bash
  # 빠른 테스트용
  TARGET_SIZE_GB=1
  NUM_RECORDS=1700000
  NUM_DEVICES=100000

  # 또는 전체 규모
  # TARGET_SIZE_GB=300
  # NUM_RECORDS=500000000
  # NUM_DEVICES=100000000
  ```

- [ ] Python 의존성 설치
  ```bash
  pip3 install -r requirements.txt
  ```

- [ ] 의존성 확인
  ```bash
  python3 -c "import boto3, clickhouse_connect; print('OK')"
  ```

---

## 🚀 빠른 테스트 실행 체크리스트 (1GB)

### Phase 0: 준비
- [ ] `.env` 파일 설정 완료
- [ ] 스크립트 실행 권한 부여
  ```bash
  chmod +x quick-test.sh setup.sh
  chmod +x scripts/*.py
  ```

### Phase 1: 빠른 테스트 실행
- [ ] 빠른 테스트 시작
  ```bash
  ./quick-test.sh
  ```

- [ ] 데이터 생성 완료 확인
  - [ ] `data/` 디렉토리 생성 확인
  - [ ] `*.json.gz` 파일 생성 확인
  - [ ] 파일 크기 확인 (~600MB per file)
  ```bash
  ls -lh data/
  du -sh data/
  ```

- [ ] S3 업로드 완료 확인
  ```bash
  aws s3 ls s3://$S3_BUCKET_NAME/device360/
  ```

- [ ] ClickHouse 수집 완료 확인
  - [ ] 에러 없이 완료
  - [ ] Rows 수 확인
  - [ ] 테이블 생성 확인

- [ ] 벤치마크 실행 완료
  - [ ] 성공한 쿼리 수 확인
  - [ ] 평균 실행 시간 확인
  - [ ] 결과 파일 생성 확인

### Phase 2: 결과 확인
- [ ] 로그 확인
  ```bash
  ls -lh logs/
  ```

- [ ] 벤치마크 결과 확인
  ```bash
  ls -lh results/
  cat results/benchmark_results_*.json | jq
  ```

- [ ] ClickHouse 데이터 확인
  ```bash
  # 직접 쿼리 실행 (선택사항)
  clickhouse-client --host $CLICKHOUSE_HOST \
    --user $CLICKHOUSE_USER \
    --password $CLICKHOUSE_PASSWORD \
    --secure \
    --query "SELECT count() FROM device360.ad_requests"
  ```

### Phase 3: 성능 검증
- [ ] 성능 목표 달성 확인
  - [ ] < 100ms 쿼리 비율: ____% (목표: 40%+)
  - [ ] < 500ms 쿼리 비율: ____% (목표: 80%+)
  - [ ] < 1s 쿼리 비율: ____% (목표: 90%+)
  - [ ] < 3s 쿼리 비율: ____% (목표: 100%)

- [ ] 주요 쿼리 성능 기록
  - [ ] Single device lookup: ____ ms (목표: <100ms)
  - [ ] Device journey timeline: ____ ms (목표: <500ms)
  - [ ] Session detection: ____ ms (목표: <1s)
  - [ ] Bot detection: ____ ms (목표: <3s)

---

## 🏗️ 전체 규모 테스트 체크리스트 (300GB)

### Phase 0: 준비
- [ ] 빠른 테스트 완료 및 검증
- [ ] 디스크 공간 확인 (500GB+)
- [ ] `.env` 파일에서 TARGET_SIZE_GB=300 설정
- [ ] 예상 소요 시간 확보 (4-6시간)

### Phase 1: 데이터 생성
- [ ] 데이터 생성 시작
  ```bash
  ./setup.sh
  # 메뉴에서 1 선택
  ```

- [ ] 진행 상황 모니터링
  - [ ] 파일 생성 진행률 확인
  - [ ] 디스크 사용량 모니터링
  ```bash
  watch -n 10 'ls -lh data/ | tail -5; df -h .'
  ```

- [ ] 생성 완료 확인
  - [ ] 총 파일 수: ~500개
  - [ ] 총 크기: ~300GB
  ```bash
  ls data/*.json.gz | wc -l
  du -sh data/
  ```

### Phase 2: S3 업로드
- [ ] S3 업로드 시작
  ```bash
  ./setup.sh
  # 메뉴에서 2 선택
  ```

- [ ] 업로드 진행 모니터링
  - [ ] 업로드 속도 확인 (MB/s)
  - [ ] 완료된 파일 수 확인

- [ ] 업로드 완료 확인
  ```bash
  aws s3 ls s3://$S3_BUCKET_NAME/device360/ | wc -l
  aws s3 ls s3://$S3_BUCKET_NAME/device360/ --summarize --human-readable
  ```

### Phase 3: S3 Integration 설정
- [ ] ClickHouse Cloud 콘솔에서 Role ID 확인
  - 경로: Settings → S3 Integration → Copy Role ID

- [ ] S3 integration 스크립트 실행
  ```bash
  ./setup.sh
  # 메뉴에서 3 선택
  ```

- [ ] Role ID 입력
  - [ ] Role ARN 출력 확인
  - [ ] `.env` 파일에 S3_ROLE_ARN 추가

- [ ] ClickHouse Cloud에서 S3 integration 설정
  - [ ] Role ARN 등록
  - [ ] Bucket 접근 권한 확인

### Phase 4: ClickHouse 데이터 수집
- [ ] 수집 시작
  ```bash
  ./setup.sh
  # 메뉴에서 4 선택
  ```

- [ ] 스키마 생성 확인
  - [ ] Database 생성
  - [ ] Main table 생성
  - [ ] Materialized views 생성

- [ ] 수집 진행 모니터링
  - [ ] Rows/s 확인
  - [ ] 총 수집된 rows 추적
  ```bash
  tail -f logs/04_ingest_*.log
  ```

- [ ] 수집 완료 확인
  - [ ] 총 rows: ~500M
  - [ ] 에러 없음
  - [ ] Materialized views populated

- [ ] ClickHouse에서 데이터 검증
  ```sql
  SELECT count() FROM device360.ad_requests;
  -- Expected: ~500,000,000

  SELECT uniq(device_id) FROM device360.ad_requests;
  -- Expected: ~100,000,000

  SELECT min(event_date), max(event_date) FROM device360.ad_requests;
  -- Expected: ~30 days range
  ```

### Phase 5: 벤치마크 실행
- [ ] 벤치마크 시작
  ```bash
  ./setup.sh
  # 메뉴에서 5 선택
  ```

- [ ] 45개 쿼리 실행 진행 확인
  - [ ] Device Journey queries (10)
  - [ ] Aggregation queries (12)
  - [ ] Bot Detection queries (12)
  - [ ] Materialized View queries (11)

- [ ] 실시간 진행 확인
  ```bash
  tail -f logs/05_benchmarks_*.log
  ```

- [ ] 벤치마크 완료 확인
  - [ ] 성공/실패 쿼리 수
  - [ ] 평균 실행 시간
  - [ ] 결과 파일 생성

---

## 📊 결과 분석 체크리스트

### 1. 성능 메트릭 수집
- [ ] 벤치마크 JSON 결과 파싱
  ```bash
  cat results/benchmark_results_*.json | jq '.results[] | {name: .query_name, duration: .duration_ms, success: .success}'
  ```

- [ ] 성능 목표 달성률 계산
  - [ ] < 100ms: ____/____  (____%)
  - [ ] < 500ms: ____/____  (____%)
  - [ ] < 1s: ____/____  (____%)
  - [ ] < 3s: ____/____  (____%)

- [ ] Top 5 가장 느린 쿼리 식별
  ```bash
  cat results/benchmark_results_*.json | jq -r '.results[] | select(.success == true) | [.query_name, .duration_ms] | @tsv' | sort -k2 -nr | head -5
  ```

### 2. 카테고리별 분석
- [ ] Device Journey 성능 (10 queries)
  - 평균: ____ ms
  - 목표 달성: ____/10

- [ ] Aggregation 성능 (12 queries)
  - 평균: ____ ms
  - 목표 달성: ____/12

- [ ] Bot Detection 성능 (12 queries)
  - 평균: ____ ms
  - 목표 달성: ____/12

- [ ] Materialized View 비교 (11 queries)
  - MV 평균: ____ ms
  - Raw 평균: ____ ms
  - 개선율: ____x

### 3. BigQuery 대비 개선율
- [ ] Single device lookup
  - ClickHouse: ____ ms
  - BigQuery 기준: 10-30s
  - 개선율: ____x

- [ ] Device journey timeline
  - ClickHouse: ____ ms
  - BigQuery 기준: 30-60s
  - 개선율: ____x

- [ ] Session detection
  - ClickHouse: ____ ms
  - BigQuery 기준: 1-2min
  - 개선율: ____x

- [ ] Daily device GROUP BY
  - ClickHouse: ____ ms
  - BigQuery 기준: 30-60s
  - 개선율: ____x

### 4. 시스템 리소스 분석
- [ ] ClickHouse 시스템 쿼리 실행
  ```sql
  -- 쿼리 로그 분석
  SELECT
      formatReadableSize(read_bytes) as read_size,
      query_duration_ms,
      query
  FROM system.query_log
  WHERE database = 'device360'
    AND type = 'QueryFinish'
  ORDER BY query_duration_ms DESC
  LIMIT 10;
  ```

- [ ] 테이블 크기 확인
  ```sql
  SELECT
      table,
      formatReadableSize(sum(bytes)) as size,
      formatReadableQuantity(sum(rows)) as rows
  FROM system.parts
  WHERE database = 'device360'
  GROUP BY table;
  ```

- [ ] 메모리 사용량 확인
  - Peak memory: ____
  - Average memory: ____

### 5. 수집 성능 분석
- [ ] 평균 수집 속도: ____ rows/s
- [ ] 총 수집 시간: ____ minutes
- [ ] 파일당 평균 시간: ____ seconds
- [ ] 네트워크 throughput: ____ MB/s

---

## 📝 최종 보고서 체크리스트

### 1. Executive Summary
- [ ] 프로젝트 목적 요약
- [ ] 주요 성과 3가지
- [ ] 성능 개선율 하이라이트
- [ ] 비즈니스 임팩트

### 2. 테스트 환경
- [ ] 데이터 규모 (GB, rows, devices)
- [ ] ClickHouse 인스턴스 스펙
- [ ] 테스트 기간
- [ ] 비용 산정

### 3. 성능 결과
- [ ] 45개 쿼리 결과 테이블
- [ ] 카테고리별 평균 성능
- [ ] BigQuery 대비 개선율 차트
- [ ] 목표 달성률 시각화

### 4. 주요 발견사항
- [ ] Device-first ORDER BY의 효과
- [ ] Materialized View 성능 향상
- [ ] 고카디널리티 처리 능력
- [ ] Bot detection 정확도

### 5. 권장사항
- [ ] 프로덕션 배포 계획
- [ ] 최적 인스턴스 크기
- [ ] Monitoring 전략
- [ ] 추가 최적화 방안

---

## ✅ 최종 확인

### 프로젝트 완료 확인
- [ ] 모든 스크립트 정상 실행
- [ ] 모든 데이터 수집 완료
- [ ] 벤치마크 결과 저장
- [ ] 로그 파일 보관

### 문서화 완료
- [ ] README.md 검토
- [ ] USAGE_GUIDE.md 검토
- [ ] PROJECT_SUMMARY.md 검토
- [ ] 이 체크리스트 완료

### 결과물 준비
- [ ] 벤치마크 JSON 파일
- [ ] 로그 파일 압축
- [ ] 스크린샷 캡처 (선택)
- [ ] 최종 보고서 작성

---

## 🎯 다음 단계

- [ ] 결과 공유 및 리뷰
- [ ] 추가 테스트 시나리오 논의
- [ ] 프로덕션 마이그레이션 계획
- [ ] 비용/성능 최적화 검토

---

**체크리스트 버전:** 1.0
**최종 업데이트:** 2025-12-11
