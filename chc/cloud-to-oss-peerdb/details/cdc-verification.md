# CDC verification — run 20260907T112912Z-lab1

Batch applied directly on sources (from the PeerDB EC2, in-VPC), then polled ClickHouse OSS
via `FINAL` queries.

## MySQL (`mysql_to_oss` mirror)

| Operation | Source | ClickHouse OSS (`peerdb_validation`, FINAL) | Result |
|---|---|---|---|
| INSERT 20 `customers` | 200 → 220 | `count() FINAL` = 220 | PASS |
| UPDATE 10 `orders` → status='shipped' (order_id 1-10) | 10/10 | `count() FINAL WHERE order_id BETWEEN 1 AND 10 AND status='shipped'` = 10 | PASS |
| DELETE 5 `order_items` (order_id 1-5, line_no=2) | 995 live | `count()`=5, `sum(_peerdb_is_deleted)`=5 for the deleted keys; `count() FINAL` total = 1000 (995 live + 5 tombstones, as expected without an `is_deleted` filter) | PASS |

CDC lag was effectively immediate (first poll ~15s after the batch already showed the new rows).

## DocumentDB (`mongo_to_oss` mirror)

| Operation | Source | ClickHouse OSS (FINAL) | Result |
|---|---|---|---|
| INSERT 20 `profiles` | 150 → 170 | `count() FINAL WHERE NOT _peerdb_is_deleted` = 170 | PASS |
| UPDATE 10 `mutable_docs` → status='updated' | 10/10 | `count() FINAL WHERE JSONExtractString(doc,'status')='updated'` = 10 | PASS |
| DELETE 5 `events` (_id 0-4) | 295 live | `count()`=5, `sum(_peerdb_is_deleted)`=5 for the deleted keys | PASS |

Note on schema: PeerDB's MongoDB→ClickHouse mirror stores each document as a single `doc`
`String` column (JSON text) plus `_id`, `_peerdb_synced_at`, `_peerdb_is_deleted`,
`_peerdb_version` — not a flattened per-field schema. Querying nested fields requires
`JSONExtractString(doc, '<field>')`. `_id` is stored as `String`, so numeric comparisons need
an explicit cast (`toUInt32OrZero(_id)`).

## Conclusion

Both PeerDB CDC mirrors (RDS MySQL → ClickHouse OSS, DocumentDB → ClickHouse OSS) are
functionally correct for initial snapshot + INSERT/UPDATE/DELETE. This satisfies the narrowed
scope agreed mid-run: "PeerDB로 documentdb와 rds mysql만 옮기면 됩니다."
