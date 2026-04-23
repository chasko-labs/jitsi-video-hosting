# ECS Express Mode Migration Brief
**Purpose**: Technical foundation for Kiro spec-driven migration  
**Date**: December 15, 2025  
**Status**: Ready for Kiro spec

> **doc status (2026-04-23):** current as a historical migration record. the Express Mode architecture described is still in production. this doc predates the JWT auth addition and the 4-container restoration — neither affects the Express Mode topology

---

## 1. What Express Mode Handles (Auto-Provisioned)

### Cluster & Compute
- ✅ ECS Cluster (default or specified)
- ✅ Fargate capacity provider (only option—no EC2)
- ✅ Task Definition with sensible defaults (awsvpc networking, Linux x86_64)
- ✅ Service with canary deployments enabled

### Load Balancing & Networking
- ✅ Application Load Balancer (internet-facing or internal based on subnet type)
- ✅ HTTPS listener on port 443 (auto-managed)
- ✅ Host-header based listener rules (up to 25 services per ALB)
- ✅ Target group (HTTP on container port, default 80)
- ✅ Security groups (minimal ingress, open outbound to internet)
- ✅ Route 53 domain (AWS-provided URL, auto-generated)
- ✅ ACM certificate (auto-issued, auto-renewed)

### Auto Scaling
- ✅ Application Auto Scaling target
- ✅ Target-tracking scaling policy (CPU-based by default, 60% threshold)
- ✅ Min/max task count (default 1-20)

### Logging & Monitoring
- ✅ CloudWatch Log Group (named `/aws/ecs/<cluster>/<service>-####`)
- ✅ Metric alarms for faulty deployments

---

## 2. What We Must Still Handle

### Certificate & Domain (Current Setup)
- ❌ **NOT auto-provisioned by Express Mode**: Cross-account DNS validation
- ❌ **We maintain**: ACM certificate in `668383289911` (infrastructure account)
- ❌ **We maintain**: DNS records in `211125425201` (DNS account)
- ✅ **Express Mode can use**: A **custom domain** if we attach our ACM cert (requires configuration)

**Implication**: Express Mode's auto-domain works great for demos. For production with custom domain (`meet.bryanchasko.com`), we either:
1. Use Express Mode's auto-domain + Route 53 CNAME to ours
2. Configure Express Mode with a custom ACM certificate (requires linking cert ARN)

### Configuration & Secrets
- ✅ Express Mode supports environment variables in the service definition
- ✅ Express Mode supports Secrets Manager references (ARN-based)
- ✅ **Our JitsiConfig module** continues to work (loads from env vars / config.json)

### Task Role & Execution Role
- ✅ Task Execution Role: Required, AWS managed policy (`AmazonECSTaskExecutionRolePolicy`)
- ✅ Task Role: Optional, custom role for S3/Secrets access
- ⚠️ **Key**: Task role permissions for S3 recordings bucket + Secrets Manager (unchanged)

---

## 3. Operational Script Compatibility

### Scale-to-Zero Behavior
- ✅ Express Mode preserves `desired_count = 0` (our control point)
- ✅ Scripts query service status via `aws ecs describe-services` (unchanged API)
- ✅ Scripts update service via `aws ecs update-service --desired-count` (unchanged API)

**Result**: Existing Perl scripts (`scale-up.pl`, `scale-down.pl`, `power-down.pl`) work **without modification** if we keep `desired_count` as the control mechanism.

### Health Checks
- ✅ Express Mode sets target group health check path (configurable)
- ✅ Health check timeout: 5 seconds (can be adjusted in target group post-creation)
- ✅ Jitsi container health endpoint (`/health` or custom) still works

---

## 4. Terraform & IaC Implications

### Removed Resources (Manual ALB → Express Mode)
```
- aws_lb (jitsi_nlb)
- aws_lb_listener (https_443, udp_10000)
- aws_lb_target_group (web_tg, jvb_tg)
- aws_lb_target_group_attachment (web, jvb)
- aws_security_group (alb_sg)
```

### Simplified Service Definition
Instead of:
```hcl
resource "aws_ecs_service" "jitsi" {
  name            = var.project_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.jitsi.arn
  load_balancer { ... }  # Manual LB config
  network_configuration { ... }
}
```

Express Mode pattern:
```hcl
resource "aws_ecs_service" "jitsi" {
  name             = var.project_name
  cluster          = aws_ecs_cluster.main.id
  task_definition  = aws_ecs_task_definition.jitsi.arn
  # LB handled by Express Mode service configuration
  # Declare via service annotations or resource tags
}
```

### Task Definition Stays Mostly the Same
- Container image, environment variables, ports, health check path → configured in service
- Task role, execution role → remain in task definition
- CloudWatch logging → remains in container definition
- **Jitsi multi-container setup (web, prosody, jicofo, jvb)**: ✅ Still works (Express Mode supports multi-container tasks)

---

## 5. Key Limitations to Plan For

| Limitation | Impact | Workaround |
|-----------|--------|-----------|
| **Fargate only** | No EC2, no custom GPU | Accept (we don't need EC2) |
| **Max 25 services per ALB** | Only relevant if scaling to 25+ services | Non-issue for 1 Jitsi service |
| **No Blue/Green by default** | Canary deployments only | Use canary + health checks (we have this) |
| **Host-header routing** | ALB routes by domain, not port | UDP (10000) must use different mechanism |

### UDP Port 10000 (JVB) Challenge
Express Mode's ALB is **HTTPS (port 443) only**. Our Jitsi setup requires:
- ✅ TCP/443 (HTTPS) → handled by Express Mode
- ❌ UDP/10000 (JVB) → **NOT supported by ALB**

**Solution**: Either
1. Keep manual NLB for UDP (hybrid approach: Express Mode ALB for web, manual NLB for JVB)
2. Rely on TCP fallback (JVB can use TCP/4443 as fallback, handled by Express Mode)
3. Use VPC endpoint / separate service for JVB UDP

---

## 6. Cost Model (Unchanged)

| Component | Current | Express Mode | Notes |
|-----------|---------|--------------|-------|
| **NLB** | $16.20/mo | $0 | Replaced by ALB (shared cost) |
| **ALB** | N/A | ~$8-12/mo | Shared across up to 25 services |
| **Fargate (4vCPU, 8GB)** | $0.198/hr | $0.198/hr | Unchanged |
| **S3 + Secrets Manager** | $0.42/mo | $0.42/mo | Unchanged |
| **Fixed Total (idle)** | $16.62/mo | ~$8.62-10/mo | **Saves $6-8/mo** |

---

## 7. Migration Strategy

### Phase 1: Terraform Refactoring
1. Remove manual ALB, listeners, target groups, ALB security groups
2. Update service definition to express-gateway-service resource (if Terraform supports it)
3. Keep task definition, cluster, security groups (tasks), IAM roles
4. Validate scale-to-zero still works

### Phase 2: Operational Testing
1. Test scale-up.pl (desired_count → 1) with new service
2. Test scale-down.pl (desired_count → 0)
3. Test health checks + auto-scaling
4. Test domain/certificate configuration

### Phase 3: Domain & Certificate Cutover
1. Decide: Use Express Mode's auto-domain or attach custom ACM cert
2. If custom domain: Configure Express Mode service with our ACM cert ARN
3. Update Route 53 DNS if needed

### Phase 4: UDP Fallback Validation
1. Test JVB connectivity via TCP/4443 (fallback)
2. Ensure UDP/10000 fallback is acceptable for production

---

## 8. Current main.tf Inventory

| Resource | Lines | Action |
|----------|-------|--------|
| VPC networking | ~87 | Keep (unchanged) |
| Security groups | ~55 | Keep task SG, remove ALB SG |
| **ALB + listeners + target groups** | **~90** | **Remove** |
| ECS cluster | ~5 | Keep (Express Mode can use it) |
| Task definition | ~420 | Keep (mostly unchanged) |
| Service | ~50 | **Refactor** (remove LB config) |
| S3 + Secrets | ~100 | Keep |
| **Total** | **909** | **Target: ~450 (50% reduction)** |

---

## 9. Kiro Spec Keywords & Focus Areas

When issuing `/specify` to Kiro, emphasize:

✅ **Remove**:
- Manual ALB, listeners, target groups (lines ~140-233)
- ALB security group
- Manual NLB listener rules

✅ **Simplify**:
- Service definition (remove `load_balancer` block, use Express Mode patterns)
- Security group rules (Express Mode provides minimal defaults)

✅ **Preserve**:
- Scale-to-zero (`desired_count = 0`)
- Task definition (Jitsi containers, env vars, health checks)
- Task role + execution role
- S3 + Secrets Manager integration
- Domain-agnostic config (JitsiConfig module)

✅ **Validate**:
- Terraform line count reduction to ~450-500
- Perl scripts still work without modification
- Health checks compatible
- UDP/10000 fallback acceptable

---

## 10. Open Questions for Kiro

1. **Terraform Resource**: Is it `aws_ecs_service` with Express Mode annotations, or a new `aws_ecs_express_gateway_service` resource?
2. **UDP Fallback**: Should we document the TCP/4443 fallback for JVB as acceptable, or plan a hybrid ALB + NLB setup?
3. **Custom Domain**: Do we use Express Mode's auto-domain or attach our custom ACM cert? (Affects cert/DNS handling)
4. **Terraform Validation**: Can we validate the refactored Terraform locally, or does it require AWS credentials for Express Mode-specific validation?

---

## References

- AWS Announcement: https://aws.amazon.com/about-aws/whats-new/2025/11/announcing-amazon-ecs-express-mode/
- ECS Express Mode Docs: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-overview.html
- Best Practices: AWS Builder Center article on ECS Express Mode
- Current Terraform: `/Users/bryanchasko/Code/Projects/jitsi-video-hosting/main.tf` (909 lines)
