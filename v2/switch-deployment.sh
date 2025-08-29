#!/bin/bash

DEPLOYMENT=$1
ACTIVE_BACKEND_CONFIG="/etc/nginx/conf.d/active_backend.conf"

# 현재 활성 환경 확인
get_current_backend() {
    if [ -f "$ACTIVE_BACKEND_CONFIG" ]; then
        grep 'default' "$ACTIVE_BACKEND_CONFIG" | awk '{print $2}' | sed 's/;//'
    else
        echo "blue_backend"  # 기본값
    fi
}

# 헬스체크 함수
health_check() {
    local backend=$1
    local port
    
    if [ "$backend" = "green_backend" ]; then
        port=3002
    else
        port=3001
    fi
    
    echo "환경 $backend (포트 $port) 헬스체크 시작..."
    
    for i in {1..10}; do
        if curl -s -f "http://127.0.0.1:$port/health" > /dev/null 2>&1; then
            echo "✓ 환경 $backend 헬스체크 성공"
            return 0
        fi
        echo "헬스체크 시도 $i/10..."
        sleep 1
    done
    
    echo "✗ 환경 $backend 헬스체크 실패"
    return 1
}

# 백엔드 전환
switch_backend() {
    local new_backend=$1
    
    echo "백엔드를 $new_backend로 전환 중..."
    
    # 백업 생성
    if [ -f "$ACTIVE_BACKEND_CONFIG" ]; then
        cp "$ACTIVE_BACKEND_CONFIG" "${ACTIVE_BACKEND_CONFIG}.backup"
    fi
    
    # 새 설정 작성
    cat > "$ACTIVE_BACKEND_CONFIG" << EOF
# 활성 백엔드 정의 - map 지시어 사용
# 이 파일을 수정하여 블루-그린 전환 수행
map \$uri \$active_backend {
    default $new_backend;
}
EOF
    
    # nginx 설정 검증
    if nginx -t > /dev/null 2>&1; then
        # nginx reload (무중단)
        if nginx -s reload; then
            echo "✓ nginx 설정 리로드 성공"
            return 0
        else
            echo "✗ nginx 리로드 실패"
            return 1
        fi
    else
        echo "✗ nginx 설정 검증 실패"
        # 백업으로 복원
        if [ -f "${ACTIVE_BACKEND_CONFIG}.backup" ]; then
            mv "${ACTIVE_BACKEND_CONFIG}.backup" "$ACTIVE_BACKEND_CONFIG"
        fi
        return 1
    fi
}

if [ "$DEPLOYMENT" = "blue" ]; then
    new_backend="blue_backend"
elif [ "$DEPLOYMENT" = "green" ]; then
    new_backend="green_backend"
else
    echo "Usage: $0 [blue|green]"
    exit 1
fi

current_backend=$(get_current_backend)
echo "현재 활성 환경: $current_backend"
echo "$new_backend 환경으로 전환 준비..."

# 새 환경 헬스체크
if ! health_check $new_backend; then
    echo "✗ 배포 중단: 새 환경이 준비되지 않음"
    exit 1
fi

# 백엔드 전환
if switch_backend $new_backend; then
    echo "✓ 성공적으로 $new_backend로 전환 완료"
    echo "배포 완료!"
else
    echo "✗ 백엔드 전환 실패"
    exit 1
fi
