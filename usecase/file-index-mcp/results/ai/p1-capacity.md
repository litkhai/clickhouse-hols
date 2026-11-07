## p1-capacity (rules)

> 용량을 가장 많이 차지하는 상위 20개 파일을 크기와 최종 수정일과 함께 보여줘. 그리고 그 파일들이 어느 root에 몰려 있는지도 요약해줘.

model `claude-sonnet-5` · Claude Code 2.1.220 · 4 turns · 17.9 s · $0.1641 · success

### call 1: `ToolSearch` (Claude Code, not MCP)

`{"query": "fileidx query files", "max_results": 10}`

### call 2: `run_query` → ok

```sql
SELECT root, path, name, ext, size, mtime FROM fileidx.files WHERE is_dir = 0 ORDER BY size DESC LIMIT 20
```

```text
{"result":"{\"columns\": [\"root\", \"path\", \"name\", \"ext\", \"size\", \"mtime\"], \"rows\": [[\"archive\", \"images/disk_00.iso\", \"disk_00.iso\", \"iso\", 8589934592, \"2019-01-15 12:00:00\"], [\"archive\", \"images/disk_29.iso\", \"disk_29.iso\", \"iso\", 8589934592, \"2020-06-15 12:00:00\"], [\"archive\", \"images/disk_26.iso\", \"disk_26.iso\", \"iso\", 8589934592, \"2021-03-15 12:00:00\"], [\"archive\", \"images/disk_06.iso\", \"disk_06.iso\", \"iso\", 8589934592, \"2021-07-15 12:00:00\"], [\"archive\", \"images/disk_14.iso\", \"disk_14.iso\", \"iso\", 8589934592, \"2021-03-15 12:00 …
```

### call 3: `run_query` → ok

```sql
SELECT root, count() AS file_count, sum(size) AS total_size FROM fileidx.files WHERE is_dir = 0 AND (root, path) IN (SELECT root, path FROM fileidx.files WHERE is_dir = 0 ORDER BY size DESC LIMIT 20) GROUP BY root ORDER BY total_size DESC
```

```text
{"result":"{\"columns\": [\"root\", \"file_count\", \"total_size\"], \"rows\": [[\"archive\", 20, 142807662592]]}"}
```

### answer

## 용량 상위 20개 파일 (`fileidx.files`, `is_dir=0`, `size DESC LIMIT 20`)

| 순위 | root | path | 크기 | 최종 수정일 |
|---|---|---|---|---|
| 1 | archive | images/disk_00.iso | 8.00 GiB | 2019-01-15 |
| 2 | archive | images/disk_29.iso | 8.00 GiB | 2020-06-15 |
| 3 | archive | images/disk_26.iso | 8.00 GiB | 2021-03-15 |
| 4 | archive | images/disk_06.iso | 8.00 GiB | 2021-07-15 |
| 5 | archive | images/disk_14.iso | 8.00 GiB | 2021-03-15 |
| 6 | archive | images/disk_10.iso | 8.00 GiB | 2021-11-15 |
| 7 | archive | images/disk_08.iso | 7.00 GiB | 2019-09-15 |
| 8 | archive | images/disk_05.iso | 7.00 GiB | 2020-06-15 |
| 9 | archive | images/disk_07.iso | 7.00 GiB | 2022-08-15 |
| 10 | archive | images/disk_13.iso | 7.00 GiB | 2020-02-15 |
| 11 | archive | images/disk_25.iso | 6.00 GiB | 2020-02-15 |
| 12 | archive | images/disk_24.iso | 6.00 GiB | 2019-01-15 |
| 13 | archive | images/disk_23.iso | 6.00 GiB | 2022-12-15 |
| 14 | archive | images/disk_17.iso | 6.00 GiB | 2020-06-15 |
| 15 | archive | images/disk_15.iso | 6.00 GiB | 2022-04-15 |
| 16 | archive | images/disk_09.iso | 6.00 GiB | 2020-10-15 |
| 17 | archive | images/disk_01.iso | 6.00 GiB | 2020-02-15 |
| 18 | archive | images/disk_27.iso | 5.00 GiB | 2022-04-15 |
| 19 | archive | images/disk_12.iso | 5.00 GiB | 2019-01-15 |
| 20 | archive | images/disk_11.iso | 5.00 GiB | 2022-12-15 |

(정렬은 원본 `size` 바이트 기준, 표시는 GiB로 반올림)

## root 분포 요약

집계 쿼리(위 20개를 `(root, path)`로 묶어 `root`별 `count()`, `sum(size)`)결과:

- **archive 루트가 20/20 전부** 차지 — 총 **142,807,662,592 바이트 ≈ 133.0 GiB**
- 전부 `archive` 루트의 `images/` 디렉터리 아래 `disk_NN.iso` 파일들(디스크 이미지)로, 다른 root는 상위 20위 안에 전혀 없음

필요하면 `archive` 루트 전체(이 20개 외 다른 iso 포함) 총량이나, `archive` 제외한 나머지 root들의 상위 파일도 추가로 뽑아드릴 수 있습니다.

