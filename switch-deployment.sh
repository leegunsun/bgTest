#!/usr/bin/env bash
#
# Enhanced Blue-Green Deployment Switch Script
# Based on NGINX Official Best Practices (새로운 판단 파일)
# Implements: atomic file replacement, enhanced health checks, proper error handling
#

set -euo pipefail

# Configuration
ACTIVE_FILE="/etc/nginx/conf.d/active.env"
NEW="$1"

# Validate input
if [[ "$NEW" != "blue" && "$NEW" != "green" ]]; then
    echo "Usage: $0 {blue|green}" >&2
    exit 2
fi

# Enhanced health check with timeout and comprehensive validation
enhanced_health_check() {
    local target_color="$1"
    local probe_port probe_url
    
    # Port mapping
    [[ "$target_color" == "green" ]] && probe_port=3002 || probe_port=3001
    probe_url="http://127.0.0.1:$probe_port/health"
    
    echo "[헬스체크] 대상: $target_color (포트: $probe_port)"
    
    # Multi-level health validation
    local max_attempts=5
    local timeout=2
    
    for attempt in $(seq 1 $max_attempts); do
        echo "  시도 $attempt/$max_attempts: $probe_url"
        
        # Enhanced curl with proper timeout and headers
        if curl -fsS --max-time $timeout --connect-timeout 1 \
               -H "User-Agent: nginx-deployment-switch/1.0" \
               "$probe_url" >/dev/null 2>&1; then
            echo "  ✓ 헬스체크 성공: $target_color 환경 준비됨"
            return 0
        fi
        
        [[ $attempt -lt $max_attempts ]] && sleep 1
    done
    
    echo "  ✗ 헬스체크 실패: $target_color 환경 준비되지 않음"
    return 1
}

# Atomic file replacement (새로운 판단 파일 권장사항)
atomic_switch() {
    local new_color="$1"
    
    echo "[원자적 전환] 설정 파일 업데이트 중..."
    
    # Create temporary file with new configuration
    local temp_file
    temp_file=$(mktemp)
    
    # Write new configuration
    cat > "$temp_file" << EOF
# Active Environment Configuration
# This file controls which upstream group is active
# Modify this file to perform blue-green deployment switching
# Current active: $new_color
set \$active "$new_color";
EOF
    
    # Atomic replacement using install command (recommended by 새로운 판단 파일)
    if install -o root -g root -m 0644 "$temp_file" "$ACTIVE_FILE"; then
        echo "  ✓ 설정 파일 원자적 교체 완료"
        rm -f "$temp_file"
        return 0
    else
        echo "  ✗ 설정 파일 교체 실패"
        rm -f "$temp_file"
        return 1
    fi
}

# Enhanced configuration validation
validate_and_reload() {
    echo "[검증] NGINX 설정 문법 검사 중..."
    
    if nginx -t 2>/dev/null; then
        echo "  ✓ 설정 문법 검증 성공"
    else
        echo "  ✗ 설정 문법 오류 발견"
        nginx -t  # Show detailed error
        return 1
    fi
    
    echo "[리로드] 무중단 NGINX 리로드 실행 중..."
    
    if nginx -s reload; then
        echo "  ✓ NGINX 무중단 리로드 성공"
        echo "  📋 새 워커 프로세스 시작, 기존 워커 우아한 종료 진행 중"
        return 0
    else
        echo "  ✗ NGINX 리로드 실패"
        return 1
    fi
}

# Get current active environment
get_current_active() {
    if [[ -f "$ACTIVE_FILE" ]]; then
        grep 'set.*active' "$ACTIVE_FILE" | sed 's/.*"\([^"]*\)".*/\1/' || echo "blue"
    else
        echo "blue"
    fi
}

# Rollback function
rollback() {
    local original_color="$1"
    echo "🚨 [복구] $original_color 환경으로 롤백 실행 중..."
    
    if atomic_switch "$original_color" && validate_and_reload; then
        echo "  ✓ 롤백 성공: $original_color 환경으로 복구됨"
    else
        echo "  ✗ 롤백 실패: 수동 개입 필요"
        exit 3
    fi
}

# Main deployment process
main() {
    echo "🚀 [시작] NGINX Blue-Green 배포 전환 시작"
    echo "목표: $NEW 환경으로 전환"
    
    # Get current state
    local current_active
    current_active=$(get_current_active)
    echo "현재 활성: $current_active"
    
    # Skip if already active
    if [[ "$NEW" == "$current_active" ]]; then
        echo "ℹ️  $NEW 환경이 이미 활성 상태입니다"
        exit 0
    fi
    
    # Step 1: Health check target environment
    if ! enhanced_health_check "$NEW"; then
        echo "❌ 배포 중단: 대상 환경 헬스체크 실패"
        exit 1
    fi
    
    # Step 2: Atomic configuration update
    if ! atomic_switch "$NEW"; then
        echo "❌ 배포 중단: 설정 파일 업데이트 실패"
        exit 1
    fi
    
    # Step 3: Validate and reload
    if ! validate_and_reload; then
        echo "❌ 배포 실패: NGINX 검증/리로드 실패, 롤백 진행"
        rollback "$current_active"
        exit 1
    fi
    
    # Step 4: Post-deployment verification
    sleep 2  # Allow for graceful transition
    echo "[검증] 전환 후 상태 확인 중..."
    
    if enhanced_health_check "$NEW"; then
        echo "🎉 배포 성공: $NEW 환경으로 전환 완료"
        echo "📊 이전: $current_active → 현재: $NEW"
    else
        echo "⚠️  배포 완료되었으나 헬스체크 경고 발생"
        echo "   수동 확인을 권장합니다"
    fi
}

# Execute main function
main "$@"
