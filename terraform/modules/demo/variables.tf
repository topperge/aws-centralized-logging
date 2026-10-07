variable "name_prefix" {
  description = "Prefix for named demo resources."
  type        = string
}

variable "destination_arn" {
  description = "CloudWatch Logs destination ARN to stream demo logs to."
  type        = string
}

variable "instance_type" {
  description = "Instance type for the demo web server."
  type        = string
  default     = "t3.micro"
}

# Passed in rather than looked up: the module is instantiated with depends_on,
# which defers its data sources to apply time and would make counts unknown.
variable "availability_zones" {
  description = "Availability zones for the demo VPC's public subnets."
  type        = list(string)
}

variable "account_id" {
  description = "Account ID the demo is deployed in (used in the CloudTrail bucket policy)."
  type        = string
}
