# ECS Express Mode Features - Implementation Summary

> **doc status (2026-04-23):** current. ECS Express Mode with Service Connect is still the deployment model. all features listed here remain active. this doc pre-dates JWT auth and the 4-container sidecar restoration — those additions are orthogonal to Express Mode and do not change what is described here

**Date**: December 27, 2025  
**Status**: ✅ Fully Implemented

## ECS Express Features Implemented

### 1. ✅ Service Connect (Automatic Load Balancing)
- **Status**: Implemented
- **Feature**: Automatic service discovery and load balancing without manual NLB configuration
- **Configuration**:
  ```hcl
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.jitsi.arn
    service {
      client_alias {
        port     = 80
        dns_name = "jitsi-web"
      }
      port_name      = "web"
      discovery_name = "jitsi-web"
    }
  }
  ```
- **Benefit**: Eliminates need for manual ALB/NLB configuration for internal service communication

### 2. ✅ ECS Exec (Interactive Debugging)
- **Status**: Implemented
- **Feature**: Execute commands in running containers without SSH
- **Configuration**:
  ```hcl
  enable_execute_command = true
  ```
- **IAM Permissions**: Added `ssmmessages:*` and `logs:*` permissions
- **Usage**:
  ```bash
  aws ecs execute-command \
    --cluster jitsi-video-platform-cluster \
    --task <TASK_ID> \
    --container jitsi-web \
    --interactive \
    --command /bin/bash
  ```
- **Benefit**: Debug running containers without exposing SSH ports

### 3. ✅ Tag Propagation
- **Status**: Implemented
- **Feature**: Automatically propagate tags from service to tasks
- **Configuration**:
  ```hcl
  propagate_tags = "SERVICE"
  ```
- **Benefit**: Consistent tagging across all resources for cost allocation and organization

### 4. ✅ Capacity Providers (Managed Scaling)
- **Status**: Implemented
- **Feature**: Automatic scaling based on resource utilization
- **Configuration**:
  ```hcl
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 100
    base              = 1
  }
  ```
- **Providers**: FARGATE (primary), FARGATE_SPOT (optional for cost optimization)
- **Benefit**: Automatic scaling without manual ASG configuration

### 5. ✅ Container Insights
- **Status**: Implemented
- **Feature**: Enhanced monitoring and logging
- **Configuration**:
  ```hcl
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  ```
- **Benefit**: Detailed metrics and logs for troubleshooting

### 6. ✅ Managed Scaling
- **Status**: Implemented
- **Feature**: Cluster-level managed scaling
- **Configuration**:
  ```hcl
  setting {
    name  = "managedScaling"
    value = "enabled"
  }
  ```
- **Benefit**: Automatic scaling of cluster capacity

## Architecture Benefits

### Before (Standard ECS)
```
909 lines of Terraform
├── Manual VPC configuration
├── Manual Security Groups
├── Manual NLB setup (5 resources)
├── Manual target groups
└── Manual health checks
```

### After (ECS Express)
```
~450 lines of Terraform (50% reduction)
├── Service Connect (automatic LB)
├── ECS Exec (no SSH needed)
├── Managed Scaling (automatic)
├── Tag Propagation (automatic)
└── Container Insights (built-in)
```

## Cost Impact

**No change to cost model:**
- Fixed costs: $16.62/month (NLB still required for external traffic)
- Variable costs: $0.198/hour (Fargate pricing unchanged)
- Scale-to-zero: Still supported (desired_count = 0)

**Operational benefits:**
- Reduced maintenance overhead
- Faster debugging with ECS Exec
- Automatic scaling reduces manual intervention
- Better observability with Container Insights

## Deployment Checklist

- ✅ Service Connect enabled with namespace
- ✅ ECS Exec enabled with IAM permissions
- ✅ Tag propagation configured
- ✅ Capacity providers configured
- ✅ Managed scaling enabled
- ✅ Container Insights enabled
- ✅ Outputs added for ECS Exec commands

## Usage Examples

### Scale Up Platform
```bash
./scripts/scale-up.pl
```

### Debug Running Container
```bash
# Get task ID
TASK_ID=$(aws ecs list-tasks --cluster jitsi-video-platform-cluster --profile jitsi-video-hosting-170473530355 --query 'taskArns[0]' --output text | cut -d'/' -f3)

# Execute command
aws ecs execute-command \
  --cluster jitsi-video-platform-cluster \
  --task $TASK_ID \
  --container jitsi-web \
  --interactive \
  --command /bin/bash \
  --profile jitsi-video-hosting-170473530355
```

### View Container Logs
```bash
aws logs tail /ecs/jitsi-video-platform --follow --profile jitsi-video-hosting-170473530355
```

## References

- [AWS ECS Express Mode Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-express.html)
- [ECS Exec Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html)
- [Service Connect Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html)
- [Capacity Providers Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/capacity-providers.html)

## Next Steps

1. Deploy infrastructure to new account (170473530355)
2. Test ECS Exec functionality
3. Monitor managed scaling behavior
4. Document operational procedures for ECS Exec debugging
