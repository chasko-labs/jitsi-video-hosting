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
  description = "EC2 instance type for Jibri. m5.xlarge provides 16 GB RAM (Jibri minimum 8 GB for 720p, 12 GB for 1080p) and non-burstable 4 vCPU for sustained ffmpeg encoding over multi-hour sessions."
  type        = string
  default     = "m5.xlarge"
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
  description = "Container memory (MiB) for the Jibri container. m5.xlarge provides ~15800 MiB usable; 12288 gives Chrome + ffmpeg + shm=2048 real headroom for 1080p@30fps recording while leaving ~3.5 GB for OS/ECS agent."
  type        = number
  default     = 12288
}

variable "task_cpu" {
  description = "Container CPU units for the Jibri container (1024 = 1 vCPU). m5.xlarge = 4096 total; 3072 dedicates 3 vCPU to ffmpeg+Chrome, leaving 1 vCPU for ECS agent/OS."
  type        = number
  default     = 3072
}
