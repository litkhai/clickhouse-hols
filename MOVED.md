# Moved labs

[English](#english) | [한국어](#한국어)

## English

Labs that left this repository or were renamed, and where they went. The last version of
every one of them in this repository is kept at the `pre-split-2026-10` tag.

`.github/scripts/build_site.py` reads the table below: an `http` target means the lab moved to
another repository, a relative one means it moved inside this repository. Each old path
that had a site page gets a redirect page there.

| Old path | New location |
|---|---|
| `managed-postgres` | https://github.com/litkhai/clickhouse-managed-postgres-hols/tree/main/managed-postgres |
| `managed-postgres/provisioning` | https://github.com/litkhai/clickhouse-managed-postgres-hols/tree/main/managed-postgres/provisioning |
| `managed-postgres/postgis-fdw-bike` | https://github.com/litkhai/clickhouse-managed-postgres-hols/tree/main/managed-postgres/postgis-fdw-bike |
| `managed-postgres/ny-citi-bike-workshop` | https://github.com/litkhai/clickhouse-managed-postgres-hols/tree/main/managed-postgres/ny-citi-bike-workshop |
| `managed-postgres/vector-search` | https://github.com/litkhai/clickhouse-managed-postgres-hols/tree/main/managed-postgres/vector-search |
| `local/pg-clickhouse-lab` | https://github.com/litkhai/clickhouse-managed-postgres-hols/tree/main/extensions/pg-clickhouse-lab |
| `chc/tool/ch2otel` | https://github.com/litkhai/clickstack-hyperdx-hols/tree/main/labs/ch2otel |
| `workshop/o11y-vector-ai` | https://github.com/litkhai/clickstack-hyperdx-hols/tree/main/workshops/o11y-vector-ai |
| `workshop/observability-waf` | https://github.com/litkhai/clickstack-hyperdx-hols/tree/main/workshops/observability-waf |
| `usecase/langfuse-ee` | https://github.com/litkhai/langfuse-hols/tree/main/labs/v4/langfuse-ee |
| `usecase/langfuse-eval` | https://github.com/litkhai/langfuse-hols/tree/main/labs/v4/langfuse-eval |
| `chc/kafka/terraform-confluent-aws` | https://github.com/litkhai/clickhouse-cloud-aws-hols/tree/main/labs/kafka/terraform-confluent-aws |
| `chc/kafka/terraform-confluent-aws-nlb-ssl` | https://github.com/litkhai/clickhouse-cloud-aws-hols/tree/main/labs/kafka/terraform-confluent-aws-nlb-ssl |
| `chc/kafka/terraform-confluent-aws-connect-sink` | https://github.com/litkhai/clickhouse-cloud-aws-hols/tree/main/labs/kafka/terraform-confluent-aws-connect-sink |
| `chc/lake/terraform-minio-on-aws` | https://github.com/litkhai/clickhouse-cloud-aws-hols/tree/main/labs/lake/terraform-minio-on-aws |
| `chc/lake/terraform-glue-s3-chc-integration` | https://github.com/litkhai/clickhouse-cloud-aws-hols/tree/main/labs/lake/terraform-glue-s3-chc-integration |
| `chc/s3/terraform-chc-secures3-aws` | https://github.com/litkhai/clickhouse-cloud-aws-hols/tree/main/labs/s3/terraform-chc-secures3-aws |
| `chc/s3/terraform-chc-secures3-aws-direct-attach` | https://github.com/litkhai/clickhouse-cloud-aws-hols/tree/main/labs/s3/terraform-chc-secures3-aws-direct-attach |
| `tpcds` | https://github.com/litkhai/clickhouse-hols/tree/pre-split-2026-10/tpcds |
| `workshop/device-360` | [usecase/device-360](usecase/device-360/) |
| `local/oss-mac-setup` | [local/oss-docker](local/oss-docker/) |

`tpcds` points at the tagged original on purpose: its queries are Altinity's
GPL-3.0 variants, which differ from the Apache-2.0 upstream queries in
[tpcds-scripts](https://github.com/litkhai/tpcds-scripts).

---

## 한국어

2026-09-27에 이 저장소를 떠난 실습과 새 위치입니다. 각 실습의 이 저장소 마지막 버전은
`pre-split-2026-10` 태그에 남아 있습니다.

위 표는 `.github/scripts/build_site.py`가 읽습니다. 새 위치가 `http`이면 다른 저장소로,
상대 경로이면 이 저장소 안에서 옮긴 것입니다. 사이트 페이지가 있던 옛 경로에는 redirect 페이지를 만듭니다.

`tpcds`는 일부러 태그의 원본을 가리킵니다. 이 쿼리는 Altinity의 GPL-3.0 변형이라
[tpcds-scripts](https://github.com/litkhai/tpcds-scripts)의 Apache-2.0 업스트림 쿼리와 다릅니다.
