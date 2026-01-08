# Operational Scripts

This directory contains operational scripts for managing the ECS Express Jitsi platform.

## Current Infrastructure (Updated 2026-01-07)

After ECS Express deployment:
- **Cluster**: `jitsi-cluster` (ECS Express with Service Connect)
- **Service**: `jitsi-service` (Fargate tasks)
- **NLB**: `jitsi-video-platform-jvb-nlb` (Terraform-managed)
- **Profile**: `jitsi-video-hosting-170473530355`

## Available Scripts:

### Core Operations (Perl) ✅ Verified Compatible
- `scale-up.pl` - Scale ECS service from 0 to 1 with health verification
- `scale-down.pl` - Scale ECS service from current count to 0 with verification ✅ Tested
- `status.pl` - Display detailed current platform status
- `check-health.pl` - Comprehensive platform health verification
- `test-platform.pl` - Complete platform testing workflow

### Power Management (Perl) ⚠️ Needs Review
- `power-down.pl` - **Full infrastructure teardown** - Deletes VPC, networking, ECS (keeps S3 + Secrets)
- `verify-power-down.pl` - Verify power-down completed successfully
- `cost-analysis.pl` - Calculate cost savings from power-down
- `test-idempotency.pl` - Test that power-down can run multiple times safely
- `fully-destroy.pl` - **DANGEROUS** - Destroy ALL resources including data

### Utility Scripts
- `setup.pl` - Make all scripts executable
- `project-status.pl` - Quick project status overview

## Configuration System ✅ Updated

All scripts use the `JitsiConfig.pm` module:

```perl
use lib '../lib';
use JitsiConfig;

my $config = JitsiConfig->new();
my $cluster = $config->cluster_name();    # jitsi-cluster
my $service = $config->service_name();    # jitsi-service
my $profile = $config->aws_profile();     # jitsi-video-hosting-170473530355
```

Configuration loads from:
1. Environment variables (highest priority)
2. Private config file (`../../jitsi-video-hosting-ops/config.json`) ✅ Fixed path
3. Compiled defaults (lowest priority)

## Usage:

### Daily Operations
```bash
# Check current status
./status.pl

# Scale up platform (start) - Creates NLB via Terraform
./scale-up.pl

# Verify health
./check-health.pl

# Scale down platform (stop, keep infrastructure) ✅ Tested
./scale-down.pl
```

### Infrastructure Management
```bash
# Deploy with NLB (from terraform directory)
cd ../../jitsi-video-hosting-ops/terraform
terraform apply -var="create_nlb=true" -auto-approve

# Scale down ECS service only (NLB remains)
cd ../../jitsi-video-hosting/scripts
./scale-down.pl

# Destroy NLB to save costs (from terraform directory)
cd ../../jitsi-video-hosting-ops/terraform
terraform apply -var="create_nlb=false" -auto-approve
```

### Complete Testing
```bash
# Run complete testing workflow
./test-platform.pl
```

## Script Compatibility Status

✅ **Updated for True Zero-Cost Architecture**:
- `power-down.pl` - Destroys ALL infrastructure via `terraform destroy` (97% cost savings)
- `scale-up.pl` - Recreates ALL infrastructure via `terraform apply` (3-5 minutes)
- `test-platform.pl` - Tests restored infrastructure functionality

### Cost Model
- **Powered Down**: $0.92/month (S3 + Secrets + DNS only)
- **Powered Up**: $32.82/month (full infrastructure)
- **Restoration**: 3-5 minutes via Terraform

⚠️ **Legacy Scripts** (no longer needed):
- `scale-down.pl` - Replaced by `power-down.pl`
- `register-nlb-targets.pl` - NLB managed by Terraform
- `fully-destroy.pl` - Replaced by `power-down.pl`

## Requirements:
- AWS CLI with SSO configured (`jitsi-video-hosting-170473530355` profile)
- JitsiConfig module (in `../lib/JitsiConfig.pm`) ✅ Updated
- Proper IAM permissions for ECS, VPC, CloudWatch, S3, Secrets Manager
- Terraform for NLB lifecycle management

## Cost Impact (ECS Express):
| State | Monthly Cost | Notes |
|-------|--------------|-------|
| Full Infrastructure + 3 tasks | ~$65/month | 3 Fargate tasks running |
| Infrastructure + 0 tasks | ~$16.62/month | ECS Express fixed costs |
| After scale-down | ~$16.62/month | Service scaled to 0 |
| Variable cost per task | ~$0.198/hour | When tasks are running |

## NLB Management:
- **Creation**: `terraform apply -var="create_nlb=true"`
- **Destruction**: `terraform apply -var="create_nlb=false"`
- **DNS**: `jitsi-video-platform-jvb-nlb-*.elb.us-west-2.amazonaws.com`
- **Ports**: UDP 10000 (media), TCP 4443 (fallback)

All scripts include detailed logging and proper exit codes for automation integration.