#!/bin/bash
#
# Blue-Green Deployment Script for Gradle Spring Boot Application
# 기존 개발 환경을 유지하면서 Blue-Green 배포 기능 추가
#

set -euo pipefail

# Configuration
BASE_DIR="/home/ubuntu/dev/woori_be"
BLUE_DIR="$BASE_DIR/blue"
GREEN_DIR="$BASE_DIR/green"
DEPLOYMENT_DIR="$BASE_DIR/deployment"

BLUE_PORT=8081
GREEN_PORT=8083
JAR_NAME="woori_be.jar"

# 현재 활성 환경 상태 파일
ACTIVE_ENV_FILE="$DEPLOYMENT_DIR/active_env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 현재 활성 환경 확인
get_current_active() {
    if [[ -f "$ACTIVE_ENV_FILE" ]]; then
        cat "$ACTIVE_ENV_FILE"
    else
        echo "blue"  # 기본값
    fi
}

# 현재 활성 환경 설정
set_current_active() {
    local env="$1"
    echo "$env" > "$ACTIVE_ENV_FILE"
}

# 환경별 포트 반환
get_port() {
    local env="$1"
    if [[ "$env" == "blue" ]]; then
        echo "$BLUE_PORT"
    else
        echo "$GREEN_PORT"
    fi
}

# 환경별 디렉토리 반환
get_env_dir() {
    local env="$1"
    if [[ "$env" == "blue" ]]; then
        echo "$BLUE_DIR"
    else
        echo "$GREEN_DIR"
    fi
}

# Spring Boot 애플리케이션 시작
start_app() {
    local env="$1"
    local env_dir=$(get_env_dir "$env")
    local port=$(get_port "$env")
    
    log "Starting $env environment on port $port..."
    
    cd "$env_dir"
    
    # 기존 프로세스 확인 및 종료
    if pgrep -f "woori_be.jar.*server.port=$port" > /dev/null; then
        warn "$env environment is already running. Stopping first..."
        stop_app "$env"
        sleep 3
    fi
    
    # .env 파일이 있는지 확인
    if [[ ! -f "$env_dir/.env" ]]; then
        error ".env file not found in $env_dir"
        return 1
    fi
    
    # JAR 파일이 있는지 확인
    if [[ ! -f "$env_dir/$JAR_NAME" ]]; then
        error "JAR file $JAR_NAME not found in $env_dir"
        return 1
    fi
    
    # Spring Boot 애플리케이션 시작 (백그라운드)
    nohup java -jar \
        -Dserver.port="$port" \
        -Dspring.profiles.active="dev,$env" \
        -Xms512m -Xmx1024m \
        "$env_dir/$JAR_NAME" \
        > "$env_dir/app.log" 2>&1 &
    
    local pid=$!
    echo "$pid" > "$env_dir/app.pid"
    
    log "$env environment started with PID $pid on port $port"
    return 0
}

# Spring Boot 애플리케이션 중지
stop_app() {
    local env="$1"
    local env_dir=$(get_env_dir "$env")
    local port=$(get_port "$env")
    
    log "Stopping $env environment..."
    
    # PID 파일로 종료 시도
    if [[ -f "$env_dir/app.pid" ]]; then
        local pid=$(cat "$env_dir/app.pid")
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid"
            sleep 5
            if kill -0 "$pid" 2>/dev/null; then
                warn "Graceful shutdown failed, forcing kill..."
                kill -KILL "$pid"
            fi
        fi
        rm -f "$env_dir/app.pid"
    fi
    
    # 포트로 프로세스 찾아서 종료
    local pids=$(pgrep -f "woori_be.jar.*server.port=$port" || true)
    if [[ -n "$pids" ]]; then
        for pid in $pids; do
            kill -TERM "$pid" 2>/dev/null || true
            sleep 2
            kill -KILL "$pid" 2>/dev/null || true
        done
    fi
    
    log "$env environment stopped"
}

# 헬스체크
health_check() {
    local env="$1"
    local port=$(get_port "$env")
    local max_attempts=30
    local attempt=1
    
    log "Running health check for $env environment (port $port)..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "http://localhost:$port/actuator/health" > /dev/null 2>&1; then
            log "✓ $env environment health check passed (attempt $attempt/$max_attempts)"
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            error "✗ $env environment health check failed after $max_attempts attempts"
            return 1
        fi
        
        echo "Attempt $attempt/$max_attempts - waiting for service..."
        sleep 5
        ((attempt++))
    done
}

# nginx 설정 업데이트 (nginx가 설치되어 있는 경우)
update_nginx() {
    local env="$1"
    local port=$(get_port "$env")
    
    # nginx가 설치되어 있고 설정 파일이 있는 경우만 업데이트
    if command -v nginx >/dev/null 2>&1 && [[ -f "/etc/nginx/sites-available/default" ]]; then
        log "Updating nginx configuration for $env environment..."
        
        # nginx 설정에서 proxy_pass 포트 변경
        sudo sed -i "s/proxy_pass http:\/\/localhost:[0-9]*;/proxy_pass http:\/\/localhost:$port;/g" \
            /etc/nginx/sites-available/default
        
        # nginx 설정 테스트
        if sudo nginx -t; then
            sudo nginx -s reload
            log "nginx configuration updated and reloaded"
        else
            error "nginx configuration test failed"
            return 1
        fi
    else
        warn "nginx not found or not configured. Skipping nginx update."
        log "Direct access: Blue(port $BLUE_PORT), Green(port $GREEN_PORT)"
    fi
}

# 배포 함수
deploy() {
    local target_env="$1"
    local current_env=$(get_current_active)
    
    log "🚀 Starting deployment to $target_env environment"
    log "Current active environment: $current_env"
    
    # 대상 환경 중지
    stop_app "$target_env"
    
    # 대상 환경 시작
    if ! start_app "$target_env"; then
        error "Failed to start $target_env environment"
        exit 1
    fi
    
    # 헬스체크
    if ! health_check "$target_env"; then
        error "Health check failed for $target_env environment"
        log "Rolling back by stopping $target_env..."
        stop_app "$target_env"
        exit 1
    fi
    
    log "✅ Deployment to $target_env completed successfully"
    log "Ready for traffic switching. Run: $0 switch $target_env"
}

# 트래픽 전환 함수
switch() {
    local target_env="$1"
    local current_env=$(get_current_active)
    
    if [[ "$target_env" == "$current_env" ]]; then
        warn "$target_env is already the active environment"
        return 0
    fi
    
    log "🔄 Switching traffic from $current_env to $target_env"
    
    # 대상 환경 헬스체크
    if ! health_check "$target_env"; then
        error "Cannot switch to $target_env - health check failed"
        exit 1
    fi
    
    # nginx 설정 업데이트 (있는 경우)
    update_nginx "$target_env"
    
    # 활성 환경 업데이트
    set_current_active "$target_env"
    
    log "🎉 Traffic switched to $target_env environment"
    log "Previous environment $current_env is still running for rollback"
}

# 환경 정리 함수
cleanup() {
    local target_env="$1"
    local current_env=$(get_current_active)
    
    if [[ "$target_env" == "$current_env" ]]; then
        error "Cannot cleanup active environment $target_env"
        exit 1
    fi
    
    log "🧹 Cleaning up $target_env environment"
    stop_app "$target_env"
    log "Cleanup completed"
}

# 상태 확인 함수
status() {
    local current_env=$(get_current_active)
    
    log "=== Blue-Green Deployment Status ==="
    log "Current active environment: $current_env"
    echo
    
    for env in blue green; do
        local port=$(get_port "$env")
        local env_dir=$(get_env_dir "$env")
        
        echo -e "${BLUE}=== $env Environment (Port $port) ===${NC}"
        
        if pgrep -f "woori_be.jar.*server.port=$port" > /dev/null; then
            echo -e "Status: ${GREEN}RUNNING${NC}"
            local pid=$(pgrep -f "woori_be.jar.*server.port=$port")
            echo "PID: $pid"
            
            if curl -sf "http://localhost:$port/actuator/health" > /dev/null 2>&1; then
                echo -e "Health: ${GREEN}HEALTHY${NC}"
            else
                echo -e "Health: ${RED}UNHEALTHY${NC}"
            fi
        else
            echo -e "Status: ${RED}STOPPED${NC}"
        fi
        
        if [[ -f "$env_dir/$JAR_NAME" ]]; then
            local jar_date=$(stat -c %y "$env_dir/$JAR_NAME" 2>/dev/null || echo "Unknown")
            echo "JAR Date: $jar_date"
        else
            echo -e "JAR File: ${RED}NOT FOUND${NC}"
        fi
        
        echo
    done
}

# 사용법 출력
usage() {
    echo "Usage: $0 {deploy|switch|cleanup|status} [blue|green]"
    echo
    echo "Commands:"
    echo "  deploy <env>   - Deploy application to specified environment"
    echo "  switch <env>   - Switch traffic to specified environment"
    echo "  cleanup <env>  - Stop and cleanup specified environment"
    echo "  status         - Show current deployment status"
    echo
    echo "Examples:"
    echo "  $0 deploy green    # Deploy to green environment"
    echo "  $0 switch green    # Switch traffic to green"
    echo "  $0 cleanup blue    # Cleanup blue environment"
    echo "  $0 status          # Show status"
}

# 초기 설정
init() {
    log "Initializing Blue-Green deployment structure..."
    
    # 디렉토리 생성
    mkdir -p "$BLUE_DIR" "$GREEN_DIR" "$DEPLOYMENT_DIR"
    
    # 기본 활성 환경 설정
    if [[ ! -f "$ACTIVE_ENV_FILE" ]]; then
        set_current_active "blue"
        log "Default active environment set to blue"
    fi
    
    log "Initialization completed"
}

# 메인 함수
main() {
    local command="${1:-}"
    local environment="${2:-}"
    
    case "$command" in
        init)
            init
            ;;
        deploy)
            if [[ -z "$environment" || ! "$environment" =~ ^(blue|green)$ ]]; then
                error "Invalid environment. Use 'blue' or 'green'"
                usage
                exit 1
            fi
            deploy "$environment"
            ;;
        switch)
            if [[ -z "$environment" || ! "$environment" =~ ^(blue|green)$ ]]; then
                error "Invalid environment. Use 'blue' or 'green'"
                usage
                exit 1
            fi
            switch "$environment"
            ;;
        cleanup)
            if [[ -z "$environment" || ! "$environment" =~ ^(blue|green)$ ]]; then
                error "Invalid environment. Use 'blue' or 'green'"
                usage
                exit 1
            fi
            cleanup "$environment"
            ;;
        status)
            status
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# 스크립트 실행
main "$@"