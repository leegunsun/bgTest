# Docker 기반 Blue-Green 배포 테스트

이 프로젝트는 Docker 컨테이너 내에서 Nginx를 사용하여 Blue-Green 배포를 테스트하는 환경을 제공합니다.

## 🏗️ 아키텍처

```
┌─────────────────────────────────────────────┐
│                Docker Container              │
│                                             │
│  ┌─────────┐    ┌──────────┐               │
│  │ Blue    │    │ Green    │               │
│  │ Server  │    │ Server   │               │
│  │ :3001   │    │ :3002    │               │
│  └─────────┘    └──────────┘               │
│       │              │                     │
│       └──────┬───────┘                     │
│              │                             │
│     ┌─────────▼─────────┐                  │
│     │ Nginx Load        │                  │
│     │ Balancer :80      │                  │
│     └─────────┬─────────┘                  │
│               │                            │
│     ┌─────────▼─────────┐                  │
│     │ Admin Interface   │                  │
│     │ :8080             │                  │
│     └───────────────────┘                  │
│                                             │
│     ┌───────────────────┐                  │
│     │ API Server :9000  │                  │
│     │ (Deployment       │                  │
│     │  Switching)       │                  │
│     └───────────────────┘                  │
└─────────────────────────────────────────────┘
```

## 🚀 빠른 시작

### 1. Docker Compose로 실행

```bash
# 컨테이너 빌드 및 실행
docker-compose up --build

# 백그라운드에서 실행
docker-compose up -d --build
```

### 2. 개별 Docker 명령어

```bash
# 이미지 빌드
docker build -t blue-green-deployment .

# 컨테이너 실행
docker run -d \
  --name blue-green-nginx \
  -p 80:80 \
  -p 8080:8080 \
  -p 3001:3001 \
  -p 3002:3002 \
  -p 9000:9000 \
  blue-green-deployment
```

## 🌐 접속 URL

- **메인 서비스**: http://localhost (현재 활성 배포)
- **관리자 패널**: http://localhost:8080 (배포 전환 인터페이스)
- **Blue 서버**: http://localhost:3001 (직접 접근)
- **Green 서버**: http://localhost:3002 (직접 접근)
- **API 서버**: http://localhost:9000 (배포 전환 API)

## 🔄 배포 전환 테스트

### 웹 인터페이스를 통한 전환

1. http://localhost:8080 접속
2. "Switch to BLUE" 또는 "Switch to GREEN" 버튼 클릭
3. "Health Check" 버튼으로 서버 상태 확인

### API를 통한 전환

```bash
# GREEN으로 전환
curl -X POST http://localhost/api/switch/green

# BLUE로 전환
curl -X POST http://localhost/api/switch/blue

# 현재 배포 확인
curl http://localhost/ | grep -o "BLUE\\|GREEN"
```

### 스크립트를 통한 전환

```bash
# 컨테이너 내부에서 실행
docker exec -it blue-green-nginx /app/switch-deployment.sh green
docker exec -it blue-green-nginx /app/switch-deployment.sh blue
```

## 🔍 모니터링

### 서버 상태 확인

```bash
# 전체 서비스 상태
curl http://localhost/status

# Blue 서버 헬스체크
curl http://localhost/blue/health

# Green 서버 헬스체크
curl http://localhost/green/health
```

### 로그 확인

```bash
# 컨테이너 로그 확인
docker logs -f blue-green-nginx

# Nginx 로그 확인
docker exec blue-green-nginx tail -f /var/log/nginx/access.log
docker exec blue-green-nginx tail -f /var/log/nginx/error.log
```

## 📁 프로젝트 구조

```
/app/
├── blue-server/
│   └── app.js          # Blue 배포 서버 (포트 3001)
├── green-server/
│   └── app.js          # Green 배포 서버 (포트 3002)
├── api-server/
│   └── app.js          # 배포 전환 API 서버 (포트 9000)
├── switch-deployment.sh # 배포 전환 스크립트
├── nginx.conf          # Nginx 설정
├── admin.html          # 관리자 인터페이스
├── Dockerfile          # Docker 이미지 정의
├── docker-compose.yml  # Docker Compose 설정
└── README.md          # 이 파일
```

## 🛠️ 개발 및 테스트

### 로컬 개발 환경에서 테스트

```bash
# Blue 서버 시작
node blue-server/app.js &

# Green 서버 시작  
node green-server/app.js &

# API 서버 시작
node api-server/app.js &

# Nginx 시작 (설정 파일 확인 후)
nginx -t && nginx
```

### 배포 전환 테스트

```bash
# GREEN으로 전환 테스트
./switch-deployment.sh green
curl http://localhost/ | grep GREEN

# BLUE로 전환 테스트
./switch-deployment.sh blue
curl http://localhost/ | grep BLUE
```

## 🔧 문제 해결

### Nginx 설정 문제

```bash
# 설정 파일 문법 확인
docker exec blue-green-nginx nginx -t

# Nginx 재시작
docker exec blue-green-nginx nginx -s reload
```

### 포트 충돌 해결

```bash
# 사용 중인 포트 확인
netstat -tulpn | grep -E ":80|:8080|:3001|:3002|:9000"

# Docker Compose에서 다른 포트 사용
# docker-compose.yml의 ports 섹션 수정
```

## 📝 주요 특징

- ✅ 무중단 배포 전환
- ✅ 헬스체크 자동 수행
- ✅ 웹 기반 관리 인터페이스
- ✅ REST API를 통한 프로그래매틱 제어
- ✅ Docker 컨테이너 기반 격리 환경
- ✅ 실시간 로그 모니터링

이 환경을 통해 Blue-Green 배포 패턴을 안전하게 테스트하고 학습할 수 있습니다.