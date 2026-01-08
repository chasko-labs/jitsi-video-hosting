#!/usr/bin/env perl
use strict;
use warnings;
use JSON;
use Term::ANSIColor qw(colored);
use lib '../lib';
use JitsiConfig;

# Load configuration
my $config = JitsiConfig->new();
my $PROJECT_NAME = $config->project_name();
my $CLUSTER_NAME = $config->cluster_name();
my $SERVICE_NAME = $config->service_name();
my $AWS_PROFILE = $config->aws_profile();
my $AWS_REGION = $config->aws_region();

sub log_message {
    my ($level, $message) = @_;
    my %colors = (
        'INFO'    => 'blue',
        'WARN'    => 'yellow', 
        'ERROR'   => 'red',
        'SUCCESS' => 'green'
    );
    
    my $color = $colors{$level} || 'white';
    print colored("[$level]", $color) . " $message\n";
}

sub get_task_ips {
    log_message('INFO', 'Discovering ECS task IP addresses...');
    
    # Get task ARNs
    my $cmd = "aws ecs list-tasks " .
              "--cluster '$CLUSTER_NAME' " .
              "--service-name '$SERVICE_NAME' " .
              "--profile '$AWS_PROFILE' " .
              "--region '$AWS_REGION' " .
              "--query 'taskArns' " .
              "--output text 2>/dev/null";
    
    my $task_arns = qx($cmd);
    chomp($task_arns) if $task_arns;
    
    if (!$task_arns || $task_arns eq 'None') {
        log_message('ERROR', 'No running tasks found');
        return ();
    }
    
    # Get task details for IP addresses
    $cmd = "aws ecs describe-tasks " .
           "--cluster '$CLUSTER_NAME' " .
           "--tasks $task_arns " .
           "--profile '$AWS_PROFILE' " .
           "--region '$AWS_REGION' " .
           "--query 'tasks[].attachments[].details[?name==\`privateIPv4Address\`].value' " .
           "--output text 2>/dev/null";
    
    my $task_ips = qx($cmd);
    chomp($task_ips) if $task_ips;
    
    if (!$task_ips) {
        log_message('ERROR', 'Could not retrieve task IP addresses');
        return ();
    }
    
    my @ips = split(/\s+/, $task_ips);
    log_message('INFO', 'Found ' . scalar(@ips) . ' task IP(s): ' . join(', ', @ips));
    return @ips;
}

sub get_target_group_arns {
    log_message('INFO', 'Retrieving NLB target group ARNs...');
    
    # Use correct path for ECS Express deployment
    my $udp_tg_cmd = "cd ../../jitsi-video-hosting-ops/terraform && terraform output -raw jvb_nlb_target_group_udp_arn 2>/dev/null";
    my $tcp_tg_cmd = "cd ../../jitsi-video-hosting-ops/terraform && terraform output -raw jvb_nlb_target_group_tcp_arn 2>/dev/null";
    
    my $udp_tg_arn = qx($udp_tg_cmd);
    my $tcp_tg_arn = qx($tcp_tg_cmd);
    chomp($udp_tg_arn) if $udp_tg_arn;
    chomp($tcp_tg_arn) if $tcp_tg_arn;
    
    if (!$udp_tg_arn || !$tcp_tg_arn) {
        log_message('ERROR', 'Could not retrieve target group ARNs - is NLB enabled?');
        log_message('INFO', 'Run: cd ../../jitsi-video-hosting-ops/terraform && terraform apply -var="create_nlb=true"');
        return (undef, undef);
    }
    
    log_message('INFO', "UDP Target Group: $udp_tg_arn");
    log_message('INFO', "TCP Target Group: $tcp_tg_arn");
    return ($udp_tg_arn, $tcp_tg_arn);
}

sub register_targets {
    my ($udp_tg_arn, $tcp_tg_arn, @ips) = @_;
    
    log_message('INFO', 'Registering targets with NLB target groups...');
    
    my $success_count = 0;
    my $total_registrations = scalar(@ips) * 2; # UDP + TCP per IP
    
    for my $ip (@ips) {
        next unless $ip;
        
        # Register UDP target
        my $udp_cmd = "aws elbv2 register-targets " .
                      "--target-group-arn '$udp_tg_arn' " .
                      "--targets Id=$ip,Port=10000 " .
                      "--profile '$AWS_PROFILE' " .
                      "--region '$AWS_REGION' 2>/dev/null";
        
        # Register TCP target  
        my $tcp_cmd = "aws elbv2 register-targets " .
                      "--target-group-arn '$tcp_tg_arn' " .
                      "--targets Id=$ip,Port=4443 " .
                      "--profile '$AWS_PROFILE' " .
                      "--region '$AWS_REGION' 2>/dev/null";
        
        my $udp_result = system($udp_cmd);
        my $tcp_result = system($tcp_cmd);
        
        if ($udp_result == 0) {
            log_message('SUCCESS', "Registered $ip:10000 (UDP)");
            $success_count++;
        } else {
            log_message('ERROR', "Failed to register $ip:10000 (UDP)");
        }
        
        if ($tcp_result == 0) {
            log_message('SUCCESS', "Registered $ip:4443 (TCP)");
            $success_count++;
        } else {
            log_message('ERROR', "Failed to register $ip:4443 (TCP)");
        }
    }
    
    log_message('INFO', "Registration complete: $success_count/$total_registrations successful");
    return $success_count == $total_registrations;
}

sub verify_target_health {
    my ($udp_tg_arn, $tcp_tg_arn) = @_;
    
    log_message('INFO', 'Verifying target health...');
    
    # Check UDP target health
    my $udp_cmd = "aws elbv2 describe-target-health " .
                  "--target-group-arn '$udp_tg_arn' " .
                  "--profile '$AWS_PROFILE' " .
                  "--region '$AWS_REGION' " .
                  "--query 'TargetHealthDescriptions[].TargetHealth.State' " .
                  "--output text 2>/dev/null";
    
    # Check TCP target health
    my $tcp_cmd = "aws elbv2 describe-target-health " .
                  "--target-group-arn '$tcp_tg_arn' " .
                  "--profile '$AWS_PROFILE' " .
                  "--region '$AWS_REGION' " .
                  "--query 'TargetHealthDescriptions[].TargetHealth.State' " .
                  "--output text 2>/dev/null";
    
    my $udp_health = qx($udp_cmd);
    my $tcp_health = qx($tcp_cmd);
    chomp($udp_health) if $udp_health;
    chomp($tcp_health) if $tcp_health;
    
    log_message('INFO', "UDP target health: $udp_health");
    log_message('INFO', "TCP target health: $tcp_health");
    
    my $healthy_count = 0;
    $healthy_count += ($udp_health =~ /healthy/gi);
    $healthy_count += ($tcp_health =~ /healthy/gi);
    
    if ($healthy_count > 0) {
        log_message('SUCCESS', "Found $healthy_count healthy target(s)");
        return 1;
    } else {
        log_message('WARN', 'No healthy targets found - may take time to become healthy');
        return 0;
    }
}

sub main {
    log_message('INFO', 'Starting NLB Target Registration Process');
    
    # Get task IPs
    my @ips = get_task_ips();
    if (!@ips) {
        log_message('ERROR', 'No task IPs found - exiting');
        exit 1;
    }
    
    # Get target group ARNs
    my ($udp_tg_arn, $tcp_tg_arn) = get_target_group_arns();
    if (!$udp_tg_arn || !$tcp_tg_arn) {
        log_message('ERROR', 'Could not retrieve target group ARNs - exiting');
        exit 1;
    }
    
    # Register targets
    unless (register_targets($udp_tg_arn, $tcp_tg_arn, @ips)) {
        log_message('WARN', 'Some target registrations failed');
    }
    
    # Verify health
    verify_target_health($udp_tg_arn, $tcp_tg_arn);
    
    log_message('SUCCESS', 'Target registration process completed');
}

main() if __FILE__ eq $0;
