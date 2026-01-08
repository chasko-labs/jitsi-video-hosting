#!/usr/bin/env perl
use strict;
use warnings;

chdir '/Users/bryanchasko/Code/Projects/jitsi-video-hosting-ops/terraform' or die "Cannot change directory: $!";

# Get NLB DNS name
my $nlb_dns = `terraform output -raw jvb_nlb_dns_name 2>/dev/null`;
chomp $nlb_dns;

if ($nlb_dns && $nlb_dns ne '') {
    print "NLB DNS Name: $nlb_dns\n";
    print "Configure DNS: A record for meet.bryanchasko.com -> $nlb_dns\n";
    
    # Note: Route 53 configuration would need actual hosted zone ID
    print "Manual step required: Update Route 53 A record\n";
} else {
    print "Error: Could not retrieve NLB DNS name\n";
}
