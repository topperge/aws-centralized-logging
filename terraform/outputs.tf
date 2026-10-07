output "destination_subscription_command" {
  description = "Command to run in spoke accounts/regions"
  value       = "aws logs put-subscription-filter --destination-arn arn:${local.partition}:logs:<region>:${local.account_id}:destination:${local.destination_name} --log-group-name <MyLogGroup> --filter-name <MyFilterName> --filter-pattern <MyFilterPattern> --profile <MyAWSProfile>"
}

output "destination_arns" {
  description = "CloudWatch Logs destination ARN per spoke region"
  value       = { for r, d in aws_cloudwatch_log_destination.spoke : r => d.arn }
}

output "unique_id" {
  description = "UUID for Centralized Logging deployment"
  value       = local.uuid
}

output "admin_email" {
  description = "Admin Email address"
  value       = var.admin_email
}

output "domain_name" {
  description = "ES Domain Name"
  value       = aws_opensearch_domain.es.domain_name
}

output "kibana_url" {
  description = "Kibana URL"
  value       = "https://${aws_opensearch_domain.es.dashboard_endpoint}"
}

output "cluster_size" {
  description = "ES Cluster Size"
  value       = var.cluster_size
}

output "demo_deployment" {
  description = "Demo data deployed?"
  value       = var.deploy_demo
}

output "demo_url" {
  description = "URL for demo web server"
  value       = var.deploy_demo ? module.demo[0].url : null
}

output "jumpbox_public_ip" {
  description = "Public IP of the Windows jumpbox"
  value       = var.deploy_jumpbox ? aws_instance.jumpbox[0].public_ip : null
}
