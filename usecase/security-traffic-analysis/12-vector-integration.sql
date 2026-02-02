-- ============================================================
-- Bug Bounty Vector Search - Step 5: Integration Guide
-- Python/API 통합 및 프로덕션 배포 가이드
-- ============================================================

/*
이 파일은 Vector Search를 실제 프로덕션 환경에 통합하는 방법을 제공합니다.

주요 내용:
1. Python 통합 예시 (OpenAI, Sentence Transformers)
2. 실시간 임베딩 파이프라인
3. 배치 처리 워크플로우
4. 성능 최적화 및 베스트 프랙티스
5. 프로덕션 체크리스트
*/

-- ============================================================
-- PART 1: Python + OpenAI API 통합
-- ============================================================

/*
필수 패키지 설치:
```bash
pip install clickhouse-connect openai python-dotenv
```

환경 변수 설정 (.env):
```
OPENAI_API_KEY=sk-...
CLICKHOUSE_HOST=your-host.clickhouse.cloud
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=your-password
CLICKHOUSE_DATABASE=bug_bounty
```
*/

-- Python 코드 예시 1: OpenAI를 사용한 임베딩 생성
/*
```python
import os
import clickhouse_connect
from openai import OpenAI
from dotenv import load_dotenv

# 환경 변수 로드
load_dotenv()

# 클라이언트 초기화
openai_client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))
ch_client = clickhouse_connect.get_client(
    host=os.getenv('CLICKHOUSE_HOST'),
    user=os.getenv('CLICKHOUSE_USER'),
    password=os.getenv('CLICKHOUSE_PASSWORD'),
    database=os.getenv('CLICKHOUSE_DATABASE'),
    secure=True
)

def get_embedding(text: str, model: str = "text-embedding-3-small") -> list[float]:
    """텍스트를 벡터 임베딩으로 변환"""
    text = text.replace("\n", " ").strip()

    # OpenAI API 호출
    response = openai_client.embeddings.create(
        model=model,
        input=text,
        encoding_format="float"
    )

    return response.data[0].embedding


def embed_http_request(packet_id: str, method: str, uri: str, body: str):
    """HTTP 요청을 임베딩하여 ClickHouse에 저장"""
    # 정규화된 텍스트 생성 (길이 제한)
    normalized = f"{method} {uri}\n{body[:1000]}"

    # 임베딩 생성
    embedding = get_embedding(normalized)

    # ClickHouse에 삽입
    ch_client.insert(
        'request_embeddings',
        [[packet_id, normalized, embedding, 'text-embedding-3-small', 1536]],
        column_names=[
            'packet_id', 'normalized_request', 'request_embedding',
            'embedding_model', 'embedding_dim'
        ]
    )

    print(f"✓ Embedded request {packet_id}")


def embed_bug_report(
    report_id: str,
    title: str,
    description: str,
    reproduction_steps: str,
    **kwargs
):
    """버그 리포트를 임베딩하여 저장"""
    # 주요 콘텐츠 결합
    content = f"{title}\n\n{description}\n\nReproduction:\n{reproduction_steps}"

    # 임베딩 생성
    embedding = get_embedding(content)

    # 리포트 데이터 준비
    data = {
        'report_id': report_id,
        'title': title,
        'description': description,
        'reproduction_steps': reproduction_steps,
        'content_embedding': embedding,
        'embedding_model': 'text-embedding-3-small',
        'embedding_dim': 1536,
        **kwargs
    }

    # ClickHouse에 삽입
    ch_client.insert('report_knowledge_base', [list(data.values())],
                     column_names=list(data.keys()))

    print(f"✓ Embedded report {report_id}")


# 사용 예시
if __name__ == "__main__":
    # HTTP 요청 임베딩
    embed_http_request(
        packet_id="550e8400-e29b-41d4-a716-446655440000",
        method="GET",
        uri="/api/users?id=1' OR '1'='1",
        body=""
    )

    # 버그 리포트 임베딩
    embed_bug_report(
        report_id="RPT-2024-009",
        title="SQL Injection in Search API",
        description="The search endpoint is vulnerable to SQL injection...",
        reproduction_steps="1. Navigate to /search\n2. Enter: test' UNION...",
        vulnerability_type="SQLi",
        affected_component="Search API",
        affected_endpoints=["/api/search"],
        reporter_id="hunter_999",
        reported_date="2024-02-01",
        status="SUBMITTED",
        priority="HIGH",
        bounty_amount=0.0
    )
```
*/


-- ============================================================
-- PART 2: 배치 임베딩 파이프라인
-- ============================================================

/*
대량의 데이터를 효율적으로 처리하는 배치 파이프라인

```python
import time
from typing import List, Tuple
from concurrent.futures import ThreadPoolExecutor, as_completed

def batch_embed_requests(batch_size: int = 100, max_workers: int = 5):
    """미처리 요청을 배치로 임베딩"""

    # 임베딩이 없는 요청 조회
    query = """
    SELECT p.packet_id, p.request_method, p.request_uri, p.request_body
    FROM bug_bounty.http_packets p
    LEFT JOIN bug_bounty.request_embeddings e ON p.packet_id = e.packet_id
    WHERE e.packet_id IS NULL
    LIMIT {batch_size}
    """

    result = ch_client.query(query.format(batch_size=batch_size))
    rows = result.result_rows

    if not rows:
        print("No pending requests to embed")
        return

    print(f"Processing {len(rows)} requests...")

    # 병렬 처리
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = []

        for packet_id, method, uri, body in rows:
            future = executor.submit(
                embed_http_request,
                packet_id, method, uri, body or ""
            )
            futures.append(future)

        # 완료 대기
        for future in as_completed(futures):
            try:
                future.result()
            except Exception as e:
                print(f"Error: {e}")

    print(f"✓ Completed batch embedding")


def incremental_embedding_job(interval_seconds: int = 60):
    """주기적으로 새 데이터를 임베딩하는 작업"""
    print(f"Starting incremental embedding job (interval: {interval_seconds}s)")

    while True:
        try:
            batch_embed_requests(batch_size=100)
            time.sleep(interval_seconds)
        except KeyboardInterrupt:
            print("\nStopping...")
            break
        except Exception as e:
            print(f"Error in incremental job: {e}")
            time.sleep(interval_seconds)


# 사용 예시
if __name__ == "__main__":
    # 배치 처리
    batch_embed_requests(batch_size=500)

    # 또는 지속적인 처리 (프로덕션)
    # incremental_embedding_job(interval_seconds=300)  # 5분마다
```
*/


-- ============================================================
-- PART 3: 실시간 유사도 검색 API
-- ============================================================

/*
Vector Search를 활용한 REST API 예시

```python
from flask import Flask, request, jsonify
from typing import List, Dict

app = Flask(__name__)

@app.route('/api/search/similar-attacks', methods=['POST'])
def search_similar_attacks():
    """유사한 공격 패턴 검색 API"""
    data = request.json
    packet_id = data.get('packet_id')
    top_k = data.get('top_k', 5)

    if not packet_id:
        return jsonify({'error': 'packet_id required'}), 400

    # Vector Search 쿼리
    query = """
    SELECT
        s.pattern_name,
        s.category,
        s.severity,
        s.cwe_id,
        round(cosineDistance(r.request_embedding, s.payload_embedding), 4) as distance,
        round(1 - cosineDistance(r.request_embedding, s.payload_embedding), 4) as similarity
    FROM bug_bounty.request_embeddings r
    CROSS JOIN bug_bounty.attack_signatures s
    WHERE r.packet_id = {packet_id:UUID}
    ORDER BY distance ASC
    LIMIT {top_k:UInt8}
    """

    result = ch_client.query(
        query,
        parameters={'packet_id': packet_id, 'top_k': top_k}
    )

    matches = [
        {
            'pattern': row[0],
            'category': row[1],
            'severity': row[2],
            'cwe_id': row[3],
            'distance': row[4],
            'similarity': row[5]
        }
        for row in result.result_rows
    ]

    return jsonify({
        'packet_id': packet_id,
        'matches': matches,
        'count': len(matches)
    })


@app.route('/api/reports/check-duplicate', methods=['POST'])
def check_duplicate_report():
    """중복 리포트 검사 API"""
    data = request.json

    # 새 리포트 콘텐츠
    title = data.get('title')
    description = data.get('description')
    reproduction_steps = data.get('reproduction_steps', '')

    # 임베딩 생성
    content = f"{title}\n\n{description}\n\n{reproduction_steps}"
    embedding = get_embedding(content)

    # 유사 리포트 검색
    query = """
    SELECT
        report_id,
        title,
        vulnerability_type,
        status,
        bounty_amount,
        round(cosineDistance(content_embedding, {embedding:Array(Float32)}), 4) as distance
    FROM bug_bounty.report_knowledge_base
    WHERE status IN ('ACCEPTED', 'FIXED', 'TRIAGED')
      AND distance < 0.4
    ORDER BY distance ASC
    LIMIT 5
    """

    result = ch_client.query(query, parameters={'embedding': embedding})

    duplicates = [
        {
            'report_id': row[0],
            'title': row[1],
            'type': row[2],
            'status': row[3],
            'bounty': float(row[4]),
            'similarity': 1 - row[5]
        }
        for row in result.result_rows
    ]

    is_duplicate = len(duplicates) > 0 and duplicates[0]['similarity'] > 0.8

    return jsonify({
        'is_duplicate': is_duplicate,
        'similar_reports': duplicates,
        'recommendation': 'REJECT' if is_duplicate else 'PROCEED'
    })


@app.route('/api/search/semantic', methods=['POST'])
def semantic_search():
    """자연어 쿼리로 리포트 검색"""
    data = request.json
    query_text = data.get('query')
    top_k = data.get('top_k', 10)

    # 쿼리 임베딩
    query_embedding = get_embedding(query_text)

    # 검색
    search_query = """
    SELECT
        report_id,
        title,
        description,
        vulnerability_type,
        status,
        bounty_amount,
        round(1 - cosineDistance(content_embedding, {embedding:Array(Float32)}), 4) as relevance
    FROM bug_bounty.report_knowledge_base
    WHERE relevance > 0.5
    ORDER BY relevance DESC
    LIMIT {top_k:UInt8}
    """

    result = ch_client.query(
        search_query,
        parameters={'embedding': query_embedding, 'top_k': top_k}
    )

    results = [
        {
            'report_id': row[0],
            'title': row[1],
            'description': row[2][:200] + '...',
            'type': row[3],
            'status': row[4],
            'bounty': float(row[5]),
            'relevance': row[6]
        }
        for row in result.result_rows
    ]

    return jsonify({
        'query': query_text,
        'results': results,
        'count': len(results)
    })


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
```

API 사용 예시:
```bash
# 유사 공격 검색
curl -X POST http://localhost:5000/api/search/similar-attacks \
  -H "Content-Type: application/json" \
  -d '{"packet_id": "550e8400-e29b-41d4-a716-446655440000", "top_k": 5}'

# 중복 리포트 검사
curl -X POST http://localhost:5000/api/reports/check-duplicate \
  -H "Content-Type: application/json" \
  -d '{
    "title": "SQL Injection in Login",
    "description": "Authentication bypass using OR statements...",
    "reproduction_steps": "1. Enter admin OR 1=1..."
  }'

# 시맨틱 검색
curl -X POST http://localhost:5000/api/search/semantic \
  -H "Content-Type: application/json" \
  -d '{"query": "Find reports about authentication bypass", "top_k": 10}'
```
*/


-- ============================================================
-- PART 4: Sentence Transformers (로컬 임베딩)
-- ============================================================

/*
OpenAI API 없이 로컬에서 실행 (무료, 오프라인 가능)

설치:
```bash
pip install sentence-transformers
```

Python 코드:
```python
from sentence_transformers import SentenceTransformer
import numpy as np

# 모델 로드 (한 번만 실행, 캐시됨)
model = SentenceTransformer('all-MiniLM-L6-v2')  # 384 dimensions

def get_local_embedding(text: str) -> list[float]:
    """로컬 모델로 임베딩 생성"""
    embedding = model.encode(text, convert_to_numpy=True)
    return embedding.tolist()

def embed_with_local_model(packet_id: str, method: str, uri: str, body: str):
    """Sentence Transformers를 사용한 임베딩"""
    normalized = f"{method} {uri}\n{body[:1000]}"
    embedding = get_local_embedding(normalized)

    ch_client.insert(
        'request_embeddings',
        [[packet_id, normalized, embedding, 'all-MiniLM-L6-v2', 384]],
        column_names=[
            'packet_id', 'normalized_request', 'request_embedding',
            'embedding_model', 'embedding_dim'
        ]
    )

# 장점:
# - 무료, 오픈소스
# - API 호출 제한 없음
# - 오프라인 작동
# - 낮은 레이턴시

# 단점:
# - OpenAI보다 낮은 정확도 (일반적으로)
# - GPU 권장 (CPU도 가능하지만 느림)
# - 모델 크기 (수백 MB)
```
*/


-- ============================================================
-- PART 5: 성능 최적화 팁
-- ============================================================

/*
1. 임베딩 캐싱 전략
```python
import hashlib
from functools import lru_cache

@lru_cache(maxsize=10000)
def get_embedding_cached(text: str) -> tuple:
    """캐시된 임베딩 (메모리 효율적)"""
    embedding = get_embedding(text)
    return tuple(embedding)  # 리스트는 캐시 불가, 튜플로 변환

# 또는 Redis 사용
import redis
r = redis.Redis(host='localhost', port=6379, db=0)

def get_embedding_redis_cached(text: str) -> list[float]:
    """Redis 캐시 사용"""
    cache_key = f"emb:{hashlib.md5(text.encode()).hexdigest()}"

    # 캐시 확인
    cached = r.get(cache_key)
    if cached:
        return eval(cached)  # 주의: 프로덕션에서는 pickle 또는 json 사용

    # 캐시 미스, 임베딩 생성
    embedding = get_embedding(text)

    # 캐시 저장 (24시간)
    r.setex(cache_key, 86400, str(embedding))

    return embedding
```

2. 배치 임베딩 최적화
```python
def batch_get_embeddings(texts: List[str]) -> List[list[float]]:
    """여러 텍스트를 한 번에 임베딩 (더 효율적)"""
    # OpenAI는 배치를 지원
    response = openai_client.embeddings.create(
        model="text-embedding-3-small",
        input=texts  # 리스트 전달
    )

    return [item.embedding for item in response.data]

# 사용
texts = ["text1", "text2", "text3"]
embeddings = batch_get_embeddings(texts)
```

3. ClickHouse 쿼리 최적화
```sql
-- 잘못된 예: 모든 데이터 스캔
SELECT * FROM request_embeddings r
CROSS JOIN attack_signatures s
WHERE cosineDistance(r.request_embedding, s.payload_embedding) < 0.5;

-- 올바른 예: WHERE로 후보군 먼저 필터링
SELECT * FROM request_embeddings r
CROSS JOIN attack_signatures s
WHERE r.created_at >= today() - 7  -- 최근 7일만
  AND s.severity IN ('CRITICAL', 'HIGH')  -- 고위험만
  AND cosineDistance(r.request_embedding, s.payload_embedding) < 0.5;
```

4. 파티셔닝 전략
```sql
-- 시간 기반 파티셔닝 추가
ALTER TABLE request_embeddings
    MODIFY SETTING partition_by = toYYYYMM(created_at);

-- 오래된 파티션 삭제 (스토리지 절약)
ALTER TABLE request_embeddings DROP PARTITION '202401';
```
*/


-- ============================================================
-- PART 6: 프로덕션 체크리스트
-- ============================================================

/*
[ ] 1. 임베딩 모델 선택
    - OpenAI text-embedding-3-small (1536 dim) - 높은 정확도
    - OpenAI text-embedding-3-large (3072 dim) - 최고 정확도, 비용 증가
    - Sentence Transformers all-MiniLM-L6-v2 (384 dim) - 무료, 낮은 정확도
    - 기업용 모델 (Cohere, Voyage AI 등)

[ ] 2. 인프라 고려사항
    - API 키 보안 관리 (AWS Secrets Manager, HashiCorp Vault)
    - Rate limiting (OpenAI: 3000 RPM, 1M TPM)
    - 실패 처리 및 재시도 로직
    - 모니터링 및 알림 (Grafana, Prometheus)

[ ] 3. 데이터 품질
    - 텍스트 정규화 (공백, 특수문자 처리)
    - 길이 제한 (OpenAI: 8191 tokens)
    - 언어별 처리 (다국어 지원 필요 시)
    - 중복 제거 (같은 텍스트 반복 임베딩 방지)

[ ] 4. 성능 최적화
    - 배치 처리 (단일 요청보다 효율적)
    - 캐싱 (Redis, Memcached)
    - 비동기 처리 (Celery, RabbitMQ)
    - 파티셔닝 (시간, 카테고리 등)

[ ] 5. 비용 최적화
    - OpenAI embedding 비용: $0.00002 / 1K tokens
    - 월 100만 요청 = 약 $20 (평균 1K tokens)
    - 캐싱으로 중복 요청 방지
    - 불필요한 임베딩 제거 (TTL 설정)

[ ] 6. 보안 및 컴플라이언스
    - PII 데이터 마스킹 (임베딩 전)
    - API 키 로테이션
    - 데이터 암호화 (전송 중, 저장 시)
    - 감사 로그 (누가, 언제, 무엇을)

[ ] 7. 백업 및 복구
    - 임베딩 데이터 백업 (S3, GCS)
    - 재생성 가능 여부 확인
    - 재해 복구 계획 (DR plan)

[ ] 8. 모니터링 메트릭
    - 임베딩 생성 레이턴시
    - API 호출 성공/실패율
    - 검색 정확도 (precision, recall)
    - 스토리지 사용량
    - 비용 추적
*/


-- ============================================================
-- PART 7: 테스트 및 검증
-- ============================================================

-- 임베딩 품질 테스트 쿼리
CREATE OR REPLACE VIEW bug_bounty.v_embedding_quality_test AS
WITH test_pairs AS (
    -- 같은 카테고리 (유사해야 함)
    SELECT
        'Same Category' as pair_type,
        s1.pattern_name as pattern_1,
        s2.pattern_name as pattern_2,
        cosineDistance(s1.payload_embedding, s2.payload_embedding) as distance,
        'PASS' as expected
    FROM bug_bounty.attack_signatures s1
    JOIN bug_bounty.attack_signatures s2
        ON s1.category = s2.category
        AND s1.signature_id < s2.signature_id

    UNION ALL

    -- 다른 카테고리 (다르어야 함)
    SELECT
        'Different Category' as pair_type,
        s1.pattern_name as pattern_1,
        s2.pattern_name as pattern_2,
        cosineDistance(s1.payload_embedding, s2.payload_embedding) as distance,
        'PASS' as expected
    FROM bug_bounty.attack_signatures s1
    JOIN bug_bounty.attack_signatures s2
        ON s1.category != s2.category
        AND s1.signature_id < s2.signature_id
)
SELECT
    pair_type,
    count() as total_pairs,
    round(avg(distance), 4) as avg_distance,
    round(min(distance), 4) as min_distance,
    round(max(distance), 4) as max_distance,
    multiIf(
        pair_type = 'Same Category' AND avg(distance) < 0.5, 'PASS',
        pair_type = 'Different Category' AND avg(distance) > 0.5, 'PASS',
        'FAIL'
    ) as test_result
FROM test_pairs
GROUP BY pair_type;

-- 품질 테스트 실행
SELECT * FROM bug_bounty.v_embedding_quality_test
FORMAT PrettyCompactMonoBlock;


-- ============================================================
-- 마무리
-- ============================================================

/*
축하합니다! 🎉

Vector Search 실습을 완료했습니다. 이제 다음을 할 수 있습니다:

✓ 공격 패턴 시그니처 저장 및 관리
✓ HTTP 요청 임베딩 생성 및 검색
✓ 버그 리포트 시맨틱 검색
✓ 중복 리포트 자동 탐지
✓ Python/API 통합
✓ 프로덕션 배포 준비

다음 단계:
1. 실제 OpenAI API 키로 테스트
2. 프로덕션 데이터로 검증
3. 성능 벤치마크
4. CI/CD 파이프라인 구성
5. 모니터링 및 알림 설정

참고 자료:
- ClickHouse Vector Search: https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/annindexes
- OpenAI Embeddings: https://platform.openai.com/docs/guides/embeddings
- Sentence Transformers: https://www.sbert.net/

질문이나 피드백: https://github.com/ClickHouse/ClickHouse/discussions
*/

-- ============================================================
-- END OF VECTOR SEARCH LAB
-- ============================================================
