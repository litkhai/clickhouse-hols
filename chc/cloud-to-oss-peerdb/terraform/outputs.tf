output "clickhouse_instance_id" {
  value = aws_instance.clickhouse.id
}

output "clickhouse_private_ip" {
  value = aws_instance.clickhouse.private_ip
}

output "peerdb_instance_id" {
  value = aws_instance.peerdb.id
}

output "peerdb_private_ip" {
  value = aws_instance.peerdb.private_ip
}

output "peerdb_stage_bucket" {
  value = aws_s3_bucket.stage.id
}

output "clickhouse_ssm_port_forward" {
  value = "aws ssm start-session --target ${aws_instance.clickhouse.id} --document-name AWS-StartPortForwardingSession --parameters portNumber=8443,localPortNumber=8443"
}

output "peerdb_ui_ssm_port_forward" {
  value = "aws ssm start-session --target ${aws_instance.peerdb.id} --document-name AWS-StartPortForwardingSession --parameters portNumber=3000,localPortNumber=3000"
}

output "peerdb_sql_ssm_port_forward" {
  value = "aws ssm start-session --target ${aws_instance.peerdb.id} --document-name AWS-StartPortForwardingSession --parameters portNumber=9900,localPortNumber=9900"
}
