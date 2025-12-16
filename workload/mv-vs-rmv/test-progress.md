# MV vs RMV 테스트 - 실시간 진행 상황
# Test Progress - Real-time Status

---

## 📊 테스트 세션 정보 / Test Session Info

**Session ID**: `6aeefe3f-e03a-4d0e-9766-5211e423ecbb`
**테스트 시작 / Start Time**: 2025-12-16 02:25:53 KST
**테스트 유형 / Test Type**: 30분 Full Test
**목표 데이터 / Target Data**: 1,800,000 rows

---

## 🚀 실행 중인 프로세스 / Running Processes

| 프로세스 / Process | PID | 상태 / Status | 설명 / Description |
|-------------------|-----|---------------|---------------------|
| Data Generator | 91522 | ✅ Running | 1초당 1,000 rows 삽입 |
| Monitoring Collector | 91529 | ✅ Running | 1분마다 메트릭 수집 |
| Progress Monitor | 91713 | ✅ Running | 5분마다 상태 체크 |

---

## 📈 현재 진행 상황 / Current Progress

**최종 업데이트 / Last Update**: 2025-12-16 04:12:05 KST

| 테이블 / Table | 행 수 / Row Count | 진행률 / Progress | 비고 / Notes |
|---------------|-------------------|------------------|-------------|
| **events_source** | 244,000 | 13.6% | 소스 데이터 삽입 중 |
| **events_agg_mv** | 720 | - | 실시간 aggregation |
| **events_agg_rmv** | 240 | - | 다음 refresh 대기 |

---

## 🔄 RMV Refresh 상태 / RMV Refresh Status

- **Status**: Scheduled
- **Last Success**: 2025-12-16 04:10:00
- **Next Refresh**: 2025-12-16 04:15:00 (약 3분 후)
- **Refresh Interval**: 5분

---

## 📊 예상 완료 시간 / Estimated Completion

```
시작 시간 / Start:        02:25:53
현재 시간 / Current:       04:12:05
경과 시간 / Elapsed:       ~1시간 46분
현재 진행률 / Progress:    13.6% (244,000 / 1,800,000)
예상 완료 / ETA:          약 27분 후
```

---

## 🔍 실시간 모니터링 명령어 / Real-time Monitoring Commands

### 1. 현재 행 수 확인 / Check Current Row Count
```bash
clickhouse client --host <your-service>.<region>.aws.clickhouse.cloud \
  --secure --password <YOUR_PASSWORD> --query "
SELECT
    'Source' AS table, count() AS rows,
    round(count() / 1800000.0 * 100, 1) AS progress_pct
FROM mv_vs_rmv.events_source
UNION ALL
SELECT 'MV' AS table, count() AS rows, 0 FROM mv_vs_rmv.events_agg_mv
UNION ALL
SELECT 'RMV' AS table, count() AS rows, 0 FROM mv_vs_rmv.events_agg_rmv
FORMAT Pretty"
```

### 2. Part 수 확인 / Check Part Count
```bash
clickhouse client --host <your-service>.<region>.aws.clickhouse.cloud \
  --secure --password <YOUR_PASSWORD> --query "
SELECT
    table,
    count() AS parts,
    formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts
WHERE database = 'mv_vs_rmv'
  AND active
GROUP BY table
ORDER BY table
FORMAT Pretty"
```

### 3. 프로세스 상태 확인 / Check Process Status
```bash
ps aux | grep -E "(data_generator|monitoring_collector)" | grep -v grep
```

### 4. 로그 확인 / Check Logs
```bash
tail -f /tmp/data_generator.log
tail -f /tmp/monitoring.log
tail -f /tmp/test_progress.log
```

---

## 📁 관련 파일 / Related Files

- **데이터 생성 로그**: `/tmp/data_generator.log`
- **모니터링 로그**: `/tmp/monitoring.log`
- **진행 상황 로그**: `/tmp/test_progress.log`
- **세션 정보**: Session ID `6aeefe3f-e03a-4d0e-9766-5211e423ecbb`

---

## 🎯 예상 결과 / Expected Results

### Part 수 비교 / Part Count Comparison
- **MV**: 많은 Part 생성 예상 (실시간 처리)
- **RMV**: 적은 Part 생성 예상 (5분 배치)

### 데이터 볼륨 / Data Volume
- **Source**: 1,800,000 rows
- **MV aggregated**: ~4,000 rows (예상)
- **RMV aggregated**: ~600-800 rows (예상)

---

## ⚠️ 중단 방법 / How to Stop

테스트를 중단하려면:
```bash
kill 91522 91529 91713
```

---

## 📝 테스트 완료 후 / After Test Completion

1. 테스트 세션 종료 마킹
```sql
ALTER TABLE mv_vs_rmv.test_sessions
UPDATE end_time = now64(3)
WHERE session_id = '6aeefe3f-e03a-4d0e-9766-5211e423ecbb';
```

2. 결과 분석 쿼리 실행
```bash
clickhouse client --host YOUR_HOST --secure --password YOUR_PASSWORD \
  < queries/analyze_results.sql
```
(analyze_results.sql에서 `<SESSION_ID>`를 `6aeefe3f-e03a-4d0e-9766-5211e423ecbb`로 교체)

---

**Status**: ✅ 테스트 진행 중 / Test in Progress
**Last Updated**: 2025-12-16 04:12:05 KST
