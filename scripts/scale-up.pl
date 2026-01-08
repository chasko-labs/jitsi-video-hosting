#!/usr/bin/env perl
use strict;
use warnings;
use lib "../../lib";
use JitsiConfig;

# Load configuration
my $config = JitsiConfig->new();

print "\033[34m[INFO]\033[0m Restoring Jitsi infrastructure from zero-cost state...\n";
print "\033[34m[INFO]\033[0m This will recreate all infrastructure via Terraform\n\n";

# Change to terraform directory and apply infrastructure
print "\033[34m[INFO]\033[0m Creating all infrastructure via Terraform...\n";
chdir("../../jitsi-video-hosting-ops/terraform") or die "Cannot change to terraform directory: $!";

my $apply_cmd = "terraform apply -auto-approve";
my $result = system($apply_cmd);

if ($result == 0) {
    print "\n\033[32m[SUCCESS]\033[0m Infrastructure restored successfully!\n\n";
    
    print "\033[34m[RESOURCES CREATED]\033[0m\n";
    print "  ✓ VPC and networking\n";
    print "  ✓ ECS cluster and service\n";
    print "  ✓ Network Load Balancer\n";
    print "  ✓ CloudWatch log groups\n";
    print "  ✓ SNS topics\n";
    print "  ✓ IAM roles and policies\n\n";
    
    print "\033[34m[COST ANALYSIS]\033[0m\n";
    print "  Before: ~\$0.92/month (S3 + Secrets + Route53 only)\n";
    print "  After:  ~\$32.82/month (full infrastructure active)\n";
    print "  Variable: +\$0.198/hour when tasks running\n\n";
    
    print "\033[34m[ACCESS]\033[0m\n";
    print "  Jitsi Meet will be available in 3-5 minutes at:\n";
    print "  https://meet.bryanchasko.com\n\n";
    
    print "\033[32m[COMPLETE]\033[0m Infrastructure fully restored!\n";
} else {
    print "\n\033[31m[ERROR]\033[0m Failed to restore infrastructure\n";
    print "Check Terraform output above for details\n";
    exit 1;
}
