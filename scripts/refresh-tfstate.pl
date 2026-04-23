#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use Term::ANSIColor qw(colored);
use lib '../lib';
use JitsiConfig;

my $dry_run = 0;
my $help = 0;
GetOptions(
    'dry-run' => \$dry_run,
    'help|h'  => \$help,
) or usage(1);
usage(0) if $help;

my $config = JitsiConfig->new();
my $AWS_PROFILE = $config->aws_profile();
my $AWS_REGION  = $config->aws_region();

my $TF_DIR = '../../jitsi-video-hosting-ops/terraform';

sub usage {
    my ($code) = @_;
    print <<"USAGE";
Usage: $0 [--dry-run]

Syncs terraform.tfstate with actual AWS reality using
'terraform apply -refresh-only -auto-approve'. No resource mutations.

Run after out-of-band deletes (e.g. cleanup-orphan-vpcs.pl) so state
reflects what exists in AWS.

  --dry-run   Preview drift via 'terraform plan -refresh-only' instead
  --help      Show this message
USAGE
    exit $code;
}

sub log_message {
    my ($level, $message) = @_;
    my %colors = (
        INFO    => 'blue',
        WARN    => 'yellow',
        ERROR   => 'red',
        SUCCESS => 'green',
        DRY     => 'yellow',
        HEADER  => 'bold cyan',
    );
    my $color = $colors{$level} || 'white';
    if ($level eq 'HEADER') {
        print colored($message, $color) . "\n";
    } else {
        print colored("[$level]", $color) . " $message\n";
    }
    return;
}

sub state_resource_count {
    my $out = `terraform state list 2>/dev/null`;
    return 0 if $? != 0;
    my @lines = split /\n/, $out;
    return scalar @lines;
}

sub main {
    log_message('HEADER', 'Jitsi Terraform State Refresh');
    log_message('INFO', "Region: $AWS_REGION | Profile: $AWS_PROFILE");

    unless (-d $TF_DIR) {
        log_message('ERROR', "Terraform directory not found at $TF_DIR (run from scripts/ cwd)");
        return 1;
    }

    my $tf_bin = `command -v terraform 2>/dev/null`;
    chomp $tf_bin;
    unless ($tf_bin) {
        log_message('ERROR', 'terraform binary not found in PATH');
        return 1;
    }

    chdir $TF_DIR or do {
        log_message('ERROR', "Cannot cd to $TF_DIR: $!");
        return 1;
    };

    my $before = state_resource_count();
    log_message('INFO', "State resources before: $before");

    local $ENV{AWS_PROFILE} = $AWS_PROFILE;
    local $ENV{AWS_REGION}  = $AWS_REGION;

    if ($dry_run) {
        log_message('DRY', 'Previewing drift — running: terraform plan -refresh-only');
        my $rc = system('terraform plan -refresh-only');
        return $rc == 0 ? 0 : 1;
    }

    log_message('INFO', 'Running: terraform apply -refresh-only -auto-approve');
    my $rc = system('terraform apply -refresh-only -auto-approve');
    if ($rc != 0) {
        log_message('ERROR', 'terraform refresh failed — see output above');
        return 1;
    }

    my $after = $before > 0 ? state_resource_count() : 0;
    my $delta = $before - $after;
    if ($delta > 0) {
        log_message('SUCCESS', "State synced — $delta stale resource(s) removed from tfstate");
    } elsif ($delta < 0) {
        log_message('SUCCESS', 'State synced — ' . abs($delta) . " resource(s) adopted into tfstate");
    } else {
        log_message('SUCCESS', 'State was already in sync — no changes');
    }

    return 0;
}

exit main() if __FILE__ eq $0;
