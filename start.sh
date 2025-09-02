#!/usr/bin/env bash
set -e  # 오류 시 스크립트 종료

# 빌드 시 검증 요청 처리
if [[ "${1:-}" == "--version" ]]; then
    echo "Blue-Green Deployment System v1.0"
    exit 0
fi

echo "🚀 Starting Blue-Green Deployment System..."

# 파일 시스템 동기화 대기 (Windows Docker 호환성)
echo "📁 Checking configuration files..."
sleep 2

# Nginx 설정 파일 검증
if [ ! -f "/etc/nginx/nginx.conf" ]; then
    echo "❌ Error: nginx.conf not found!"
    exit 1
fi

if [ ! -d "/etc/nginx/conf.d" ]; then
    echo "❌ Error: conf.d directory not found!"
    exit 1
fi

echo "✅ Configuration files verified"

# 서버 시작
echo "🔵 Starting Blue Server on port 3001..."
node /app/blue-server/app.js &
BLUE_PID=$!

echo "🟢 Starting Green Server on port 3002..."
node /app/green-server/app.js &
GREEN_PID=$!

echo "🔧 Starting API Server on port 9000..."
cd /app/api-server && node app.js &
API_PID=$!

# 서버 준비 대기 및 헬스체크
echo "⏳ Waiting for servers to start..."
sleep 5

# 서버 헬스체크 함수
check_server() {
    local name="$1"
    local port="$2"
    local max_attempts=10
    
    echo "🔍 Checking $name server on port $port..."
    
    for i in $(seq 1 $max_attempts); do
        if curl -s -o /dev/null --max-time 3 "http://localhost:$port/health"; then
            echo "✅ $name server is ready (attempt $i)"
            return 0
        fi
        echo "⏳ $name server not ready yet (attempt $i/$max_attempts)..."
        sleep 2
    done
    
    echo "❌ $name server failed to start after $max_attempts attempts"
    return 1
}

# 각 서버 헬스체크
if ! check_server "Blue" 3001; then
    echo "💥 Blue server startup failed"
    kill $BLUE_PID $GREEN_PID $API_PID 2>/dev/null || true
    exit 1
fi

if ! check_server "Green" 3002; then
    echo "💥 Green server startup failed"
    kill $BLUE_PID $GREEN_PID $API_PID 2>/dev/null || true
    exit 1
fi

if ! check_server "API" 9000; then
    echo "⚠️ API server startup failed (non-critical)"
    # API 서버는 선택적이므로 계속 진행
fi

# Nginx 설정 테스트
echo "🔍 Testing Nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
    echo "✅ Nginx configuration is valid"
    echo "🌐 Starting Nginx..."
    echo "🚀 All services are ready!"
    echo "📊 Service Status:"
    echo "  - Blue Server: http://localhost:3001/health"
    echo "  - Green Server: http://localhost:3002/health" 
    echo "  - API Server: http://localhost:9000/health"
    echo "  - NGINX Proxy: http://localhost:80/status"
    echo "  - Admin Interface: http://localhost:8080"
    exec nginx -g "daemon off;"
else
    echo "❌ Nginx configuration test failed!"
    # 서버 프로세스 정리
    kill $BLUE_PID $GREEN_PID $API_PID 2>/dev/null || true
    exit 1
fi
