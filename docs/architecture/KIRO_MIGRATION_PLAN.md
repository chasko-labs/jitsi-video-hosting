# Jitsi Platform Configuration Guide - Domain-Agnostic Refactoring

> **doc status (2026-04-23):** current. the domain-agnostic config pattern via `lib/JitsiConfig.pm` and private ops repo is still the correct model. no changes to this pattern from the 4-container restore or JWT addition

## Overview

This guide explains how the Jitsi platform has been refactored to be **domain-agnostic** and **profile-agnostic**. All sensitive configuration (domain names, AWS profiles) is now externalized to a private repository.

## Architecture Change

### Before: Hardcoded Values
```perl
# BEFORE - scripts/status.pl
my $DOMAIN_NAME = "meet.awsaerospace.org";
my $AWS_PROFILE = "jitsi-dev";
```

### After: Configuration-Driven
```perl
# AFTER - scripts/status.pl
use lib '../lib';
use JitsiConfig;
my $config = JitsiConfig->new();
my $DOMAIN_NAME = $config->domain();
my $AWS_PROFILE = $config->aws_profile();
```

### Terraform: From Static to Dynamic
```hcl
# BEFORE
variable "domain_name" {
  default = "meet.awsaerospace.org"
}
provider "aws" {
  profile = "jitsi-dev"
}

# AFTER
variable "domain_name" {
  # No default - loaded from env vars
}
variable "aws_profile" {
  # No default - loaded from env vars
}
provider "aws" {
  profile = var.aws_profile
}
```

## Configuration Components

### 1. JitsiConfig Module (`lib/JitsiConfig.pm`)

**What it does:**
- Provides OOP interface for accessing configuration
- Loads from multiple sources with priority hierarchy
- Validates required fields (domain, aws_profile)
- Provides `get_env_vars()` for Terraform integration

**Usage:**
```perl
use lib 'lib';
use JitsiConfig;

my $config = JitsiConfig->new();
my $domain = $config->domain();          # Returns "meet.yourdomain.com"
my $profile = $config->aws_profile();    # Returns "your-aws-profile"
my $all = $config->all();                # Returns all config as hashref
```

### 2. Configuration Sources (Priority Order)

1. **Environment Variables** (highest priority)
   - `JITSI_DOMAIN` → `domain`
   - `JITSI_AWS_PROFILE` → `aws_profile`
   - `JITSI_AWS_REGION` → `aws_region`
   - `JITSI_PROJECT` → `project_name`
   - `JITSI_CLUSTER` → `cluster_name`
   - `JITSI_SERVICE` → `service_name`
   - `JITSI_NLB` → `nlb_name`

2. **Private Config File** (medium priority)
   - Location: `../jitsi-video-hosting-ops/config.json`
   - Format: JSON key-value pairs
   - Only loaded if file exists

3. **Compiled Defaults** (lowest priority)
   - Defined in `lib/JitsiConfig.pm`
   - AWS Region: `us-west-2`
   - Project Name: `jitsi-video-platform`
   - Environment: `prod`
   - **Required fields have no defaults** (domain, aws_profile)

### 3. Private Repository Structure

```
jitsi-video-hosting-ops/
├── config.json              # Your specific config (NOT versioned)
├── config.json.template     # Template for setup
├── CONFIG_SETUP.md          # Setup instructions
└── OPERATIONS.md            # Sensitive operational details
```

### 4. Terraform Configuration

**New variables in `variables.tf`:**

```hcl
variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
  default     = null
  validation {
    condition     = var.aws_profile != null
    error_message = "aws_profile must be provided via TF_VAR_aws_profile or JITSI_AWS_PROFILE"
  }
}

variable "domain_name" {
  description = "Domain for Jitsi platform"
  type        = string
  default     = null
  validation {
    condition     = var.domain_name != null
    error_message = "domain_name must be provided via TF_VAR_domain_name or JITSI_DOMAIN"
  }
}
```

**Updated provider in `main.tf`:**

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile  # No longer hardcoded
}
```

## Configuration Workflow

### For End Users

```bash
# 1. Clone both repositories
git clone https://github.com/BryanChasko/jitsi-video-hosting.git
git clone https://github.com/YOUR_ORG/jitsi-video-hosting-ops.git

# 2. Set up private configuration
cd jitsi-video-hosting-ops
cp config.json.template config.json
vim config.json  # Edit with your domain and AWS profile

# 3. Run scripts (they load config automatically)
cd ../jitsi-video-hosting/scripts
./status.pl
./test-platform.pl
```

### For Terraform

```bash
# Method 1: Via environment variables
export JITSI_DOMAIN="meet.yourdomain.com"
export JITSI_AWS_PROFILE="your-profile"
export TF_VAR_domain_name="$JITSI_DOMAIN"
export TF_VAR_aws_profile="$JITSI_AWS_PROFILE"
terraform plan

# Method 2: Via private config (automatic conversion)
# JitsiConfig reads from config.json
# Use helper script to export to Terraform
source scripts/load-config.sh
terraform plan
```

### For CI/CD (GitHub Actions)

```yaml
env:
  TF_VAR_domain_name: ${{ secrets.JITSI_DOMAIN }}
  TF_VAR_aws_profile: ${{ secrets.AWS_PROFILE }}

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: terraform plan
      - run: ./scripts/scale-up.pl
```

## Files Modified

### Terraform Files
- `main.tf`: Changed `profile = "jitsi-dev"` to `profile = var.aws_profile`
- `variables.tf`: Added `aws_profile` variable, removed `domain_name` default

### Perl Scripts (All Updated to Use JitsiConfig)
- `scripts/status.pl`
- `scripts/test-platform.pl`
- `scripts/scale-up.pl`
- `scripts/scale-down.pl`
- `scripts/power-down.pl`
- `scripts/fully-destroy.pl`
- `scripts/project-status.pl`
- `scripts/check-health.pl`

### New Files
- `lib/JitsiConfig.pm` - Configuration module
- `jitsi-video-hosting-ops/config.json.template` - Configuration template
- `jitsi-video-hosting-ops/CONFIG_SETUP.md` - Setup instructions
- `CONFIG_GUIDE.md` - Comprehensive configuration guide

## Domain-Agnostic Public Repository

The public repository no longer contains:
- ❌ Hardcoded domain names
- ❌ Hardcoded AWS profiles  
- ❌ AWS account IDs
- ❌ SSL certificate ARNs

Instead, users provide these via:
- ✅ Private `jitsi-video-hosting-ops/config.json`
- ✅ Environment variables
- ✅ Terraform variables

## Object-Oriented Configuration Pattern

Instead of hardcoded constants:
```perl
# OLD
my $DOMAIN_NAME = "meet.awsaerospace.org";
my $AWS_PROFILE = "jitsi-dev";

# NEW
use JitsiConfig;
my $config = JitsiConfig->new();
my $DOMAIN_NAME = $config->domain();
my $AWS_PROFILE = $config->aws_profile();
```

Benefits:
- **Reusability**: Same module used in all scripts
- **Maintainability**: Change config in one place
- **Testability**: Easy to mock config for tests
- **Security**: Sensitive details stay in private repo

---

## Next Steps for Your Deployment

1. **Set up private repository**:
   - Create `jitsi-video-hosting-ops` (private, same parent directory)
   - Add `config.json` from template
   - Update with your domain and AWS profile

2. **Test configuration loading**:
   ```bash
   cd scripts
   ./status.pl  # Should use your domain
   ```

3. **Deploy infrastructure**:
   ```bash
   export TF_VAR_domain_name="your-domain.com"
   export TF_VAR_aws_profile="your-profile"
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

4. **Verify deployment**:
   ```bash
   ./scripts/test-platform.pl
   ```

For detailed configuration instructions, see `CONFIG_GUIDE.md`

