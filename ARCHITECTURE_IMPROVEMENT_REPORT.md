# Architecture Improvement Report v2.0
## Migration from Single EC2 to Dual EC2 + AWS Load Balancer

**Date**: 2025-01-19  
**Version**: 2.0 (개선사항 반영)  
**Project**: True Blue-Green Deployment System  
**Migration Target**: EC2 서버 2대 + AWS 로드밸런서 + AWS CodeDeploy

---

## Executive Summary

본 보고서는 현재의 단일 EC2 Blue-Green 배포 시스템을 분석하고, 듀얼 EC2 아키텍처 with AWS Application Load Balancer(ALB) 및 AWS CodeDeploy 통합으로의 마이그레이션을 위한 포괄적인 권장사항을 제공합니다.

### Current vs Target Architecture

| Aspect | Current (Single EC2) | Target (Dual EC2 + ALB) |
|--------|---------------------|--------------------------|
| **Infrastructure** | 1 EC2 + Docker Compose | 2 EC2 + AWS ALB |
| **Load Balancing** | Internal NGINX proxy | AWS ALB + Internal NGINX |
| **App Instances** | 2 containers (Blue/Green) | 8 instances (4 per EC2) |
| **Deployment** | GitLab CI/CD + Docker | AWS CodeDeploy + GitLab (Hybrid) |
| **Traffic Switching** | API-based config change | ALB target group switching |
| **Process Isolation** | Container-based | Process-based (with ECS migration path) |

---

## Current System Analysis

### 🏗️ Architecture Overview

```
[GitLab CI/CD] → [Single EC2 Instance]
                      │
                  [Docker Compose]
                      │
    ┌─────────────────┼─────────────────┐
    │                 │                 │
[nginx-proxy]    [blue-app]      [green-app]
    │               │                │
    └─────────────────┼─────────────────┘
           [api-server]
```

### 📦 Core Components Analysis

#### 1. **Container Services**
- **nginx-proxy**: 변수 기반 라우팅을 통한 트래픽 라우터
- **blue-app/green-app**: 환경 변수를 사용하는 동일한 Node.js 애플리케이션
- **api-server**: 트래픽 전환을 위한 배포 제어 API

#### 2. **NGINX Configuration**
- **Dynamic routing**: `$active` 변수가 업스트림 서버에 매핑
- **Atomic switching**: `active.env` 파일 수정 + `nginx -s reload`
- **Health endpoints**: 다층 헬스 검증

#### 3. **Application Architecture**
- **Single codebase**: `app-server/app.js`가 양쪽 환경 서빙
- **Environment variables**: 코드 중복 없는 동적 구성
- **Deployment metadata**: 버전 추적 및 롤백 지원

#### 4. **CI/CD Pipeline (10 Stages)**
```yaml
build-dev → test-dev → detect-env-dev → deploy-inactive-dev 
→ health-check-dev → zero-downtime-test-dev → switch-traffic-dev 
→ verify-deployment-dev → cleanup-dev → [emergency-rollback]
```

### 🎯 Strengths of Current System

1. **True Blue-Green**: 무중단 전환이 가능한 동일한 환경
2. **Atomic operations**: 모든 구성 변경이 원자적이고 검증됨
3. **Resource optimized**: 메모리/CPU 제한으로 t2.micro에 효율적
4. **Comprehensive testing**: 다층 헬스 체크 및 검증
5. **Version tracking**: 완전한 배포 메타데이터 및 롤백 기능
6. **Container isolation**: Docker 기반 프로세스 격리

### ⚠️ Current Limitations

1. **Single point of failure**: 단일 EC2 인스턴스
2. **Limited scalability**: 2개의 애플리케이션 인스턴스만 가능
3. **Manual scaling**: 자동 스케일링 기능 없음
4. **Docker dependency**: 컨테이너 기반 아키텍처 복잡성
5. **Internal load balancing**: NGINX 프록시가 병목 지점이 됨

---

## Target Architecture Design

### 🎯 Dual EC2 + AWS ALB Architecture

```
[GitLab CI/CD] → [Hybrid Integration] → [AWS CodeDeploy]
                      │                        │
    ┌─────────────────┼────────────────────────┼─────────────┐
    │                 │                        │             │
[EC2 Instance 1]  [EC2 Instance 2]    [Future: ECS Cluster]
    │                 │                        │
[NGINX + 4 Apps]  [NGINX + 4 Apps]    [Container Tasks]
    │                 │                        │
    └─────────────────┼────────────────────────┘
              [AWS ALB]
              │
        [Target Groups]
        │         │
   [Blue TG]  [Green TG]
```

### 🔧 Component Architecture

#### 1. **AWS Application Load Balancer**
- **Primary load balancer**: Docker Compose nginx-proxy 대체
- **Target group switching**: ALB 레벨에서 Blue/Green 배포
- **Health checks**: ALB 네이티브 헬스 체킹 (앱 프로세스까지 관통)
- **SSL termination**: ALB 레벨에서 HTTPS 처리
- **Cost structure**: 월 $22.50 (기본) + LCU 단위 추가 비용

#### 2. **EC2 Instance Configuration** (Per Instance)
- **NGINX**: 4개 애플리케이션 프로세스를 위한 로컬 로드 밸런서
- **4 Application processes**: 직접 Node.js 프로세스 (Docker 선택적 유지)
- **Process manager**: PM2 또는 systemd (Docker 유지 시 docker-compose)
- **Health endpoints**: 애플리케이션 레벨 헬스 체크 (ALB와 통합)

#### 3. **AWS CodeDeploy Integration**
- **Deployment groups**: Blue 및 Green 타겟 그룹
- **Application revisions**: GitLab CI/CD → S3 → CodeDeploy
- **Auto-scaling support**: 타겟 그룹 기반 스케일링
- **Rollback capability**: CodeDeploy 네이티브 롤백
- **Hybrid operation**: GitLab CI/CD와 병행 운영 기간 설정

#### 4. **Container Strategy Options**
- **Short-term**: PM2/systemd 기반 프로세스 관리
- **Mid-term**: Docker 컨테이너 유지 (격리 수준 유지)
- **Long-term**: ECS/EKS 마이그레이션 (권장)

---

## Implementation Roadmap

### Phase 0: Container Strategy Decision (Week 0)

#### Option A: Docker 유지
```yaml
# 장점:
- 프로세스 격리 수준 유지
- 현재 CI/CD 파이프라인 최소 변경
- 로컬 개발 환경과 일관성

# 단점:
- EC2 인스턴스 리소스 오버헤드
- Docker 데몬 관리 필요
```

#### Option B: Native Process (PM2)
```yaml
# 장점:
- 리소스 효율성 향상
- 단순한 프로세스 관리
- 빠른 시작/정지

# 단점:
- 프로세스 격리 수준 감소
- 환경 일관성 관리 어려움
```

### Phase 1: Infrastructure Setup (Week 1-2)

#### 1.1 AWS Infrastructure
```bash
# VPC 및 서브넷 생성
aws ec2 create-vpc --cidr-block 10.0.0.0/16
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 10.0.1.0/24 --availability-zone us-east-1a
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 10.0.2.0/24 --availability-zone us-east-1b

# Application Load Balancer 생성
aws elbv2 create-load-balancer \
  --name bluegreen-alb \
  --subnets subnet-xxx subnet-yyy \
  --security-groups sg-xxx \
  --scheme internet-facing
```

#### 1.2 Target Groups with Health Check Configuration
```bash
# Blue target group with app-level health check
aws elbv2 create-target-group \
  --name bluegreen-blue-tg \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-xxx \
  --health-check-path /health/deep \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3

# Green target group with identical configuration
aws elbv2 create-target-group \
  --name bluegreen-green-tg \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-xxx \
  --health-check-path /health/deep \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3
```

#### 1.3 EC2 Instances Setup with Improved User Data
```bash
#!/bin/bash
# codedeploy-setup.sh - Improved version
yum update -y
yum install -y nginx nodejs npm ruby wget

# Node.js 버전 관리
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 18
nvm use 18

# PM2 설치 (Native Process 옵션 선택 시)
npm install -g pm2
pm2 startup systemd

# Docker 설치 (Container 옵션 선택 시)
yum install -y docker
systemctl start docker
systemctl enable docker
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# CodeDeploy agent 설치
cd /home/ec2-user
wget https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install
chmod +x ./install
./install auto
systemctl start codedeploy-agent
systemctl enable codedeploy-agent

# CloudWatch 에이전트 설치
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm
```

### Phase 2: Application Migration (Week 2-3)

#### 2.1 Improved Health Check Implementation
```javascript
// app-server/health.js - Deep health check for ALB
const express = require('express');
const router = express.Router();

// 기본 헬스 체크 (NGINX용)
router.get('/health', (req, res) => {
  res.status(200).send('healthy\n');
});

// 심층 헬스 체크 (ALB용 - 실제 앱 프로세스 검증)
router.get('/health/deep', async (req, res) => {
  try {
    // 데이터베이스 연결 확인
    const dbHealthy = await checkDatabaseConnection();
    
    // 메모리 사용량 확인
    const memUsage = process.memoryUsage();
    const memHealthy = memUsage.heapUsed < memUsage.heapTotal * 0.9;
    
    // 외부 서비스 연결 확인
    const extServicesHealthy = await checkExternalServices();
    
    if (dbHealthy && memHealthy && extServicesHealthy) {
      res.status(200).json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        checks: {
          database: 'ok',
          memory: 'ok',
          externalServices: 'ok'
        }
      });
    } else {
      res.status(503).json({
        status: 'unhealthy',
        timestamp: new Date().toISOString(),
        checks: {
          database: dbHealthy ? 'ok' : 'failed',
          memory: memHealthy ? 'ok' : 'failed',
          externalServices: extServicesHealthy ? 'ok' : 'failed'
        }
      });
    }
  } catch (error) {
    res.status(503).json({
      status: 'error',
      message: error.message
    });
  }
});

module.exports = router;
```

#### 2.2 Enhanced NGINX Configuration
```nginx
# /etc/nginx/nginx.conf
upstream app_backend {
    least_conn;  # 최소 연결 로드 밸런싱
    server 127.0.0.1:3001 max_fails=2 fail_timeout=30s;
    server 127.0.0.1:3002 max_fails=2 fail_timeout=30s;
    server 127.0.0.1:3003 max_fails=2 fail_timeout=30s;
    server 127.0.0.1:3004 max_fails=2 fail_timeout=30s;
    
    # 헬스 체크 설정
    keepalive 32;
}

server {
    listen 80;
    server_name _;
    
    # 기본 헬스 체크 (NGINX 자체)
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # 심층 헬스 체크 (ALB → NGINX → App)
    location /health/deep {
        proxy_pass http://app_backend/health/deep;
        proxy_set_header Host $host;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_connect_timeout 2s;
        proxy_send_timeout 2s;
        proxy_read_timeout 2s;
    }
    
    # 애플리케이션 트래픽
    location / {
        proxy_pass http://app_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Keep-alive 설정
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
```

#### 2.3 Corrected CodeDeploy Configuration
```yaml
# appspec.yml - 수정된 버전
version: 0.0
os: linux
files:
  - source: /
    destination: /opt/bluegreen-app
    
permissions:
  - object: /opt/bluegreen-app
    pattern: "**"
    owner: ec2-user
    group: ec2-user
    mode: 755
    
hooks:
  ApplicationStop:
    - location: scripts/stop-services.sh
      timeout: 300
      runas: ec2-user
      
  BeforeInstall:
    - location: scripts/prepare-environment.sh  # 환경 준비 (디렉터리, 권한)
      timeout: 300
      runas: root
      
  AfterInstall:
    - location: scripts/install-dependencies.sh  # npm install 등
      timeout: 600
      runas: ec2-user
      
  ApplicationStart:
    - location: scripts/start-services.sh
      timeout: 300
      runas: ec2-user
      
  ValidateService:
    - location: scripts/validate-deployment.sh  # 심층 헬스 체크
      timeout: 300
      runas: ec2-user
```

### Phase 3: Hybrid CI/CD Pipeline Migration (Week 3-4)

#### 3.1 GitLab CI/CD + CodeDeploy Hybrid Strategy
```yaml
# .gitlab-ci.yml - Hybrid approach
stages:
  - build
  - test
  - package
  - deploy-staging    # GitLab 직접 배포 (기존 방식)
  - deploy-production # CodeDeploy 사용 (새 방식)
  - switch-traffic
  - rollback

variables:
  DEPLOYMENT_STRATEGY: "hybrid"  # hybrid | codedeploy-only | gitlab-only

# 스테이징은 기존 GitLab 방식 유지 (전환 기간)
deploy-to-staging:
  stage: deploy-staging
  script:
    - |
      if [ "$DEPLOYMENT_STRATEGY" != "codedeploy-only" ]; then
        echo "Using traditional GitLab deployment for staging"
        ssh $STAGING_SERVER "docker-compose pull && docker-compose up -d"
      else
        echo "Using CodeDeploy for staging"
        aws deploy create-deployment \
          --application-name BlueGreenApp-Staging \
          --deployment-group-name StagingGroup \
          --s3-location bucket=codedeploy-bucket,key=staging/app.zip
      fi
  environment:
    name: staging

# 프로덕션은 CodeDeploy 사용
deploy-to-blue-production:
  stage: deploy-production
  script:
    # 배포 패키지 생성 및 S3 업로드
    - zip -r deployment-package.zip . -x "*.git*"
    - aws s3 cp deployment-package.zip s3://codedeploy-bucket/production/
    
    # CodeDeploy 배포 생성
    - |
      DEPLOYMENT_ID=$(aws deploy create-deployment \
        --application-name BlueGreenApp \
        --deployment-group-name BlueGroup \
        --s3-location bucket=codedeploy-bucket,key=production/deployment-package.zip \
        --description "GitLab Pipeline: $CI_PIPELINE_ID" \
        --output text --query 'deploymentId')
    
    # 배포 상태 모니터링
    - |
      while true; do
        STATUS=$(aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --query 'deploymentInfo.status' --output text)
        if [ "$STATUS" = "Succeeded" ]; then
          echo "Deployment succeeded"
          break
        elif [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Stopped" ]; then
          echo "Deployment failed with status: $STATUS"
          exit 1
        fi
        echo "Current status: $STATUS. Waiting..."
        sleep 10
      done
  environment:
    name: production-blue
  when: manual

# 트래픽 전환 (수동 승인)
switch-traffic-to-green:
  stage: switch-traffic
  script:
    - |
      # 현재 활성 타겟 그룹 확인
      CURRENT_TG=$(aws elbv2 describe-listeners \
        --listener-arns $LISTENER_ARN \
        --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
        --output text)
      
      # Green으로 전환
      if [[ "$CURRENT_TG" == *"blue"* ]]; then
        echo "Switching from Blue to Green"
        TARGET_ARN=$GREEN_TG_ARN
      else
        echo "Switching from Green to Blue"
        TARGET_ARN=$BLUE_TG_ARN
      fi
      
      aws elbv2 modify-listener \
        --listener-arn $LISTENER_ARN \
        --default-actions Type=forward,TargetGroupArn=$TARGET_ARN
      
      # 전환 확인
      sleep 5
      ./scripts/verify-traffic-switch.sh $TARGET_ARN
  when: manual
  environment:
    name: production-active

# 긴급 롤백
emergency-rollback:
  stage: rollback
  script:
    - |
      # 이전 버전으로 즉시 롤백
      aws deploy stop-deployment --deployment-id $CURRENT_DEPLOYMENT_ID --auto-rollback-enabled
      
      # 트래픽도 이전 타겟 그룹으로 전환
      ./scripts/switch-to-previous-target-group.sh
  when: manual
  only:
    - master
```

### Phase 4: Monitoring & Optimization (Week 4-5)

#### 4.1 Enhanced CloudWatch Configuration
```json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "BlueGreen/Application",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {"name": "cpu_usage_idle", "rename": "CPU_IDLE", "unit": "Percent"},
          {"name": "cpu_usage_iowait", "rename": "CPU_IOWAIT", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          {"name": "used_percent", "rename": "DISK_USED", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60,
        "resources": ["/", "/opt"]
      },
      "mem": {
        "measurement": [
          {"name": "mem_used_percent", "rename": "MEM_USED", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      },
      "processes": {
        "measurement": [
          {"name": "running", "rename": "PROCESSES_RUNNING", "unit": "Count"},
          {"name": "sleeping", "rename": "PROCESSES_SLEEPING", "unit": "Count"}
        ]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/aws/ec2/bluegreen/nginx/access"
          },
          {
            "file_path": "/opt/bluegreen-app/logs/app.log",
            "log_group_name": "/aws/ec2/bluegreen/app"
          }
        ]
      }
    }
  }
}
```

#### 4.2 Auto Scaling with Proper Health Checks
```bash
# Launch Template 생성
aws ec2 create-launch-template \
  --launch-template-name bluegreen-lt \
  --launch-template-data '{
    "ImageId": "ami-xxx",
    "InstanceType": "t3.medium",
    "KeyName": "your-key",
    "SecurityGroupIds": ["sg-xxx"],
    "UserData": "'"$(base64 codedeploy-setup.sh)"'",
    "IamInstanceProfile": {
      "Arn": "arn:aws:iam::xxx:instance-profile/CodeDeployEC2"
    },
    "TagSpecifications": [{
      "ResourceType": "instance",
      "Tags": [
        {"Key": "Name", "Value": "BlueGreen-ASG"},
        {"Key": "Environment", "Value": "Production"}
      ]
    }]
  }'

# Auto Scaling Group 생성
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name bluegreen-asg \
  --launch-template LaunchTemplateName=bluegreen-lt,Version='$Latest' \
  --target-group-arns $BLUE_TG_ARN $GREEN_TG_ARN \
  --health-check-type ELB \
  --health-check-grace-period 300 \
  --min-size 2 \
  --max-size 6 \
  --desired-capacity 2 \
  --vpc-zone-identifier "subnet-xxx,subnet-yyy"
```

---

## Detailed Cost Analysis

### Current vs New Architecture Costs (Monthly)

| Component | Current | New (Basic) | New (Optimized) | Delta |
|-----------|---------|-------------|-----------------|-------|
| **EC2 Instances** | 1 × t2.micro ($8.50) | 2 × t3.medium ($60.70) | 2 × t3.medium RI ($42.49) | +$33.99 |
| **Load Balancer** | None | ALB Base ($22.50) | ALB Base ($22.50) | +$22.50 |
| **LCU Charges** | None | ~$8-15 (estimated) | ~$8-15 (estimated) | +$8-15 |
| **Data Transfer** | Minimal | Inter-AZ ($0.01/GB) | Inter-AZ ($0.01/GB) | +$5-10 |
| **CodeDeploy** | None | Free tier (1000 deployments) | Free tier | $0 |
| **CloudWatch** | None | Basic ($3-5) | Basic ($3-5) | +$3-5 |
| **EBS Storage** | 8GB ($0.80) | 2 × 20GB ($4.00) | 2 × 20GB ($4.00) | +$3.20 |
| **Total** | **~$9.30** | **~$99-111** | **~$81-93** | **+$72-84** |

### Cost Breakdown Details
```
ALB 비용 계산:
- 기본 시간당 요금: $0.0225/hour × 730 hours = $16.43
- 신규 연결 LCU: 25 connections/sec = 0.025 LCU
- 활성 연결 LCU: 3,000 concurrent = 0.1 LCU  
- 처리 데이터 LCU: 1GB/hour = 1 LCU
- 규칙 평가 LCU: 1,000 rules/sec = 0.01 LCU
- 총 LCU: ~1.135 LCU × $0.008 × 730 = ~$6.63
- 월 총 ALB 비용: $16.43 + $6.63 = ~$23.06
```

### Cost Optimization Strategies
1. **Reserved Instances**: 1년 약정 시 30%, 3년 약정 시 50% 절감
2. **Savings Plans**: Compute Savings Plans로 27% 절감
3. **Spot Instances**: 개발/스테이징 환경에서 70% 절감
4. **ALB Idle Connection Timeout**: 연결 시간 최적화로 LCU 절감
5. **CloudWatch Logs Retention**: 로그 보관 기간 조정으로 비용 절감

---

## Risk Assessment & Mitigation (Enhanced)

### High Priority Risks

#### 1. **Migration Downtime**
- **Risk**: 마이그레이션 중 서비스 중단
- **Mitigation**:
    - Blue-green 마이그레이션 전략 (기존 시스템 유지)
    - DNS TTL 60초로 감소 (마이그레이션 1주일 전)
    - 트래픽 가중치 기반 점진적 전환
    - 즉시 롤백 가능한 스크립트 준비

#### 2. **Docker Removal Impact** (신규 추가)
- **Risk**: 컨테이너 제거 시 프로세스 격리 수준 감소
- **Mitigation**:
    - 단계적 접근: Docker 유지 → PM2 전환 → ECS 마이그레이션
    - 각 단계별 성능/안정성 검증
    - 컨테이너 기반 백업 환경 유지

#### 3. **Application Compatibility**
- **Risk**: Docker 없이 Node.js 앱 동작 변경
- **Mitigation**:
    - 스테이징 환경에서 최소 2주 테스트
    - 프로세스 매니저 설정 검증
    - 헬스 체크 엔드포인트 다층 검증
    - 환경 변수 관리 시스템 구축

#### 4. **AWS Service Dependencies**
- **Risk**: ALB 또는 CodeDeploy 서비스 이슈
- **Mitigation**:
    - Multi-AZ 배포 필수
    - CloudWatch 알람 및 SNS 알림
    - 수동 배포 절차 문서화
    - AWS Personal Health Dashboard 모니터링

### Medium Priority Risks

#### 5. **Cost Overrun**
- **Risk**: 예상보다 10배 높은 비용 증가
- **Mitigation**:
    - Reserved Instance 즉시 구매 검토
    - 자동 스케일링 정책 세밀 조정
    - AWS Cost Explorer 일일 모니터링
    - 예산 알림 설정 ($100 초과 시)

#### 6. **Team Learning Curve**
- **Risk**: AWS 서비스 미숙련
- **Mitigation**:
    - AWS 교육 세션 (주 2회, 4주간)
    - 상세 런북 및 트러블슈팅 가이드
    - 페어 운영 (숙련자 + 신규 담당자)
    - Slack 채널 통한 실시간 지원

---

## Implementation Timeline (Revised)

### Week 0: Strategic Decisions
- [ ] Docker 유지 vs 제거 결정
- [ ] ECS/EKS 장기 전략 수립
- [ ] 비용 승인 및 예산 확보
- [ ] 팀 역할 및 책임 할당

### Week 1: Infrastructure Setup
- [ ] AWS 계정 설정 및 IAM 권한
- [ ] VPC, 서브넷, 보안 그룹 생성
- [ ] ALB 및 타겟 그룹 구성
- [ ] EC2 인스턴스 시작 및 기본 설정

### Week 2: Application Migration
- [ ] 헬스 체크 엔드포인트 구현 (심층)
- [ ] NGINX 구성 (내부 로드 밸런싱)
- [ ] PM2/Docker 프로세스 관리 설정
- [ ] 로컬 테스트 환경 검증

### Week 3: Hybrid CI/CD Integration
- [ ] CodeDeploy 애플리케이션 및 배포 그룹
- [ ] S3 버킷 (배포 아티팩트)
- [ ] GitLab CI/CD 파이프라인 하이브리드 구성
- [ ] 스테이징 환경 병렬 운영 시작

### Week 4: Testing & Validation
- [ ] 스테이징 환경 종단 간 테스트
- [ ] 다중 인스턴스 부하 테스트 (JMeter/K6)
- [ ] Blue-green 배포 검증 (10회 이상)
- [ ] 성능 벤치마킹 및 비교 분석

### Week 5: Production Migration
- [ ] DNS 준비 (TTL 60초 설정)
- [ ] 프로덕션 배포 (Blue 환경)
- [ ] 트래픽 점진적 마이그레이션 (10% → 50% → 100%)
- [ ] 24시간 모니터링 및 안정화

### Week 6: Optimization & ECS Planning
- [ ] 자동 스케일링 구성 및 테스트
- [ ] 비용 최적화 검토 (RI 구매)
- [ ] 문서 업데이트 및 팀 교육
- [ ] ECS/EKS 마이그레이션 PoC 시작

---

## Success Metrics

### Performance Metrics
- **Zero downtime**: 배포 중 99.99% 가용성
- **Response time**: 평균 응답 시간 < 200ms (P95 < 500ms)
- **Scalability**: 동시 사용자 4배 지원 (검증됨)
- **Deployment time**: 전체 배포 < 10분
- **Health check latency**: < 100ms

### Operational Metrics
- **MTTR**: 평균 복구 시간 < 5분
- **Deployment frequency**: 일일 배포 가능
- **Error rate**: 애플리케이션 오류율 < 0.1%
- **Cost efficiency**: 요청당 비용 최적화 (목표: $0.00001/request)
- **Team readiness**: 팀원 100% AWS 기본 교육 완료

---

## Immediate Actions & Long-term Strategy

### Immediate Actions (Week 1)
1. **Container 전략 결정 회의**: Docker 유지/제거 최종 결정
2. **스테이징 환경 구축**: 완전한 스테이징 복제본 구축
3. **팀 교육 시작**: AWS 서비스 교육 즉시 시작
4. **비용 모니터링**: 빌링 알림 및 예산 설정
5. **마이그레이션 런북**: 상세 절차서 작성 시작

### Mid-term Goals (3-6 months)
1. **하이브리드 운영 안정화**: GitLab + CodeDeploy 병행 운영
2. **자동 스케일링 최적화**: 트래픽 패턴 기반 정책 조정
3. **모니터링 고도화**: APM 도구 통합 (DataDog/New Relic)
4. **비용 최적화**: Reserved Instance 및 Savings Plans 적용

### Long-term Strategy (6-12 months)
1. **ECS 마이그레이션**:
    - Fargate 기반 서버리스 컨테이너 운영
    - Blue-Green 배포 자동화 강화
    - 컨테이너 이미지 버전 관리
2. **Multi-region 확장**: DR 및 글로벌 서비스 준비
3. **Kubernetes 검토**: EKS 도입 타당성 평가
4. **Serverless 컴포넌트**: Lambda + API Gateway 부분 적용

### Alternative Approaches

#### Alternative 1: Gradual Hybrid Migration
```
Phase 1: Docker 유지 + ALB 도입 (Risk: Low, Cost: Medium)
Phase 2: CodeDeploy 통합 (Risk: Medium, Cost: Low)
Phase 3: Native 프로세스 전환 (Risk: High, Cost: Low)
Phase 4: ECS 마이그레이션 (Risk: Medium, Cost: Medium)
```

#### Alternative 2: Direct ECS Migration
```
장점:
- 컨테이너 격리 유지
- AWS 네이티브 오케스트레이션
- 장기적 관점에서 최적

단점:
- 높은 초기 학습 곡선
- 마이그레이션 복잡도 증가
- 초기 비용 상승
```

#### Alternative 3: Kubernetes on EKS
```
고려사항:
- 최고 수준의 유연성
- 벤더 종속성 감소
- 복잡한 운영 요구사항
- 팀 전문성 필요
```

---

## Deployment Scripts (Enhanced)

### prepare-environment.sh
```bash
#!/bin/bash
# CodeDeploy BeforeInstall Hook

echo "Preparing deployment environment..."

# 디렉터리 생성
mkdir -p /opt/bluegreen-app/{logs,temp,config}
mkdir -p /var/log/bluegreen

# 이전 배포 백업
if [ -d "/opt/bluegreen-app/current" ]; then
    mv /opt/bluegreen-app/current /opt/bluegreen-app/backup-$(date +%Y%m%d-%H%M%S)
fi

# 권한 설정
chown -R ec2-user:ec2-user /opt/bluegreen-app
chmod 755 /opt/bluegreen-app

echo "Environment preparation completed"
```

### validate-deployment.sh
```bash
#!/bin/bash
# CodeDeploy ValidateService Hook

echo "Starting deployment validation..."

# 심층 헬스 체크
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health/deep)
    
    if [ "$HEALTH_RESPONSE" = "200" ]; then
        echo "Health check passed"
        
        # 추가 검증: 애플리케이션 응답 확인
        APP_VERSION=$(curl -s http://localhost/api/version)
        echo "Deployed version: $APP_VERSION"
        
        # CloudWatch 메트릭 전송
        aws cloudwatch put-metric-data \
            --namespace "BlueGreen/Deployment" \
            --metric-name "DeploymentSuccess" \
            --value 1 \
            --dimensions Environment=Production,Version=$APP_VERSION
        
        exit 0
    fi
    
    echo "Health check attempt $((RETRY_COUNT+1))/$MAX_RETRIES failed. Retrying..."
    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 5
done

echo "Deployment validation failed after $MAX_RETRIES attempts"
exit 1
```

---

## Conclusion

단일 EC2에서 듀얼 EC2 + AWS ALB 아키텍처로의 마이그레이션은 확장성, 가용성, 운영 효율성 요구사항을 해결하는 중요한 인프라 개선입니다. 비용이 약 10배 증가하지만 (실제 최적화 시 8-9배), 확장성, 신뢰성, 운영 능력 측면에서의 이점이 투자를 정당화합니다.

**핵심 성공 요소:**
1. **단계적 접근**: Docker 유지 → Native Process → ECS 순차 전환
2. **하이브리드 운영**: GitLab CI/CD와 CodeDeploy 병행 기간 설정
3. **철저한 헬스 체크**: ALB에서 애플리케이션까지 관통하는 심층 검증
4. **비용 최적화**: Reserved Instance 및 자동 스케일링 적극 활용
5. **팀 준비도**: AWS 교육 및 문서화 선행

**즉시 시작해야 할 사항:**
1. Container 전략 (Docker 유지/제거) 최종 결정
2. 스테이징 환경 AWS 인프라 구축 시작
3. 팀 AWS 교육 프로그램 시작
4. 상세 마이그레이션 런북 작성
5. ECS/EKS PoC 환경 구성

**예상 결과:**
- 4배 이상의 트래픽 처리 능력
- 99.99% 가용성 달성
- 일일 배포 가능한 CI/CD 파이프라인
- 자동 스케일링을 통한 비용 효율성
- 장기적 클라우드 네이티브 전환 기반 마련

---

*이 보고서는 개발팀 및 운영팀과 함께 검토한 후 실행에 착수해야 합니다. 특히 Docker 유지/제거 결정과 ECS 마이그레이션 타이밍은 비즈니스 요구사항과 팀 역량을 고려하여 결정되어야 합니다.*

---

## Appendix A: AWS Resource Checklist

### Required AWS Services
- [ ] EC2 (t3.medium × 2)
- [ ] Application Load Balancer
- [ ] Target Groups (Blue/Green)
- [ ] CodeDeploy
- [ ] S3 (Deployment artifacts)
- [ ] CloudWatch (Monitoring)
- [ ] IAM Roles & Policies
- [ ] VPC & Security Groups
- [ ] Auto Scaling Groups (Optional)
- [ ] Route 53 (DNS)

### Required IAM Roles
```json
{
  "CodeDeployEC2Role": {
    "Policies": [
      "AmazonEC2RoleforAWSCodeDeploy",
      "CloudWatchLogsFullAccess",
      "AmazonS3ReadOnlyAccess"
    ]
  },
  "CodeDeployServiceRole": {
    "Policies": [
      "AWSCodeDeployRole",
      "AutoScalingFullAccess"
    ]
  },
  "GitLabCIRole": {
    "Policies": [
      "AWSCodeDeployDeployerAccess",
      "AmazonS3FullAccess",
      "ElasticLoadBalancingFullAccess"
    ]
  }
}
```