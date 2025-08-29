#!/bin/bash

DEPLOYMENT=$1
NGINX_CONFIG="/etc/nginx/nginx.conf"
TEMP_CONFIG="/tmp/nginx.conf.tmp"

if [ "$DEPLOYMENT" = "blue" ]; then
    echo "Switching to BLUE deployment..."
    sed 's/server localhost:300[12]/server localhost:3001/' $NGINX_CONFIG > $TEMP_CONFIG
    
elif [ "$DEPLOYMENT" = "green" ]; then
    echo "Switching to GREEN deployment..."
    sed 's/server localhost:300[12]/server localhost:3002/' $NGINX_CONFIG > $TEMP_CONFIG
    
else
    echo "Usage: $0 [blue|green]"
    exit 1
fi

# 설정 파일 교체
mv $TEMP_CONFIG $NGINX_CONFIG

# Nginx 설정 테스트
nginx -t

if [ $? -eq 0 ]; then
    # 설정이 유효하면 리로드
    nginx -s reload
    echo "Successfully switched to $DEPLOYMENT deployment"
    
    # 헬스체크 수행
    sleep 1
    PORT=$([ "$DEPLOYMENT" = "blue" ] && echo "3001" || echo "3002")
    curl -s http://localhost:$PORT/health | grep -q "healthy"
    
    if [ $? -eq 0 ]; then
        echo "Health check passed for $DEPLOYMENT server"
    else
        echo "WARNING: Health check failed for $DEPLOYMENT server"
    fi
else
    echo "ERROR: Nginx configuration test failed"
    exit 1
fi
