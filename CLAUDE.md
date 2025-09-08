# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a production-ready True Blue-Green Deployment system implementing dual EC2 instances with AWS Application Load Balancer (ALB) for zero-downtime switching. The system follows AWS best practices with PM2 process management and CodeDeploy automation.

## Core Architecture

### Dual EC2 + ALB Architecture
- **Primary Application**: `app-server/app.js` - Single Node.js application with PM2 process management
- **Deployment Strategy**: PM2-based with 4 instances per EC2 for optimal resource utilization
- **Infrastructure**: Dual EC2 instances across multiple AZs with ALB traffic management
- **Health Monitoring**: Enhanced health checks with `/health/deep` endpoint for comprehensive validation

### Service Architecture
- **AWS ALB**: Traffic distribution between Blue/Green target groups
- **Blue EC2 Instance**: PM2-managed application instances (Ports 3001-3004)
- **Green EC2 Instance**: PM2-managed application instances (Ports 3001-3004)
- **NGINX**: Load balancing across 4 PM2 instances per EC2
- **CodeDeploy**: Automated deployment with lifecycle hooks

### Zero-Downtime Switching Mechanism
- **Target Group Switching**: ALB routes traffic between Blue/Green target groups
- **Health Validation**: Deep health checks validate database, memory, and external services
- **Atomic Deployments**: CodeDeploy ensures atomic deployments with automatic rollback
- **Multi-AZ Redundancy**: Cross-AZ deployment for high availability

## Development Commands

### System Management
```bash
# Start PM2 processes
npm run start:pm2
pm2 start ecosystem.config.js

# System status and monitoring
pm2 status
pm2 monit
./scripts/manage-pm2.sh status

# View application logs
pm2 logs
pm2 logs app-instance-1
```

### Deployment Operations
```bash
# Enhanced deployment management
./scripts/enhanced-deploy.sh deploy              # Deploy to inactive environment
./scripts/enhanced-deploy.sh switch              # Switch ALB traffic
./scripts/enhanced-deploy.sh rollback            # Emergency rollback
./scripts/enhanced-deploy.sh validate            # Comprehensive validation

# PM2 process management
./scripts/manage-pm2.sh start                    # Start all PM2 processes
./scripts/manage-pm2.sh stop                     # Stop all PM2 processes
./scripts/manage-pm2.sh restart                  # Restart with zero downtime
./scripts/manage-pm2.sh scale 6                  # Scale to 6 instances
```

### Health and Version Validation
```bash
# Deep health checks (ALB integration)
curl http://your-alb-dns/health/deep             # Comprehensive health check
curl http://localhost:3001/health/deep           # Direct instance health check

# Basic health checks
curl http://your-alb-dns/health                  # Basic ALB health
curl http://localhost:3001/health                # Direct instance health
curl http://localhost:3002/health                # Instance 2 health
curl http://localhost:3003/health                # Instance 3 health
curl http://localhost:3004/health                # Instance 4 health

# Version and deployment information
curl http://localhost:3001/version               # Version information
curl http://localhost:3001/deployment            # Deployment metadata
```

## Configuration Management

### Environment Variables (Primary Configuration Method)
```bash
# Blue Environment (EC2 Instance 1)
ENV_NAME=blue
NODE_ENV=production
PM2_INSTANCES=4
HEALTH_CHECK_ENABLED=true
DB_CONNECTION_CHECK=true

# Green Environment (EC2 Instance 2)
ENV_NAME=green
NODE_ENV=production
PM2_INSTANCES=4
HEALTH_CHECK_ENABLED=true
DB_CONNECTION_CHECK=true
```

### Critical Configuration Files
- `ecosystem.config.js`: PM2 process configuration with 4 instances
- `nginx-alb.conf`: ALB-optimized NGINX configuration
- `conf.d/upstreams-alb.conf`: Load balancing configuration for PM2 instances
- `appspec.yml`: CodeDeploy application specification
- `aws-infrastructure/cloudformation/`: Infrastructure as Code templates

### NGINX Load Balancing Architecture
The system uses NGINX to load balance across 4 PM2 instances per EC2:
```nginx
upstream app_backend {
    least_conn;
    server 127.0.0.1:3001 max_fails=2 fail_timeout=30s weight=1;
    server 127.0.0.1:3002 max_fails=2 fail_timeout=30s weight=1;
    server 127.0.0.1:3003 max_fails=2 fail_timeout=30s weight=1;
    server 127.0.0.1:3004 max_fails=2 fail_timeout=30s weight=1;
}

location / {
    proxy_pass http://app_backend;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

## Deployment Safety Mechanisms

### CodeDeploy Lifecycle Hooks
All deployments follow the 6-stage CodeDeploy lifecycle:
1. **Stop Services**: Gracefully stop running PM2 processes
2. **Prepare Environment**: Setup deployment environment and validate prerequisites  
3. **Install Dependencies**: Install Node.js dependencies and validate packages
4. **Configure Services**: Configure PM2, NGINX, and application settings
5. **Start Services**: Start PM2 processes with health validation
6. **Validate Deployment**: Comprehensive health checks and smoke tests

### Multi-Layer Health Validation
1. **Application Health**: Basic `/health` endpoint for ALB health checks
2. **Deep Health**: `/health/deep` endpoint with database and external service checks
3. **Process Health**: PM2 process monitoring and automatic restart
4. **Infrastructure Health**: ALB target group health monitoring
5. **End-to-End**: Complete request flow validation across instances

### Emergency Recovery Procedures
```bash
# Complete system recovery
pm2 kill
./scripts/manage-pm2.sh start

# Manual PM2 restart
pm2 restart ecosystem.config.js
pm2 reload ecosystem.config.js  # Zero-downtime reload

# NGINX configuration reload
sudo nginx -t && sudo nginx -s reload

# CodeDeploy rollback
aws deploy create-deployment --application-name YourApp --deployment-group-name YourGroup --s3-location bucket=your-bucket,key=previous-version.zip
```

## AWS Infrastructure

### CloudFormation Templates
- `bluegreen-infrastructure.yaml`: Complete infrastructure definition
- **VPC Configuration**: Multi-AZ setup with public/private subnets
- **ALB Setup**: Application Load Balancer with Blue/Green target groups
- **Auto Scaling**: EC2 Auto Scaling Groups for Blue and Green environments
- **IAM Roles**: Proper permissions for CodeDeploy and EC2 instances

### CodeDeploy Integration
- **Application**: Blue-Green deployment application
- **Deployment Groups**: Separate groups for Blue and Green environments
- **Deployment Configuration**: Zero-downtime deployment with automatic rollback
- **Service Role**: IAM role with necessary permissions for deployment operations

## GitLab CI/CD Pipeline

### Hybrid Pipeline Stages (.gitlab-ci-hybrid.yml)
1. **build**: Node.js build and artifact preparation
2. **test**: Syntax validation and unit testing
3. **package**: Create CodeDeploy deployment package
4. **deploy-staging**: Deploy to inactive environment via CodeDeploy
5. **validate-staging**: Health validation of deployed environment
6. **deploy-production**: Manual trigger for ALB traffic switching
7. **validate-production**: Post-deployment verification

### Deployment Variables
- **DEPLOYMENT_BUCKET**: S3 bucket for CodeDeploy artifacts
- **APPLICATION_NAME**: CodeDeploy application name
- **DEPLOYMENT_GROUP_BLUE/GREEN**: Environment-specific deployment groups
- **ALB_LISTENER_ARN**: ALB listener for traffic switching

## Resource Optimization

### Dual EC2 Configuration
- **Instance Type**: t3.small or larger (recommended for PM2 workload)
- **PM2 Instances**: 4 instances per EC2 for optimal resource utilization
- **Memory Management**: Node.js memory optimization with `--max-old-space-size`
- **Health Check Intervals**: Optimized intervals for responsive health monitoring

### Network Architecture
- **Multi-AZ Deployment**: Cross-AZ redundancy for high availability
- **ALB Integration**: Layer 7 load balancing with health checks
- **Security Groups**: Proper ingress/egress rules for secure communication
- **Target Groups**: Blue/Green target groups for zero-downtime switching

## Key Architectural Principles

### True Blue-Green Implementation
- **Dual Infrastructure**: Complete Blue and Green environments in separate AZs
- **Environment Variables**: Dynamic configuration without code duplication
- **Identical Deployments**: Same application, same PM2 configuration, different targets
- **Zero Downtime**: ALB traffic switching without service interruption
- **Instant Rollback**: Previous environment always ready for immediate switch

### Production Safety
- **Infrastructure as Code**: All infrastructure defined in CloudFormation
- **Automated Deployment**: CodeDeploy with proper lifecycle hooks
- **Health Validation**: Comprehensive health checking before traffic switching
- **Manual Gates**: CI/CD pipeline requires manual approval for production switches
- **Monitoring Integration**: CloudWatch integration for performance monitoring

### Performance Optimization
- **PM2 Cluster Mode**: Multiple Node.js processes for CPU utilization
- **NGINX Load Balancing**: Efficient request distribution across instances
- **Keep-Alive Connections**: Optimized connection pooling
- **Health Check Optimization**: Separate basic and deep health check endpoints

When working with this codebase, always prioritize the AWS best practices and PM2 process management. All deployment operations should go through CodeDeploy and proper validation procedures to maintain zero-downtime guarantees.