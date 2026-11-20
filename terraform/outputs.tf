output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  value = aws_instance.app.public_ip
}

output "api_url" {
  value = "http://${aws_instance.app.public_ip}:${var.app_port}"
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/todo-api ec2-user@${aws_instance.app.public_ip}"
}

output "rds_endpoint" {
  value = aws_db_instance.todo.address
}

output "rds_identifier" {
  value = aws_db_instance.todo.identifier
}

output "db_secret_name" {
  value = aws_secretsmanager_secret.db.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.todo.dashboard_name}"
}
