output "destination_arn" {
  description = "CloudWatch Logs destination arn"
  value       = var.destination_arn
}

output "url" {
  description = "URL for demo web server"
  value       = "http://${aws_instance.web.public_ip}"
}
