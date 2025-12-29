#!/usr/bin/env perl
use strict;
use warnings;
use lib '../lib';
use JitsiConfig;

# Load configuration from JitsiConfig
my $config = JitsiConfig->new();
my $region = $config->aws_region();
my $profile = $config->aws_profile();

print "\033[31m[WARNING]\033[0m This will destroy ECS/Jitsi infrastructure\n";
print "\033[31m[WARNING]\033[0m Keeping: S3 buckets, Secrets Manager, IAM roles\n";
print "\033[33m[CONFIRM]\033[0m Type 'DESTROY' to confirm: ";

my $confirmation = <STDIN>;
chomp($confirmation);

if ($confirmation ne "DESTROY") {
    print "\033[34m[INFO]\033[0m Operation cancelled\n";
    exit(0);
}

print "\n\033[34m[INFO]\033[0m Destroying ECS/Jitsi infrastructure...\n\n";

# Destroy ECS service first
print "\033[34m[INFO]\033[0m Deleting ECS service...\n";
system("aws ecs delete-service --cluster jitsi-cluster --service jitsi-service --force --region $region --profile $profile 2>/dev/null");

# Destroy ECS cluster
print "\033[34m[INFO]\033[0m Deleting ECS cluster...\n";
system("aws ecs delete-cluster --cluster jitsi-cluster --region $region --profile $profile 2>/dev/null");

# Destroy VPC resources
print "\033[34m[INFO]\033[0m Deleting VPC resources...\n";
system("aws ec2 delete-security-group --group-id sg-062125c55fa3002e7 --region $region --profile $profile 2>/dev/null");

# Run terraform destroy for remaining resources
print "\033[34m[INFO]\033[0m Running terraform destroy (keeping S3/Secrets)...\n";
my $result = system("cd ../../jitsi-video-hosting-ops && terraform destroy -auto-approve 2>&1 | grep -E 'Destroy|destroyed|Error'");

if ($result == 0) {
    print "\n\033[32m[SUCCESS]\033[0m ECS/Jitsi infrastructure destroyed\n";
    print "\033[34m[INFO]\033[0m Preserved: S3 buckets, Secrets Manager, IAM roles\n";
} else {
    print "\n\033[31m[ERROR]\033[0m Destroy had issues\n";
    print "\033[34m[INFO]\033[0m Check AWS console for remaining resources\n";
    exit(1);
}