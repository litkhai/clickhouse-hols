## p4-contracts (rules)

> 파일명에 '계약' 또는 'contract' 가 들어간 문서를 최신 수정순으로 30개 보여줘. 확장자가 pdf, docx, hwp 인 것만.

model `claude-sonnet-5` · Claude Code 2.1.220 · 3 turns · 18.0 s · $0.1243 · success

### call 1: `ToolSearch` (Claude Code, not MCP)

`{"query": "fileidx files query", "max_results": 10}`

### call 2: `run_query` → ok

```sql
SELECT root, path, name, ext, size, mtime FROM fileidx.files WHERE is_dir = 0 AND ext IN ('pdf','docx','hwp') AND (positionCaseInsensitive(name, '계약') > 0 OR positionCaseInsensitive(name, 'contract') > 0) ORDER BY mtime DESC LIMIT 30
```

```text
{"result":"{\"columns\": [\"root\", \"path\", \"name\", \"ext\", \"size\", \"mtime\"], \"rows\": [[\"docs\", \"legal/contracts/\\uacc4\\uc57d\\uc11c_081.docx\", \"\\uacc4\\uc57d\\uc11c_081.docx\", \"docx\", 155260, \"2026-08-15 12:00:00\"], [\"docs\", \"legal/contracts/contract_058.hwp\", \"contract_058.hwp\", \"hwp\", 796247, \"2026-07-11 12:00:00\"], [\"docs\", \"legal/contracts/contract_088.pdf\", \"contract_088.pdf\", \"pdf\", 427336, \"2026-05-19 12:00:00\"], [\"docs\", \"legal/contracts/contract_037.docx\", \"contract_037.docx\", \"docx\", 560082, \"2026-03-02 12:00:00\"], [\"docs\", \"l …
```

### answer

조건: `is_dir=0`, `ext IN ('pdf','docx','hwp')`, 파일명에 '계약' 또는 'contract' 포함, `mtime DESC LIMIT 30`.

| # | root | 경로 | 크기 | 수정일 |
|---|---|---|---|---|
| 1 | docs | legal/contracts/계약서_081.docx | 151.6 KB | 2026-08-15 |
| 2 | docs | legal/contracts/contract_058.hwp | 777.6 KB | 2026-07-11 |
| 3 | docs | legal/contracts/contract_088.pdf | 417.3 KB | 2026-05-19 |
| 4 | docs | legal/contracts/contract_037.docx | 547.0 KB | 2026-03-02 |
| 5 | docs | legal/contracts/계약서_096.pdf | 816.3 KB | 2026-01-07 |
| 6 | docs | legal/contracts/contract_073.docx | 389.5 KB | 2025-11-02 |
| 7 | docs | legal/contracts/계약서_084.pdf | 658.9 KB | 2025-08-27 |
| 8 | docs | legal/contracts/계약서_114.hwp | 784.8 KB | 2025-07-21 |
| 9 | docs | legal/contracts/계약서_021.docx | 263.7 KB | 2025-06-24 |
| 10 | docs | legal/contracts/contract_118.hwp | 348.1 KB | 2025-05-20 |
| 11 | docs | legal/contracts/contract_061.docx | 602.5 KB | 2025-03-14 |
| 12 | docs | legal/contracts/계약서_000.pdf | 79.7 KB | 2025-01-17 |
| 13 | docs | legal/contracts/contract_094.hwp | 522.8 KB | 2024-12-14 |
| 14 | docs | legal/contracts/계약서_042.hwp | 730.8 KB | 2024-07-21 |
| 15 | docs | legal/contracts/contract_001.docx | 761.0 KB | 2024-06-04 |
| 16 | docs | legal/contracts/contract_064.pdf | 205.8 KB | 2024-03-19 |
| 17 | docs | legal/contracts/contract_097.docx | 357.0 KB | 2024-01-04 |
| 18 | docs | legal/contracts/계약서_105.docx | 620.4 KB | 2023-12-03 |
| 19 | docs | legal/contracts/계약서_036.pdf | 806.7 KB | 2023-11-09 |
| 20 | docs | legal/contracts/계약서_060.pdf | 600.7 KB | 2023-11-01 |
| 21 | docs | legal/contracts/contract_052.pdf | 330.4 KB | 2023-10-09 |
| 22 | docs | legal/contracts/contract_016.pdf | 681.6 KB | 2023-09-22 |
| 23 | docs | legal/contracts/contract_076.pdf | 709.3 KB | 2023-05-03 |
| 24 | docs | legal/contracts/계약서_069.docx | 313.5 KB | 2023-04-12 |
| 25 | docs | legal/contracts/계약서_048.pdf | 288.8 KB | 2023-03-26 |
| 26 | docs | legal/contracts/계약서_066.hwp | 567.8 KB | 2023-03-21 |
| 27 | docs | legal/contracts/계약서_102.hwp | 613.0 KB | 2023-03-20 |
| 28 | docs | legal/contracts/계약서_078.hwp | 769.2 KB | 2023-02-18 |
| 29 | docs | legal/contracts/계약서_024.pdf | 312.2 KB | 2023-01-26 |
| 30 | docs | legal/contracts/contract_004.pdf | 91.5 KB | 2023-01-13 |

참고: 전부 `docs` 루트의 `legal/contracts/` 경로에 몰려 있고, 가장 오래된 항목이 2023-01-13, 가장 최신이 2026-08-15입니다.

