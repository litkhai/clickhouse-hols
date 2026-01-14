variable "organization_id" {
  description = "ClickHouse Cloud Organization ID"
  type        = string
}

variable "service_id" {
  description = "ClickHouse Cloud Service ID"
  type        = string
}

variable "api_key" {
  description = "ClickHouse Cloud API Key"
  type        = string
  sensitive   = true
}

variable "pipe_name" {
  description = "Name of the ClickPipe"
  type        = string
  default     = "test_s3_checkpoint_pipe"
}

variable "table_name" {
  description = "Destination table name"
  type        = string
  default     = "test_clickpipe_checkpoint"
}

variable "s3_bucket" {
  description = "S3 bucket name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "test_prefix" {
  description = "S3 prefix for test data"
  type        = string
  default     = "clickpipe-test"
}

variable "aws_access_key_id" {
  description = "AWS Access Key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key"
  type        = string
  sensitive   = true
}
