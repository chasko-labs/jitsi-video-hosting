#!/usr/bin/env perl
use strict;
use warnings;

chdir '/Users/bryanchasko/Code/Projects/jitsi-video-hosting/scripts' or die "Cannot change directory: $!";

# Execute deploy-prod.pl with yes confirmation
open(my $deploy_fh, '|-', './deploy-prod.pl') or die "Cannot execute deploy-prod.pl: $!";
print $deploy_fh "yes\n";
close($deploy_fh);

print "Phase 2 complete - Infrastructure deployed\n";
