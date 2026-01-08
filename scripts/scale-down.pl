#!/usr/bin/env perl
use strict;
use warnings;
use JSON;
use Term::ANSIColor qw(colored);
use POSIX qw(strftime);
use lib '../lib';
use JitsiConfig;

# Load configuration from JitsiConfig
my $config = JitsiConfig->new();
my $PROJECT_NAME = $config->project_name();
my $CLUSTER_NAME = $config->cluster_name();
my $SERVICE_NAME = $config->service_name();
my $AWS_PROFILE = $config->aws_profile();
my $AWS_REGION = $config->aws_region();
my $DESIRED_COUNT = 0;
my $TIMEOUT_MINUTES = 5;

# Logging function
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
    my $colored_message = colored("[$level]", $color) . " $message";
    
    print "$colored_message\n";
    return;
}

# Function to get current service status
sub get_service_status {
    my $cmd = "aws ecs describe-services " .
              "--cluster '$CLUSTER_NAME' " .
              "--services '$SERVICE_NAME' " .
              "--profile '$AWS_PROFILE' " .
              "--region '$AWS_REGION' " .
              "--query 'services[0]' " .
              "--output json 2>/dev/null";
    
    my $output = qx($cmd);
    return $? == 0 ? $output : "{}";
}

# Function to get current running count
sub get_running_count {
    my $service_info = get_service_status();
    my $data = decode_json($service_info);
    return $data->{runningCount} // 0;
}

# Function to get current desired count
sub get_desired_count {
    my $service_info = get_service_status();
    my $data = decode_json($service_info);
    return $data->{desiredCount} // 0;
}

# Function to get current pending count
sub get_pending_count {
    my $service_info = get_service_status();
    my $data = decode_json($service_info);
    return $data->{pendingCount} // 0;
}

# Function to check if service exists
sub check_service_exists {
    my $service_info = get_service_status();
    my $data = decode_json($service_info);
    my $service_name = $data->{serviceName} // "";
    
    return $service_name eq $SERVICE_NAME;
}

# Function to get running task ARNs
sub get_running_tasks {
    my $cmd = "aws ecs list-tasks " .
              "--cluster '$CLUSTER_NAME' " .
              "--service-name '$SERVICE_NAME' " .
              "--desired-status 'RUNNING' " .
              "--profile '$AWS_PROFILE' " .
              "--region '$AWS_REGION' " .
              "--query 'taskArns' " .
              "--output json 2>/dev/null";
    
    my $output = qx($cmd);
    return $? == 0 ? decode_json($output) : [];
}

# Function to scale down the service
sub scale_down_service {
    log_message('INFO', "Scaling down ECS service '$SERVICE_NAME' to $DESIRED_COUNT instances...");
    
    my $cmd = "aws ecs update-service " .
              "--cluster '$CLUSTER_NAME' " .
              "--service '$SERVICE_NAME' " .
              "--desired-count $DESIRED_COUNT " .
              "--profile '$AWS_PROFILE' " .
              "--region '$AWS_REGION' " .
              "--output json 2>&1";
    
    my $result = qx($cmd);
    my $exit_code = $? >> 8;
    
    if ($exit_code == 0) {
        log_message('SUCCESS', "Scale-down command executed successfully");
        return 1;
    } else {
        log_message('ERROR', "Failed to execute scale-down command: $result");
        return 0;
    }
}

# Function to wait for tasks to stop
sub wait_for_tasks_to_stop {
    log_message('INFO', "Waiting for all tasks to stop (timeout: ${TIMEOUT_MINUTES} minutes)...");
    
    my $start_time = time();
    my $timeout_seconds = $TIMEOUT_MINUTES * 60;
    
    while (1) {
        my $current_time = time();
        my $elapsed = $current_time - $start_time;
        
        if ($elapsed >= $timeout_seconds) {
            log_message('ERROR', "Timeout reached waiting for tasks to stop");
            return 0;
        }
        
        my $running_count = get_running_count();
        my $pending_count = get_pending_count();
        my $desired_count = get_desired_count();
        
        log_message('INFO', "Status: Running=$running_count, Pending=$pending_count, Desired=$desired_count (${elapsed}s elapsed)");
        
        if ($running_count == 0 && $pending_count == 0 && $desired_count == 0) {
            log_message('SUCCESS', "All tasks have stopped successfully");
            return 1;
        }
        
        # List remaining tasks for debugging
        my $running_tasks = get_running_tasks();
        my $task_count = @$running_tasks;
        
        if ($task_count > 0) {
            log_message('INFO', "Remaining tasks:");
            for my $task_arn (@$running_tasks) {
                my $task_id = (split '/', $task_arn)[-1];
                log_message('INFO', "  Task: $task_id");
            }
        }
        
        log_message('INFO', "Waiting 10 seconds before next check...");
        sleep 10;
    }
    return;
}

# Function to verify scale-down completion
sub verify_scale_down {
    log_message('INFO', "Verifying scale-down completion...");
    
    my $running_count = get_running_count();
    my $pending_count = get_pending_count();
    my $desired_count = get_desired_count();
    
    if ($running_count == 0 && $pending_count == 0 && $desired_count == 0) {
        log_message('SUCCESS', "Scale-down verification passed");
        return 1;
    } else {
        log_message('ERROR', "Scale-down verification failed: Running=$running_count, Pending=$pending_count, Desired=$desired_count");
        return 0;
    }
}

# Function to display final status
sub display_final_status {
    log_message('INFO', "Final service status:");
    
    my $service_info = get_service_status();
    my $data = decode_json($service_info);
    
    my $running_count = $data->{runningCount};
    my $desired_count = $data->{desiredCount};
    my $pending_count = $data->{pendingCount};
    
    log_message('INFO', "  Running: $running_count");
    log_message('INFO', "  Desired: $desired_count");
    log_message('INFO', "  Pending: $pending_count");
    
    # Check for any remaining tasks
    my $running_tasks = get_running_tasks();
    my $task_count = @$running_tasks;
    
    if ($task_count == 0) {
        log_message('SUCCESS', "No running tasks remaining");
    } else {
        log_message('WARN', "$task_count task(s) still running:");
        for my $task_arn (@$running_tasks) {
            my $task_id = (split '/', $task_arn)[-1];
            log_message('WARN', "  Task: $task_id");
        }
    }
    return;
}

# Function to destroy NLB
sub destroy_nlb {
    log_message('INFO', 'Destroying Network Load Balancer...');
    
    # Use correct Terraform variable and path for ECS Express deployment
    my $cmd = "cd ../../jitsi-video-hosting-ops/terraform && terraform apply -var='create_nlb=false' -auto-approve";
    my $result = system($cmd);
    
    if ($result != 0) {
        log_message('ERROR', 'Failed to destroy NLB');
        return 0;
    }
    
    log_message('SUCCESS', 'NLB destroyed successfully');
    return 1;
}

# Function to verify NLB cleanup
sub verify_nlb_cleanup {
    log_message('INFO', 'Verifying NLB cleanup...');
    
    my $cmd = "aws elbv2 describe-load-balancers " .
              "--names '$PROJECT_NAME-jvb-nlb' " .
              "--profile '$AWS_PROFILE' " .
              "--region '$AWS_REGION' " .
              "--query 'LoadBalancers[0].LoadBalancerName' " .
              "--output text 2>/dev/null";
    
    my $result = qx($cmd);
    my $exit_code = $? >> 8;
    
    if ($exit_code != 0 || !$result || $result =~ /None/) {
        log_message('SUCCESS', 'NLB cleanup verified - no orphaned resources');
        return 1;
    } else {
        log_message('WARN', 'NLB may still exist - manual cleanup may be required');
        return 0;
    }
}

# Main function
sub main {
    log_message('INFO', "Starting Jitsi Platform Scale-Down Process");
    
    # Check if service exists
    unless (check_service_exists()) {
        log_message('ERROR', "ECS service '$SERVICE_NAME' not found in cluster '$CLUSTER_NAME'");
        exit 1;
    }
    
    # Check current status
    my $current_running = get_running_count();
    my $current_desired = get_desired_count();
    my $current_pending = get_pending_count();
    
    log_message('INFO', "Current service status: Running=$current_running, Desired=$current_desired, Pending=$current_pending");
    
    # Check if already scaled down
    if ($current_running == 0 && $current_desired == 0 && $current_pending == 0) {
        log_message('SUCCESS', "Service is already scaled down to zero");
        display_final_status();
        exit 0;
    }
    
    # Scale down the service
    unless (scale_down_service()) {
        log_message('ERROR', "Failed to scale down service");
        exit 1;
    }
    
    # Wait for tasks to stop
    unless (wait_for_tasks_to_stop()) {
        log_message('ERROR', "Failed to wait for all tasks to stop");
        display_final_status();
        exit 1;
    }
    
    # Verify scale-down completion
    unless (verify_scale_down()) {
        log_message('ERROR', "Scale-down verification failed");
        display_final_status();
        exit 1;
    }
    
    # Destroy NLB after ECS is scaled down
    unless (destroy_nlb()) {
        log_message('WARN', 'Failed to destroy NLB - manual cleanup may be required');
    }
    
    unless (verify_nlb_cleanup()) {
        log_message('WARN', 'NLB cleanup verification failed');
    }
    
    # Display final status
    display_final_status();
    
    log_message('SUCCESS', "Scale-down process completed successfully");
    log_message('INFO', "Service '$SERVICE_NAME' is now scaled to zero instances");
    log_message('INFO', "Platform is in cost-optimized state with no running compute resources");
    return;
}

# Script entry point
main() if __FILE__ eq $0;