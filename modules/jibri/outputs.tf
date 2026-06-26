output "asg_name" {
  description = "Name of the Jibri Auto Scaling Group"
  value       = aws_autoscaling_group.jibri.name
}

output "service_name" {
  description = "Name of the Jibri ECS service"
  value       = aws_ecs_service.jibri.name
}

output "capacity_provider_name" {
  description = "Name of the Jibri ECS capacity provider (wire into aws_ecs_cluster_capacity_providers in JIB-2)"
  value       = aws_ecs_capacity_provider.jibri.name
}

output "instance_role_arn" {
  description = "ARN of the Jibri EC2 instance IAM role"
  value       = aws_iam_role.jibri_instance.arn
}
