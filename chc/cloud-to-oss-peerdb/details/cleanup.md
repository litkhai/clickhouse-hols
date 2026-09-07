# Cleanup — run 20260907T112912Z-lab1

Approved by user ("네 삭제해주세요"). All resources deleted in this order:

1. EC2 instances `<instance-id>` (ClickHouse OSS), `<instance-id>` (PeerDB) — terminated
2. RDS MySQL `chc-lab-mysql` — deleted, `--skip-final-snapshot` (lab-only synthetic data)
3. DocumentDB instance `chc-lab-docdb-1` then cluster `chc-lab-docdb` — deleted, `--skip-final-snapshot`
4. S3 stage bucket — emptied then deleted
5. IAM: removed role from instance profile, deleted instance profile, deleted inline policy,
   detached `AmazonSSMManagedInstanceCore`, deleted role
6. RDS parameter group `chc-lab-mysql8`, DocumentDB cluster parameter groups `chc-lab-docdb4`
   (orphaned after the engine-version recreate) and `chc-lab-docdb8`
7. RDS/DocumentDB subnet groups
8. Security groups — RDS and DocumentDB SGs deleted cleanly; the ClickHouse and PeerDB SGs
   initially failed with `DependencyViolation` because they had mutual cross-referencing
   ingress rules (PeerDB→ClickHouse 9000/8123, ClickHouse→PeerDB 9001 for MinIO). Revoked those
   specific rules first, then both groups deleted successfully.

Final verification: `resourcegroupstaggingapi get-resources` for this RunId returns only the
two terminated EC2 instance ARNs (expected — terminated instances remain visible for a period),
confirmed both in `terminated` state via `describe-instances`. IAM role and S3 bucket confirmed
gone (`NoSuchEntity` / `404`).

No resources from this run remain active or billing.
