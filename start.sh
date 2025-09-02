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
node /app/api-server/app.js &
API_PID=$!

# 서버 준비 대기
echo "⏳ Waiting for servers to start..."
sleep 3

# Nginx 설정 테스트
echo "🔍 Testing Nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
    echo "✅ Nginx configuration is valid"
    echo "🌐 Starting Nginx..."
    exec nginx -g "daemon off;"
else
    echo "❌ Nginx configuration test failed!"
    # 서버 프로세스 정리
    kill $BLUE_PID $GREEN_PID $API_PID 2>/dev/null || true
    exit 1
fi
