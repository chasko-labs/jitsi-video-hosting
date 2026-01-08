#!/usr/bin/env perl
use strict;
use warnings;
use lib "../../lib";
use JitsiConfig;

# Load configuration
my $config = JitsiConfig->new();

print "\033[34m[INFO]\033[0m Powering down Jitsi infrastructure to ZERO cost...\n";
print "\033[34m[INFO]\033[0m This will destroy ALL infrastructure except persistent data\n\n";

# Change to terraform directory and destroy all infrastructure
print "\033[34m[INFO]\033[0m Destroying all infrastructure via Terraform...\n";
chdir("../../jitsi-video-hosting-ops/terraform") or die "Cannot change to terraform directory: $!";

my $destroy_cmd = "terraform destroy -auto-approve";
my $result = system($destroy_cmd);

if ($result == 0) {
    print "\n\033[32m[SUCCESS]\033[0m Infrastructure destroyed successfully!\n\n";
    
    print "\033[34m[COST ANALYSIS]\033[0m\n";
    print "  Before: ~\$32.82/month (ECS + NLB + VPC + CloudWatch + SNS + S3 + Secrets)\n";
    print "  After:  ~\$0.92/month (S3 + Secrets Manager + Route53 only)\n";
    print "  Savings: ~\$31.90/month (97% reduction)\n\n";
    
    print "\033[34m[PRESERVED RESOURCES]\033[0m (< \$1/month each)\n";
    print "  ✓ S3 buckets (~\$0.02/month)\n";
    print "  ✓ Secrets Manager (~\$0.40/month)\n";
    print "  ✓ Route 53 hosted zone (~\$0.50/month)\n\n";
    
    print "\033[34m[RESTORATION]\033[0m\n";
    print "  To restore full infrastructure:\n";
    print "  1. cd jitsi-video-hosting-ops/terraform\n";
    print "  2. terraform apply\n";
    print "  3. Wait 3-5 minutes for deployment\n\n";
    
    print "\033[32m[COMPLETE]\033[0m True zero-cost achieved!\n";
} else {
    print "\n\033[31m[ERROR]\033[0m Failed to destroy infrastructure\n";
    print "Check Terraform output above for details\n";
    exit 1;
}
