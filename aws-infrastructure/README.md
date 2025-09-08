# AWS Infrastructure for True Blue-Green Deployment

This directory contains AWS infrastructure configuration for migrating from single EC2 to dual EC2 + AWS Application Load Balancer architecture.

## Architecture Overview

### Current vs New Architecture
| Component | Current (Single EC2) | New (Dual EC2 + ALB) |
|-----------|---------------------|----------------------|
| **Infrastructure** | 1 EC2 + Docker Compose | 2+ EC2 + AWS ALB |
| **Load Balancing** | Internal NGINX proxy | AWS ALB + Internal NGINX |
| **App Instances** | 2 containers (Blue/Green) | 8+ instances (4 per EC2) |
| **Deployment** | GitLab CI/CD + Docker | AWS CodeDeploy + GitLab (Hybrid) |
| **Traffic Switching** | API-based config change | ALB target group switching |
| **Auto Scaling** | Manual | AWS Auto Scaling Groups |

### New Infrastructure Components

1. **VPC with Multi-AZ Setup**
   - Public subnets for ALB (2 AZs)
   - Private subnets for EC2 instances (2 AZs)
   - NAT Gateways for outbound internet access

2. **Application Load Balancer (ALB)**
   - Internet-facing with SSL termination capability
   - Health checks using `/health/deep` endpoint
   - Blue/Green target group switching

3. **Auto Scaling Groups**
   - Blue ASG: 2 instances minimum (active environment)
   - Green ASG: 0-2 instances (deployment environment)
   - t3.medium instances optimized for production workloads

4. **Security Groups**
   - ALB Security Group: HTTP/HTTPS from internet
   - EC2 Security Group: HTTP from ALB, SSH from VPC

5. **IAM Roles & Policies**
   - EC2 Role: CodeDeploy, CloudWatch, S3 access
   - CodeDeploy Role: Deployment management

## Quick Start

### Prerequisites

1. **AWS CLI installed and configured**
   ```bash
   aws configure
   # Provide: Access Key, Secret Key, Region, Output format
   ```

2. **EC2 Key Pair created**
   ```bash
   aws ec2 create-key-pair --key-name my-bluegreen-key --query 'KeyMaterial' --output text > my-bluegreen-key.pem
   chmod 400 my-bluegreen-key.pem
   ```

### Infrastructure Deployment

1. **Deploy Infrastructure**
   ```bash
   ./aws-infrastructure/scripts/deploy-infrastructure.sh -k my-bluegreen-key deploy
   ```

2. **Check Deployment Status**
   ```bash
   ./aws-infrastructure/scripts/deploy-infrastructure.sh status
   ```

3. **Get Stack Outputs**
   ```bash
   ./aws-infrastructure/scripts/deploy-infrastructure.sh outputs
   ```

### Custom Configuration

Deploy with custom parameters:
```bash
./aws-infrastructure/scripts/deploy-infrastructure.sh \
  --project-name my-project \
  --environment staging \
  --region us-west-2 \
  --key-pair my-key \
  --instance-type t3.large \
  deploy
```

## File Structure

```
aws-infrastructure/
├── cloudformation/
│   └── bluegreen-infrastructure.yaml    # Main CloudFormation template
├── scripts/
│   ├── deploy-infrastructure.sh         # Infrastructure deployment script
│   └── switch-traffic.sh               # ALB traffic switching script
├── terraform/                          # Future: Terraform alternative
└── README.md                           # This file
```

## Infrastructure Components Detail

### CloudFormation Template

**File**: `cloudformation/bluegreen-infrastructure.yaml`

**Resources Created**:
- 1 VPC with 4 subnets (2 public, 2 private)
- 1 Internet Gateway + 2 NAT Gateways
- 1 Application Load Balancer
- 2 Target Groups (Blue/Green)
- 2 Auto Scaling Groups
- 1 Launch Template
- Security Groups and IAM Roles
- CodeDeploy Application and Deployment Groups

**Key Features**:
- Multi-AZ deployment for high availability
- Auto Scaling based on target group health
- CodeDeploy integration for automated deployments
- Deep health checks for application-level monitoring

### Deployment Scripts

**Infrastructure Management**: `scripts/deploy-infrastructure.sh`
```bash
# Deploy new infrastructure
./deploy-infrastructure.sh -k keypair-name deploy

# Update existing infrastructure  
./deploy-infrastructure.sh -k keypair-name update

# Check status
./deploy-infrastructure.sh status

# Show outputs
./deploy-infrastructure.sh outputs

# Delete infrastructure
./deploy-infrastructure.sh delete
```

## Health Check Configuration

### Application Load Balancer Health Checks
- **Path**: `/health/deep`
- **Interval**: 30 seconds
- **Timeout**: 5 seconds
- **Healthy threshold**: 2 consecutive successes
- **Unhealthy threshold**: 3 consecutive failures

### Enhanced Health Check Features
The application now includes deep health checks that verify:
- Database connectivity
- Memory usage (< 90% of heap)
- External service availability
- Application response time (< 100ms)
- Process uptime (> 10 seconds)

## Cost Analysis

### Monthly Cost Estimates (US-East-1)

| Component | Basic Setup | Optimized Setup |
|-----------|------------|-----------------|
| **EC2 Instances** (2 × t3.medium) | $60.70 | $42.49 (Reserved) |
| **Application Load Balancer** | $22.50 | $22.50 |
| **NAT Gateway** (2 × $45) | $90.00 | $90.00 |
| **Data Transfer** | $10.00 | $10.00 |
| **CloudWatch** | $5.00 | $5.00 |
| **Total** | **~$188/month** | **~$170/month** |

**Cost Optimization Tips**:
1. Use Reserved Instances (30-50% savings)
2. Implement proper auto-scaling policies
3. Monitor and optimize data transfer
4. Use CloudWatch Logs retention policies

## Migration Path

### Phase 1: Infrastructure Setup
1. Deploy AWS infrastructure using CloudFormation
2. Configure security groups and networking
3. Set up CodeDeploy applications

### Phase 2: Application Migration
1. Update NGINX configuration for 4-instance load balancing
2. Implement PM2 process management
3. Configure enhanced health checks

### Phase 3: CI/CD Integration
1. Create hybrid GitLab + CodeDeploy pipeline
2. Configure deployment scripts
3. Set up monitoring and alerting

### Phase 4: Production Migration
1. DNS cutover to ALB
2. Gradual traffic migration
3. Monitor and optimize

## Troubleshooting

### Common Issues

1. **Stack Creation Fails**
   ```bash
   # Check CloudFormation events
   aws cloudformation describe-stack-events --stack-name bluegreen-deployment-production-infrastructure
   ```

2. **Health Checks Failing**
   ```bash
   # Check target group health
   ./scripts/deploy-infrastructure.sh status
   
   # SSH to instance and check application
   ssh -i keypair.pem ec2-user@instance-ip
   curl http://localhost/health/deep
   ```

3. **Auto Scaling Issues**
   ```bash
   # Check Auto Scaling Group activities
   aws autoscaling describe-scaling-activities --auto-scaling-group-name bluegreen-deployment-production-blue-asg
   ```

### Health Check Debugging

1. **Application Level**
   ```bash
   # Test health endpoints
   curl http://alb-dns-name/health
   curl http://alb-dns-name/health/deep
   ```

2. **Target Group Level**
   ```bash
   # Check target health
   aws elbv2 describe-target-health --target-group-arn target-group-arn
   ```

3. **Instance Level**
   ```bash
   # Check CodeDeploy agent
   sudo service codedeploy-agent status
   
   # Check application logs
   tail -f /opt/bluegreen-app/logs/app.log
   ```

## Security Considerations

### Network Security
- ALB only accepts HTTP/HTTPS traffic from internet
- EC2 instances in private subnets
- Security groups with minimal required ports
- NACLs for additional network-level protection

### Application Security
- IAM roles with minimal required permissions
- CodeDeploy with automatic rollback on failure
- Enhanced health checks for application integrity
- CloudWatch monitoring for security events

## Next Steps

1. **SSL/TLS Configuration**: Add HTTPS listener and SSL certificate
2. **WAF Integration**: Add AWS WAF for application-level protection
3. **Monitoring Enhancement**: Add CloudWatch dashboards and alarms
4. **Backup Strategy**: Implement automated backup procedures
5. **Disaster Recovery**: Multi-region deployment consideration

## Support

For issues or questions:
1. Check CloudFormation events and stack status
2. Review Auto Scaling Group activities
3. Check CodeDeploy deployment history
4. Monitor CloudWatch logs and metrics
5. Verify security group and IAM permissions