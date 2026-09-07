# Bootstrap notes — run 20260907T112912Z-lab1

Scope decision (user-approved): security hardening (TLS/mTLS/KMS/PrivateLink/private-subnet)
is explicitly out of scope for this run. Goal is functional validation only, on minimal
instances, in the existing default VPC's public subnets. All lab resources tagged
`Purpose=cloud-to-oss-lab`, `RunId=20260907T112912Z-lab1`.

## ClickHouse OSS EC2 (<instance-id>, chc-lab-clickhouse-oss)

- Installed clickhouse-server/client 26.8.2.7 from the official `lts` apt repo on Ubuntu 24.04.
- **Issue 1**: initial users.d/10-lab-users.xml override for the `default` user did not use
  `replace="1"`, so ClickHouse merged it with the package's built-in `default` user block and
  ended up with two authentication methods on the same user → server crash-looped with
  `Cannot specify multiple authentication methods for user default`.
  Fix: added `replace="1"` on the `<default>` node.
- **Issue 2**: `peerdb_ingest` was originally defined via XML (users.d), which makes that
  user's ACL storage read-only from SQL — `GRANT ... TO peerdb_ingest` failed with
  `ACCESS_STORAGE_READONLY`. Fix: removed peerdb_ingest from XML, created it via
  `CREATE USER ... IDENTIFIED WITH sha256_hash` through the SQL-managed `default` user instead,
  then granted privileges.
- **Issue 3**: `GRANT CREATE TEMPORARY TABLE ... ON analytics.*` is invalid — this privilege
  can only be granted at the global level (`ON *.*`), matching the runbook's own example.
  Fixed by granting `CREATE TEMPORARY TABLE, S3 ON *.*` instead of at the database level.
- Ports left in default plaintext state (8123 HTTP, 9000 native) since TLS is out of scope.
  `listen_host` set to `0.0.0.0`; access restricted at the security-group layer instead
  (PeerDB SG and operator IP only).
- Root EBS volume enlarged to 50 GiB and used directly for `/var/lib/clickhouse` (skipped the
  separate-EBS-volume-with-UUID-mount pattern from the production template, to save setup time
  for a small synthetic dataset).
- Databases created: `analytics`, `peerdb_validation`.

## PeerDB EC2 (<instance-id>, chc-lab-peerdb)

- Docker Engine + Compose plugin installed from Docker's official apt repo.
- **Issue**: initial `docker-compose.yml` used image tag `v0.37.5` for the PeerDB images,
  which does not exist on ghcr.io for `flow-snapshot-worker` (pull failed with "not found").
  Cross-checked against PeerDB's own published `docker-compose.yml`
  (https://raw.githubusercontent.com/PeerDB-io/peerdb/main/docker-compose.yml) — the correct
  tag format is `stable-v0.37.5`. Fixed `.env` and re-ran `docker compose pull && up -d`.
- All 7 services now `Up`/`healthy`: catalog (Postgres 17), temporal, flow-api,
  flow-snapshot-worker, flow-worker, peerdb-server, peerdb-ui.
- UI (3000) and SQL (9900) ports bound to `0.0.0.0`, restricted at the security-group layer to
  the operator IP only (TLS/mTLS to ClickHouse intentionally skipped per scope decision).
- This EC2 also doubles as the SSH bastion for the ClickPipes→DocumentDB tunnel (DocumentDB has
  no public endpoint option in AWS), and its security group additionally allows port 22 from
  ClickHouse Cloud's published static NAT IPs for ap-northeast-2.

## Discovered ClickHouse Cloud ClickPipes API (undocumented at time of writing)

No public OpenAPI spec was reachable (`/v1/swagger.json`, `/_specs/cloud-openapi.json` both
404). Reverse-engineered by iterative POST against
`https://api.clickhouse.cloud/v1/organizations/{orgId}/services/{serviceId}/clickpipes`
using validation error messages. Working MySQL body:

```json
{
  "name": "...",
  "source": {
    "mysql": {
      "type": "mysql",
      "host": "...", "port": 3306, "database": "...",
      "authentication": "basic",
      "credentials": {"username": "...", "password": "..."},
      "settings": {"replicationMode": "cdc"},
      "tableMappings": [{"sourceSchemaName": "...", "sourceTable": "...", "targetTable": "...",
        "excludedColumns": [], "useCustomSortingKey": false, "sortingKeys": [], "tableEngine": "ReplacingMergeTree"}]
    }
  },
  "destination": {"database": "analytics"}
}
```

MongoDB/DocumentDB body uses `source.mongodb` with `uri`, `readPreference`, `settings`, and
`tableMappings[].{sourceDatabaseName, sourceCollection, targetTable, ...}` instead of the MySQL
field names. (This ClickPipes work was later dropped from scope — see `02-plan/NOTES.md` — but
kept here since it's the only public record of the schema.)

## PeerDB peer/mirror creation — issues hit and fixes (after scope narrowed to PeerDB-only)

PeerDB's SQL docs (`docs.peerdb.io/sql/commands/create-peer`) are stale/incomplete in places;
ground truth came from the `stable-v0.37.5` proto definitions and Rust SQL analyzer source
(`nexus/analyzer/src/lib.rs`) on GitHub. Issues hit, in order:

1. **ClickHouse peer S3 staging always fails validation** ("static credentials are empty",
   then "InvalidAccessKeyId"). Root cause, found by reading `flow/connectors/clickhouse/staging_s3.go`:
   a ClickHouse destination in PeerDB always stages data through an S3-compatible bucket before
   `INSERT`ing into ClickHouse (via ClickHouse's own `s3()` table function) — there is no
   staging-free mode. Our compose file omitted the `minio` service entirely; PeerDB's own
   reference compose (github.com/PeerDB-io/peerdb `docker-compose.yml`) includes one. Fixed by
   adding a `minio` service + `x-minio` anchor.
2. **MinIO silently ran on default `minioadmin:minioadmin` creds** even after setting
   `PEERDB_CLICKHOUSE_AWS_CREDENTIALS_AWS_ACCESS_KEY_ID/SECRET_ACCESS_KEY` — those env vars only
   tell *PeerDB* what credentials to present; MinIO itself needs its own native
   `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` vars set on the `minio` service, which our first
   attempt omitted. This is what actually produced the misleading "InvalidAccessKeyId" (from
   MinIO's own AWS-S3-compatible error response, not real AWS — easy to misattribute).
3. **`PEERDB_CLICKHOUSE_AWS_CREDENTIALS_AWS_ENDPOINT_URL_S3` was hardcoded to `http://minio:9000`**
   (the internal Docker network name) in our compose file. That address is only reachable from
   containers on the PeerDB EC2's own Docker network — but ClickHouse OSS runs on a *separate
   EC2* and needs to reach the same staging bucket directly via its `s3()` table function. Fixed
   by publishing MinIO's port to the host (`0.0.0.0:9001:9000`), opening that port in
   `SG_PEERDB` to `SG_CH`, and pointing the endpoint at the PeerDB EC2's private IP instead of
   the in-network service name.
4. **`CREATE PEER ... FROM CLICKHOUSE`'s SQL grammar always sets the peer's nested `s3` config
   to `None`** (confirmed in `nexus/analyzer/src/lib.rs`) — the flat `s3_path` /
   `access_key_id` / `secret_access_key` / `region` / `endpoint` WITH-options are what actually
   get used (`flow/connectors/clickhouse/staging_s3.go` falls back to these fields when `s3` is
   nil), so those flat fields are the correct/only way to configure staging via SQL.
5. **MySQL peer**: `flavor` must be set explicitly (`'mysql'`) — the create-peer.md example
   omits it but validation rejects the default/unset value ("flavor is set to unknown").
6. **MySQL CDC mirror validation requires** `binlog retention hours >= 24` (RDS-specific,
   set via `CALL mysql.rds_set_configuration('binlog retention hours', 48)`) and
   `binlog_row_metadata = FULL` (a static parameter-group setting requiring a reboot) — the
   runbook's own MySQL CDC checklist mentions `binlog_format`/`binlog_row_image` but not
   `binlog_row_metadata`, which PeerDB also enforces.
7. **Mongo peer**: `CREATE PEER ... FROM MONGO` needs `username`/`password` as separate
   WITH-options even when the `uri` already looks like it could embed credentials — passing
   embedded-in-URI credentials alone fails with "no username specified". `read_preference` must
   be the **numeric** enum value (e.g. `'1'` for `PRIMARY`), not the string name — the SQL
   parser does `s.parse::<i32>()`, not an enum-name lookup.
8. **Mongo peer validation failed outright against DocumentDB engine 4.0.0**:
   `server ... reports wire version 7, but this version of the Go driver requires at least 8
   (MongoDB 4.2)`. DocumentDB 4.0 does not speak a wire protocol new enough for PeerDB's Mongo
   connector. Fixed by discovering (via `aws docdb describe-orderable-db-instance-options`
   without a `--db-instance-class` filter — the earlier single-class check only showed the
   *default* version, not the full list) that `db.t4g.medium` also supports DocumentDB engine
   **8.0.1**, and recreating the cluster on that engine version instead of 4.0.0.
