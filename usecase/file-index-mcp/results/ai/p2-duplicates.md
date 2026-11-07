## p2-duplicates (rules)

> 내용이 동일한 중복 파일 때문에 낭비되는 용량이 얼마야? 낭비가 큰 상위 20개 그룹을 경로 예시와 함께 보여줘.

model `claude-sonnet-5` · Claude Code 2.1.220 · 4 turns · 41.2 s · $0.1744 · success

### call 1: `ToolSearch` (Claude Code, not MCP)

`{"query": "fileidx query files", "max_results": 10}`

### call 2: `run_query` → ok

```sql
SELECT content_hash, count() AS cnt, any(size) AS sz, (cnt-1)*sz AS wasted, groupArray(5)(concat(root, ':', path)) AS examples FROM fileidx.files WHERE content_hash != '' AND NOT is_dir GROUP BY content_hash HAVING cnt > 1 ORDER BY wasted DESC LIMIT 20
```

```text
{"result":"{\"columns\": [\"content_hash\", \"cnt\", \"sz\", \"wasted\", \"examples\"], \"rows\": [[\"15ae6dbfa0d4f827be0cbdfe601b9f89\", 6, 3134464, 15672320, [\"docs:finance/shared/dataset_24 (5).csv\", \"docs:hr/shared/dataset_24.csv\", \"archive:old_copies/set1/dataset_24 (1).csv\", \"archive:old_copies/set2/dataset_24 (2).csv\", \"archive:old_copies/set3/dataset_24 (3).csv\"]], [\"d21368ff969c7f3383c7a1dea2f5f3a2\", 6, 3011584, 15057920, [\"docs:eng/shared/dataset_01 (3).csv\", \"docs:sales/shared/dataset_01 (2).csv\", \"archive:old_copies/set0/dataset_01.csv\", \"archive:old_copies/set1/ …
```

### call 3: `run_query` → ok

```sql
SELECT count() AS dup_groups, sum(cnt) AS dup_files, sum((cnt-1)*sz) AS total_wasted FROM (SELECT content_hash, count() AS cnt, any(size) AS sz FROM fileidx.files WHERE content_hash != '' AND NOT is_dir GROUP BY content_hash HAVING cnt > 1)
```

```text
{"result":"{\"columns\": [\"dup_groups\", \"dup_files\", \"total_wasted\"], \"rows\": [[63, 574, 214320666]]}"}
```

### answer

## 중복 파일로 인한 낭비 용량

**쿼리**: `fileidx.files`에서 `content_hash != ''`(해시 계산된 것만, `NOT is_dir`)로 `content_hash` 기준 그룹핑 → `count() > 1`인 그룹만 집계. 낭비 용량 = `(그룹 내 파일 수 - 1) × 파일 크기`(동일 해시이므로 크기도 동일).

### 전체 요약
- 중복 그룹 수: **63개**
- 중복에 포함된 전체 파일 수: **574개**
- **총 낭비 용량: 약 204.4 MiB (214,320,666 바이트)**

### 낭비가 큰 상위 20개 그룹

| # | 중복 개수 | 파일 1개 크기 | 낭비 용량 | 경로 예시 |
|---|---|---|---|---|
| 1 | 6 | 2.99 MiB | **14.95 MiB** | `docs:finance/shared/dataset_24 (5).csv`, `docs:hr/shared/dataset_24.csv`, `archive:old_copies/set1/dataset_24 (1).csv` |
| 2 | 6 | 2.87 MiB | **14.36 MiB** | `docs:eng/shared/dataset_01 (3).csv`, `docs:sales/shared/dataset_01 (2).csv`, `archive:old_copies/set0/dataset_01.csv` |
| 3 | 6 | 2.87 MiB | **14.34 MiB** | `docs:eng/shared/dataset_18 (4).csv`, `docs:eng/shared/dataset_18 (5).csv`, `archive:old_copies/set0/dataset_18.csv` |
| 4 | 6 | 2.85 MiB | **14.25 MiB** | `docs:eng/shared/dataset_20 (1).csv`, `docs:hr/shared/dataset_20.csv`, `archive:old_copies/set2/dataset_20 (2).csv` |
| 5 | 6 | 2.42 MiB | **12.11 MiB** | `docs:eng/shared/dataset_37 (1).csv`, `docs:hr/shared/dataset_37 (3).csv`, `archive:old_copies/set0/dataset_37.csv` |
| 6 | 6 | 2.08 MiB | **10.41 MiB** | `docs:eng/shared/dataset_27 (3).csv`, `docs:finance/shared/dataset_27 (2).csv`, `archive:old_copies/set0/dataset_27.csv` |
| 7 | 6 | 1.96 MiB | **9.81 MiB** | `docs:hr/shared/dataset_35 (4).csv`, `docs:ops/shared/dataset_35 (3).csv`, `archive:old_copies/set0/dataset_35.csv` |
| 8 | 4 | 2.94 MiB | **8.82 MiB** | `docs:legal/shared/dataset_30 (1).csv`, `docs:legal/shared/dataset_30 (2).csv`, `docs:ops/shared/dataset_30.csv` |
| 9 | 6 | 1.68 MiB | **8.42 MiB** | `docs:eng/shared/dataset_00.csv`, `docs:legal/shared/dataset_00 (4).csv`, `docs:sales/shared/dataset_00 (1).csv` |
| 10 | 4 | 2.66 MiB | **7.97 MiB** | `docs:eng/shared/dataset_10 (3).csv`, `docs:legal/shared/dataset_10 (2).csv`, `archive:old_copies/set0/dataset_10.csv` |
| 11 | 4 | 2.37 MiB | **7.11 MiB** | `docs:ops/shared/dataset_28 (2).csv`, `archive:old_copies/set0/dataset_28.csv`, `archive:old_copies/set1/dataset_28 (1).csv` |
| 12 | 4 | 2.28 MiB | **6.83 MiB** | `docs:ops/shared/dataset_04 (1).csv`, `docs:sales/shared/dataset_04 (3).csv`, `archive:old_copies/set0/dataset_04.csv` |
| 13 | 4 | 2.27 MiB | **6.82 MiB** | `docs:eng/shared/dataset_34 (1).csv`, `docs:finance/shared/dataset_34 (2).csv`, `archive:old_copies/set0/dataset_34.csv` |
| 14 | 6 | 1.27 MiB | **6.37 MiB** | `docs:eng/shared/dataset_14 (2).csv`, `docs:hr/shared/dataset_14.csv`, `docs:ops/shared/dataset_14 (4).csv` |
| 15 | 4 | 2.07 MiB | **6.21 MiB** | `docs:hr/shared/dataset_29.csv`, `docs:sales/shared/dataset_29 (3).csv`, `archive:old_copies/set1/dataset_29 (1).csv` |
| 16 | 3 | 2.58 MiB | **5.17 MiB** | `docs:legal/shared/dataset_17 (1).csv`, `docs:ops/shared/dataset_17.csv`, `archive:old_copies/set2/dataset_17 (2).csv` |
| 17 | 3 | 2.48 MiB | **4.95 MiB** | `docs:finance/shared/dataset_32.csv`, `docs:ops/shared/dataset_32 (1).csv`, `docs:ops/shared/dataset_32 (2).csv` |
| 18 | 4 | 1.29 MiB | **3.88 MiB** | `docs:eng/shared/dataset_15.csv`, `docs:finance/shared/dataset_15 (2).csv`, `docs:sales/shared/dataset_15 (1).csv` |
| 19 | 6 | 0.76 MiB | **3.80 MiB** | `docs:finance/shared/dataset_23 (2).csv`, `docs:ops/shared/dataset_23.csv`, `archive:old_copies/set1/dataset_23 (1).csv` |
| 20 | 3 | 1.77 MiB | **3.55 MiB** | `docs:hr/shared/dataset_21.csv`, `archive:old_copies/set1/dataset_21 (1).csv`, `archive:old_copies/set2/dataset_21 (2).csv` |

상위 20개 그룹만으로 약 170 MiB(전체 낭비 204.4 MiB의 ~83%)를 차지합니다.

**패턴**: 전부 `dataset_NN.csv` 계열 파일로, `docs` 루트 안에서 `eng/finance/hr/legal/ops/sales` 등 여러 부서 `shared/` 폴더에 동일 내용이 `(1)`, `(2)` 같은 복사본 이름으로 흩어져 있고, `archive:old_copies/setN/`에도 똑같이 복제돼 있습니다. "부서별 공유 + 아카이브 백업"이 같은 원본 데이터를 반복 복사하면서 생긴 중복으로 보입니다.

