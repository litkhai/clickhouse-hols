# HyperDX 설정 빠른 참조 카드

## 🚀 1분 설정 가이드

### 옵션 1: Materialized View 사용 (권장 ⭐)

**Connection 정보:**
```
Name: ClickHouse Cloud - OTEL (Converted)
Host: a7rzc4b3c1.ap-northeast-2.aws.clickhouse.cloud
Port: 9440
User: default
Password: HTPiB0FXg8.3K
Database: o11y
Secure: ✅
```

**Trace Source 기본 설정:**
```
Name: OTEL Traces (Converted)
Table: otel_traces_conv
Timestamp Column: Timestamp
```

### 옵션 2: ingest_otel 데이터베이스 사용

**Connection 정보:**
```
Name: ClickHouse Cloud - OTEL
Host: a7rzc4b3c1.ap-northeast-2.aws.clickhouse.cloud
Port: 9440
User: default
Password: HTPiB0FXg8.3K
Database: ingest_otel
Secure: ✅
```

**Trace Source 기본 설정:**
```
Name: OTEL Traces
Table: otel_traces
Timestamp Column: Timestamp
```

### Expression 설정 (복사해서 붙여넣기)

#### 옵션 1 사용 시 (otel_traces_conv) ⭐

| 필드 | 값 |
|------|-----|
| Trace Id Expression | `TraceId` |
| Span Id Expression | `SpanId` |
| Parent Span Id Expression | `ParentSpanId` |
| Span Name Expression | `SpanName` |
| Service Name Expression | `ServiceName` |
| **Span Kind Expression** | `SpanKind` ⭐ (변환 불필요!) |
| Duration Expression | `Duration` |
| Duration Precision | `nanoseconds` |
| Status Code Expression | `StatusCode` |
| Status Message Expression | `StatusMessage` |

#### 옵션 2 사용 시 (ingest_otel)

| 필드 | 값 |
|------|-----|
| Trace Id Expression | `TraceId` |
| Span Id Expression | `SpanId` |
| Parent Span Id Expression | `ParentSpanId` |
| Span Name Expression | `SpanName` |
| Service Name Expression | `ServiceName` |
| **Span Kind Expression** | `replaceAll(SpanKind, 'SPAN_KIND_', '')` |
| Duration Expression | `Duration` |
| Duration Precision | `nanoseconds` |
| Status Code Expression | `StatusCode` |
| Status Message Expression | `StatusMessage` |

---

## 📋 복사 가능한 Expression 값

### Trace Id Expression
```
TraceId
```

### Span Id Expression
```
SpanId
```

### Parent Span Id Expression
```
ParentSpanId
```

### Span Name Expression
```
SpanName
```

### Service Name Expression
```
ServiceName
```

### Span Kind Expression (⭐ 가장 중요!)

**옵션 1 (otel_traces_conv) - 권장:**
```
SpanKind
```

**옵션 2 (ingest_otel):**
```
replaceAll(SpanKind, 'SPAN_KIND_', '')
```

### Duration Expression
```
Duration
```

### Duration Precision
```
nanoseconds
```

### Status Code Expression
```
StatusCode
```

### Status Message Expression
```
StatusMessage
```

---

## ✅ 검증 명령어

```bash
cd /Users/kenlee/Documents/GitHub/clickhouse-hols/workshop/o11y-vector-ai
./verify-hyperdx-data.sh
```

---

## 🔍 예상 결과

### Service Map

```
            sample-ecommerce-app
                  ↓        ↓
        inventory-service  payment-service
```

### 호출 통계

- **inventory-service**: ~160 calls/10min, ~95ms avg
- **payment-service**: ~15 calls/10min, ~850ms avg

---

## 🐛 문제 해결

### Service Map이 안 보이는 경우

**옵션 1 (otel_traces_conv) 사용 시:**

1. **Table 확인**
   - 반드시: `otel_traces_conv`
   - ❌ 잘못된 값: `otel_traces`

2. **Span Kind Expression 확인**
   - 반드시: `SpanKind` (단순 컬럼명)
   - ❌ 잘못된 값: `replaceAll(...)` (불필요)

3. **브라우저 캐시 클리어**
   - Windows: Ctrl+Shift+R
   - Mac: Cmd+Shift+R

**옵션 2 (ingest_otel) 사용 시:**

1. **Span Kind Expression 확인**
   - 반드시: `replaceAll(SpanKind, 'SPAN_KIND_', '')`
   - ❌ 잘못된 값: `SpanKind` (변환 없음)

2. **Database 확인**
   - 반드시: `ingest_otel`
   - ❌ 잘못된 값: `o11y`

3. **브라우저 캐시 클리어**
   - Windows: Ctrl+Shift+R
   - Mac: Cmd+Shift+R

**공통:**

4. **Trace Source 재생성**
   - 기존 Source 삭제
   - 새로 생성 (위의 값 사용)

---

## 📚 더 많은 정보

- **Materialized View 설정**: [MATERIALIZED_VIEW_SETUP.md](./MATERIALIZED_VIEW_SETUP.md) ⭐
- 빠른 시작: [README_HYPERDX.md](./README_HYPERDX.md)
- 상세 설정: [HYPERDX_CONFIGURATION_SUMMARY.md](./HYPERDX_CONFIGURATION_SUMMARY.md)
- 문제 해결: [HYPERDX_TROUBLESHOOTING.md](./HYPERDX_TROUBLESHOOTING.md)
- 한국어 요약: [SOLUTION_SUMMARY_KO.md](./SOLUTION_SUMMARY_KO.md)
