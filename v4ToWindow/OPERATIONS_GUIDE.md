# NGINX Blue-Green Deployment Operations Guide

> **Based on 새로운 판단 파일 Best Practices**  
> Official NGINX mechanisms with atomic file replacement and enhanced safety

## 🏗️ System Architecture

### Core Components

```
📁 /etc/nginx/conf.d/
├── upstreams.conf    # Blue/Green upstream definitions
├── active.env        # Active color variable (set $active "color")
├── routing.conf      # Map $active to $backend
└── active_backend.conf.backup  # Legacy backup (keep for emergency)

🔧 Scripts:
├── /app/switch-deployment.sh   # Enhanced atomic deployment script
├── /app/health-check.sh        # Comprehensive health checker
└── /app/start.sh              # Container initialization script

🌐 Services:
├── Blue Server (Port 3001)    # Version 1.0.0
├── Green Server (Port 3002)   # Version 2.0.0
├── NGINX Proxy (Port 80)      # Main entry point
├── Admin Interface (Port 8080) # Management dashboard
└── API Server (Port 9000)     # Deployment control API
```

### Key Design Principles (새로운 판단 파일)

1. **공식 NGINX 메커니즘**: 설정 변경 → `nginx -t` → `nginx -s reload`
2. **원자적 파일 교체**: `mktemp` + `install` 명령 사용
3. **무중단 리로드**: HUP 신호를 통한 우아한 전환
4. **헬스체크 우선**: 전환 전 대상 환경 검증
5. **즉시 롤백**: 실패 시 자동 복구

## 🚀 Deployment Procedures

### Method 1: Script-Based Deployment (Recommended)

```bash
# Blue 환경으로 전환
./switch-deployment.sh blue

# Green 환경으로 전환  
./switch-deployment.sh green

# 헬스체크 실행
./health-check.sh
```

### Method 2: Web Interface Deployment

1. **Admin Interface 접속**: http://localhost:8080
2. **Current Status 확인**: 모든 서비스 상태 점검
3. **Target Environment 선택**: Blue/Green 버튼 클릭
4. **Deployment Progress 모니터링**: 실시간 로그 확인
5. **Post-Deployment Validation**: 자동 헬스체크 결과 검토

### Method 3: API-Based Deployment

```bash
# Blue 환경으로 전환
curl -X POST http://localhost:9000/switch/blue

# Green 환경으로 전환
curl -X POST http://localhost:9000/switch/green

# 응답 예시
{
  "success": true,
  "deployment": "green",
  "message": "Successfully switched to GREEN deployment"
}
```

## 🔒 Safety Mechanisms

### Atomic File Replacement Process

1. **Temporary File Creation**: `mktemp`로 임시 파일 생성
2. **Configuration Write**: 새 설정을 임시 파일에 작성
3. **Atomic Move**: `install` 명령으로 원자적 교체
4. **Validation**: `nginx -t`로 문법 검증
5. **Reload**: `nginx -s reload`로 무중단 적용

### Enhanced Health Checks

```bash
# 개별 서비스 체크
./health-check.sh blue    # Blue 서버만
./health-check.sh green   # Green 서버만
./health-check.sh nginx   # NGINX 프록시만
./health-check.sh config  # NGINX 설정만

# 전체 시스템 체크
./health-check.sh         # 모든 구성 요소 검사
```

### Automatic Rollback

- **조건**: NGINX 설정 검증 실패 또는 리로드 실패
- **동작**: 이전 활성 환경으로 즉시 복원
- **검증**: 롤백 후 자동 헬스체크 실행

## 📊 Monitoring & Validation

### Health Check Endpoints

| Service | Endpoint | Expected Response |
|---------|----------|-------------------|
| Blue Server | `http://localhost:3001/health` | `{"status":"healthy","server":"blue"}` |
| Green Server | `http://localhost:3002/health` | `{"status":"healthy","server":"green"}` |
| NGINX Proxy | `http://localhost:80/health` | `ok` |
| API Server | `http://localhost:9000/health` | `{"status":"healthy","service":"api-server"}` |

### Status Indicators

- **🟢 HEALTHY**: 서비스가 정상적으로 응답
- **🔴 UNHEALTHY**: 서비스 응답 없음 또는 오류
- **🟡 UNKNOWN**: 상태 확인 중

### Log Monitoring

```bash
# NGINX 로그 실시간 모니터링
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# 배포 스크립트 로그는 화면 출력으로 실시간 확인
```

## 🛠️ Troubleshooting Guide

### Common Issues

#### 1. 헬스체크 실패 (Health Check Failed)

**증상**: "헬스체크 실패: 환경이 준비되지 않음"

**원인**: 대상 서버가 시작되지 않았거나 응답하지 않음

**해결**:
```bash
# 서비스 상태 개별 확인
./health-check.sh blue
./health-check.sh green

# Docker 컨테이너 상태 확인
docker ps
docker logs blue-green-nginx

# 서비스 재시작 (필요시)
docker restart blue-green-nginx
```

#### 2. NGINX 설정 검증 실패 (Configuration Validation Failed)

**증상**: "nginx 설정 검증 실패"

**원인**: 설정 파일 문법 오류 또는 경로 문제

**해결**:
```bash
# 설정 파일 문법 수동 검사
nginx -t

# 설정 파일 내용 확인
cat /etc/nginx/conf.d/active.env
cat /etc/nginx/conf.d/upstreams.conf
cat /etc/nginx/conf.d/routing.conf

# 권한 확인
ls -la /etc/nginx/conf.d/
```

#### 3. 롤백 실패 (Rollback Failed)

**증상**: "롤백 실패: 수동 개입 필요"

**원인**: 심각한 설정 오류로 자동 복구 불가

**해결**:
```bash
# 수동으로 이전 설정 복원
cp /etc/nginx/conf.d/active_backend.conf.backup /etc/nginx/conf.d/active.env

# 또는 안전한 기본값으로 복원
echo 'set $active "blue";' > /etc/nginx/conf.d/active.env

# 설정 검증 및 리로드
nginx -t && nginx -s reload
```

#### 4. 부분적 서비스 장애 (Partial Service Failure)

**증상**: 일부 서비스만 UNHEALTHY 상태

**해결 우선순위**:
1. **NGINX 프록시 우선**: 가장 중요한 구성 요소
2. **활성 환경 우선**: 현재 트래픽 처리 중인 환경
3. **API 서버**: 배포 기능에만 영향
4. **비활성 환경**: 가장 낮은 우선순위

### Emergency Procedures

#### 완전 시스템 복구

```bash
# 1단계: 컨테이너 재시작
docker restart blue-green-nginx

# 2단계: 기본 설정으로 복원
docker exec blue-green-nginx sh -c 'echo "set \$active \"blue\";" > /etc/nginx/conf.d/active.env'

# 3단계: NGINX 재시작
docker exec blue-green-nginx nginx -s reload

# 4단계: 상태 확인
./health-check.sh
```

## 📋 Pre-Deployment Checklist

### 배포 전 점검사항

- [ ] **대상 환경 헬스체크** 통과 확인
- [ ] **현재 활성 환경** 식별 및 기록
- [ ] **백업 설정** 파일 존재 확인
- [ ] **롤백 계획** 준비 완료
- [ ] **모니터링 도구** 준비 (로그, 대시보드)

### 배포 중 점검사항

- [ ] **헬스체크** 5회 연속 성공 확인
- [ ] **설정 파일 원자적 교체** 완료
- [ ] **NGINX 설정 검증** (`nginx -t`) 성공
- [ ] **무중단 리로드** (`nginx -s reload`) 성공
- [ ] **새 워커 프로세스** 시작 확인

### 배포 후 점검사항

- [ ] **전체 서비스 헬스체크** 통과
- [ ] **트래픽 전환** 확인 (실제 요청 테스트)
- [ ] **성능 지표** 이상 없음 확인
- [ ] **오류 로그** 새로운 에러 없음 확인
- [ ] **사용자 영향도** 최소화 확인

## 🔧 Advanced Configuration

### Canary Deployment (Optional)

새로운 판단 파일에서 제시된 단계적 전환:

```nginx
# conf.d/routing.conf 파일에 추가
split_clients "$remote_addr$request_id" $bucket {
    5%     "canary";
    *      "stable";
}

map $bucket $canary_backend {
    canary  green;
    stable  blue;
}

# 기본 $backend 대신 $canary_backend 사용
# location / {
#     proxy_pass http://$canary_backend;
# }
```

### Performance Tuning

```nginx
# upstreams.conf 최적화
upstream blue {
    server 127.0.0.1:3001;
    keepalive 32;
    keepalive_requests 100;
    keepalive_timeout 60s;
}

upstream green {
    server 127.0.0.1:3002;
    keepalive 32;
    keepalive_requests 100;
    keepalive_timeout 60s;
}
```

## 📞 Support Contacts

### Escalation Path

1. **Level 1**: 자동화된 헬스체크 및 롤백
2. **Level 2**: 운영팀 매뉴얼 개입
3. **Level 3**: 시스템 전문가 지원
4. **Level 4**: 벤더 기술 지원

### Monitoring Dashboards

- **Admin Interface**: http://localhost:8080
- **Health Check API**: http://localhost:9000/health
- **NGINX Status**: http://localhost:80/status

---

## 📝 Change Log

### Version 2.0 (새로운 판단 파일 기반)

- ✅ 원자적 파일 교체 구현
- ✅ 향상된 헬스체크 로직
- ✅ 자동 롤백 메커니즘
- ✅ 실시간 모니터링 대시보드
- ✅ 포괄적인 운영 가이드

### Version 1.0 (Legacy)

- ⚠️ 기본적인 블루/그린 전환
- ⚠️ 단순한 헬스체크
- ⚠️ 수동 롤백 필요

---

*Based on **새로운 판단 파일** NGINX Official Best Practices*  
*Implements atomic file replacement, enhanced health checks, and graceful rollback mechanisms*