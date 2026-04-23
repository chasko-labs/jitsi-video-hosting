# SSM Parameter Store Migration - Implementation Complete

> **doc status (2026-04-23):** partially current. SSM is still the store for the 5 internal XMPP secrets (jicofo_component, jicofo_auth, jvb_component, jvb_auth, jigasi_auth) at `/jitsi-video-platform/*`. the migration from Secrets Manager to SSM for those secrets is accurate. however, Secrets Manager was re-introduced alongside SSM: the JWT shared secret (`${project_name}/jitsi-jwt-secret`, KMS-encrypted under `alias/${project_name}`) lives in Secrets Manager, not SSM. the IAM execution role now holds grants for both SSM (`ssm:GetParameter`) and Secrets Manager (`secretsmanager:GetSecretValue`) + `kms:Decrypt`

## Tasks Completed ✅

### Task 1: Create SSM Parameter Resources ✅
- Added 5 `aws_ssm_parameter` resources to main.tf
- All use SecureString type with AWS-managed KMS key
- Reference existing `random_password` resources for values
- Proper tags applied to all parameters

### Task 2: Update IAM Execution Role Policy ✅
- Modified `aws_iam_role_policy.ecs_task_execution_secrets`
- Replaced `secretsmanager:GetSecretValue` with `ssm:GetParameter`, `ssm:GetParameters`
- Updated Resource ARN to SSM parameter path pattern: `/${var.project_name}/*`

### Task 3: Update IAM Task Role Policy ✅
- Modified `aws_iam_role_policy.ecs_task_s3`
- Replaced `secretsmanager:GetSecretValue` with `ssm:GetParameter`, `ssm:GetParameters`
- Updated Resource ARN to SSM parameter path pattern: `/${var.project_name}/*`

### Task 4: Update ECS Task Definition Secrets ✅
- Updated all `secrets` blocks in container definitions
- Changed `valueFrom` from Secrets Manager ARN format to SSM ARN format
- Updated containers: prosody, jicofo, jvb
- All secret references now use: `aws_ssm_parameter.{secret_name}.arn`

### Task 5: Remove Secrets Manager Resources ✅
- Removed `aws_secretsmanager_secret.jitsi_secrets` resource block
- Removed `aws_secretsmanager_secret_version.jitsi_secrets` resource block
- Updated outputs.tf to remove `secrets_manager_arn` output
- Added new `ssm_parameter_prefix` output

### Task 6: Update Cost Analysis Script ✅
- Updated `scripts/cost-analysis.pl`
- Changed Secrets Manager cost from $0.40 to $0.00 (SSM free tier)
- Updated descriptions to reflect "SSM Parameter Store" usage
- Updated both before/after cost calculations

## Additional Updates Made

### outputs.tf Updates ✅
- Removed `secrets_manager_arn` output (sensitive)
- Added `ssm_parameter_prefix` output
- Updated `deployment_summary` to reflect "AWS SSM Parameter Store"

### Terraform Validation ✅
- Configuration validates successfully
- No syntax errors or missing references
- Ready for terraform plan/apply

## Cost Impact

### Before Migration
- Secrets Manager: $0.40/month per secret
- Total secrets cost: $0.40/month

### After Migration  
- SSM Parameter Store: $0.00/month (free tier covers up to 10,000 parameters)
- Total secrets cost: $0.00/month
- **Monthly savings: $0.40**
- **Annual savings: $4.80**

## SSM Parameters Created

1. `/${var.project_name}/jicofo_component_secret`
2. `/${var.project_name}/jicofo_auth_password`
3. `/${var.project_name}/jvb_component_secret`
4. `/${var.project_name}/jvb_auth_password`
5. `/${var.project_name}/jigasi_auth_password`

All parameters:
- Type: SecureString (encrypted at rest)
- KMS Key: AWS-managed key (default)
- Tags: Name, Project, Environment

## Security Benefits

### Maintained Security
- SecureString encryption at rest (same as Secrets Manager)
- IAM-based access control
- AWS-managed KMS encryption

### Improved Cost Efficiency
- Free tier covers typical usage
- No per-secret monthly charges
- Reduced operational costs

## Next Steps

### Ready for Deployment
```bash
# Plan the migration
terraform plan -out=tfplan

# Apply the changes (requires AWS credentials)
terraform apply tfplan

# Verify SSM parameters
aws ssm get-parameters --names \
  "/jitsi-video-platform/jicofo_component_secret" \
  "/jitsi-video-platform/jicofo_auth_password" \
  "/jitsi-video-platform/jvb_component_secret" \
  "/jitsi-video-platform/jvb_auth_password" \
  "/jitsi-video-platform/jigasi_auth_password" \
  --with-decryption

# Test ECS service
./scripts/scale-up.pl
```

### Validation Steps
1. Terraform plan shows expected changes
2. SSM parameters created successfully
3. ECS service starts without errors
4. Jitsi containers can access secrets
5. Cost analysis reflects $0.40/month savings

## Migration Benefits Summary

✅ **Cost Reduction**: $0.40/month → $0.00/month  
✅ **Security Maintained**: SecureString encryption  
✅ **Operational Simplicity**: Fewer AWS services to manage  
✅ **Free Tier Coverage**: Up to 10,000 parameters included  
✅ **Same Functionality**: No application changes required  

The SSM Parameter Store migration is complete and ready for deployment!
