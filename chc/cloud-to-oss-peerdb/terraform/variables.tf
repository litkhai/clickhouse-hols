variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "name_prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "clickhouse-migration"
}

variable "vpc_id" {
  description = "Existing VPC ID"
  type        = string
}

variable "private_subnet_id" {
  description = "Existing private subnet ID with NAT or equivalent package registry egress"
  type        = string
}

variable "private_route_table_ids" {
  description = "Route tables that receive the optional S3 gateway endpoint"
  type        = list(string)
  default     = []
}

variable "create_s3_gateway_endpoint" {
  description = "Create an S3 gateway endpoint for the supplied private route tables"
  type        = bool
  default     = true
}

variable "clickhouse_instance_type" {
  type    = string
  default = "m7i.4xlarge"
}

variable "peerdb_instance_type" {
  type    = string
  default = "m7i.2xlarge"
}

variable "clickhouse_data_size_gib" {
  type    = number
  default = 300
}

variable "clickhouse_data_iops" {
  type    = number
  default = 6000
}

variable "clickhouse_data_throughput" {
  type    = number
  default = 250
}

variable "peerdb_data_size_gib" {
  type    = number
  default = 150
}

variable "clickhouse_channel" {
  description = "Official package channel: stable or lts"
  type        = string
  default     = "lts"

  validation {
    condition     = contains(["stable", "lts"], var.clickhouse_channel)
    error_message = "clickhouse_channel must be stable or lts."
  }
}

variable "clickhouse_private_dns_name" {
  description = "Private DNS name present in the ClickHouse server certificate SAN"
  type        = string
}

variable "route53_private_zone_id" {
  description = "Existing Route 53 private hosted zone ID for the ClickHouse A record"
  type        = string
}

variable "peerdb_image_tag" {
  description = "Pinned PeerDB image tag validated by the operator"
  type        = string
  default     = "stable-v0.37.5"
}

variable "clickhouse_tls_secret_arn" {
  description = "Existing Secrets Manager secret containing JSON keys server_crt, server_key and ca_crt"
  type        = string
}

variable "clickhouse_ca_secret_arn" {
  description = "Existing Secrets Manager secret whose SecretString is the CA PEM only"
  type        = string
}

variable "clickhouse_admin_password_secret_arn" {
  description = "Existing Secrets Manager secret whose SecretString is the ClickHouse admin password"
  type        = string
}

variable "peerdb_clickhouse_password_secret_arn" {
  description = "Existing Secrets Manager secret whose SecretString is the PeerDB ClickHouse user password"
  type        = string
}

variable "peerdb_env_secret_arn" {
  description = "Existing secret in dotenv format containing CATALOG_PASSWORD, PEERDB_PASSWORD and NEXTAUTH_SECRET"
  type        = string
}

variable "bootstrap_secret_kms_key_arns" {
  description = "Customer-managed KMS keys used by the supplied Secrets Manager secrets"
  type        = list(string)
  default     = []
}

variable "peerdb_ui_base_url" {
  description = "URL used by NextAuth; localhost works with SSM port forwarding"
  type        = string
  default     = "http://localhost:3000"
}

variable "operator_cidr" {
  description = "Optional private VPN CIDR allowed to ClickHouse HTTPS and PeerDB UI/SQL. Leave null to use SSM only."
  type        = string
  default     = null
}

variable "tags" {
  type = map(string)
  default = {
    ManagedBy   = "Terraform"
    Environment = "migration"
  }
}
