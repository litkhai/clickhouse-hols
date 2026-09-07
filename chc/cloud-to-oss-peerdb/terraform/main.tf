data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnet" "selected" {
  id = var.private_subnet_id
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_kms_key" "data" {
  description             = "KMS key for ClickHouse migration EC2, EBS and S3"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "data" {
  name          = "alias/${var.name_prefix}-data"
  target_key_id = aws_kms_key.data.key_id
}

resource "aws_s3_bucket" "stage" {
  bucket_prefix = "${var.name_prefix}-stage-"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "stage" {
  bucket = aws_s3_bucket.stage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "stage_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    actions = [
      "s3:*"
    ]
    resources = [
      aws_s3_bucket.stage.arn,
      "${aws_s3_bucket.stage.arn}/*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "stage" {
  bucket = aws_s3_bucket.stage.id
  policy = data.aws_iam_policy_document.stage_bucket.json
}

resource "aws_s3_bucket_server_side_encryption_configuration" "stage" {
  bucket = aws_s3_bucket.stage.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.data.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "stage" {
  bucket = aws_s3_bucket.stage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "stage" {
  bucket = aws_s3_bucket.stage.id

  rule {
    id     = "expire-peerdb-stage"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_vpc_endpoint" "s3" {
  count = var.create_s3_gateway_endpoint && length(var.private_route_table_ids) > 0 ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids
}

resource "aws_security_group" "clickhouse" {
  name_prefix = "${var.name_prefix}-clickhouse-"
  description = "ClickHouse TLS-only access"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PeerDB to ClickHouse native TLS"
    from_port       = 9440
    to_port         = 9440
    protocol        = "tcp"
    security_groups = [aws_security_group.peerdb.id]
  }

  dynamic "ingress" {
    for_each = var.operator_cidr == null ? [] : [var.operator_cidr]
    content {
      description = "Operator HTTPS from private network"
      from_port   = 8443
      to_port     = 8443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "peerdb" {
  name_prefix = "${var.name_prefix}-peerdb-"
  description = "PeerDB operator access; source connections are outbound"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.operator_cidr == null ? [] : [var.operator_cidr]
    content {
      description = "PeerDB UI from private network"
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.operator_cidr == null ? [] : [var.operator_cidr]
    content {
      description = "PeerDB SQL from private network"
      from_port   = 9900
      to_port     = 9900
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "clickhouse" {
  name_prefix        = "${var.name_prefix}-clickhouse-"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role" "peerdb" {
  name_prefix        = "${var.name_prefix}-peerdb-"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "clickhouse_ssm" {
  role       = aws_iam_role.clickhouse.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "peerdb_ssm" {
  role       = aws_iam_role.peerdb.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "clickhouse" {
  statement {
    sid     = "ReadBootstrapSecrets"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      var.clickhouse_tls_secret_arn,
      var.clickhouse_admin_password_secret_arn,
      var.peerdb_clickhouse_password_secret_arn
    ]
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = concat([aws_kms_key.data.arn], var.bootstrap_secret_kms_key_arns)
  }

  statement {
    sid       = "ListStageBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.stage.arn]
  }

  statement {
    sid       = "UseStageObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.stage.arn}/*"]
  }
}

resource "aws_iam_role_policy" "clickhouse" {
  name   = "bootstrap-and-stage"
  role   = aws_iam_role.clickhouse.id
  policy = data.aws_iam_policy_document.clickhouse.json
}

data "aws_iam_policy_document" "peerdb" {
  statement {
    sid     = "ReadBootstrapSecrets"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      var.peerdb_env_secret_arn,
      var.clickhouse_ca_secret_arn,
      var.peerdb_clickhouse_password_secret_arn
    ]
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = concat([aws_kms_key.data.arn], var.bootstrap_secret_kms_key_arns)
  }

  statement {
    sid       = "ListStageBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.stage.arn]
  }

  statement {
    sid       = "UseStageObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.stage.arn}/*"]
  }
}

resource "aws_iam_role_policy" "peerdb" {
  name   = "bootstrap-and-stage"
  role   = aws_iam_role.peerdb.id
  policy = data.aws_iam_policy_document.peerdb.json
}

resource "aws_iam_instance_profile" "clickhouse" {
  name_prefix = "${var.name_prefix}-clickhouse-"
  role        = aws_iam_role.clickhouse.name
}

resource "aws_iam_instance_profile" "peerdb" {
  name_prefix = "${var.name_prefix}-peerdb-"
  role        = aws_iam_role.peerdb.name
}

resource "aws_instance" "clickhouse" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.clickhouse_instance_type
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [aws_security_group.clickhouse.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.clickhouse.name
  ebs_optimized               = true
  monitoring                  = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    encrypted             = true
    kms_key_id            = aws_kms_key.data.arn
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/clickhouse-user-data.sh.tftpl", {
    aws_region                   = var.aws_region
    clickhouse_channel           = var.clickhouse_channel
    clickhouse_tls_secret_arn    = var.clickhouse_tls_secret_arn
    clickhouse_admin_secret_arn  = var.clickhouse_admin_password_secret_arn
    clickhouse_allowed_cidr      = data.aws_vpc.selected.cidr_block
    clickhouse_tls_server_name   = var.clickhouse_private_dns_name
    peerdb_private_ip            = aws_instance.peerdb.private_ip
    peerdb_clickhouse_secret_arn = var.peerdb_clickhouse_password_secret_arn
  })

  tags = {
    Name = "${var.name_prefix}-clickhouse"
    Role = "clickhouse"
  }
}

resource "aws_route53_record" "clickhouse" {
  zone_id = var.route53_private_zone_id
  name    = var.clickhouse_private_dns_name
  type    = "A"
  ttl     = 60
  records = [aws_instance.clickhouse.private_ip]
}

resource "aws_instance" "peerdb" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.peerdb_instance_type
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [aws_security_group.peerdb.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.peerdb.name
  ebs_optimized               = true
  monitoring                  = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    encrypted             = true
    kms_key_id            = aws_kms_key.data.arn
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/peerdb-user-data.sh.tftpl", {
    aws_region                   = var.aws_region
    peerdb_image_tag             = var.peerdb_image_tag
    peerdb_env_secret_arn        = var.peerdb_env_secret_arn
    clickhouse_ca_secret_arn     = var.clickhouse_ca_secret_arn
    peerdb_clickhouse_secret_arn = var.peerdb_clickhouse_password_secret_arn
    peerdb_stage_bucket          = aws_s3_bucket.stage.id
    peerdb_ui_base_url           = var.peerdb_ui_base_url
    expose_operator_ports        = var.operator_cidr == null ? "127.0.0.1" : "0.0.0.0"
  })

  tags = {
    Name = "${var.name_prefix}-peerdb"
    Role = "peerdb"
  }
}

resource "aws_ebs_volume" "clickhouse_data" {
  availability_zone = data.aws_subnet.selected.availability_zone
  type              = "gp3"
  size              = var.clickhouse_data_size_gib
  iops              = var.clickhouse_data_iops
  throughput        = var.clickhouse_data_throughput
  encrypted         = true
  kms_key_id        = aws_kms_key.data.arn

  tags = {
    Name = "${var.name_prefix}-clickhouse-data"
  }
}

resource "aws_ebs_volume" "peerdb_data" {
  availability_zone = data.aws_subnet.selected.availability_zone
  type              = "gp3"
  size              = var.peerdb_data_size_gib
  iops              = 3000
  throughput        = 125
  encrypted         = true
  kms_key_id        = aws_kms_key.data.arn

  tags = {
    Name = "${var.name_prefix}-peerdb-state"
  }
}

resource "aws_volume_attachment" "clickhouse_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.clickhouse_data.id
  instance_id = aws_instance.clickhouse.id
}

resource "aws_volume_attachment" "peerdb_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.peerdb_data.id
  instance_id = aws_instance.peerdb.id
}
