# Blue-Green 배포 검증 체크리스트

## 📋 배포 전 사전 점검 (Pre-Deployment Checklist)

### 1. 인프라 상태 확인
- [ ] **ALB 상태**: 로드밸런서가 Active 상태이며 정상 작동 중
- [ ] **Target Group**: Blue/Green 타겟 그룹 모두 생성되고 올바르게 구성됨
- [ ] **EC2 인스턴스**: Blue/Green 환경의 모든 EC2 인스턴스가 running 상태
- [ ] **보안 그룹**: 필요한 포트(80, 3001-3004) 규칙이 올바르게 설정됨
- [ ] **IAM 역할**: CodeDeploy 및 EC2 인스턴스 역할 권한 확인

### 2. 코드 및 설정 검증
- [ ] **코드 품질**: 모든 코드 리뷰 및 테스트 통과
- [ ] **AppSpec.yml**: 올바른 형식과 필수 훅 스크립트 포함
- [ ] **PM2 설정**: ecosystem.config.js의 4개 인스턴스 설정 검증
- [ ] **NGINX 설정**: upstream 구성 및 health check 경로 확인
- [ ] **환경 변수**: 필요한 모든 환경 변수 설정 완료

### 3. GitLab CI/CD 파이프라인 점검
- [ ] **OIDC 인증**: AWS_ROLE_ARN 변수 설정 및 권한 확인
- [ ] **S3 버킷**: CodeDeploy 아티팩트 버킷 접근 가능
- [ ] **브랜치 보호**: main 브랜치 보호 규칙 설정
- [ ] **파이프라인 변수**: 모든 필수 CI/CD 변수 설정 완료

## 🚀 배포 중 실시간 모니터링 (During Deployment Monitoring)

### 1. CodeDeploy 배포 상태 확인
```bash
# 배포 상태 실시간 모니터링
aws deploy get-deployment --deployment-id $DEPLOYMENT_ID \
  --query 'deploymentInfo.{Status:status,Progress:deploymentOverview}' \
  --output table

# 배포 인스턴스 상태 확인
aws deploy list-deployment-instances --deployment-id $DEPLOYMENT_ID \
  --query 'instancesList[].{Instance:instanceId,Status:status}' \
  --output table
```

### 2. 애플리케이션 상태 모니터링
- [ ] **PM2 프로세스**: 4개 인스턴스가 모두 online 상태
- [ ] **Health Check**: `/health` 및 `/health/deep` 엔드포인트 응답 확인
- [ ] **로그 확인**: 애플리케이션 로그에서 오류 메시지 모니터링
- [ ] **메모리/CPU**: 리소스 사용률이 임계치 내 유지

### 3. 네트워크 연결성 검증
- [ ] **NGINX → PM2**: upstream 연결 정상
- [ ] **ALB → NGINX**: 로드밸런서에서 인스턴스 연결 정상
- [ ] **외부 접근**: ALB DNS를 통한 외부 접근 가능

## ✅ 배포 후 검증 (Post-Deployment Verification)

### 1. 기능 검증 (Functional Testing)
- [ ] **기본 페이지**: 메인 페이지 로딩 및 콘텐츠 확인
- [ ] **API 엔드포인트**: 주요 API 호출 응답 시간 및 정확성 검증
- [ ] **데이터베이스**: 데이터 연결 및 CRUD 작업 정상
- [ ] **외부 서비스**: 연동 서비스와의 통신 정상

### 2. 성능 검증 (Performance Testing)
- [ ] **응답 시간**: 평균 응답 시간 < 200ms
- [ ] **동시 사용자**: 예상 트래픽 수준에서 안정성 확인
- [ ] **메모리 사용률**: < 80% 유지
- [ ] **CPU 사용률**: < 70% 유지

### 3. 보안 검증 (Security Validation)
- [ ] **HTTPS 리다이렉션**: HTTP → HTTPS 자동 리다이렉션
- [ ] **보안 헤더**: 필수 보안 헤더 설정 확인
- [ ] **불필요 포트**: 불필요한 포트 노출 차단
- [ ] **인증/인가**: 접근 제어 정상 작동

### 4. 모니터링 및 알림 (Monitoring & Alerting)
- [ ] **CloudWatch**: 메트릭 수집 정상
- [ ] **로그 수집**: 애플리케이션 로그 중앙집중화
- [ ] **알림 설정**: 장애 발생 시 알림 전송 테스트
- [ ] **대시보드**: 모니터링 대시보드 데이터 업데이트 확인

## 🔄 트래픽 전환 검증 (Traffic Switch Validation)

### 1. 전환 전 준비사항
- [ ] **현재 활성 환경**: Blue 또는 Green 환경 식별
- [ ] **새 환경 상태**: 배포된 새 환경의 완전한 검증 완료
- [ ] **롤백 준비**: 문제 발생 시 즉시 롤백 가능한 상태
- [ ] **모니터링 준비**: 실시간 메트릭 모니터링 체계 가동

### 2. 점진적 트래픽 전환 (Canary 방식)
```bash
# 1단계: 5% 트래픽 전환
# 새 타겟 그룹에 가중치 5 설정, 기존 95 유지

# 2단계: 모니터링 (5-10분)
# 오류율, 응답시간, 사용자 피드백 모니터링

# 3단계: 50% 트래픽 전환
# 문제없으면 가중치 50:50으로 조정

# 4단계: 100% 전환
# 최종적으로 새 환경으로 완전 전환
```

### 3. 전환 후 검증
- [ ] **트래픽 분산**: 모든 트래픽이 새 환경으로 라우팅
- [ ] **이전 환경**: 기존 환경에 트래픽 유입 중단 확인
- [ ] **사용자 경험**: 실제 사용자 관점에서 서비스 정상성 확인
- [ ] **비즈니스 메트릭**: 핵심 비즈니스 지표에 부정적 영향 없음

## 🚨 장애 대응 절차 (Incident Response Procedures)

### 1. 즉시 롤백 시나리오
다음 상황에서는 즉시 롤백을 실행합니다:
- [ ] **응답 시간**: 평균 응답 시간이 1초 초과
- [ ] **오류율**: 5% 이상의 오류율 발생
- [ ] **서비스 중단**: 임계 기능 완전 중단
- [ ] **보안 이슈**: 보안 취약점 발견

### 2. 롤백 실행 절차
```bash
# 1단계: ALB 트래픽 즉시 이전 환경으로 전환
aws elbv2 modify-listener \
  --listener-arn $ALB_LISTENER_ARN \
  --default-actions Type=forward,TargetGroupArn=$PREVIOUS_TARGET_GROUP_ARN

# 2단계: CodeDeploy 배포 중단
aws deploy stop-deployment \
  --deployment-id $DEPLOYMENT_ID \
  --auto-rollback-enabled

# 3단계: 상태 확인
aws deploy get-deployment --deployment-id $DEPLOYMENT_ID
```

### 3. 장애 분석 및 복구
- [ ] **로그 수집**: 모든 관련 로그 수집 및 보존
- [ ] **근본 원인 분석**: RCA(Root Cause Analysis) 수행
- [ ] **개선 계획**: 재발 방지를 위한 개선 사항 도출
- [ ] **문서화**: 장애 대응 과정 및 교훈 문서화

## 📊 성공 기준 (Success Criteria)

### 필수 기준 (Must Have)
- ✅ **가용성**: 99.9% 이상 (월 8.7시간 이하 다운타임)
- ✅ **응답 시간**: 평균 200ms 이하, 95%tile 500ms 이하
- ✅ **오류율**: 0.1% 이하
- ✅ **복구 시간**: 장애 발생 시 5분 내 롤백 완료

### 권장 기준 (Nice to Have)
- 🎯 **응답 시간**: 평균 100ms 이하
- 🎯 **가용성**: 99.95% 이상
- 🎯 **복구 시간**: 2분 내 자동 롤백
- 🎯 **모니터링**: 실시간 알림 및 자동화된 대응

## 🔍 배포 후 24시간 모니터링 (24-Hour Post-Deployment Monitoring)

### 1. 첫 1시간 (Critical Period)
- 5분 간격으로 모든 메트릭 확인
- 실시간 사용자 피드백 모니터링
- 오류 로그 지속적 감시

### 2. 첫 24시간 (Stabilization Period)  
- 30분 간격으로 주요 메트릭 확인
- 성능 트렌드 분석
- 용량 및 확장성 평가

### 3. 보고서 작성
- [ ] **배포 성공 보고서**: 주요 메트릭 및 성과 지표 정리
- [ ] **개선 사항**: 다음 배포를 위한 개선점 도출
- [ ] **교훈 학습**: 배포 과정에서 얻은 교훈 문서화

---

**참고**: 이 체크리스트는 배포 담당자와 운영팀이 함께 사용하며, 각 항목은 반드시 검증 후 체크 표시를 해야 합니다.