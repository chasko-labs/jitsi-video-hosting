output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.coturn.name
}

output "security_group_id" {
  description = "ID of the coturn security group (opens 3478 udp/tcp, 5349 tcp, relay UDP range)"
  value       = aws_security_group.coturn.id
}

output "public_endpoint_note" {
  description = "Operational note: coturn has no NLB. The task ENI public IP changes on each redeploy. After apply, retrieve the running task's public IP and update your DNS A record for var.turn_realm."
  value       = "No static endpoint — update DNS A record for ${var.turn_realm} after each redeploy. Run: aws ecs describe-tasks --cluster <cluster> --tasks <task-arn> | jq '.tasks[].attachments[].details[] | select(.name==\"networkInterfaceId\")' then aws ec2 describe-network-interfaces --network-interface-ids <eni-id> | jq '.NetworkInterfaces[].Association.PublicIp'"
}
