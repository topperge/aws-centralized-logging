#==============================================================================
# General
#==============================================================================
variable "region" {
  description = "AWS region for the primary (log destination) deployment. Defaults to the provider's environment configuration when null."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix used for named resources (Firehose, Kinesis stream, Lambda, CloudWatch Logs destinations, ...)."
  type        = string
  default     = "CL"
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}

#==============================================================================
# Elasticsearch configuration
#==============================================================================
variable "domain_name" {
  description = "OpenSearch/Elasticsearch domain name."
  type        = string
  default     = "centralizedlogging"
}

variable "admin_email" {
  description = "Email address of the Cognito admin user for Kibana. Also subscribed to Lambda error alarms."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\\.[a-zA-Z0-9-.]+$", var.admin_email))
    error_message = "admin_email must be a valid email address."
  }
}

variable "cluster_size" {
  description = "Elasticsearch cluster size; Small (4 data nodes), Medium (6 data nodes), Large (6 data nodes)."
  type        = string
  default     = "Small"

  validation {
    condition     = contains(["Small", "Medium", "Large"], var.cluster_size)
    error_message = "cluster_size must be one of Small, Medium, Large."
  }
}

variable "engine_version" {
  description = "Domain engine version. The transformer and sample dashboard target Elasticsearch 7.10 / Kibana."
  type        = string
  default     = "Elasticsearch_7.10"
}

variable "ebs_volume_size" {
  description = "EBS volume size (GiB) per data node."
  type        = number
  default     = 10
}

variable "create_es_service_linked_role" {
  description = "Create the es.amazonaws.com service-linked role. Set to false if it already exists in the account."
  type        = bool
  default     = true
}

variable "cognito_advanced_security_mode" {
  description = "Cognito user pool advanced security (threat protection) mode: OFF, AUDIT or ENFORCED. AUDIT/ENFORCED put the pool on the PLUS feature tier."
  type        = string
  default     = "ENFORCED"

  validation {
    condition     = contains(["OFF", "AUDIT", "ENFORCED"], var.cognito_advanced_security_mode)
    error_message = "cognito_advanced_security_mode must be one of OFF, AUDIT, ENFORCED."
  }
}

#==============================================================================
# Spoke configuration
#==============================================================================
variable "spoke_accounts" {
  description = "Account IDs allowed to stream logs to the centralized destination (e.g. [\"111111111111\", \"222222222222\"])."
  type        = list(string)

  validation {
    condition     = length(var.spoke_accounts) > 0 && alltrue([for a in var.spoke_accounts : can(regex("^[0-9]{12}$", a))])
    error_message = "spoke_accounts must be a non-empty list of 12-digit AWS account IDs."
  }
}

variable "spoke_regions" {
  description = "Regions in which to create CloudWatch Logs destinations (e.g. [\"us-east-1\", \"us-west-2\"]). [\"All\"] means every region enabled in the account."
  type        = list(string)
  default     = ["All"]
}

#==============================================================================
# Sample log sources
#==============================================================================
variable "deploy_demo" {
  description = "Deploy demo resources (web server, VPC flow logs, CloudTrail) that stream sample logs. Requires the primary account ID in spoke_accounts and the deployment region in spoke_regions."
  type        = bool
  default     = false
}

#==============================================================================
# Jumpbox configuration
#==============================================================================
variable "deploy_jumpbox" {
  description = "Deploy a Windows jumpbox in the domain VPC's public subnet for Kibana access."
  type        = bool
  default     = false
}

variable "jumpbox_key" {
  description = "EC2 key pair name for the jumpbox (required when deploy_jumpbox is true)."
  type        = string
  default     = ""
}

variable "jumpbox_instance_type" {
  description = "Instance type for the jumpbox."
  type        = string
  default     = "t3.micro"
}

#==============================================================================
# Transformer Lambda
#==============================================================================
variable "transformer_zip_path" {
  description = "Path to the transformer Lambda package produced by `npm run build` at the repository root."
  type        = string
  default     = "../source/services/transformer/dist/transformer/cl-transformer.zip"
}

variable "lambda_runtime" {
  description = "Node.js runtime for the transformer Lambda."
  type        = string
  default     = "nodejs22.x"
}

variable "lambda_log_level" {
  description = "Log level for the transformer Lambda (error, warn, info, debug)."
  type        = string
  default     = "info"
}

variable "send_anonymized_metrics" {
  description = "Send anonymized usage metrics to AWS Solutions."
  type        = bool
  default     = true
}
