# Scope decision — run 20260907T112912Z-lab1

User instructions (in order) that shaped scope:
1. "성능 수치는 검증 범위가 아니며 기능적으로 동작하는것을 확인하는게 주안 사항" — functional
   correctness only, not performance.
2. "최소한의 인스턴스로 모두 배포해서 테스트를 진행" — deploy with minimal instances.
3. "기능적으로 되는지가 중요하므로 보안 기능까지는 검토하지 않아도 됩니다" and "보안 기능 모두
   제외하고 빠르게 효율적으로 진행" — explicitly skip the security-hardening profile (SEC-2 in
   the runbook) and move fast.

Resulting deviations from `AI-VALIDATION-WORK-INSTRUCTIONS.md` (deliberate, not oversights):

| Runbook requirement | This run |
|---|---|
| Private subnet + NAT/VPC endpoints | Default VPC public subnets, SG-scoped access only |
| TLS 8443/9440 client, mTLS PeerDB↔ClickHouse | Plaintext 8123/9000, SG-restricted |
| KMS encryption everywhere | Default encryption only (EBS gp3 default, S3 SSE-S3) |
| Secrets Manager for all credentials | Lab-only random secrets generated locally, injected via user-data, never committed to git |
| GTID mode on RDS MySQL | Skipped — requires a multi-step staged transition (OFF→...→ON) that costs multiple reboots; `binlog_format=ROW` + `binlog_row_image=FULL` kept, which is what CDC actually requires |
| Separate EBS volume for ClickHouse data (UUID mount) | Single enlarged root volume (50 GiB) |
| 7-scenario failure-injection matrix, full backup/restore drill | Deferred/trimmed — see SUMMARY.md for what was actually exercised in this run |
| RunId/ExpiresAt tags, evidence directories | Kept — cost/blast-radius hygiene, independent of the security-profile decision |

Resources are still tagged and an explicit cleanup-approval gate is still planned before any
`terraform destroy`/`delete-db-instance`/etc., regardless of the security scope reduction —
that gate is about cost/irreversibility, not security review.

## Scope narrowed further (mid-run)

After infra was already up, the user clarified the actual goal is narrower than the full
runbook: **"PeerDB로 documentdb와 rds mysql만 옮기면 됩니다"** — just prove PeerDB can move
RDS MySQL and DocumentDB into ClickHouse OSS, with working CDC. Explicitly not wanted:
dual-run comparison against the existing ClickHouse Cloud service, ClickPipes at all,
`remoteSecure` backfill (that's for copying pre-existing Cloud tables, not part of this ask),
and the cutover/rollback simulation. This also sidesteps a ClickPipes→RDS connectivity issue
hit mid-run (i/o timeout connecting to the RDS public endpoint from ClickPipes' NAT IPs,
root cause not investigated since the ClickPipes path was dropped from scope).

Remaining scope: MySQL fixtures + DocumentDB fixtures (already seeded) → PeerDB initial
snapshot + CDC mirrors → ClickHouse OSS, verified with an INSERT/UPDATE/DELETE batch on both
sources.
