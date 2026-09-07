# Source fixtures — run 20260907T112912Z-lab1

## RDS MySQL (`shopdb`)

Seeded via `mysql` client from the operator machine (SG allowed direct access at the time):
- `customers`: 200 rows (nullable name/email ~1/30, unicode/emoji names)
- `orders`: 500 rows (decimal amount, status enum, `updated_at` auto-update)
- `order_items`: 1000 rows (composite PK `order_id, line_no`)
- `immutable_history`: 100 rows — created per the runbook's fixture schema, but **unused**
  since remoteSecure backfill was dropped from scope.

Dedicated users created: `clickpipes_reader` (unused after scope cut, left in place — see
cleanup notes), `peerdb_reader` (`SELECT, REPLICATION SLAVE, REPLICATION CLIENT`).

## DocumentDB (`shopdb`)

Seeded via `docker run mongo:4.0 mongo <uri> /seed.js` from the PeerDB EC2 (DocumentDB has no
public endpoint; this instance is in the same VPC and its SG is allowlisted on port 27017).

Note: DocumentDB engine 4.0.0 speaks MongoDB wire protocol version 7, which the modern
`mongosh` (bundled in the `mongo:7` image) refuses to talk to (requires wire version ≥8, i.e.
MongoDB 4.2+ driver). Had to fall back to the legacy `mongo` shell from the `mongo:4.0` image.
Anything mongosh-only in later PeerDB/DocumentDB tooling should account for this same
constraint.

- `profiles`: 150 docs (nullable name/zip, nested `address`, array `tags`, unicode/emoji)
- `events`: 300 docs (append-only pattern)
- `mutable_docs`: 100 docs (target for update/delete CDC checks)

Change streams enabled cluster-wide for database `shopdb` via
`db.adminCommand({modifyChangeStreams: 1, database: "shopdb", collection: "", enable: true})`.

Dedicated user created: `peerdb_reader` (`readAnyDatabase` on `admin` + `read` on `local`,
needed for oplog/change-stream access).
