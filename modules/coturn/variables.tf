variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of public subnet IDs (assign_public_ip=true, so public subnets required)"
  type        = list(string)
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution IAM role"
  type        = string
}

variable "turn_realm" {
  description = "TURN realm (e.g. turn.clouddelnorte.org)"
  type        = string
}

variable "turn_cert_secret_arn" {
  description = "Secrets Manager ARN for TLS cert+key JSON blob with keys 'cert' and 'pkey'"
  type        = string
}

variable "turn_static_auth_secret_ssm_arn" {
  description = "SSM Parameter ARN (SecureString) holding the static-auth-secret for time-limited TURN credentials"
  type        = string
}

variable "coturn_image" {
  description = "coturn Docker image"
  type        = string
  default     = "coturn/coturn:latest"
}

variable "relay_min_port" {
  description = "Minimum UDP relay port (keep range small — each port needs a SG rule)"
  type        = number
  default     = 49160
}

variable "relay_max_port" {
  description = "Maximum UDP relay port (default 49200 = 41 ports; expand if concurrent sessions > ~10)"
  type        = number
  default     = 49200
}

variable "task_cpu" {
  description = "Fargate task CPU units"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory (MiB)"
  type        = number
  default     = 512
}

variable "project_name" {
  description = "Project name for resource tagging/naming"
  type        = string
}

variable "environment" {
  description = "Environment (e.g. prod, staging)"
  type        = string
  default     = "prod"
}
