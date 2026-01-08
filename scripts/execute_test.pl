#!/usr/bin/env perl
use strict;
use warnings;

chdir '/Users/bryanchasko/Code/Projects/jitsi-video-hosting/scripts' or die "Cannot change directory: $!";

# Run comprehensive platform validation
system('./test-platform.pl');

print "Phase 5 complete - Platform validation executed\n";
