#!/usr/bin/env perl
use strict;
use warnings;

chdir '/Users/bryanchasko/Code/Projects/jitsi-video-hosting/scripts' or die "Cannot change directory: $!";

# Generate deployment summary
system('./status.pl');
system('./cost-analysis.pl');

print "Phase 6 complete - Status and cost analysis generated\n";
