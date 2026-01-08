package JitsiConfig;

use strict;
use warnings;
use JSON;
use File::Spec;
use Carp qw(croak);

our $VERSION = '1.0.0';

=head1 NAME

JitsiConfig - Configuration manager for Jitsi video platform

=head1 SYNOPSIS

    use lib 'lib';
    use JitsiConfig;

    my $config = JitsiConfig->new();
    my $domain = $config->domain();
    my $aws_profile = $config->aws_profile();
    my $aws_region = $config->aws_region();

=head1 DESCRIPTION

JitsiConfig provides a centralized, object-oriented interface for accessing
Jitsi platform configuration. It follows the principle of separation of concerns:

- Public repository contains the abstraction layer and defaults
- Private jitsi-video-hosting-ops repository contains actual configuration

Configuration is loaded from:
1. Environment variables (highest priority)
2. Private config file (jitsi-video-hosting-ops/config.json)
3. Compiled defaults (lowest priority)

=head1 METHODS

=cut

my %DEFAULTS = (
    domain           => undef,  # Must be provided
    aws_profile      => undef,  # Must be provided
    aws_region       => 'us-west-2',
    project_name     => 'jitsi-video-platform',
    environment      => 'prod',
    cluster_name     => 'jitsi-video-platform-cluster',
    service_name     => 'jitsi-video-platform-service',
    nlb_name         => 'jitsi-video-platform-nlb',
);

my %ENV_MAPPING = (
    JITSI_DOMAIN       => 'domain',
    JITSI_AWS_PROFILE  => 'aws_profile',
    JITSI_AWS_REGION   => 'aws_region',
    JITSI_PROJECT      => 'project_name',
    JITSI_ENVIRONMENT  => 'environment',
    JITSI_CLUSTER      => 'cluster_name',
    JITSI_SERVICE      => 'service_name',
    JITSI_NLB          => 'nlb_name',
);

sub new {
    my ($class) = @_;

    my $self = { _config => {} };
    bless $self, $class;

    $self->_load_config();
    $self->_validate_config();

    return $self;
}

=head2 domain()

Returns the domain name for the Jitsi platform (e.g., 'meet.example.com')

=cut

sub domain { shift->_get_config('domain'); }

=head2 aws_profile()

Returns the AWS CLI profile name for operations

=cut

sub aws_profile { shift->_get_config('aws_profile'); }

=head2 aws_region()

Returns the AWS region for deployment (default: us-west-2)

=cut

sub aws_region { shift->_get_config('aws_region'); }

=head2 project_name()

Returns the project name for resource naming

=cut

sub project_name { shift->_get_config('project_name'); }

=head2 environment()

Returns the environment name (default: prod)

=cut

sub environment { shift->_get_config('environment'); }

=head2 cluster_name()

Returns the ECS cluster name

=cut

sub cluster_name { shift->_get_config('cluster_name'); }

=head2 service_name()

Returns the ECS service name

=cut

sub service_name { shift->_get_config('service_name'); }

=head2 nlb_name()

Returns the Network Load Balancer name

=cut

sub nlb_name { shift->_get_config('nlb_name'); }

=head2 all()

Returns a hash reference containing all configuration values

=cut

sub all {
    my ($self) = @_;
    return { %{ $self->{_config} } };
}

=head2 get_env_vars()

Returns a hash of environment variable assignments for use in shell/Terraform

=cut

sub get_env_vars {
    my ($self) = @_;
    my %env_vars = ();

    for my $env_key (sort keys %ENV_MAPPING) {
        my $config_key = $ENV_MAPPING{$env_key};
        my $value = $self->_get_config($config_key);
        $env_vars{$env_key} = $value if defined $value;
    }

    return \%env_vars;
}

# Private methods

sub _load_config {
    my ($self) = @_;

    # Start with defaults
    %{ $self->{_config} } = %DEFAULTS;

    # Load from private config file if it exists
    my $config_file = $self->_find_config_file();
    if (defined $config_file && -f $config_file) {
        $self->_load_from_file($config_file);
    }

    # Override with environment variables (highest priority)
    $self->_load_from_env();
}

sub _find_config_file {
    my ($self) = @_;

    # Look for config in parent directory (jitsi-video-hosting-ops)
    my @search_paths = (
        '../../jitsi-video-hosting-ops/config.json',
        '../../jitsi-video-hosting-ops/jitsi-config.json',
        '../jitsi-video-hosting-ops/config.json',
        '../jitsi-video-hosting-ops/jitsi-config.json',
    );

    for my $path (@search_paths) {
        my $abs_path = File::Spec->rel2abs($path, File::Spec->curdir());
        return $abs_path if -f $abs_path;
    }

    return undef;
}

sub _load_from_file {
    my ($self, $filepath) = @_;

    open my $fh, '<', $filepath or croak "Cannot open config file $filepath: $!";
    local $/;
    my $json_str = <$fh>;
    close $fh;

    my $config = eval { decode_json($json_str) };
    if ($@) {
        croak "Invalid JSON in config file $filepath: $@";
    }

    # Merge into config, overwriting defaults
    for my $key (keys %{$config}) {
        $self->{_config}->{$key} = $config->{$key};
    }
}

sub _load_from_env {
    my ($self) = @_;

    for my $env_key (keys %ENV_MAPPING) {
        if (exists $ENV{$env_key}) {
            my $config_key = $ENV_MAPPING{$env_key};
            $self->{_config}->{$config_key} = $ENV{$env_key};
        }
    }
}

sub _validate_config {
    my ($self) = @_;

    # Check required fields
    for my $required (qw(domain aws_profile)) {
        unless (defined $self->{_config}->{$required}) {
            croak "Missing required configuration: $required. "
                . "Set via env var (JITSI_" . uc($required) . "), "
                . "config file, or contact maintainer.";
        }
    }
}

sub _get_config {
    my ($self, $key) = @_;
    return $self->{_config}->{$key};
}

1;

__END__

=head1 CONFIGURATION SOURCES

Configuration is loaded in this order (later sources override earlier ones):

1. **Compiled defaults** (in this module)
2. **Private config file** (../jitsi-video-hosting-ops/config.json)
3. **Environment variables** (JITSI_* variables)

=head1 ENVIRONMENT VARIABLES

- JITSI_DOMAIN: Domain name (e.g., meet.example.com)
- JITSI_AWS_PROFILE: AWS CLI profile name
- JITSI_AWS_REGION: AWS region (default: us-west-2)
- JITSI_PROJECT: Project name (default: jitsi-video-platform)
- JITSI_ENVIRONMENT: Environment (default: prod)
- JITSI_CLUSTER: ECS cluster name
- JITSI_SERVICE: ECS service name
- JITSI_NLB: Network Load Balancer name

=head1 PRIVATE CONFIG FILE

Create jitsi-video-hosting-ops/config.json:

    {
        "domain": "meet.example.com",
        "aws_profile": "my-aws-profile",
        "aws_region": "us-west-2",
        "project_name": "jitsi-video-platform",
        "environment": "prod",
        "cluster_name": "jitsi-video-platform-cluster",
        "service_name": "jitsi-video-platform-service",
        "nlb_name": "jitsi-video-platform-nlb"
    }

=head1 AUTHOR

Bryan Chasko

=cut
