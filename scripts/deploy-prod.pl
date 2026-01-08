#!/usr/bin/env perl
use strict;
use warnings;
use JSON;
use Term::ANSIColor qw(colored);
use POSIX qw(strftime);
use lib '../lib';
use JitsiConfig;

my $config = JitsiConfig->new();
my $AWS_PROFILE = $config->aws_profile();
my $AWS_REGION = $config->aws_region();
my $OPS_DIR = '../../jitsi-video-hosting-ops';

sub log_message {
    my ($level, $message) = @_;
    my $timestamp = strftime('%Y-%m-%d %H:%M:%S', localtime);
    
    my %colors = (
        'INFO'    => 'blue',
        'WARN'    => 'yellow', 
        'ERROR'   => 'red',
        'SUCCESS' => 'green'
    );
    
    my $color = $colors{$level} || 'white';
    print colored("[$level]", $color) . " $message\n";
}

sub run_cmd {
    my ($cmd, $description) = @_;
    log_message('INFO', "Running: $description");
    my $output = qx($cmd 2>&1);
    if ($? != 0) {
        log_message('ERROR', "Failed: $description");
        log_message('ERROR', $output);
        return 0;
    }
    return 1;
}

# Validate ops directory
unless (-d $OPS_DIR) {
    log_message('ERROR', "Ops directory not found: $OPS_DIR");
    exit 1;
}

chdir $OPS_DIR or die "Cannot change to $OPS_DIR: $!";

# Initialize Terraform
log_message('INFO', 'Initializing Terraform...');
run_cmd("terraform init", "Terraform init") or exit 1;

# Validate configuration
log_message('INFO', 'Validating Terraform configuration...');
run_cmd("terraform validate", "Terraform validate") or exit 1;

# Plan deployment
log_message('INFO', 'Planning deployment...');
run_cmd("terraform plan -out=tfplan", "Terraform plan") or exit 1;

# Show plan summary
my $plan_output = qx(terraform show -json tfplan 2>&1);
my $plan_json = decode_json($plan_output);
my $resource_count = scalar @{$plan_json->{resource_changes} || []};

log_message('INFO', "Plan shows $resource_count resource changes");

# Confirm deployment
print colored("\n[CONFIRM]", 'yellow') . " Ready to deploy? (yes/no): ";
my $confirm = <STDIN>;
chomp $confirm;

unless ($confirm eq 'yes') {
    log_message('WARN', 'Deployment cancelled');
    exit 0;
}

# Apply deployment
log_message('INFO', 'Applying Terraform configuration...');
run_cmd("terraform apply tfplan", "Terraform apply") or exit 1;

# Get outputs
log_message('INFO', 'Retrieving deployment outputs...');
my $outputs = qx(terraform output -json 2>&1);
my $output_json = decode_json($outputs);

log_message('SUCCESS', 'Deployment complete!');
log_message('INFO', "ECS Cluster: " . $output_json->{ecs_cluster_name}{value});
log_message('INFO', "ECS Service: " . $output_json->{ecs_service_name}{value});
log_message('INFO', "Log Groups: " . $output_json->{jitsi_app_log_group}{value});
log_message('INFO', "Architecture: ECS Express Mode + Service Connect (HTTP/WSS)");
log_message('INFO', "Media Plane: On-demand NLB (created during scale-up)");

exit 0;
