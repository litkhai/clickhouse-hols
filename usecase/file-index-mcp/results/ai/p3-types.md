## p3-types (rules)

> 확장자별 파일 수와 총용량 상위 30개를 표로 만들어줘. 문서/이미지/영상/기타로 묶은 요약도 함께.

model `claude-sonnet-5` · Claude Code 2.1.220 · 4 turns · 24.9 s · $0.1378 · success

### call 1: `ToolSearch` (Claude Code, not MCP)

`{"query": "fileidx files query", "max_results": 10}`

### call 2: `run_query` → ok

```sql
SELECT ext, count() AS cnt, sum(size) AS total_size FROM fileidx.files WHERE is_dir = 0 GROUP BY ext ORDER BY total_size DESC LIMIT 30
```

```text
{"result":"{\"columns\": [\"ext\", \"cnt\", \"total_size\"], \"rows\": [[\"mp4\", 400, 600569806848], [\"iso\", 30, 182536110080], [\"zip\", 200, 98655272960], [\"jpg\", 17000, 5083850454], [\"docx\", 941, 1795969165], [\"pdf\", 787, 1179946695], [\"xlsx\", 623, 980080433], [\"part\", 15, 446643849], [\"pptx\", 272, 426760141], [\"tmp\", 15, 388854090], [\"csv\", 152, 292260864], [\"hwp\", 169, 243667272], [\"txt\", 248, 22202], [\"md\", 151, 18516], [\"\", 25, 2500]]}"}
```

### call 3: `run_query` → ok

```sql
SELECT
  multiIf(
    ext IN ('docx','pdf','xlsx','pptx','csv','hwp','txt','md'), '문서',
    ext IN ('jpg','jpeg','png','gif','bmp','webp'), '이미지',
    ext IN ('mp4','mov','avi','mkv'), '영상',
    '기타'
  ) AS category,
  count() AS cnt,
  sum(size) AS total_size
FROM fileidx.files
WHERE is_dir = 0
GROUP BY category
ORDER BY total_size DESC
```

```text
{"result":"{\"columns\": [\"category\", \"cnt\", \"total_size\"], \"rows\": [[\"\\uc601\\uc0c1\", 400, 600569806848], [\"\\uae30\\ud0c0\", 285, 282026883479], [\"\\uc774\\ubbf8\\uc9c0\", 17000, 5083850454], [\"\\ubb38\\uc11c\", 3343, 4918725288]]}"}
```

### answer

## 확장자별 파일 수 · 총용량 (상위 15개 — 전체 확장자 수가 30개 미만)

쿼리: `SELECT ext, count(), sum(size) FROM fileidx.files WHERE is_dir=0 GROUP BY ext ORDER BY sum(size) DESC`

| 순위 | 확장자 | 파일 수 | 총 용량 |
|---|---|---|---|
| 1 | mp4 | 400 | 559.35 GiB |
| 2 | iso | 30 | 170.02 GiB |
| 3 | zip | 200 | 91.88 GiB |
| 4 | jpg | 17,000 | 4.73 GiB |
| 5 | docx | 941 | 1.67 GiB |
| 6 | pdf | 787 | 1.10 GiB |
| 7 | xlsx | 623 | 934.6 MiB |
| 8 | part | 15 | 426.0 MiB |
| 9 | pptx | 272 | 407.0 MiB |
| 10 | tmp | 15 | 370.8 MiB |
| 11 | csv | 152 | 278.7 MiB |
| 12 | hwp | 169 | 232.4 MiB |
| 13 | txt | 248 | 21.7 KiB |
| 14 | md | 151 | 18.1 KiB |
| 15 | (확장자 없음) | 25 | 2.44 KiB |

※ 색인 전체에 등록된 확장자가 15종뿐이라 상위 30개 전부를 채울 수 없었습니다.

## 문서 / 이미지 / 영상 / 기타 요약

쿼리: 위 결과를 `multiIf(ext IN (문서군), '문서', ext IN (이미지군), '이미지', ext IN (영상군), '영상', '기타')`로 묶어 집계

| 분류 | 포함 확장자 | 파일 수 | 총 용량 | 비중(용량) |
|---|---|---|---|---|
| 영상 | mp4 | 400 | 559.35 GiB | 67.4% |
| 기타 | iso, zip, part, tmp, 확장자없음 | 285 | 262.65 GiB | 31.7% |
| 이미지 | jpg | 17,000 | 4.73 GiB | 0.6% |
| 문서 | docx, pdf, xlsx, pptx, csv, hwp, txt, md | 3,343 | 4.58 GiB | 0.6% |

**요약**: 전체 용량의 약 99%가 mp4(영상)와 iso/zip(기타) 두 묶음에 몰려 있습니다. 파일 개수로는 jpg(이미지)가 17,000개로 압도적 다수지만 평균 크기가 작아 용량 비중은 1% 미만입니다. "기타" 분류 안의 tmp·part(총 30건)는 임시/미완성 파일 가능성이 있어 정리 대상으로 볼 만합니다.

