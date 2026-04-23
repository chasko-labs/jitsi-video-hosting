# Jitsi Container Production Optimization Guide

> **doc status (2026-04-23):** largely current. environment variable recommendations, NAT traversal config, JVB health check path (`/about/health`), and scale-to-zero patterns are still accurate. the Secrets Manager integration described here was later supplemented by SSM (5 internal XMPP secrets) and JWT (shared secret in Secrets Manager, KMS). for current secrets architecture, see README authentication section + `SSM_MIGRATION_COMPLETE.md`

## Overview

This document outlines the comprehensive production optimizations implemented for the Jitsi Meet deployment on AWS. The enhancements focus on security, performance, scalability, monitoring, and video recording capabilities while maintaining the existing scale-to-zero architecture.

## 🔧 Production Optimizations Implemented

### 1. Security Enhancements

#### AWS Secrets Manager Integration
- **Replaced hardcoded passwords** with AWS Secrets Manager
- **Automatic secret generation** using Terraform random providers
- **Secure secret retrieval** at container runtime
- **Centralized secret management** for all Jitsi components

**Components with Secret Management:**
- Jicofo authentication (component secret & password)
- JVB authentication (component secret & password)
- Jigasi authentication password
- Jibri recording authentication

#### Enhanced Security Groups
- Added JVB TCP fallback port (4443) for improved connectivity
- HTTP port (80) for health checks
- Maintained existing HTTPS (443) and JVB UDP (10000) ports

### 2. Container Configuration Optimizations

#### Jitsi Web Container
- **Recording integration** with environment variables
- **Resolution optimization** (1280x720 default)
- **Enhanced XMPP configuration** for recording domain
- **Production-grade health checks**

#### Prosody XMPP Server
- **Recorder domain configuration** for Jibri integration
- **Enhanced logging** with configurable log levels
- **Jibri user authentication** setup
- **Production stability improvements**

#### Jicofo Conference Focus
- **Bridge health checks** enabled
- **Participant timeout optimization** (15s initial, 20s single)
- **Enhanced conference management** settings
- **Improved reliability configurations**

#### JVB Video Bridge (Critical for AWS)
- **AWS-specific NAT traversal** configuration
- **STUN server integration** (Google STUN servers)
- **Private candidate filtering** for AWS networking
- **TCP harvester optimization** for fallback connectivity
- **WebSocket domain configuration**
- **REST API enablement** for monitoring and control
- **Colibri REST API** for advanced management

#### Jibri Recording Service (New)
- **S3 integration** for video storage
- **AWS region configuration**
- **Recording directory management**
- **Finalization script integration**
- **Brewery MUC configuration** for scaling

### 3. Resource Optimization

#### Dynamic Resource Allocation
- **Configurable CPU/Memory** via Terraform variables
- **Default allocation**: 4 vCPU (4096 CPU units) / 8GB RAM (8192 MB)
- **Production-sized** for handling multiple concurrent meetings
- **Scalable** based on actual usage patterns

#### Auto-Scaling Configuration
- **Target tracking scaling** based on CPU and memory utilization
- **Scale range**: 0-3 instances (maintains scale-to-zero capability)
- **Target utilization**: 70% CPU and memory
- **Cooldown periods**: 5 minutes for scale-in/out stability

### 4. Monitoring and Observability

#### CloudWatch Integration
- **Extended log retention** (30 days vs. 7 days)
- **Custom metric filters** for Jitsi-specific metrics:
  - JVB participant count tracking
  - Conference count monitoring
- **Comprehensive logging** for all containers

#### CloudWatch Alarms
- **High CPU utilization** alarm (>80% threshold)
- **High memory utilization** alarm (>80% threshold)
- **SNS integration** for alert notifications
- **Operational visibility** for proactive management

#### Custom Metrics Namespace
- **Jitsi/JVB namespace** for application-specific metrics
- **Participant and conference tracking**
- **Performance monitoring** capabilities

### 5. Video Recording Integration

#### S3 Storage Configuration
- **Dedicated S3 bucket** with encryption
- **Versioning enabled** for recording history
- **Public access blocked** for security
- **IAM integration** for secure access

#### Jibri Container Features
- **Privileged mode** for video processing
- **AWS SDK integration** for S3 uploads
- **Recording finalization** scripts
- **Brewery MUC** for horizontal scaling preparation

## 📊 Performance Improvements

### JVB Optimizations for AWS
1. **NAT Traversal**: Optimized for AWS networking with proper STUN configuration
2. **Private Candidate Filtering**: Prevents internal IP exposure
3. **TCP Fallback**: Ensures connectivity when UDP is blocked
4. **WebSocket Support**: Enhanced browser compatibility
5. **REST API**: Enables monitoring and management

### Resource Efficiency
1. **Right-sized Resources**: 4 vCPU / 8GB RAM for production workloads
2. **Auto-scaling**: Automatic resource adjustment based on demand
3. **Scale-to-zero**: Maintains cost optimization when not in use
4. **Efficient Logging**: Optimized retention and filtering

## 🔍 Monitoring Capabilities

### Available Metrics
- **ECS Service Metrics**: CPU, memory, task count
- **Custom Jitsi Metrics**: Participants, conferences
- **Application Logs**: All container logs with structured filtering
- **Performance Tracking**: Real-time utilization monitoring

### Alerting
- **Proactive Notifications**: SNS topic for critical alerts
- **Threshold-based Alarms**: CPU and memory utilization
- **Operational Awareness**: Early warning system

## 🎥 Video Recording Features

### Recording Capabilities
- **On-demand Recording**: Start/stop via Jitsi interface
- **S3 Integration**: Automatic upload to dedicated bucket
- **Secure Storage**: Encrypted at rest with versioning
- **Scalable Architecture**: Ready for multiple concurrent recordings

### Recording Workflow
1. User initiates recording in Jitsi Meet interface
2. Jibri container processes video/audio streams
3. Recording saved to local temporary storage
4. Finalization script uploads to S3 bucket
5. Local files cleaned up automatically

## 🚀 Deployment Variables

### New Configuration Options
```hcl
# Resource allocation
task_cpu    = 4096  # CPU units (4 vCPU)
task_memory = 8192  # Memory in MB (8 GB)

# Feature toggles
enable_recording   = true   # Enable Jibri recording
max_participants   = 50     # Maximum participants per meeting

# Environment
environment = "prod"        # Production environment
```

### Customization Guidelines
- **CPU/Memory**: Adjust based on expected concurrent meetings
- **Recording**: Disable if not needed to reduce resource usage
- **Participants**: Set based on expected meeting sizes
- **Scaling**: Modify auto-scaling policies for different usage patterns

## 🔧 Operational Procedures

### Scaling Operations
```bash
# Manual scaling (if needed)
aws ecs update-service \
  --cluster jitsi-video-platform-cluster \
  --service jitsi-video-platform-service \
  --desired-count 1

# Check auto-scaling status
aws application-autoscaling describe-scalable-targets \
  --service-namespace ecs
```

### Monitoring Commands
```bash
# View CloudWatch logs
aws logs tail /ecs/jitsi-video-platform --follow

# Check service health
aws ecs describe-services \
  --cluster jitsi-video-platform-cluster \
  --services jitsi-video-platform-service
```

### Secret Management
```bash
# View secrets (requires appropriate IAM permissions)
aws secretsmanager get-secret-value \
  --secret-id jitsi-video-platform-jitsi-secrets

# Rotate secrets (if needed)
aws secretsmanager rotate-secret \
  --secret-id jitsi-video-platform-jitsi-secrets
```

## 📈 Performance Expectations

### Capacity Planning
- **Single Instance**: 20-30 concurrent participants
- **Auto-scaled (3 instances)**: 60-90 concurrent participants
- **Recording Impact**: ~20% additional resource usage per active recording

### Network Requirements
- **Bandwidth per participant**: ~1-2 Mbps (video + audio)
- **JVB UDP traffic**: Primary media path
- **TCP fallback**: Backup for restricted networks
- **WebSocket**: Browser compatibility enhancement

## 🔒 Security Considerations

### Production Security Features
1. **No hardcoded secrets** in configuration
2. **Encrypted S3 storage** for recordings
3. **IAM least privilege** access
4. **VPC isolation** with proper security groups
5. **TLS encryption** for all web traffic

### Ongoing Security Maintenance
- **Regular secret rotation** (recommended quarterly)
- **Container image updates** (monitor Jitsi releases)
- **Security group reviews** (audit access patterns)
- **S3 bucket policies** (verify access controls)

## 🎯 Success Metrics

### Key Performance Indicators
- **Service availability**: >99.5% uptime
- **Auto-scaling responsiveness**: <5 minutes to scale
- **Recording success rate**: >95% successful uploads
- **Resource utilization**: 60-80% average during active use
- **Cost optimization**: $0 during inactive periods

### Monitoring Dashboards
Create CloudWatch dashboards to track:
- ECS service health and scaling events
- JVB participant and conference counts
- Resource utilization trends
- Recording activity and success rates
- Cost optimization metrics

## 🔄 Maintenance and Updates

### Regular Maintenance Tasks
1. **Monthly**: Review CloudWatch metrics and optimize scaling policies
2. **Quarterly**: Rotate secrets and update container images
3. **Bi-annually**: Review and update resource allocations
4. **Annually**: Security audit and architecture review

### Update Procedures
1. **Test changes** in non-production environment
2. **Update Terraform configuration**
3. **Plan and apply** infrastructure changes
4. **Verify functionality** with end-to-end testing
5. **Monitor performance** post-deployment

This production optimization provides a robust, scalable, and secure Jitsi Meet deployment optimized for AWS environments with comprehensive monitoring, auto-scaling, and video recording capabilities.