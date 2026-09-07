# EC2 deployment quick start

This directory provisions one ClickHouse EC2 instance and one PeerDB EC2 instance in an existing private VPC/subnet. It also creates encrypted gp3 data volumes, a KMS-encrypted S3 staging bucket, least-privilege instance roles, SSM access, security groups and a private Route 53 record.

The instances have no public IP. The private subnet must provide outbound access to Ubuntu, ClickHouse, Docker and GHCR package registries through NAT or an approved mirror. S3 can use the optional gateway endpoint; add interface endpoints for SSM, `ssmmessages`, Secrets Manager, KMS and CloudWatch when NAT is not used.

## Prerequisites

- Terraform 1.6+
- AWS credentials authorized to create the resources in `main.tf`
- Existing VPC, private subnet, route table and Route 53 private hosted zone
- A certificate whose SAN includes the selected ClickHouse private DNS name
- Five existing Secrets Manager secrets; do not put secret values in `tfvars`

Secret formats:

1. ClickHouse TLS secret, JSON:

   ```json
   {
     "server_crt": "-----BEGIN CERTIFICATE-----\n...",
     "server_key": "-----BEGIN PRIVATE KEY-----\n...",
     "ca_crt": "-----BEGIN CERTIFICATE-----\n..."
   }
   ```

2. ClickHouse CA secret: CA certificate PEM as the raw `SecretString`.
3. ClickHouse admin password secret: password as the raw `SecretString`.
4. PeerDB ClickHouse password secret: password as the raw `SecretString`.
5. PeerDB environment secret, raw dotenv text:

   ```dotenv
   CATALOG_PASSWORD=replace_with_long_alphanumeric_value
   PEERDB_PASSWORD=replace_with_long_alphanumeric_value
   NEXTAUTH_SECRET=replace_with_at_least_32_random_characters
   ```

Use long URL-safe or alphanumeric password values so dotenv parsing is unambiguous. If a secret uses a customer-managed KMS key, add its ARN to `bootstrap_secret_kms_key_arns`.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit IDs, DNS name and secret ARNs.
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

`user_data` waits for the separately attached EBS volume, mounts it by filesystem UUID, then installs and starts the service. An apply completing does not mean cloud-init has completed.

Check each instance through Session Manager:

```bash
sudo cloud-init status --wait
sudo test -f /var/log/clickhouse-bootstrap.done
sudo tail -n 200 /var/log/clickhouse-bootstrap.log
```

For PeerDB, replace the filenames with `peerdb-bootstrap.done` and `peerdb-bootstrap.log`, then run:

```bash
cd /opt/peerdb
sudo docker compose ps
sudo docker compose logs --tail=100
```

The Compose bootstrap also starts Temporal admin tools, registers the required `MirrorName` custom search attribute, and only then releases the Flow services. This ordering is required for mirror creation on the pinned PeerDB release.

Terraform outputs ready-to-copy SSM port-forwarding commands. With the default `operator_cidr = null`, the PeerDB UI and SQL endpoint listen only on loopback and are reachable through those tunnels.

## Important operational notes

- Pin and test `peerdb_image_tag` and the ClickHouse channel before production. For strict reproducibility, bake the validated package and image digests into an AMI.
- Changing `user_data` does not reconfigure an existing instance automatically. Apply upgrades through SSM/automation or replace the instance during an approved maintenance window.
- The Compose deployment is a production-lite single-host topology, not PeerDB HA. Back up the catalog/Temporal PostgreSQL volume and rehearse restore.
- Do not run `terraform destroy` as an uninstall procedure. The S3 bucket has `force_destroy = false`, while the separately managed EBS volumes contain persistent state and require an explicit retention/deletion decision.
