variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the ASG and ECS service"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for EC2 instances and ECS tasks"
  type        = string
}

variable "cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name (written to ecs.config)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "recordings_bucket" {
  description = "S3 bucket name for recordings"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name (e.g. /ecs/jitsi-app)"
  type        = string
}

variable "jibri_recorder_password_ssm_arn" {
  description = "SSM parameter ARN for JIBRI_RECORDER_PASSWORD"
  type        = string
}

variable "jibri_xmpp_password_ssm_arn" {
  description = "SSM parameter ARN for JIBRI_XMPP_PASSWORD"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN (for SSM secret pulls)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Jibri"
  type        = string
  default     = "t3.medium"
}

variable "jibri_count" {
  description = "Desired number of Jibri instances"
  type        = number
  default     = 1
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. prod)"
  type        = string
  default     = "prod"
}

variable "prosody_dns" {
  description = "Cloud Map DNS name for the jitsi service (prosody). Resolved via Route 53 private hosted zone."
  type        = string
}

variable "task_memory" {
  description = "Container memory (MiB) for the Jibri container. t3.medium ~3800 MiB usable; leave headroom for ECS agent/OS. Reduced from 3584 to 3072 to safely accommodate sharedMemorySize=2048 (counts against container memory)."
  type        = number
  default     = 3072
}

variable "task_cpu" {
  description = "Container CPU units for the Jibri container (1024 = 1 vCPU). t3.medium = 2048 total."
  type        = number
  default     = 1536
}


variable "jibri_image" {
  description = "Docker image for the Jibri container (ECR URL with tag)"
  type        = string
  default     = "170473530355.dkr.ecr.us-west-2.amazonaws.com/jitsi-jibri:latest"
}
