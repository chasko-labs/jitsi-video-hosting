#!/usr/bin/env perl
use strict;
use warnings;
use JSON;
use Getopt::Long;
use Term::ANSIColor qw(colored);
use lib '../lib';
use JitsiConfig;

# Options
my $dry_run = 0;
my $tag_name = 'jitsi-vpc';
my $refresh_tfstate = 1;
my $help = 0;
GetOptions(
    'dry-run'           => \$dry_run,
    'tag-name=s'        => \$tag_name,
    'refresh-tfstate!'  => \$refresh_tfstate,
    'help|h'            => \$help,
) or usage(1);
usage(0) if $help;

# Load configuration from JitsiConfig
my $config = JitsiConfig->new();
my $AWS_PROFILE = $config->aws_profile();
my $AWS_REGION  = $config->aws_region();

sub usage {
    my ($code) = @_;
    print <<"USAGE";
Usage: $0 [--dry-run] [--tag-name=NAME]

Deletes orphan VPCs matching tag Name=<tag-name> in the configured region.
Refuses to delete any VPC with attached ENIs or active NAT gateways.

On successful deletes, auto-invokes refresh-tfstate.pl so terraform.tfstate
is synced with AWS reality (disable with --no-refresh-tfstate).

  --dry-run             Report planned actions without making changes
  --tag-name=NAME       VPC Name tag to match (default: jitsi-vpc)
  --no-refresh-tfstate  Skip post-cleanup terraform state refresh
  --help                Show this message
USAGE
    exit $code;
}

# Logging helper
sub log_message {
    my ($level, $message) = @_;
    my %colors = (
        INFO    => 'blue',
        WARN    => 'yellow',
        ERROR   => 'red',
        SUCCESS => 'green',
        SKIP    => 'magenta',
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

sub section_header {
    my ($title) = @_;
    print "\n";
    log_message('HEADER', "═══ $title ═══");
    return;
}

# Run an aws mutation with dry-run awareness. Returns 1 on success, 0 on failure.
sub run_aws {
    my ($desc, $cmd) = @_;
    if ($dry_run) {
        log_message('DRY', $desc);
        return 1;
    }
    my $out = qx($cmd 2>&1);
    my $rc = $? >> 8;
    if ($rc == 0) {
        log_message('SUCCESS', $desc);
        return 1;
    }
    chomp $out;
    log_message('ERROR', "$desc — $out");
    return 0;
}

# Run an aws read-only query; returns decoded JSON or empty array on error.
sub query_aws {
    my ($cmd) = @_;
    my $out = qx($cmd 2>/dev/null);
    return [] if $? != 0 || !$out;
    my $data = eval { decode_json($out) };
    return $@ ? [] : $data;
}

sub aws_prefix {
    return "aws --profile '$AWS_PROFILE' --region '$AWS_REGION'";
}

# Discover VPCs matching the Name tag
sub discover_vpcs {
    my $cmd = aws_prefix()
        . " ec2 describe-vpcs"
        . " --filters 'Name=tag:Name,Values=$tag_name'"
        . " --query 'Vpcs[].VpcId'"
        . " --output json";
    return query_aws($cmd);
}

# Return (eni_count, active_nat_count) for a VPC
sub vpc_in_use {
    my ($vpc) = @_;
    my $eni_cmd = aws_prefix()
        . " ec2 describe-network-interfaces"
        . " --filters 'Name=vpc-id,Values=$vpc'"
        . " --query 'length(NetworkInterfaces)'"
        . " --output text";
    my $eni = qx($eni_cmd 2>/dev/null);
    chomp $eni;
    $eni = 0 unless $eni =~ /^\d+$/;

    my $nat_cmd = aws_prefix()
        . " ec2 describe-nat-gateways"
        . " --filter 'Name=vpc-id,Values=$vpc'"
        . " --query 'NatGateways[?State!=`deleted`] | length(@)'"
        . " --output text";
    my $nat = qx($nat_cmd 2>/dev/null);
    chomp $nat;
    $nat = 0 unless $nat =~ /^\d+$/;

    return ($eni, $nat);
}

# Delete non-main route tables in a VPC. Disassociates subnet associations first.
sub delete_route_tables {
    my ($vpc) = @_;
    my $cmd = aws_prefix()
        . " ec2 describe-route-tables"
        . " --filters 'Name=vpc-id,Values=$vpc'"
        . " --output json";
    my $data = query_aws($cmd);
    my $tables = $data->{RouteTables} // [];

    for my $rt (@$tables) {
        my $is_main = grep { $_->{Main} } @{ $rt->{Associations} // [] };
        next if $is_main;

        for my $assoc (@{ $rt->{Associations} // [] }) {
            next if $assoc->{Main};
            run_aws(
                "Disassociate route table $rt->{RouteTableId} from $assoc->{SubnetId}",
                aws_prefix() . " ec2 disassociate-route-table --association-id $assoc->{RouteTableAssociationId}",
            );
        }
        run_aws(
            "Delete route table $rt->{RouteTableId}",
            aws_prefix() . " ec2 delete-route-table --route-table-id $rt->{RouteTableId}",
        );
    }
    return;
}

# Detach and delete all internet gateways attached to a VPC
sub delete_internet_gateways {
    my ($vpc) = @_;
    my $cmd = aws_prefix()
        . " ec2 describe-internet-gateways"
        . " --filters 'Name=attachment.vpc-id,Values=$vpc'"
        . " --query 'InternetGateways[].InternetGatewayId'"
        . " --output json";
    my $igws = query_aws($cmd);

    for my $igw (@$igws) {
        run_aws(
            "Detach IGW $igw from $vpc",
            aws_prefix() . " ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc",
        );
        run_aws(
            "Delete IGW $igw",
            aws_prefix() . " ec2 delete-internet-gateway --internet-gateway-id $igw",
        );
    }
    return;
}

sub delete_subnets {
    my ($vpc) = @_;
    my $cmd = aws_prefix()
        . " ec2 describe-subnets"
        . " --filters 'Name=vpc-id,Values=$vpc'"
        . " --query 'Subnets[].SubnetId'"
        . " --output json";
    my $subnets = query_aws($cmd);

    for my $subnet (@$subnets) {
        run_aws(
            "Delete subnet $subnet",
            aws_prefix() . " ec2 delete-subnet --subnet-id $subnet",
        );
    }
    return;
}

# Revoke all ingress/egress rules on non-default SGs, then delete them.
# Rules are revoked first so cross-SG references don't block deletes.
sub delete_security_groups {
    my ($vpc) = @_;
    my $cmd = aws_prefix()
        . " ec2 describe-security-groups"
        . " --filters 'Name=vpc-id,Values=$vpc'"
        . " --output json";
    my $data = query_aws($cmd);
    my $sgs = $data->{SecurityGroups} // [];

    my @non_default = grep { $_->{GroupName} ne 'default' } @$sgs;

    for my $sg (@non_default) {
        if (@{ $sg->{IpPermissions} // [] }) {
            my $json = encode_json($sg->{IpPermissions});
            $json =~ s/'/'\\''/g;
            run_aws(
                "Revoke ingress rules on $sg->{GroupId} ($sg->{GroupName})",
                aws_prefix() . " ec2 revoke-security-group-ingress --group-id $sg->{GroupId} --ip-permissions '$json'",
            );
        }
        if (@{ $sg->{IpPermissionsEgress} // [] }) {
            my $json = encode_json($sg->{IpPermissionsEgress});
            $json =~ s/'/'\\''/g;
            run_aws(
                "Revoke egress rules on $sg->{GroupId} ($sg->{GroupName})",
                aws_prefix() . " ec2 revoke-security-group-egress --group-id $sg->{GroupId} --ip-permissions '$json'",
            );
        }
    }

    for my $sg (@non_default) {
        run_aws(
            "Delete security group $sg->{GroupId} ($sg->{GroupName})",
            aws_prefix() . " ec2 delete-security-group --group-id $sg->{GroupId}",
        );
    }
    return;
}

sub delete_vpc {
    my ($vpc) = @_;
    return run_aws(
        "Delete VPC $vpc",
        aws_prefix() . " ec2 delete-vpc --vpc-id $vpc",
    );
}

sub process_vpc {
    my ($vpc) = @_;
    section_header("VPC $vpc");

    my ($eni, $nat) = vpc_in_use($vpc);
    if ($eni > 0 || $nat > 0) {
        log_message('SKIP', "In use — ENIs=$eni, active NAT gateways=$nat. Refusing to delete.");
        return 0;
    }

    delete_route_tables($vpc);
    delete_internet_gateways($vpc);
    delete_subnets($vpc);
    delete_security_groups($vpc);
    return delete_vpc($vpc);
}

sub main {
    log_message('HEADER', "Jitsi Orphan VPC Cleanup");
    log_message('INFO', "Region: $AWS_REGION | Profile: $AWS_PROFILE | Tag: Name=$tag_name");
    log_message('DRY', "Dry-run mode — no changes will be made") if $dry_run;

    my $vpcs = discover_vpcs();
    if (!@$vpcs) {
        log_message('INFO', "No VPCs found with Name=$tag_name — nothing to do");
        return 0;
    }

    log_message('INFO', "Found " . scalar(@$vpcs) . " VPC(s) matching tag Name=$tag_name:");
    print "  - $_\n" for @$vpcs;

    my @deleted;
    my $failures = 0;
    for my $vpc (@$vpcs) {
        if (process_vpc($vpc)) {
            push @deleted, $vpc;
        } else {
            $failures++;
        }
    }

    section_header("Summary");
    log_message('INFO', "Deleted: " . scalar(@deleted) . " / " . scalar(@$vpcs));
    log_message('WARN', "Failures/skips: $failures") if $failures;

    if (@deleted && !$dry_run && $refresh_tfstate) {
        section_header('Terraform State Refresh');
        log_message('INFO', 'Syncing terraform.tfstate with AWS reality');
        my $rc = system('./refresh-tfstate.pl');
        if ($rc != 0) {
            log_message('WARN', 'refresh-tfstate.pl exited non-zero — review above');
            log_message('WARN', 'Fallback: cd to ops terraform dir and run');
            log_message('WARN', '  terraform apply -refresh-only -auto-approve');
            $failures++;
        }
    } elsif (@deleted && !$refresh_tfstate) {
        print "\n";
        log_message('WARN', 'Skipped tfstate refresh (--no-refresh-tfstate)');
        log_message('WARN', 'Run manually before next terraform plan:');
        log_message('WARN', '  ./refresh-tfstate.pl');
    } elsif (@deleted && $dry_run) {
        print "\n";
        log_message('DRY', 'Would invoke refresh-tfstate.pl after real deletes');
    }

    return $failures ? 1 : 0;
}

exit main() if __FILE__ eq $0;
