variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "vpc_id" {
  description = "VPC ID where the NLB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "DEPRECATED — use subnet_eip_mappings instead. Kept for backward compat."
  type        = list(string)
  default     = []
}

variable "subnet_eip_mappings" {
  description = "List of {subnet_id, allocation_id} maps — one per AZ. Pins the NLB to static Elastic IPs."
  type = list(object({
    subnet_id     = string
    allocation_id = string
  }))
}

variable "security_group_id" {
  description = "Security group ID for the NLB (not directly used but for reference)"
  type        = string
}
