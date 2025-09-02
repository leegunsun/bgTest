# GitLab Runner를 통한 EC2 블루-그린 배포 전략 가이드

> **단일 EC2 서버에서 4대 스프링 부트 서버 블루-그린 배포**  
> GitLab CI/CD | nginx 트래픽 스위칭 | 무중단 배포 | 자동 롤백

## 📋 목차
1. [개요](#개요)
2. [아키텍처 설계](#아키텍처-설계)
3. [인프라 구성](#인프라-구성)
4. [GitLab Runner 설정](#gitlab-runner-설정)
5. [nginx 설정 전략](#nginx-설정-전략)
6. [CI/CD 파이프라인 설계](#cicd-파이프라인-설계)
7. [배포 전략 구현](#배포-전략-구현)
8. [모니터링 및 롤백](#모니터링-및-롤백)
9. [운영 가이드](#운영-가이드)

---

## 개요

### 🎯 프로젝트 목적
기존 Gradle 기반 Spring Boot 개발 환경을 유지하면서 GitLab Runner를 통한 블루-그린 배포 시스템으로 업그레이드

**기존 환경 특성:**
- Gradle 빌드 시스템
- JDK 19 (eclipse-temurin:19)
- SSH 기반 배포
- ubuntu 사용자 및 기존 경로 구조 유지

### 🏗️ 핵심 요구사항
- **기존 환경 유지**: Gradle + JDK 19 + ubuntu 사용자
- **단일 EC2 서버**: 비용 효율적인 배포 환경
- **2대 스프링 부트 서버**: 1개 블루 + 1개 그린 구성
- **기존 경로 활용**: /home/ubuntu/dev/woori_be/ 구조 유지
- **GitLab CI/CD**: 기존 SSH 키 및 변수 활용
- **무중단 배포**: 블루-그린 전환으로 다운타임 제거

### 🔑 핵심 혜택
- ✅ **Zero Downtime**: 서비스 중단 없는 배포
- ✅ **Risk Mitigation**: 즉시 롤백 가능한 안전한 배포
- ✅ **Cost Efficiency**: 단일 EC2로 운영 비용 최소화
- ✅ **Automated CI/CD**: 수동 작업 제거로 인적 오류 방지
- ✅ **Production Ready**: 실제 운영 환경에 적용 가능한 견고한 아키텍처

---



## 아키텍처 설계

### 🏗️ 전체 시스템 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS EC2 Instance                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │   nginx     │  │ GitLab      │  │ Deployment  │  │ Monitoring  │ │
│  │   (Port 80) │  │ Runner      │  │ API         │  │ Agent       │ │
│  │             │  │             │  │ (Port 9000) │  │             │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │
│                                                                    │
│  ┌─────────────────────────────┐  ┌─────────────────────────────┐   │
│  │        BLUE Environment     │  │       GREEN Environment     │   │
│  │  ┌─────────────────────┐   │  │  ┌─────────────────────┐   │   │
│  │  │     Spring Boot     │   │  │  │     Spring Boot     │   │   │
│  │  │     (Gradle)       │   │  │  │     (Gradle)       │   │   │
│  │  │     Port: 8081     │   │  │  │     Port: 8083     │   │   │
│  │  └─────────────────────┘   │  │  └─────────────────────┘   │   │
│  └─────────────────────────────┘  └─────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 🔄 블루-그린 배포 플로우

```
GitLab Repository → GitLab Runner → Build → Test → Deploy to GREEN → 
Health Check → Traffic Switch (nginx) → Monitor → Cleanup BLUE
```

### 📊 서비스 포트 매핑

| 서비스 | 환경 | 포트 | 역할 | 상태 |
|--------|------|------|------|------|
| **nginx** | 공통 | 80 | 메인 프록시 (선택사항) | 조건부 활성 |
| **Spring Boot Blue** | BLUE | 8081 | 블루 환경 서버 | 조건부 활성 |
| **Spring Boot Green** | GREEN | 8083 | 그린 환경 서버 | 조건부 활성 |

**배포 경로:**
- Blue: `/home/ubuntu/dev/woori_be/blue/`
- Green: `/home/ubuntu/dev/woori_be/green/`
- Deployment: `/home/ubuntu/dev/woori_be/deployment/`

---

## 인프라 구성

### 🖥️ EC2 인스턴스 요구사항

#### 권장 인스턴스 타입 (기존 환경 고려)
```yaml
Instance Type: t3.medium 또는 t3.large
- CPU: 2-4 vCPUs (기존 단일 앱 → 2개 앱으로 확장)
- Memory: 4-8 GB
- Storage: 50-100 GB (기존보다 약간 증가)
- Network: Up to 5 Gbps
- 추정 월 비용: ~$30-60 (기존 환경 대비 소폭 증가)
```

#### 보안 그룹 설정
```yaml
Inbound Rules:
  - Port 22:   SSH (관리용)
  - Port 80:   HTTP (메인 트래픽)
  - Port 443:  HTTPS (SSL 적용 시)
  - Port 9000: Deployment API (내부 네트워크만)

Outbound Rules:
  - All traffic allowed (패키지 설치, GitLab 통신)
```

### 🐧 EC2 서버 초기 설정

#### 1. 기본 패키지 설치
```bash
#!/bin/bash
# 시스템 업데이트
sudo apt update && sudo apt upgrade -y

# 필수 패키지 설치
sudo apt install -y nginx openjdk-17-jdk maven git curl wget unzip

# Docker 설치 (GitLab Runner용)
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER

# nginx 서비스 활성화
sudo systemctl enable nginx
sudo systemctl start nginx
```

#### 2. 블루-그린 디렉토리 구조 생성 (기존 경로 확장)
```bash
# 기존 경로에 블루-그린 구조 추가
cd /home/ubuntu/dev/woori_be/
sudo mkdir -p {blue,green,deployment}

# 권한 설정 (기존 ubuntu 사용자 유지)
sudo chown -R ubuntu:ubuntu /home/ubuntu/dev/woori_be/
chmod 755 /home/ubuntu/dev/woori_be/{blue,green,deployment}

# 로그 디렉토리 생성
mkdir -p /home/ubuntu/dev/woori_be/{blue,green}/logs
```

#### 3. 기존 사용자 권한 조정 (ubuntu 사용자 유지)
```bash
# 기존 ubuntu 사용자 권한 확장 (nginx 및 시스템 서비스 제어용)
# 필요한 경우에만 추가 - nginx가 설치되어 있다면
echo "ubuntu ALL=(ALL) NOPASSWD: /usr/sbin/nginx -s reload, /usr/sbin/nginx -t" | sudo tee /etc/sudoers.d/ubuntu-nginx

# SSH 키는 기존 설정 유지
# GitLab Variables의 AWS_PEM_DEV 키를 계속 사용
# 추가 설정 불필요
```

---

## GitLab Runner 설정

### 🏃‍♂️ GitLab Runner 설정 (선택사항 - 기존 구조 활용)

#### GitLab CI/CD 실행 방식 선택

**옵션 1: 기존 방식 유지 (권장)**
- GitLab.com의 Shared Runner 사용
- 별도 GitLab Runner 설치 불필요
- 기존 CI/CD 파이프라인과 동일한 방식

**옵션 2: 전용 Runner 설치 (고급 사용자)**
```bash
# GitLab Runner 설치 (필요시)
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
sudo apt-get update
sudo apt-get install gitlab-runner

# Docker executor 등록 (JDK 19 사용)
sudo gitlab-runner register \
  --url "https://gitlab.com/" \
  --registration-token "YOUR_PROJECT_TOKEN" \
  --executor "docker" \
  --docker-image "eclipse-temurin:19" \
  --description "EC2-BlueGreen-Gradle-Runner" \
  --tag-list "ec2,blue-green,gradle,spring-boot"
```

#### 2. Runner 설정 최적화
```toml
# /etc/gitlab-runner/config.toml
concurrent = 2
check_interval = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = "EC2-BlueGreen-Runner"
  url = "https://gitlab.com/"
  token = "YOUR_TOKEN"
  executor = "docker"
  [runners.docker]
    tls_verify = false
    image = "openjdk:17-jdk-alpine"
    privileged = true
    disable_cache = false
    volumes = ["/var/run/docker.sock:/var/run/docker.sock", "/cache"]
    shm_size = 0
  [runners.cache]
    Type = "local"
    Path = "/opt/gitlab-runner/cache"
    MaxUploadedArchiveSize = 0
```

### 🔐 보안 설정 (기존 변수 활용)

#### GitLab Variables 설정 (기존 변수 유지 + 추가)
GitLab 프로젝트에서 Settings → CI/CD → Variables에 기존 변수 유지하고 필요시 추가:

```yaml
# 기존 변수 (그대로 유지)
Variables:
  DEPLOY_SERVER_DEV: "your-ec2-ip"        # 기존 변수명 유지
  AWS_PEM_DEV: "-----BEGIN PRIVATE KEY-----..." # 기존 SSH 키 유지
  DEV_ENV_FILE: ".env 파일 내용"           # 기존 환경 설정
  DEV_APPLICATION: "application.yml 내용"  # 기존 스프링 설정
  
# 블루-그린 배포용 추가 변수 (선택사항)
  BLUE_GREEN_ENABLED: "true"              # 블루-그린 모드 활성화
  HEALTH_CHECK_TIMEOUT: "300"             # 헬스체크 타임아웃
```

#### SSH 키 설정 (기존 유지)
```bash
# 기존 SSH 키 그대로 사용
# AWS_PEM_DEV 변수에 저장된 키를 계속 활용
# 추가 SSH 키 생성 불필요

# 기존 연결 테스트
ssh -i your-existing-key.pem ubuntu@$DEPLOY_SERVER_DEV "echo 'Connection test successful'"
```

---

## nginx 설정 전략 (선택사항)

### 🌐 nginx 설정 개요

**중요**: nginx 설정은 선택사항입니다. nginx가 설치되어 있지 않은 경우 각 환경에 직접 접근할 수 있습니다:
- Blue 환경: `http://your-server:8081`
- Green 환경: `http://your-server:8083`

### nginx 설치 및 기본 설정 (필요시)

#### 1. nginx 설치
```bash
# nginx 설치 (Ubuntu)
sudo apt update
sudo apt install -y nginx

# nginx 서비스 시작
sudo systemctl enable nginx
sudo systemctl start nginx
```

#### 2. 기본 설정 파일: `/etc/nginx/sites-available/default`
```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    # 메인 애플리케이션 라우팅 (기본: Blue 환경)
    location / {
        proxy_pass http://localhost:8081;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 타임아웃 설정
        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # 헬스체크 엔드포인트
    location /health {
        proxy_pass http://localhost:8081/actuator/health;
        proxy_set_header Host $host;
    }
    
    # Blue 환경 직접 액세스 (디버깅용)
    location /blue/ {
        proxy_pass http://localhost:8081/;
        proxy_set_header Host $host;
    }
    
    # Green 환경 직접 액세스 (디버깅용)
    location /green/ {
        proxy_pass http://localhost:8083/;
        proxy_set_header Host $host;
    }
}
```

### 트래픽 전환 방법 (nginx 사용시)

#### 수동 트래픽 전환
```bash
# Blue 환경으로 전환 (포트 8081)
sudo sed -i 's/proxy_pass http:\/\/localhost:[0-9]*;/proxy_pass http:\/\/localhost:8081;/g' /etc/nginx/sites-available/default
sudo nginx -t && sudo nginx -s reload

# Green 환경으로 전환 (포트 8083)
sudo sed -i 's/proxy_pass http:\/\/localhost:[0-9]*;/proxy_pass http:\/\/localhost:8083;/g' /etc/nginx/sites-available/default
sudo nginx -t && sudo nginx -s reload
```

### nginx 없이 직접 접근하는 방법 (권장)

환경별 직접 접근을 통해 더 간단하게 운영할 수 있습니다:

```yaml
# 환경별 접근 URL
Blue 환경:
  - URL: http://your-server:8081
  - Health: http://your-server:8081/actuator/health
  
Green 환경:
  - URL: http://your-server:8083
  - Health: http://your-server:8083/actuator/health
```

#### 로드밸런서나 클라우드 서비스 활용
```yaml
# AWS ALB/ELB 설정 예시
Target Groups:
  Blue:
    - Target: EC2-Instance:8081
    - Health Check: /actuator/health
  
  Green:
    - Target: EC2-Instance:8083  
    - Health Check: /actuator/health

# 트래픽 전환: ALB 콘솔에서 Target Group 변경
```

### 🔄 트래픽 전환 방법

#### 1. nginx 사용시 (선택사항)
```bash
# Blue 환경으로 전환
sudo sed -i 's/proxy_pass http:\/\/localhost:[0-9]*;/proxy_pass http:\/\/localhost:8081;/g' /etc/nginx/sites-available/default
sudo nginx -t && sudo nginx -s reload
echo "Traffic switched to Blue (port 8081)"

# Green 환경으로 전환  
sudo sed -i 's/proxy_pass http:\/\/localhost:[0-9]*;/proxy_pass http:\/\/localhost:8083;/g' /etc/nginx/sites-available/default
sudo nginx -t && sudo nginx -s reload
echo "Traffic switched to Green (port 8083)"
```

#### 2. 직접 접근 방식 (권장)
```bash
# 각 환경에 직접 접근하여 사용
echo "Blue 환경: http://your-server:8081"
echo "Green 환경: http://your-server:8083"

# 클라이언트 애플리케이션에서 환경별 엔드포인트 설정
# 예: 로드밸런서나 DNS 설정으로 트래픽 전환
```

#### 3. AWS ALB/클라우드 로드밸런서 사용 (프로덕션 권장)
```yaml
# AWS ALB Target Group 설정 예시
Production-Blue:
  Targets: ["EC2-Instance:8081"]
  Health: "/actuator/health"
  
Production-Green:
  Targets: ["EC2-Instance:8083"]
  Health: "/actuator/health"
  
# ALB Listener Rules로 트래픽 전환
# 0% Blue / 100% Green → 트래픽 전환
```

---

## CI/CD 파이프라인 설계

### 📋 GitLab CI/CD 파이프라인 (기존 Gradle 기반 + 블루-그린)

⚠️ **주의**: 아래 파이프라인 대신 `Customized_BlueGreen_CI_CD_Pipeline.yml` 파일을 사용하세요.

```yaml
# Gradle 기반 Blue-Green Deployment 파이프라인
# 기존 개발 환경을 유지하면서 Blue-Green 배포 적용
variables:
  GIT_DEPTH: 0                              # 기존 설정 유지
  GRADLE_OPTS: "-Dorg.gradle.daemon=false"    # Gradle 최적화
  GRADLE_USER_HOME: "$CI_PROJECT_DIR/.gradle"

# Cache Gradle dependencies (기존 Maven → Gradle)
cache:
  key: "$CI_COMMIT_REF_NAME-gradle"
  paths:
    - .gradle/wrapper
    - .gradle/caches

stages:
  - build-dev                    # 기존 stage 이름 유지
  - test-dev
  - deploy-green-dev            # 블루-그린 배포용
  - health-check-dev
  - switch-traffic-dev
  - verify-dev
  - cleanup-dev

# Build Stage - 기존 Gradle 빌드 환경 유지
build-dev:
  stage: build-dev
  image: eclipse-temurin:19      # 기존 JDK 19 유지
  before_script:
    - chmod +x ./gradlew         # 기존 설정 유지
  script:
    - echo "🔨 Building Spring Boot application with Gradle..."
    - cp $DEV_ENV_FILE ./.env                    # 기존 환경 설정 유지
    - cp $DEV_APPLICATION ./src/main/resources/application.yml
    - ./gradlew clean build -x test             # Gradle 사용
    - cd build/libs/
    - mv woorishop_be-1.0-SNAPSHOT.jar woori_be.jar  # 표준화
  artifacts:
    expire_in: 1 hour
    paths:
      - ./build/libs/woori_be.jar  # 기존 target/ → build/libs/
      - ./.env
      - ./deploy-bluegreen.sh      # 블루-그린 스크립트
  only:
    - dev                        # 기존 브랜치 유지

# Test Stage - Gradle 테스트 실행
test-dev:
  stage: test-dev
  image: eclipse-temurin:19      # 기존 JDK 19 유지
  before_script:
    - chmod +x ./gradlew
  script:
    - echo "🧪 Running unit tests with Gradle..."
    - cp $DEV_ENV_FILE ./.env
    - cp $DEV_APPLICATION ./src/main/resources/application.yml
    - ./gradlew test             # Gradle 테스트
  artifacts:
    reports:
      junit:
        - build/test-results/test/TEST-*.xml  # Gradle 경로
    paths:
      - build/reports/tests/     # Gradle 리포트 경로
  dependencies:
    - build-dev
  only:
    - dev

# Security Scan Stage
security-scan:
  stage: security-scan
  image: maven:3.8.6-openjdk-17-slim
  script:
    - echo "🛡️ Running security scans..."
    - mvn dependency-check:check
  artifacts:
    reports:
      dependency_scanning: dependency-check-report.json
  allow_failure: true
  dependencies:
    - build

# Deploy to Green Environment - 기존 SSH 구조 활용
deploy-green-dev:
  stage: deploy-green-dev
  image: alpine:latest
  before_script:
    - "which ssh-agent || ( apk update && apk add openssh-client )"  # 기존 스타일 유지
    - mkdir -p ~/.ssh
    - eval $(ssh-agent -s)
    - chmod 600 $AWS_PEM_DEV                    # 기존 SSH 키 사용
    - ssh-add $AWS_PEM_DEV
    - echo -e "Host *\\n\\tStrictHostKeyChecking no\\n\\n" > ~/.ssh/config
  script:
    - echo "🚀 Deploying to GREEN environment..."
    
    # 1. 블루-그린 디렉토리 구조 생성 (한 번만 실행)
    - ssh ubuntu@$DEPLOY_SERVER_DEV "mkdir -p /home/ubuntu/dev/woori_be/{blue,green,deployment}"
    
    # 2. 배포 스크립트와 설정 파일 업로드
    - scp ./deploy-bluegreen.sh ubuntu@$DEPLOY_SERVER_DEV:/home/ubuntu/dev/woori_be/deployment/
    - scp ./.env ubuntu@$DEPLOY_SERVER_DEV:/home/ubuntu/dev/woori_be/green/
    
    # 3. JAR 파일 업로드 (기존 방식에서 Gradle 로 변경)
    - scp ./build/libs/woori_be.jar ubuntu@$DEPLOY_SERVER_DEV:/home/ubuntu/dev/woori_be/green/
    
    # 4. Green 환경 배포 실행 (블루-그린 스크립트 사용)
    - ssh ubuntu@$DEPLOY_SERVER_DEV "
        cd /home/ubuntu/dev/woori_be/deployment;
        chmod +x deploy-bluegreen.sh;
        ./deploy-bluegreen.sh deploy green;
      "
    
    - echo "GREEN environment deployment completed"
  environment:
    name: green-dev
    url: http://$DEPLOY_SERVER_DEV:8083     # Green 포트 직접 접근
  dependencies:
    - build-dev
    - test-dev
  only:
    - dev                                   # 기존 브랜치 유지

# Health Check Green Environment - 기존 인프라 활용
health-check-dev:
  stage: health-check-dev
  image: alpine:latest
  before_script:
    - apk add --no-cache openssh-client curl
    - mkdir -p ~/.ssh
    - eval $(ssh-agent -s)
    - chmod 600 $AWS_PEM_DEV                # 기존 SSH 키 사용
    - ssh-add $AWS_PEM_DEV
    - echo -e "Host *\\n\\tStrictHostKeyChecking no\\n\\n" > ~/.ssh/config
  script:
    - echo "🏥 Running health checks on GREEN environment..."
    
    # Wait for services to be ready
    - sleep 30
    
    # Health check script - 기존 서버 구조에 맞춰 조정
    - ssh ubuntu@$DEPLOY_SERVER_DEV "
        echo 'Checking GREEN services health...';
        
        # Check Green service (port 8083) - 단일 서버
        for i in {1..10}; do
          if curl -sf http://localhost:8083/actuator/health > /dev/null 2>&1; then
            echo '✓ Green service (8083) is healthy';
            break;
          fi;
          if [ \$i -eq 10 ]; then
            echo '✗ Green service health check failed';
            exit 1;
          fi;
          echo 'Attempt '\$i'/10 - waiting for service...';
          sleep 5;
        done;
        
        echo 'GREEN service is healthy';
      "
    
    - echo "Health check completed successfully"
  dependencies:
    - deploy-green-dev
  retry: 2

# Switch Traffic to Green - Manual Approval
switch-traffic-dev:
  stage: switch-traffic-dev
  image: alpine:latest
  when: manual                             # 수동 승인 요구
  before_script:
    - apk add --no-cache openssh-client
    - mkdir -p ~/.ssh
    - eval $(ssh-agent -s)
    - chmod 600 $AWS_PEM_DEV
    - ssh-add $AWS_PEM_DEV
    - echo -e "Host *\\n\\tStrictHostKeyChecking no\\n\\n" > ~/.ssh/config
  script:
    - echo "🔄 Switching traffic to GREEN environment..."
    
    # Execute traffic switch using deployment script
    - ssh ubuntu@$DEPLOY_SERVER_DEV "
        cd /home/ubuntu/dev/woori_be/deployment;
        ./deploy-bluegreen.sh switch green;
      "
    
    - echo "Traffic switched to GREEN environment"
    - echo "🎉 Production deployment completed!"
  environment:
    name: production-dev
    url: http://$DEPLOY_SERVER_DEV          # nginx 있으면 80포트, 없으면 8083
  dependencies:
    - health-check-dev

# Verify Production - 기존 검증 방식 유지
verify-dev:
  stage: verify-dev
  image: alpine:latest
  before_script:
    - apk add --no-cache curl
  script:
    - echo "✅ Verifying production deployment..."
    
    # Production health check - 기존 서버 사용
    - |
      for i in {1..5}; do
        # nginx가 있으면 80포트, 없으면 8083포트로 직접 테스트
        if curl -sf http://$DEPLOY_SERVER_DEV/actuator/health > /dev/null 2>&1 || curl -sf http://$DEPLOY_SERVER_DEV:8083/actuator/health > /dev/null 2>&1; then
          echo "✓ Production health check passed"
          break
        fi
        if [ $i -eq 5 ]; then
          echo "✗ Production health check failed"
          exit 1
        fi
        sleep 5
      done
    
    # Basic smoke tests
    - curl -sf http://$DEPLOY_SERVER_DEV > /dev/null 2>&1 || echo "Note: Basic connectivity test (nginx not configured yet)"
    - echo "✓ Verification completed"
    
    - echo "Production verification completed"
  dependencies:
    - switch-traffic-dev

# Cleanup Blue Environment - Manual
cleanup-dev:
  stage: cleanup-dev
  image: alpine:latest
  when: manual
  before_script:
    - apk add --no-cache openssh-client
    - mkdir -p ~/.ssh
    - eval $(ssh-agent -s)
    - chmod 600 $AWS_PEM_DEV
    - ssh-add $AWS_PEM_DEV
    - echo -e "Host *\\n\\tStrictHostKeyChecking no\\n\\n" > ~/.ssh/config
  script:
    - echo "🧹 Cleaning up BLUE environment..."
    
    - ssh ubuntu@$DEPLOY_SERVER_DEV "
        cd /home/ubuntu/dev/woori_be/deployment;
        ./deploy-bluegreen.sh cleanup blue;
      "
    
    - echo "BLUE environment cleanup completed"
  dependencies:
    - verify-dev

# Emergency Rollback Job - Manual
rollback-dev:
  stage: cleanup-dev
  image: alpine:latest
  when: manual
  before_script:
    - apk add --no-cache openssh-client
    - mkdir -p ~/.ssh
    - eval $(ssh-agent -s)
    - chmod 600 $AWS_PEM_DEV
    - ssh-add $AWS_PEM_DEV
    - echo -e "Host *\\n\\tStrictHostKeyChecking no\\n\\n" > ~/.ssh/config
  script:
    - echo "🔙 Rolling back to BLUE environment..."
    
    - ssh ubuntu@$DEPLOY_SERVER_DEV "
        cd /home/ubuntu/dev/woori_be/deployment;
        ./deploy-bluegreen.sh switch blue;
      "
    
    - echo "Rollback to BLUE environment completed"
  environment:
    name: production-dev
    url: http://$DEPLOY_SERVER_DEV
```

### 🔧 프로세스 관리 (systemd 없이)

#### 배포 스크립트 기반 프로세스 관리

**중요**: 기존 환경과의 호환성을 위해 systemd 서비스 대신 프로세스 직접 관리 방식을 사용합니다.

#### 프로세스 시작 예시 (deploy-bluegreen.sh 사용)
```bash
# Blue 환경 시작
cd /home/ubuntu/dev/woori_be/deployment
./deploy-bluegreen.sh deploy blue

# Green 환경 시작
./deploy-bluegreen.sh deploy green

# 환경 상태 확인
./deploy-bluegreen.sh status
```

#### 수동 프로세스 시작 (필요시)
```bash
# Blue 환경 (포트 8081)
cd /home/ubuntu/dev/woori_be/blue
nohup java -jar \
    -Dserver.port=8081 \
    -Dspring.profiles.active=dev,blue \
    -Xms512m -Xmx1024m \
    woori_be.jar \
    > app.log 2>&1 &
echo $! > app.pid

# Green 환경 (포트 8083)
cd /home/ubuntu/dev/woori_be/green
nohup java -jar \
    -Dserver.port=8083 \
    -Dspring.profiles.active=dev,green \
    -Xms512m -Xmx1024m \
    woori_be.jar \
    > app.log 2>&1 &
echo $! > app.pid
```

#### 프로세스 상태 확인
```bash
# 실행 중인 Java 프로세스 확인
ps aux | grep "woori_be.jar"

# 포트별 프로세스 확인
sudo netstat -tlnp | grep -E ':(8081|8083)'

# PID 파일로 프로세스 확인
if [ -f "/home/ubuntu/dev/woori_be/blue/app.pid" ]; then
    pid=$(cat /home/ubuntu/dev/woori_be/blue/app.pid)
    if kill -0 "$pid" 2>/dev/null; then
        echo "Blue environment is running (PID: $pid)"
    else
        echo "Blue environment is not running"
    fi
fi
```

#### 프로세스 종료
```bash
# PID 파일을 이용한 종료
if [ -f "/home/ubuntu/dev/woori_be/blue/app.pid" ]; then
    kill -TERM $(cat /home/ubuntu/dev/woori_be/blue/app.pid)
fi

# 포트 기반으로 프로세스 종료
pkill -f "woori_be.jar.*server.port=8081"
pkill -f "woori_be.jar.*server.port=8083"

# 강제 종료 (필요시)
pkill -9 -f "woori_be.jar"
```

#### 로그 확인
```bash
# Blue 환경 로그
tail -f /home/ubuntu/dev/woori_be/blue/app.log

# Green 환경 로그
tail -f /home/ubuntu/dev/woori_be/green/app.log

# 모든 환경 로그 동시 확인
tail -f /home/ubuntu/dev/woori_be/*/app.log
```

---

## 배포 전략 구현

### 🚀 배포 프로세스 플로우

```
1. [개발자] 코드 커밋 → dev 브랜치 (기존 방식 유지)
2. [GitLab] 자동 빌드 & 테스트 실행 (Gradle + JDK 19)
3. [GitLab] Green 환경에 자동 배포 (deploy-bluegreen.sh 사용)
4. [GitLab] Green 환경 헬스체크 수행 (Spring Actuator)
5. [운영자] 수동 승인으로 트래픽 전환
6. [System] 트래픽 전환 (nginx 또는 직접 접근)
7. [GitLab] 프로덕션 검증 실행
8. [운영자] Blue 환경 정리 (선택사항)
```

### 🔄 트래픽 전환 메커니즘

#### 1. 현재 상태 확인
```bash
# 현재 활성 환경 확인 (deploy-bluegreen.sh 사용)
cd /home/ubuntu/dev/woori_be/deployment
./deploy-bluegreen.sh status

# 프로세스 상태 확인
ps aux | grep "woori_be.jar"
sudo netstat -tlnp | grep -E ':(8081|8083)'
```

#### 2. 헬스체크 실행
```bash
# 배포 스크립트를 통한 헬스체크
cd /home/ubuntu/dev/woori_be/deployment
./deploy-bluegreen.sh status

# 직접 헬스체크
curl -sf http://localhost:8081/actuator/health  # Blue 환경
curl -sf http://localhost:8083/actuator/health  # Green 환경
```

#### 3. 트래픽 전환 실행
```bash
# 배포 스크립트를 통한 트래픽 전환
cd /home/ubuntu/dev/woori_be/deployment

# Green으로 전환
./deploy-bluegreen.sh switch green

# Blue로 롤백
./deploy-bluegreen.sh switch blue
```

### 📊 배포 상태 모니터링

#### 배포 상태 모니터링 (선택사항)

**중요**: 배포 스크립트에서 기본적인 상태 모니터링 기능을 제공합니다.

#### 배포 스크립트로 상태 확인
```bash
# 전체 시스템 상태 확인
cd /home/ubuntu/dev/woori_be/deployment
./deploy-bluegreen.sh status

# 결과 예시:
# === Blue-Green Deployment Status ===
# Current active environment: blue
# 
# === blue Environment (Port 8081) ===
# Status: RUNNING
# PID: 12345
# Health: HEALTHY
# JAR Date: 2025-01-15 10:30:15
# 
# === green Environment (Port 8083) ===
# Status: STOPPED
```

#### REST API 방식 모니터링 (선택사항)

필요한 경우 간단한 API를 만들어 외부에서 모니터링할 수 있습니다:

```bash
#!/bin/bash
# /home/ubuntu/dev/woori_be/deployment/status-api.sh
# 간단한 HTTP API 서버 (검증용)

echo "Content-Type: application/json"
echo ""

# Blue 환경 상태
if pgrep -f "woori_be.jar.*server.port=8081" > /dev/null; then
    BLUE_STATUS="running"
else
    BLUE_STATUS="stopped"
fi

# Green 환경 상태
if pgrep -f "woori_be.jar.*server.port=8083" > /dev/null; then
    GREEN_STATUS="running"
else
    GREEN_STATUS="stopped"
fi

# JSON 응답
cat << EOF
{
  "timestamp": "$(date -Iseconds)",
  "environments": {
    "blue": {
      "status": "$BLUE_STATUS",
      "port": 8081
    },
    "green": {
      "status": "$GREEN_STATUS",
      "port": 8083
    }
  }
}
EOF
```

---

## 모니터링 및 롤백

### 📈 모니터링 전략

#### 1. 애플리케이션 로그 모니터링
```bash
# Blue 환경 로그 실시간 확인
tail -f /home/ubuntu/dev/woori_be/blue/app.log

# Green 환경 로그 실시간 확인
tail -f /home/ubuntu/dev/woori_be/green/app.log

# 모든 환경 로그 동시 확인
tail -f /home/ubuntu/dev/woori_be/*/app.log

# nginx 로그 확인 (설치된 경우)
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

#### 2. 시스템 리소스 모니터링
```bash
# Java 프로세스 CPU, 메모리 사용률
top -p $(pgrep -f "woori_be.jar")

# 디스크 사용률
df -h

# 네트워크 연결 상태 (2개 포트만)
netstat -tlnp | grep -E ':(8081|8083)'

# 메모리 사용량 상세 정보
ps aux | grep "woori_be.jar" | grep -v grep
```

#### 3. 헬스체크 모니터링
```bash
#!/bin/bash
# /home/ubuntu/dev/woori_be/deployment/health-monitor.sh

ENDPOINTS=(
    "http://localhost:8081/actuator/health"  # Blue 환경
    "http://localhost:8083/actuator/health"  # Green 환경
)

# nginx가 설치된 경우 추가
if command -v nginx >/dev/null 2>&1; then
    ENDPOINTS+=("http://localhost/health")
fi

echo "=== Health Check Report ==="
for endpoint in "${ENDPOINTS[@]}"; do
    if curl -sf "$endpoint" > /dev/null 2>&1; then
        echo "✓ $endpoint - HEALTHY"
    else
        echo "✗ $endpoint - UNHEALTHY"
    fi
done

echo ""
echo "=== Process Status ==="
if pgrep -f "woori_be.jar.*server.port=8081" > /dev/null; then
    echo "✓ Blue environment (8081) - RUNNING"
else
    echo "✗ Blue environment (8081) - STOPPED"
fi

if pgrep -f "woori_be.jar.*server.port=8083" > /dev/null; then
    echo "✓ Green environment (8083) - RUNNING"
else
    echo "✗ Green environment (8083) - STOPPED"
fi
```

### 🔄 자동 롤백 메커니즘

#### 1. 헬스체크 기반 자동 롤백
```bash
#!/bin/bash
# /home/ubuntu/dev/woori_be/deployment/auto-rollback.sh

CURRENT_ENV=$(cat /home/ubuntu/dev/woori_be/deployment/active_env 2>/dev/null || echo "blue")
PREVIOUS_ENV="blue"
[[ "$CURRENT_ENV" == "blue" ]] && PREVIOUS_ENV="green"

echo "현재 환경: $CURRENT_ENV, 이전 환경: $PREVIOUS_ENV"

# 5회 연속 헬스체크 실패 시 롤백
FAIL_COUNT=0
MAX_FAILS=5

# 헬스체크 포트 결정
if [[ "$CURRENT_ENV" == "blue" ]]; then
    HEALTH_PORT=8081
else
    HEALTH_PORT=8083
fi

echo "모니터링 시작: 포트 $HEALTH_PORT 헬스체크"

while true; do
    if curl -sf "http://localhost:$HEALTH_PORT/actuator/health" > /dev/null; then
        FAIL_COUNT=0
        echo "$(date): 헬스체크 성공 (포트 $HEALTH_PORT)"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "$(date): 헬스체크 실패 ($FAIL_COUNT/$MAX_FAILS) - 포트 $HEALTH_PORT"
        
        if [[ $FAIL_COUNT -ge $MAX_FAILS ]]; then
            echo "$(date): 자동 롤백 실행 - $PREVIOUS_ENV 환경으로 전환"
            cd /home/ubuntu/dev/woori_be/deployment
            ./deploy-bluegreen.sh switch "$PREVIOUS_ENV"
            
            # 알림 발송 (선택사항 - Slack Webhook URL 설정 시)
            # curl -X POST -H 'Content-type: application/json' \
            #     --data '{"text":"🚨 자동 롤백 실행됨: '"$CURRENT_ENV"' → '"$PREVIOUS_ENV"'"}' \
            #     YOUR_SLACK_WEBHOOK_URL
            
            break
        fi
    fi
    
    sleep 30
done
```

#### 2. GitLab CI를 통한 원격 롤백

기존 CI/CD 파이프라인에 롤백 Job이 이미 포함되어 있습니다:

```yaml
# rollback-dev job (Customized_BlueGreen_CI_CD_Pipeline.yml에 이미 포함)
rollback-dev:
  stage: cleanup-dev
  image: alpine:latest
  when: manual  # 수동 실행
  before_script:
    - apk add --no-cache openssh-client
    - mkdir -p ~/.ssh
    - eval $(ssh-agent -s)
    - chmod 600 $AWS_PEM_DEV
    - ssh-add $AWS_PEM_DEV
    - echo -e "Host *\\n\\tStrictHostKeyChecking no\\n\\n" > ~/.ssh/config
  script:
    - echo "🔙 Rolling back to BLUE environment..."
    - ssh ubuntu@$DEPLOY_SERVER_DEV "
        cd /home/ubuntu/dev/woori_be/deployment;
        ./deploy-bluegreen.sh switch blue;
      "
    - echo "Rollback to BLUE environment completed"
  environment:
    name: production-dev
    url: http://$DEPLOY_SERVER_DEV
```

#### 수동 롤백 절차
```bash
# SSH로 직접 서버 접속
ssh -i your-key.pem ubuntu@$DEPLOY_SERVER_DEV

# 롤백 실행
cd /home/ubuntu/dev/woori_be/deployment
./deploy-bluegreen.sh switch blue

# 상태 확인
./deploy-bluegreen.sh status
```

### ⚠️ 장애 대응 시나리오

#### 시나리오 1: Green 환경 배포 실패
```
상황: Green 환경 배포 중 서비스 시작 실패
대응: 
1. 배포 파이프라인 자동 중단 (GitLab CI/CD)
2. Blue 환경 유지 (트래픽 전환하지 않음)
3. Green 환경 로그 분석: tail -f /home/ubuntu/dev/woori_be/green/app.log
4. 문제 해결 후 재배포
```

#### 시나리오 2: 트래픽 전환 후 성능 저하
```
상황: Green으로 전환 후 성능 저하 또는 오류 발생
대응:
1. 즐시 롤백 실행: ./deploy-bluegreen.sh switch blue
2. Blue 환경으로 즉시 복원
3. Green 환경 로그 분석: tail -f /home/ubuntu/dev/woori_be/green/app.log
4. 원인 파악 및 수정 후 재배포
```

#### 시나리오 3: nginx 설정 오류
```
상황: nginx 설정 오류 또는 네트워크 문제
대응:
1. nginx가 설치된 경우: sudo nginx -t → 설정 검증
2. nginx 재시작: sudo systemctl restart nginx
3. nginx 없이 직접 접근: http://server:8081 (Blue), http://server:8083 (Green)
4. 로드밸런서/CDN 설정 확인
```

---

## 운영 가이드

### 🚀 일상 운영 절차

#### 1. 일상 배포 절차
```bash
# 1. 사전 점검
cd /home/ubuntu/dev/woori_be/deployment
./deploy-bluegreen.sh status

# 2. 현재 상태 확인
ps aux | grep "woori_be.jar"
netstat -tlnp | grep -E ':(8081|8083)'

# 3. GitLab에서 배포 파이프라인 실행
# → 자동으로 Green 환경에 배포 (Gradle + JDK 19)
# → Customized_BlueGreen_CI_CD_Pipeline.yml 사용

# 4. 헬스체크 통과 후 수동 승인으로 트래픽 전환

# 5. 배포 후 모니터링
tail -f /home/ubuntu/dev/woori_be/green/app.log
tail -f /var/log/nginx/access.log  # nginx 사용시
```

#### 2. 긴급 상황 대응
```bash
# 즉시 롤백 (배포 스크립트 사용)
cd /home/ubuntu/dev/woori_be/deployment
./deploy-bluegreen.sh switch blue

# 서비스 재시작 (필요시)
./deploy-bluegreen.sh stop blue
./deploy-bluegreen.sh deploy blue

# nginx 재시작 (설치된 경우)
sudo systemctl restart nginx

# 수동 프로세스 종료 (긴급시)
pkill -f "woori_be.jar"
```

#### 3. 정기 점검 항목
```bash
# 디스크 공간 확인
df -h

# 메모리 사용량 확인
free -h

# 서비스 상태 확인
systemctl status app-* nginx

# 로그 크기 관리
find /var/log -name "*.log" -size +100M
```

### 🔧 유지보수 작업

#### 1. 로그 로테이션 설정
```bash
# /etc/logrotate.d/spring-boot-apps
/var/log/apps/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

#### 2. 시스템 백업
```bash
#!/bin/bash
# /opt/deployment/backup.sh

BACKUP_DIR="/opt/backups/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# nginx 설정 백업
cp -r /etc/nginx/conf.d "$BACKUP_DIR/"

# 애플리케이션 백업
cp /opt/apps/blue/*.jar "$BACKUP_DIR/app-blue.jar"
cp /opt/apps/green/*.jar "$BACKUP_DIR/app-green.jar"

# 배포 스크립트 백업
cp -r /opt/deployment "$BACKUP_DIR/"

echo "백업 완료: $BACKUP_DIR"
```

#### 3. 성능 튜닝
```bash
# JVM 힙 크기 조정 (systemd 서비스 파일에서)
ExecStart=/usr/bin/java -Xms1024m -Xmx2048m ...

# nginx worker 프로세스 수 조정
worker_processes auto;

# 커넥션 풀 설정
keepalive 64;
```

### 📞 모니터링 및 연락처 정보

```yaml
운영 팀 연락처:
  - Level 1: 개발팀 (+82-10-XXXX-XXXX)
  - Level 2: 인프라팀 (+82-10-YYYY-YYYY)
  - Level 3: 아키텍트 (+82-10-ZZZZ-ZZZZ)

모니터링 엔드포인트:
  - Blue 환경: http://$DEPLOY_SERVER_DEV:8081/actuator/health
  - Green 환경: http://$DEPLOY_SERVER_DEV:8083/actuator/health
  - nginx (선택사항): http://$DEPLOY_SERVER_DEV/health
  - 시스템 메트릭: AWS CloudWatch

알림 채널:
  - Slack: #production-alerts
  - Email: ops@yourcompany.com
  - GitLab: 파이프라인 실패 대시보드
```

---

## 🎉 결론

본 가이드는 GitLab Runner를 활용한 EC2에서의 블루-그린 배포 시스템을 완전히 구현할 수 있는 포괄적인 전략을 제공합니다.

### ✅ 핵심 성과

1. **무중단 배포**: 2개 환경 간 실시간 트래픽 전환
2. **기존 환경 유지**: Gradle + JDK 19 + SSH 기반 배포 방식 보존
3. **자동화**: 사용자 친화적 GitLab CI/CD 파이프라인
4. **안전성**: 헬스체크 및 자동 롤백 메커니즘
5. **단순성**: 2개 Spring Boot 서비스로 관리 용이성 극대화
6. **비용 효율성**: 기존 EC2 인스턴스에서 소하 추가 비용

### 🚀 다음 단계

1. **기존 환경 확인**: Gradle, JDK 19, SSH 키 및 서버 설정 검증
2. **디렉토리 구성**: Blue-Green 구조 생성 (blue, green, deployment)
3. **파이프라인 적용**: `Customized_BlueGreen_CI_CD_Pipeline.yml` 교체
4. **배포 스크립트 설치**: `deploy-bluegreen.sh` 파일 복사 및 권한 설정
5. **테스트 배포**: dev 브랜치에서 전체 과정 검증
6. **운영 전환**: 성공적 검증 후 실제 운영 환경 적용

이 가이드를 통해 **기존 Gradle 개발 환경을 유지하면서** 안정적이고 효율적인 블루-그린 배포 시스템을 구축하실 수 있습니다.

---

*2025년 최신 GitLab CI/CD 및 AWS EC2 베스트 프랙티스를 반영한 Gradle 기반 환경 맞춤형 실전 가이드입니다.*