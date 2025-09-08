# 🚀 Blue-Green 배포 빠른 시작 체크리스트

이 체크리스트는 [`DEPLOYMENT_SETUP_GUIDE.md`](./DEPLOYMENT_SETUP_GUIDE.md)의 핵심 내용을 요약한 것입니다. 
상세한 설명은 메인 가이드를 참조하세요.

## 📋 사전 준비 체크리스트

### AWS 계정 준비
- [ ] AWS 계정 준비 (관리자 권한 또는 적절한 IAM 권한)
- [ ] AWS CLI 설치 및 설정 완료
- [ ] SSH 키페어 생성 및 다운로드

### GitLab 프로젝트 준비  
- [ ] GitLab 프로젝트에 Maintainer 이상 권한 확보
- [ ] 프로젝트에 `.gitlab-ci.yml` 파일 존재 확인
- [ ] `appspec.yml` 및 `ecosystem.config.js` 파일 존재 확인

---

## 🔧 AWS Console 설정 체크리스트

### 1. IAM 사용자 생성
- [ ] `gitlab-deployment-user` IAM 사용자 생성
- [ ] 필수 AWS 관리형 정책 연결 (총 10개)
- [ ] 사용자 정의 정책 생성 및 연결
- [ ] Access Key ID와 Secret Key 안전하게 저장

### 2. S3 버킷 생성
- [ ] `bluegreen-codedeploy-artifacts-[ACCOUNT-ID]` 버킷 생성
- [ ] 버킷 리전을 배포 리전과 동일하게 설정
- [ ] 버전 관리 활성화

### 3. EC2 키페어 생성
- [ ] `bluegreen-deployment-keypair` 키페어 생성
- [ ] `.pem` 파일 안전하게 저장

---

## ⚙️ GitLab CI/CD 변수 설정 체크리스트

### AWS 인증 변수 (필수)
- [ ] `AWS_ACCESS_KEY_ID` (Protected ✅, Masked ❌)
- [ ] `AWS_SECRET_ACCESS_KEY` (Protected ✅, Masked ✅)  
- [ ] `AWS_DEFAULT_REGION` (Protected ❌, Masked ❌)

### 프로젝트 구성 변수 (필수)
- [ ] `APPLICATION_NAME` = `bluegreen-app`
- [ ] `CODEDEPLOY_APPLICATION_NAME` = `bluegreen-deployment-production-app`
- [ ] `CODEDEPLOY_S3_BUCKET` = `bluegreen-codedeploy-artifacts-[ACCOUNT-ID]`

### 인프라 변수 (인프라 배포 후 설정)
- [ ] `BLUE_TARGET_GROUP` = CloudFormation 출력에서 확인
- [ ] `GREEN_TARGET_GROUP` = CloudFormation 출력에서 확인  
- [ ] `ALB_LISTENER_ARN` = ALB 리스너 ARN
- [ ] `ALB_DNS_NAME` = ALB DNS 이름

---

## 🏗️ 인프라 배포 체크리스트

### CloudFormation 스택 배포
- [ ] `aws-infrastructure/cloudformation/bluegreen-infrastructure.yaml` 템플릿 유효성 검증
- [ ] CloudFormation 스택 생성 (`bluegreen-deployment-production`)
- [ ] 필수 파라미터 설정:
  - `ProjectName`: `bluegreen-deployment`
  - `Environment`: `production`  
  - `KeyPairName`: `bluegreen-deployment-keypair`
  - `InstanceType`: `t3.medium`
- [ ] 스택 배포 완료 확인 (10-15분 소요)

### 출력값 확인 및 GitLab 변수 업데이트
- [ ] CloudFormation 출력값 조회
- [ ] ALB DNS 이름 확인하여 `ALB_DNS_NAME` 변수 설정
- [ ] ALB 리스너 ARN 확인하여 `ALB_LISTENER_ARN` 변수 설정
- [ ] Target Group 이름들 확인하여 변수 설정

### 인프라 검증
- [ ] Blue Auto Scaling Group 인스턴스 2개 실행 중인지 확인
- [ ] Green Auto Scaling Group 인스턴스 0개 (초기 상태)
- [ ] Blue Target Group에 2개 인스턴스가 `healthy` 상태인지 확인

---

## 🚀 첫 번째 배포 체크리스트

### 코드 푸시 및 파이프라인 실행
- [ ] main 브랜치에 최신 코드 푸시
- [ ] GitLab 파이프라인 자동 시작 확인
- [ ] `build`, `test`, `package` 단계 자동 완료 확인

### Blue 환경 첫 배포
- [ ] `deploy-to-blue-production` job 수동 실행
- [ ] CodeDeploy 배포 성공 확인 (5-10분 소요)
- [ ] Blue Target Group의 인스턴스들이 `healthy` 상태인지 확인

### 트래픽 스위칭 및 검증
- [ ] `switch-traffic-to-blue` job 수동 실행
- [ ] ALB 리스너가 Blue Target Group을 가리키는지 확인
- [ ] `validate-deployment` 자동 실행 및 성공 확인
- [ ] 애플리케이션 접근 테스트: `curl http://[ALB_DNS]/health`

---

## 🔄 Blue-Green 배포 프로세스 체크리스트

### Green 환경 배포
- [ ] 새로운 코드 변경사항을 main 브랜치에 푸시
- [ ] 새 파이프라인에서 `deploy-to-green-production` 수동 실행
- [ ] Green 환경 배포 완료 및 Target Group Health 확인
- [ ] Green 환경 개별 테스트 (직접 인스턴스 IP 접근)

### 트래픽 전환
- [ ] `switch-traffic-to-green` job 수동 실행  
- [ ] ALB 트래픽이 Green으로 전환되었는지 확인
- [ ] 애플리케이션 동작 정상성 확인
- [ ] `validate-deployment` 통과 확인

### 이전 환경 정리 (선택사항)
- [ ] Blue Auto Scaling Group Desired Capacity를 0으로 설정
- [ ] 리소스 비용 절감 확인

---

## 🚨 필수 명령어 모음

### 인프라 상태 확인
```bash
# CloudFormation 스택 상태
aws cloudformation describe-stacks --stack-name bluegreen-deployment-production

# Auto Scaling Group 상태  
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names bluegreen-deployment-production-blue-asg

# Target Group Health
aws elbv2 describe-target-health --target-group-arn [TARGET_GROUP_ARN]
```

### 배포 상태 확인
```bash
# CodeDeploy 최근 배포 확인
aws deploy list-deployments --application-name bluegreen-deployment-production-app --max-items 5

# 배포 세부사항
aws deploy get-deployment --deployment-id [DEPLOYMENT_ID]
```

### 애플리케이션 테스트
```bash
# Health Check
curl -I http://[ALB_DNS]/health
curl -I http://[ALB_DNS]/health/deep

# 버전 확인
curl http://[ALB_DNS]/version
```

### 긴급 롤백
```bash
# 이전 Target Group으로 즉시 전환
aws elbv2 modify-listener --listener-arn [LISTENER_ARN] --default-actions Type=forward,TargetGroupArn=[PREVIOUS_TG_ARN]

# CodeDeploy 배포 중단
aws deploy stop-deployment --deployment-id [DEPLOYMENT_ID] --auto-rollback-enabled
```

---

## ⚠️ 주의사항

### 보안
- [ ] IAM 액세스 키는 GitLab 변수에 Masked로 설정
- [ ] SSH 키페어 파일 권한 설정: `chmod 400 keypair.pem`
- [ ] 불필요한 포트는 Security Group에서 차단

### 비용 관리
- [ ] 사용하지 않는 환경의 Auto Scaling Group Desired Capacity는 0으로 설정
- [ ] S3 버킷의 오래된 배포 아티팩트 정기 삭제
- [ ] CloudWatch 로그 보존 기간 적절히 설정

### 모니터링
- [ ] CloudWatch 알람 설정 (CPU, Memory, 응답 시간)
- [ ] 배포 성공률 모니터링
- [ ] 정기적인 Health Check 확인

---

## 📞 문제 해결

### 배포 실패 시
1. CodeDeploy 에러 로그 확인: `aws deploy get-deployment --deployment-id [ID]`
2. EC2 인스턴스 SSH 접속하여 로그 확인: `/var/log/aws/codedeploy-agent/`
3. PM2 프로세스 상태 확인: `pm2 status`

### Target Group Unhealthy 시  
1. Health Check 설정 확인: `/health/deep` 엔드포인트 응답 확인
2. NGINX 상태 확인: `sudo systemctl status nginx`
3. 방화벽 및 Security Group 규칙 확인

### GitLab CI/CD 실패 시
1. AWS 권한 확인: `aws sts get-caller-identity`
2. S3 버킷 액세스 확인: `aws s3 ls s3://[BUCKET_NAME]`
3. IAM 정책 검토

---

## ✅ 완료 확인

모든 체크리스트를 완료했다면:
- [ ] ALB DNS를 통해 애플리케이션에 정상 접근 가능
- [ ] Blue-Green 전환이 무중단으로 동작
- [ ] 롤백 절차 테스트 완료
- [ ] 모니터링 및 알람 설정 완료

**🎉 축하합니다! Blue-Green 무중단 배포 시스템이 완성되었습니다.**

---

*자세한 설명과 트러블슈팅은 [`DEPLOYMENT_SETUP_GUIDE.md`](./DEPLOYMENT_SETUP_GUIDE.md)를 참조하세요.*