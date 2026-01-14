terraform {
  required_providers {
    clickhouse = {
      source  = "ClickHouse/clickhouse"
      version = "~> 0.0.3"
    }
  }
}

provider "clickhouse" {
  organization_id = var.organization_id
  token           = var.api_key
}

# ClickPipe for S3 to ClickHouse
resource "clickhouse_pipe" "s3_test_pipe" {
  name        = var.pipe_name
  description = "Test pipe for checkpoint validation"

  source {
    type = "s3"

    s3 {
      bucket     = var.s3_bucket
      region     = var.aws_region
      path       = "${var.test_prefix}/"
      format     = "JSONEachRow"

      credentials {
        access_key_id     = var.aws_access_key_id
        secret_access_key = var.aws_secret_access_key
      }
    }
  }

  destination {
    service_id = var.service_id
    table      = var.table_name
  }
}

output "pipe_id" {
  value       = clickhouse_pipe.s3_test_pipe.id
  description = "The ID of the created ClickPipe"
}

output "pipe_status" {
  value       = clickhouse_pipe.s3_test_pipe.status
  description = "The status of the ClickPipe"
}
