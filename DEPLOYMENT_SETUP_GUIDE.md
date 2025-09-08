# Blue-Green 무중단 배포 설정 가이드

GitLab CI/CD와 AWS CodeDeploy를 사용한 True Blue-Green 무중단 배포 구현을 위한 완전한 설정 가이드입니다.

## 📋 목차

1. [전제 조건](#전제-조건)
2. [AWS Console 설정](#aws-console-설정)
3. [GitLab CI/CD 변수 설정](#gitlab-cicd-변수-설정)
4. [인프라 배포](#인프라-배포)
5. [첫 번째 애플리케이션 배포](#첫-번째-애플리케이션-배포)
6. [트러블슈팅](#트러블슈팅)

---

## 전제 조건

### 필수 계정 및 도구
- ✅ **AWS 계정** (관리자 권한 또는 적절한 IAM 권한)
- ✅ **GitLab 계정** (프로젝트 Maintainer 이상 권한)
- ✅ **AWS CLI** 설치 및 구성
- ✅ **SSH 키페어** (EC2 인스턴스 접근용)

### 아키텍처 개요
```
Internet → ALB → [Blue EC2] [Green EC2]
                  ↓         ↓
                PM2 (4개)  PM2 (4개)
                Process    Process
```

- **ALB**: 트래픽 라우팅 및 Target Group 스위칭
- **EC2**: Blue/Green 환경 (각각 PM2로 4개 프로세스 실행)
- **CodeDeploy**: 무중단 배포 자동화
- **GitLab CI/CD**: 빌드, 테스트, 배포 파이프라인

---

## AWS Console 설정

### 1단계: IAM 사용자 생성 및 권한 설정

#### 1.1 GitLab용 IAM 사용자 생성
1. **AWS Console** → **IAM** → **Users** → **Create user**
2. **User name**: `gitlab-deployment-user`
3. **Access type**: Programmatic access 선택
4. **Next: Permissions** 클릭

#### 1.2 필수 IAM 정책 연결 (최소 권한 원칙 적용)

⚠️ **중요**: 보안 모범 사례에 따라 최소 권한 원칙을 적용합니다. 광범위한 Full Access 정책 대신 필요한 권한만 부여합니다.

**권장 관리형 정책 (최소한만 사용)**:
```
- CloudWatchLogsFullAccess  # 로그 모니터링용
```

**사용자 정의 정책 생성 (최소 권한 적용)**:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowS3ArtifactAccess",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::bluegreen-codedeploy-artifacts-*",
                "arn:aws:s3:::bluegreen-codedeploy-artifacts-*/*"
            ]
        },
        {
            "Sid": "AllowCodeDeployActions",
            "Effect": "Allow",
            "Action": [
                "codedeploy:CreateDeployment",
                "codedeploy:GetApplication",
                "codedeploy:GetDeployment",
                "codedeploy:GetDeploymentConfig",
                "codedeploy:ListDeployments",
                "codedeploy:StopDeployment",
                "codedeploy:GetDeploymentGroup",
                "codedeploy:ListDeploymentGroups"
            ],
            "Resource": [
                "arn:aws:codedeploy:*:*:application/bluegreen-deployment-*",
                "arn:aws:codedeploy:*:*:deploymentgroup:bluegreen-deployment-*/*"
            ]
        },
        {
            "Sid": "AllowELBReadAndModifySpecificListener",
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:DescribeLoadBalancers"
            ],
            "Resource": "*"
        },
        {
            "Sid": "AllowCloudFormationRead",
            "Effect": "Allow",
            "Action": [
                "cloudformation:DescribeStacks",
                "cloudformation:ListStackResources",
                "cloudformation:DescribeStackResources"
            ],
            "Resource": "arn:aws:cloudformation:*:*:stack/bluegreen-deployment-*/*"
        }
    ]
}
```

**🛡️ 보안 개선 권장사항**:
1. **OIDC 인증 사용**: 액세스 키 대신 GitLab → AWS OIDC 인증 방식 사용 권장
2. **리소스 수준 제한**: 특정 S3 버킷, CodeDeploy 애플리케이션으로 권한 제한
3. **정기적 권한 검토**: 최소 3개월마다 권한 사용 현황 검토
4. **Account ID 교체**: `bluegreen-codedeploy-artifacts-*`를 실제 Account ID로 교체

#### 1.3 액세스 키 생성
1. 사용자 생성 완료 후 **Security credentials** 탭
2. **Create access key** → **Command Line Interface (CLI)** 선택
3. **Access Key ID**와 **Secret Access Key** 안전하게 저장 ⚠️

### 2단계: S3 버킷 생성

#### 2.1 CodeDeploy 아티팩트용 S3 버킷
1. **AWS Console** → **S3** → **Create bucket**
2. **Bucket name**: `bluegreen-codedeploy-artifacts-[YOUR-ACCOUNT-ID]`
3. **AWS Region**: 배포할 리전 선택 (예: us-east-1)
4. **Block Public Access**: 모든 퍼블릭 액세스 차단 (기본값)
5. **Versioning**: Enable 권장
6. **Create bucket** 클릭

### 3단계: EC2 키 페어 생성

1. **AWS Console** → **EC2** → **Key Pairs** → **Create key pair**
2. **Name**: `bluegreen-deployment-keypair`
3. **Key pair type**: RSA
4. **Private key file format**: .pem (Linux/macOS) 또는 .ppk (Windows)
5. **Create key pair** 클릭하여 다운로드

---

## GitLab CI/CD 변수 설정

### 1단계: GitLab 프로젝트 설정

1. GitLab 프로젝트 → **Settings** → **CI/CD** → **Variables** 섹션 확장

### 2단계: AWS 인증 변수 설정

#### 필수 AWS 변수
| 변수명 | 값 | 설명 | Protected | Masked |
|--------|----|----|----------|--------|
| `AWS_ACCESS_KEY_ID` | `AKIA...` | IAM 사용자 액세스 키 ID | ✅ | ❌ |
| `AWS_SECRET_ACCESS_KEY` | `xxxxx...` | IAM 사용자 시크릿 키 | ✅ | ✅ |
| `AWS_DEFAULT_REGION` | `us-east-1` | AWS 리전 | ❌ | ❌ |

### 3단계: 프로젝트 구성 변수 설정

#### 애플리케이션 구성 변수
| 변수명 | 값 | 설명 |
|--------|----|----|
| `APPLICATION_NAME` | `bluegreen-app` | 애플리케이션 이름 |
| `CODEDEPLOY_APPLICATION_NAME` | `bluegreen-deployment-production-app` | CodeDeploy 애플리케이션 이름 |
| `CODEDEPLOY_S3_BUCKET` | `bluegreen-codedeploy-artifacts-[ACCOUNT-ID]` | S3 버킷 이름 |

#### Target Group 변수 (인프라 배포 후 설정)
| 변수명 | 값 (예시) | 설명 |
|--------|----------|-----|
| `BLUE_TARGET_GROUP` | `bluegreen-deployment-production-blue-tg` | Blue Target Group 이름 |
| `GREEN_TARGET_GROUP` | `bluegreen-deployment-production-green-tg` | Green Target Group 이름 |
| `ALB_LISTENER_ARN` | `arn:aws:elasticloadbalancing:us-east-1:...` | ALB 리스너 ARN |
| `ALB_DNS_NAME` | `bluegreen-deployment-production-alb-xxxx.us-east-1.elb.amazonaws.com` | ALB DNS 이름 |

### 4단계: 환경별 변수 설정 (선택사항)

#### 스테이징 환경 변수
| 변수명 | 값 | Environment Scope |
|--------|----|--------------------|
| `STAGING_SERVER` | `staging.example.com` | `develop` |
| `STAGING_SSH_PRIVATE_KEY` | `-----BEGIN PRIVATE KEY-----...` | `develop` |

---

## 인프라 배포

### 1단계: CloudFormation 스택 배포

#### 1.1 AWS CLI로 배포
```bash
# 1. 프로젝트 디렉토리에서 실행
cd /path/to/your/project

# 2. CloudFormation 템플릿 유효성 검사
aws cloudformation validate-template \
  --template-body file://aws-infrastructure/cloudformation/bluegreen-infrastructure.yaml

# 3. 스택 배포
aws cloudformation create-stack \
  --stack-name bluegreen-deployment-production \
  --template-body file://aws-infrastructure/cloudformation/bluegreen-infrastructure.yaml \
  --parameters \
    ParameterKey=ProjectName,ParameterValue=bluegreen-deployment \
    ParameterKey=Environment,ParameterValue=production \
    ParameterKey=KeyPairName,ParameterValue=bluegreen-deployment-keypair \
    ParameterKey=InstanceType,ParameterValue=t3.medium \
  --capabilities CAPABILITY_NAMED_IAM

# 4. 배포 상태 확인 (10-15분 소요)
aws cloudformation describe-stacks \
  --stack-name bluegreen-deployment-production \
  --query 'Stacks[0].StackStatus'
```

#### 1.2 AWS Console을 통한 배포
1. **AWS Console** → **CloudFormation** → **Create stack**
2. **Template source**: Upload a template file
3. **Choose file**: `aws-infrastructure/cloudformation/bluegreen-infrastructure.yaml` 업로드
4. **Stack name**: `bluegreen-deployment-production`
5. **Parameters** 입력:
   - **ProjectName**: `bluegreen-deployment`
   - **Environment**: `production`
   - **KeyPairName**: `bluegreen-deployment-keypair`
   - **InstanceType**: `t3.medium`
6. **Next** → **Next** → **I acknowledge...** 체크 → **Create stack**

### 2단계: 스택 출력값 확인 및 GitLab 변수 업데이트

#### 2.1 출력값 확인
```bash
# CloudFormation 출력값 조회
aws cloudformation describe-stacks \
  --stack-name bluegreen-deployment-production \
  --query 'Stacks[0].Outputs'
```

#### 2.2 GitLab CI/CD 변수 업데이트
CloudFormation 출력값을 사용하여 다음 변수들을 업데이트하세요:

| GitLab 변수 | CloudFormation 출력 키 | 예시 값 |
|-------------|----------------------|---------|
| `ALB_DNS_NAME` | `ApplicationLoadBalancerDNSName` | `bluegreen-deployment-production-alb-xxxx.us-east-1.elb.amazonaws.com` |
| `ALB_LISTENER_ARN` | `ApplicationLoadBalancerArn` + `:listener/app/...` | `arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/...` |
| `BLUE_TARGET_GROUP` | `BlueTargetGroupArn`에서 이름 추출 | `bluegreen-deployment-production-blue-tg` |
| `GREEN_TARGET_GROUP` | `GreenTargetGroupArn`에서 이름 추출 | `bluegreen-deployment-production-green-tg` |

#### 2.3 ALB 리스너 ARN 조회
```bash
# ALB 리스너 ARN 조회
ALB_ARN=$(aws cloudformation describe-stacks \
  --stack-name bluegreen-deployment-production \
  --query 'Stacks[0].Outputs[?OutputKey==`ApplicationLoadBalancerArn`].OutputValue' \
  --output text)

aws elbv2 describe-listeners \
  --load-balancer-arn $ALB_ARN \
  --query 'Listeners[0].ListenerArn' \
  --output text
```

### 3단계: 인프라 검증

#### 3.1 EC2 인스턴스 상태 확인
```bash
# Auto Scaling Group 인스턴스 확인
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names \
    bluegreen-deployment-production-blue-asg \
    bluegreen-deployment-production-green-asg \
  --query 'AutoScalingGroups[*].{Name:AutoScalingGroupName,Desired:DesiredCapacity,Running:Instances[?LifecycleState==`InService`] | length(@)}'
```

#### 3.2 Target Group Health 확인
```bash
# Blue Target Group Health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names bluegreen-deployment-production-blue-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)

# Green Target Group Health  
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names bluegreen-deployment-production-green-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
```

---

## 첫 번째 애플리케이션 배포

### 1단계: GitLab 파이프라인 실행

#### 1.1 main 브랜치에 커밋
```bash
# 최신 변경사항을 main 브랜치에 푸시
git checkout main
git add .
git commit -m "feat: Initial deployment setup"
git push origin main
```

#### 1.2 파이프라인 단계별 실행
GitLab 프로젝트에서 **CI/CD** → **Pipelines**로 이동하여 다음 단계를 순차적으로 실행:

1. **build** (자동 실행) ✅
2. **test** (자동 실행) ✅
3. **package** (자동 실행) ✅
4. **deploy-to-blue-production** (수동 실행) 🔄
5. **switch-traffic-to-blue** (수동 실행) 🔄
6. **validate-deployment** (자동 실행) ✅

### 2단계: Blue 환경 첫 배포

#### 2.1 Blue 배포 실행
1. GitLab 파이프라인에서 **deploy-to-blue-production** job 클릭
2. **Play** 버튼 클릭하여 수동 실행
3. 배포 로그 확인 (약 5-10분 소요)

#### 2.2 배포 성공 확인
```bash
# CodeDeploy 배포 상태 확인
aws deploy list-deployments \
  --application-name bluegreen-deployment-production-app \
  --deployment-group-name bluegreen-deployment-production-app-blue-dg \
  --max-items 1

# Target Group Health 재확인
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names bluegreen-deployment-production-blue-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text) \
  --query 'TargetHealthDescriptions[*].{Target:Target.Id,Health:TargetHealth.State}'
```

### 3단계: 트래픽 스위칭

#### 3.1 Blue로 트래픽 전환
1. GitLab 파이프라인에서 **switch-traffic-to-blue** job 클릭
2. **Play** 버튼 클릭하여 실행
3. ALB 리스너가 Blue Target Group으로 변경되는지 확인

#### 3.2 애플리케이션 접근 확인
```bash
# ALB를 통한 애플리케이션 접근 테스트
curl -I http://[ALB_DNS_NAME]/health
# 응답: HTTP/1.1 200 OK

curl -I http://[ALB_DNS_NAME]/health/deep  
# 응답: HTTP/1.1 200 OK

curl http://[ALB_DNS_NAME]/
# 응답: HTML 페이지 내용 확인
```

---

## Blue-Green 배포 프로세스

### 1단계: Green 환경으로 새 버전 배포

#### 1.1 코드 변경 및 커밋
```bash
# 애플리케이션 코드 수정
echo "Version 2.0.0" > version.txt
git add version.txt
git commit -m "feat: Update to version 2.0.0"
git push origin main
```

#### 1.2 Green 배포 실행
1. 새로운 파이프라인에서 **deploy-to-green-production** 수동 실행
2. Green 환경 배포 완료 대기
3. Green Target Group Health 확인

#### 1.3 Green 환경 테스트
```bash
# Green Target Group의 개별 인스턴스 직접 테스트
# (인스턴스 IP는 AWS Console에서 확인)
curl http://[GREEN_INSTANCE_IP]/health/deep
curl http://[GREEN_INSTANCE_IP]/version
```

### 2단계: 트래픽 전환

#### 2.1 Green으로 트래픽 전환
1. **switch-traffic-to-green** job 수동 실행
2. 트래픽 전환 완료 확인
3. **validate-deployment** 자동 실행 확인

#### 2.2 전환 검증
```bash
# 트래픽이 Green으로 전환되었는지 확인
for i in {1..10}; do
  curl -s http://[ALB_DNS_NAME]/version
  sleep 1
done
```

### 3단계: Blue 환경 정리 (선택사항)

Blue 환경이 더 이상 필요 없다면 Auto Scaling Group의 Desired Capacity를 0으로 설정:

```bash
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name bluegreen-deployment-production-blue-asg \
  --desired-capacity 0
```

---

## 트러블슈팅

### 일반적인 문제 및 해결방법

#### 1. CodeDeploy 배포 실패

**증상**: 배포가 "Failed" 상태로 끝남

**해결방법**:
```bash
# 배포 실패 상세 로그 확인
DEPLOYMENT_ID="d-XXXXXXXXX"
aws deploy get-deployment --deployment-id $DEPLOYMENT_ID

# 개별 인스턴스 배포 상태 확인
aws deploy list-deployment-instances \
  --deployment-id $DEPLOYMENT_ID \
  --query 'instancesList[?status==`Failed`]'

# EC2 인스턴스에 SSH 접속하여 로그 확인
ssh -i bluegreen-deployment-keypair.pem ec2-user@[INSTANCE_IP]
sudo tail -f /var/log/aws/codedeploy-agent/codedeploy-agent.log
sudo tail -f /opt/bluegreen-app/logs/application.log
```

#### 2. Target Group Health Check 실패

**증상**: Target이 "unhealthy" 상태

**해결방법**:
```bash
# Health Check 설정 확인
aws elbv2 describe-target-groups \
  --names bluegreen-deployment-production-blue-tg \
  --query 'TargetGroups[0].{HealthCheckPath:HealthCheckPath,HealthCheckPort:HealthCheckPort,HealthCheckProtocol:HealthCheckProtocol}'

# EC2 인스턴스에서 직접 Health Check 엔드포인트 테스트
ssh -i bluegreen-deployment-keypair.pem ec2-user@[INSTANCE_IP]
curl -I http://localhost/health/deep
sudo systemctl status nginx
sudo systemctl status codedeploy-agent
pm2 status
```

#### 3. GitLab CI/CD 파이프라인 실패

**증상**: AWS 관련 job에서 권한 오류

**해결방법**:
```bash
# GitLab Runner에서 AWS CLI 테스트
aws sts get-caller-identity
aws s3 ls s3://bluegreen-codedeploy-artifacts-[ACCOUNT-ID]/

# IAM 사용자 권한 확인
aws iam list-attached-user-policies --user-name gitlab-deployment-user
aws iam get-user-policy --user-name gitlab-deployment-user --policy-name CustomDeploymentPolicy
```

#### 4. ALB 트래픽 스위칭 실패

**증상**: 트래픽이 의도한 Target Group으로 가지 않음

**해결방법**:
```bash
# 현재 ALB 리스너 설정 확인
aws elbv2 describe-listeners --listener-arns $ALB_LISTENER_ARN

# Target Group ARN 확인
aws elbv2 describe-target-groups \
  --names bluegreen-deployment-production-blue-tg bluegreen-deployment-production-green-tg \
  --query 'TargetGroups[*].{Name:TargetGroupName,Arn:TargetGroupArn}'
```

#### 5. 롤백 절차

**긴급 롤백이 필요한 경우**:

```bash
# 1. 이전 Target Group으로 즉시 트래픽 전환
PREVIOUS_TG_ARN="arn:aws:elasticloadbalancing:..."
aws elbv2 modify-listener \
  --listener-arn $ALB_LISTENER_ARN \
  --default-actions Type=forward,TargetGroupArn=$PREVIOUS_TG_ARN

# 2. CodeDeploy 배포 중단 (배포 중인 경우)
aws deploy stop-deployment \
  --deployment-id $DEPLOYMENT_ID \
  --auto-rollback-enabled

# 3. 수동 롤백 확인
curl -I http://[ALB_DNS_NAME]/health
curl http://[ALB_DNS_NAME]/version
```

### 로그 위치

#### EC2 인스턴스 로그
```bash
# CodeDeploy Agent 로그
/var/log/aws/codedeploy-agent/codedeploy-agent.log

# 애플리케이션 로그
/opt/bluegreen-app/logs/application.log
/opt/bluegreen-app/logs/pm2.log

# NGINX 로그
/var/log/nginx/access.log
/var/log/nginx/error.log

# System 로그
/var/log/messages
journalctl -u codedeploy-agent
```

#### GitLab CI/CD 로그
- GitLab 프로젝트 → **CI/CD** → **Pipelines** → 각 job 클릭
- **Show complete raw** 링크로 전체 로그 확인

---

## 모니터링 및 유지보수

### CloudWatch 모니터링 설정

#### 1. ALB 메트릭 모니터링
- `TargetResponseTime`
- `HTTPCode_Target_2XX_Count`
- `HTTPCode_Target_4XX_Count`
- `HTTPCode_Target_5XX_Count`

#### 2. EC2 메트릭 모니터링
- `CPUUtilization`
- `MemoryUtilization`
- `DiskSpaceUtilization`

#### 3. CodeDeploy 메트릭
- 배포 성공률
- 배포 시간
- 롤백 빈도

### 정기 점검 항목

#### 월간 점검
- [ ] S3 버킷의 오래된 배포 아티팩트 정리
- [ ] EC2 인스턴스 보안 업데이트 적용
- [ ] SSL 인증서 만료 확인
- [ ] 로그 로테이션 확인

#### 분기별 점검
- [ ] AWS 비용 최적화 검토
- [ ] 보안 그룹 규칙 검토
- [ ] Auto Scaling 정책 검토
- [ ] 재해 복구 절차 테스트

---

## 보안 고려사항

### 1. IAM 최소 권한 원칙
- GitLab 사용자에게 필요한 최소한의 권한만 부여
- 정기적인 권한 검토 및 감사

### 2. 네트워크 보안
- Security Group 규칙 최소화
- VPC Flow Logs 활성화
- WAF 적용 고려

### 3. 애플리케이션 보안
- 정기적인 보안 스캔
- 의존성 취약점 점검
- SSL/TLS 인증서 관리

### 4. 로그 및 모니터링
- CloudTrail 로그 활성화
- Config Rules 설정
- GuardDuty 활성화 고려

---

## 추가 자료

### 관련 문서
- [AWS CodeDeploy User Guide](https://docs.aws.amazon.com/codedeploy/)
- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

### 유용한 명령어
```bash
# 전체 인프라 상태 한눈에 보기
./scripts/manage-infrastructure.sh status

# 배포 이력 확인
aws deploy list-deployments --application-name bluegreen-deployment-production-app

# 현재 활성 Target Group 확인
aws elbv2 describe-listeners --listener-arns $ALB_LISTENER_ARN \
  --query 'Listeners[0].DefaultActions[0].TargetGroupArn'
```

---

**🎉 축하합니다!** Blue-Green 무중단 배포 시스템이 성공적으로 구성되었습니다. 이제 안전하고 신뢰할 수 있는 무중단 배포를 자동화할 수 있습니다.

궁금한 점이 있으시면 이 문서의 트러블슈팅 섹션을 참조하거나, AWS 및 GitLab 공식 문서를 확인하세요.