# Blue-Green 배포 운영 스크립트 가이드

## 📁 스크립트 개요

이 디렉토리는 Blue-Green 배포 시스템의 운영을 위한 핵심 스크립트들을 포함하고 있습니다.

### 🔧 운영 스크립트 목록

| 스크립트 | 용도 | 실행 시점 |
|---------|------|-----------|
| **deployment-validator.sh** | 배포 완료 후 종합 검증 | 배포 완료 직후 |
| **system-monitor.sh** | 실시간 시스템 모니터링 | 상시 운영 |
| **performance-test.sh** | 성능 테스트 및 벤치마킹 | 배포 검증 단계 |
| **emergency-rollback.sh** | 응급 상황 시 즉시 롤백 | 장애 발생 시 |

## 🚀 배포 검증 워크플로

### 1단계: 배포 완료 후 기본 검증
```bash
# 배포가 완료된 후 종합적인 검증 수행
./deployment-validator.sh --alb-dns-name your-alb-dns.elb.amazonaws.com

# 특정 재시도 횟수로 검증
./deployment-validator.sh --max-retries 10 --retry-delay 15
```

### 2단계: 성능 테스트 실행
```bash
# 기본 성능 테스트 (10 동시 사용자, 60초)
./performance-test.sh --alb-dns-name your-alb-dns.elb.amazonaws.com

# 고부하 성능 테스트 (50 동시 사용자, 300초)
./performance-test.sh \
  --concurrent-users 50 \
  --test-duration 300 \
  --max-response-time 1500 \
  --min-throughput 100
```

### 3단계: 실시간 모니터링 활성화
```bash
# 대화형 모니터링 시작
./system-monitor.sh --interactive

# 백그라운드 데몬으로 실행
./system-monitor.sh --daemon --interval 30
```

## 🔍 각 스크립트 상세 가이드

### 🛡️ deployment-validator.sh

**목적**: 배포 완료 후 시스템 전반의 상태를 검증

**주요 기능**:
- ALB 상태 및 Target Group Health 확인
- PM2 프로세스 상태 검증
- NGINX 서비스 정상성 확인  
- Health 엔드포인트 응답 검증
- 애플리케이션 기능 테스트

**사용 예시**:
```bash
# 기본 검증
./deployment-validator.sh

# 상세 설정으로 검증
./deployment-validator.sh \
  --alb-dns-name my-alb-12345.us-east-1.elb.amazonaws.com \
  --max-retries 5 \
  --retry-delay 10
```

**검증 항목**:
- ✅ ALB 상태: Active 여부 확인
- ✅ Target Groups: Blue/Green 환경의 healthy targets 수
- ✅ Health Endpoints: `/health` 및 `/health/deep` 응답
- ✅ Application: 메인 페이지 응답 및 내용 검증
- ✅ PM2 Processes: 4개 이상의 online 프로세스
- ✅ NGINX Service: 서비스 활성화 및 설정 유효성

### 📊 system-monitor.sh

**목적**: 실시간 시스템 모니터링 및 알림

**주요 기능**:
- CPU, 메모리, 디스크 사용률 모니터링
- PM2 프로세스 상태 추적
- ALB 및 Target Group Health 감시
- 임계값 초과 시 자동 알림
- Slack/Email 통합 지원

**모드별 실행**:
```bash
# 대화형 대시보드 모드 (기본)
./system-monitor.sh --interactive

# 백그라운드 데몬 모드
./system-monitor.sh --daemon

# 일회성 체크
./system-monitor.sh --once

# 데몬 중지
./system-monitor.sh --stop
```

**설정 가능한 임계값**:
```bash
./system-monitor.sh \
  --cpu-threshold 90 \
  --memory-threshold 85 \
  --disk-threshold 95 \
  --response-threshold 3
```

**알림 설정** (`/etc/bluegreen-monitor.conf`):
```bash
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
EMAIL_RECIPIENTS="ops@company.com"
ALERT_ENABLED=true
ALERT_COOLDOWN=300
```

### ⚡ performance-test.sh

**목적**: 배포 후 성능 검증 및 벤치마킹

**주요 기능**:
- Apache Bench 기반 부하 테스트
- 응답 시간 분석 (평균, 95%tile, 99%tile)
- 동시 연결 테스트
- 상세한 응답 시간 분해 분석
- HTML/JSON 보고서 생성

**테스트 시나리오**:
```bash
# 가벼운 테스트 (개발/스테이징)
./performance-test.sh \
  --concurrent-users 5 \
  --test-duration 30

# 프로덕션 수준 테스트
./performance-test.sh \
  --concurrent-users 50 \
  --test-duration 300 \
  --max-response-time 1000 \
  --max-95th-percentile 2000 \
  --max-error-rate 1 \
  --min-throughput 200

# 스트레스 테스트
./performance-test.sh \
  --concurrent-users 100 \
  --test-duration 600 \
  --max-response-time 3000
```

**성능 기준**:
- **평균 응답시간**: < 2초 (기본)
- **95%tile 응답시간**: < 3초 (기본)
- **오류율**: < 5% (기본)
- **처리량**: > 50 RPS (기본)

**출력 파일**:
- JSON 보고서: `/tmp/performance-test-report-YYYYMMDD_HHMMSS.json`
- HTML 보고서: `/tmp/performance-test-report-YYYYMMDD_HHMMSS.html`
- 로그 파일: `/tmp/performance-test-YYYYMMDD_HHMMSS.log`

### 🚨 emergency-rollback.sh

**목적**: 응급 상황에서 즉시 이전 환경으로 롤백

**주요 기능**:
- 현재 배포 상태 자동 분석
- 진행 중인 CodeDeploy 배포 중단
- ALB 트래픽 즉시 이전 환경으로 전환
- 롤백 후 Health 검증
- 자동 알림 및 보고서 생성

**실행 방법**:
```bash
# 안전한 대화형 롤백 (권장)
./emergency-rollback.sh

# Dry Run으로 사전 확인
./emergency-rollback.sh --dry-run

# 자동 롤백 (위험! - 응급 상황만)
./emergency-rollback.sh --auto-confirm
```

**필수 환경 변수**:
```bash
export ALB_LISTENER_ARN="arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/..."
export ALB_DNS_NAME="my-alb-12345.us-east-1.elb.amazonaws.com"
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
```

**롤백 프로세스**:
1. **상태 분석**: 현재 Blue/Green 환경 식별
2. **검증**: 롤백 대상 환경의 Health 확인
3. **확인**: 사용자 확인 (auto-confirm 제외)
4. **배포 중단**: 진행 중인 CodeDeploy 배포 정지
5. **트래픽 전환**: ALB 트래픽 즉시 전환
6. **Health 검증**: 롤백 후 서비스 정상성 확인
7. **알림**: 롤백 결과 알림 발송

## 🔧 종합 운영 시나리오

### 정상 배포 검증 절차
```bash
#!/bin/bash
# 1. 배포 검증
./deployment-validator.sh --alb-dns-name $ALB_DNS || {
    echo "배포 검증 실패 - 롤백 고려"
    exit 1
}

# 2. 성능 테스트
./performance-test.sh --concurrent-users 20 --test-duration 120 || {
    echo "성능 테스트 실패 - 성능 분석 필요"
}

# 3. 모니터링 활성화
./system-monitor.sh --daemon --interval 60

echo "배포 검증 완료 - 프로덕션 트래픽 전환 가능"
```

### 응급 상황 대응 절차
```bash
#!/bin/bash
# 1. 즉시 롤백 (자동)
./emergency-rollback.sh --auto-confirm

# 2. 시스템 상태 점검
./system-monitor.sh --once

# 3. 성능 확인
./performance-test.sh --concurrent-users 10 --test-duration 60

echo "응급 롤백 완료 - 시스템 안정화 확인됨"
```

### 일일 운영 체크리스트
```bash
#!/bin/bash
# 매일 오전 9시 실행 권장

echo "=== 일일 시스템 점검 시작 ==="

# 1. 시스템 상태 확인
./system-monitor.sh --once

# 2. 가벼운 성능 테스트
./performance-test.sh --concurrent-users 5 --test-duration 30

# 3. 배포 상태 검증
./deployment-validator.sh --max-retries 3

echo "=== 일일 시스템 점검 완료 ==="
```

## 📋 체크리스트 통합

각 스크립트는 [DEPLOYMENT_VERIFICATION_CHECKLIST.md](../../DEPLOYMENT_VERIFICATION_CHECKLIST.md)와 연동되어 체계적인 검증을 수행합니다:

| 체크리스트 섹션 | 관련 스크립트 | 자동화 레벨 |
|-----------------|---------------|-------------|
| 배포 전 사전 점검 | system-monitor.sh | 🔄 자동 |
| 배포 중 실시간 모니터링 | system-monitor.sh | 🔄 자동 |
| 배포 후 검증 | deployment-validator.sh | 🔄 자동 |
| 성능 검증 | performance-test.sh | 🔄 자동 |
| 트래픽 전환 검증 | deployment-validator.sh | 🔄 자동 |
| 응급 롤백 | emergency-rollback.sh | 🔄 자동 |

## ⚠️ 중요 주의사항

### 보안
- 모든 스크립트는 적절한 AWS IAM 권한이 필요합니다
- `emergency-rollback.sh`의 `--auto-confirm` 옵션은 매우 위험하므로 신중하게 사용
- Slack Webhook URL, 이메일 등 민감 정보는 환경 변수로 관리

### 모니터링
- `system-monitor.sh`는 데몬 모드로 실행 시 시스템 리소스를 지속적으로 사용
- 로그 파일 크기 관리를 위한 로그 로테이션 설정 권장
- 알림 스팸 방지를 위한 쿨다운 기능 활용

### 성능
- `performance-test.sh`는 실제 프로덕션 트래픽에 영향을 줄 수 있으므로 적절한 부하 수준으로 실행
- 테스트 실행 전 현재 시스템 부하 확인 필수

## 📞 문제 해결

각 스크립트는 상세한 로그와 에러 메시지를 제공합니다:

```bash
# 로그 파일 위치
ls -la /var/log/*rollback* /var/log/*monitor* /tmp/*test* /tmp/*validation*

# 실시간 로그 모니터링
tail -f /var/log/system-monitor.log

# 에러 로그 확인
grep ERROR /var/log/system-alerts.log
```

**일반적인 문제들**:
- **AWS 권한 부족**: IAM 정책 확인 및 OIDC 설정 검증
- **네트워크 연결 실패**: 보안 그룹 및 NACL 설정 확인  
- **타겟 그룹 Unhealthy**: EC2 인스턴스 상태 및 애플리케이션 로그 확인
- **성능 테스트 실패**: 시스템 리소스 부족 또는 네트워크 병목 현상

---

**지원**: 스크립트 관련 문제 발생 시 생성된 로그 파일과 함께 운영팀에 문의하세요.