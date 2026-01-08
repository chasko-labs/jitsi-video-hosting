#!/usr/bin/env perl
use strict;
use warnings;

chdir '/Users/bryanchasko/Code/Projects/jitsi-video-hosting/scripts' or die "Cannot change directory: $!";

# Execute scale-up.pl
system('./scale-up.pl');

print "Phase 3 complete - NLB created and service scaled up\n";
