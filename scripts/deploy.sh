#!/usr/bin/env bash
#
# True Blue-Green Deployment Management Script v2.0
# For use with separated container architecture
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if system is running
is_system_running() {
    docker ps --filter "name=nginx-proxy" --format "table {{.Names}}" | grep -q nginx-proxy 2>/dev/null
}

# Get current active environment
get_active_environment() {
    if is_system_running; then
        docker exec nginx-proxy cat /etc/nginx/conf.d/active.env 2>/dev/null | grep -o "blue\|green" || echo "unknown"
    else
        echo "system_down"
    fi
}

# Health check function
check_service_health() {
    local service_name="$1"
    local url="$2"
    local timeout="${3:-3}"
    
    if curl -fsS --max-time "$timeout" --connect-timeout 1 "$url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Switch traffic between environments
switch_traffic() {
    local target="$1"
    
    if [[ "$target" != "blue" && "$target" != "green" ]]; then
        error "Invalid target: $target. Must be 'blue' or 'green'"
        return 1
    fi
    
    log "🔄 Switching traffic to $target environment..."
    
    if ! is_system_running; then
        error "System is not running. Please start the system first."
        return 1
    fi
    
    # Use API to switch traffic
    local response
    response=$(curl -s -X POST "http://localhost:9000/switch/$target" 2>/dev/null || echo '{"success":false,"error":"API call failed"}')
    
    local success
    success=$(echo "$response" | jq -r '.success' 2>/dev/null || echo "false")
    
    if [[ "$success" == "true" ]]; then
        log "✅ Traffic successfully switched to $target"
        
        # Verify the switch
        sleep 2
        if check_service_health "Main proxy" "http://localhost:80/status" 3; then
            log "✅ Traffic switch verification successful"
            return 0
        else
            warn "⚠️  Traffic switch completed but verification had issues"
            return 1
        fi
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error' 2>/dev/null || echo "Unknown error")
        error "❌ Traffic switch failed: $error_msg"
        return 1
    fi
}

# Deploy to specific environment with version
deploy_to_environment() {
    local env="$1"
    local version="${2:-latest}"
    
    if [[ "$env" != "blue" && "$env" != "green" ]]; then
        error "Invalid environment: $env. Must be 'blue' or 'green'"
        return 1
    fi
    
    log "🚀 Deploying version $version to $env environment..."
    
    # Set version environment variables for deployment
    local version_var="${env^^}_VERSION"
    export "$version_var=$version"
    
    log "🔧 Setting deployment configuration: $version_var=$version"
    
    # Stop and rebuild the target environment
    log "🛑 Stopping $env environment..."
    docker-compose -f "$COMPOSE_FILE" stop "${env}-app" 2>/dev/null || true
    docker-compose -f "$COMPOSE_FILE" rm -f "${env}-app" 2>/dev/null || true
    
    log "🏗️  Rebuilding $env environment with version $version..."
    docker-compose -f "$COMPOSE_FILE" build "${env}-app"
    
    log "🚀 Starting $env environment..."
    docker-compose -f "$COMPOSE_FILE" up -d "${env}-app"
    
    # Wait for health check with dynamic port detection
    log "⏳ Waiting for $env environment to be healthy..."
    local port
    [[ "$env" == "green" ]] && port=3002 || port=3001
    
    # Wait for deployment metadata to be created
    sleep 3
    
    for attempt in {1..20}; do
        if check_service_health "$env server" "http://localhost:$port/health" 3; then
            log "✅ $env environment is healthy"
            
            # Validate version deployment
            local deployed_version
            deployed_version=$(curl -fsS "http://localhost:$port/version" 2>/dev/null | jq -r '.version' 2>/dev/null || echo "unknown")
            
            if [[ "$deployed_version" == "$version" ]]; then
                log "✅ Version validation successful: $deployed_version"
                
                # Show deployment metadata
                local deployment_info
                deployment_info=$(curl -fsS "http://localhost:$port/deployment" 2>/dev/null | jq -r '.deployment_id' 2>/dev/null || echo "unknown")
                log "📦 Deployment ID: $deployment_info"
                
                return 0
            else
                warn "⚠️  Version mismatch: expected $version, got $deployed_version"
            fi
        fi
        
        if [[ $attempt -eq 20 ]]; then
            error "❌ $env environment failed to become healthy after 20 attempts"
            return 1
        fi
        
        info "⏳ $env environment not ready yet (attempt $attempt/20)..."
        sleep 5
    done
}

# Full system status
show_status() {
    info "📊 Blue-Green Deployment System Status"
    echo "========================================="
    
    if is_system_running; then
        log "✅ System is running"
        
        local current_active
        current_active=$(get_active_environment)
        info "🎯 Active environment: $current_active"
        
        echo ""
        info "Service Health Status:"
        echo "----------------------"
        
        # Check all services
        check_service_health "NGINX Proxy" "http://localhost:80/status" 3 && \
            echo -e "  ✅ NGINX Proxy: ${GREEN}HEALTHY${NC}" || \
            echo -e "  ❌ NGINX Proxy: ${RED}UNHEALTHY${NC}"
            
        check_service_health "Blue App" "http://localhost:3001/health" 3 && \
            echo -e "  ✅ Blue App: ${GREEN}HEALTHY${NC}" || \
            echo -e "  ❌ Blue App: ${RED}UNHEALTHY${NC}"
            
        check_service_health "Green App" "http://localhost:3002/health" 3 && \
            echo -e "  ✅ Green App: ${GREEN}HEALTHY${NC}" || \
            echo -e "  ❌ Green App: ${RED}UNHEALTHY${NC}"
            
        check_service_health "API Server" "http://localhost:9000/health" 3 && \
            echo -e "  ✅ API Server: ${GREEN}HEALTHY${NC}" || \
            echo -e "  ❌ API Server: ${RED}UNHEALTHY${NC}"
        
        echo ""
        info "Container Status:"
        docker ps --filter "network=bluegreen-network" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        
    else
        warn "⚠️  System is not running"
        echo ""
        info "To start the system:"
        echo "  docker-compose -f docker-compose.yml up -d"
    fi
}

# Start the entire system
start_system() {
    log "🚀 Starting Blue-Green deployment system..."
    
    # Ensure we're in the right directory
    cd "$PROJECT_DIR"
    
    if is_system_running; then
        warn "⚠️  System is already running"
        show_status
        return 0
    fi
    
    log "🏗️  Building and starting all services..."
    docker-compose -f "$COMPOSE_FILE" build
    docker-compose -f "$COMPOSE_FILE" up -d
    
    log "⏳ Waiting for services to be ready..."
    sleep 30
    
    # Verify system health
    local healthy=true
    
    for service in "nginx-proxy:80/status" "blue-app:3001/health" "green-app:3002/health" "api-server:9000/health"; do
        local name="${service%%:*}"
        local endpoint="http://localhost:${service#*:}"
        
        if check_service_health "$name" "$endpoint" 5; then
            log "✅ $name is healthy"
        else
            error "❌ $name failed to start properly"
            healthy=false
        fi
    done
    
    if [[ "$healthy" == "true" ]]; then
        log "🎉 System started successfully!"
        show_status
    else
        error "❌ System startup had issues"
        return 1
    fi
}

# Stop the entire system
stop_system() {
    log "🛑 Stopping Blue-Green deployment system..."
    
    cd "$PROJECT_DIR"
    docker-compose -f "$COMPOSE_FILE" down --timeout 30
    
    log "✅ System stopped"
}

# Version management functions
show_version_info() {
    info "📋 Version Information"
    echo "======================"
    
    if is_system_running; then
        local current_env
        current_env=$(get_active_environment)
        info "🎯 Active environment: $current_env"
        
        echo ""
        info "Current Deployed Versions:"
        echo "-------------------------"
        
        # Get version info from both environments
        for env in blue green; do
            local port
            [[ "$env" == "green" ]] && port=3002 || port=3001
            
            if check_service_health "$env server" "http://localhost:$port/health" 1; then
                local version deployment_id build_time
                version=$(curl -fsS "http://localhost:$port/version" 2>/dev/null | jq -r '.version' 2>/dev/null || echo "unknown")
                deployment_id=$(curl -fsS "http://localhost:$port/version" 2>/dev/null | jq -r '.deployment_id' 2>/dev/null || echo "unknown")
                build_time=$(curl -fsS "http://localhost:$port/version" 2>/dev/null | jq -r '.build_time' 2>/dev/null || echo "unknown")
                
                local status_icon
                [[ "$env" == "$current_env" ]] && status_icon="🟢 ACTIVE" || status_icon="🔵 STANDBY"
                
                echo -e "  ${env^^}: ${GREEN}$version${NC} ($deployment_id) $status_icon"
                [[ "$build_time" != "unknown" ]] && echo "       Built: $build_time"
            else
                echo -e "  ${env^^}: ${RED}UNHEALTHY${NC}"
            fi
        done
        
        echo ""
    else
        warn "⚠️  System is not running"
    fi
}

list_deployed_versions() {
    info "📚 Deployment Version History"
    echo "============================="
    
    # Check for deployment state directory
    local deploy_state_dir="$PROJECT_DIR/deployment_state"
    if [[ -d "$deploy_state_dir" ]]; then
        local history_file="$deploy_state_dir/deployment_history.json"
        if [[ -f "$history_file" ]]; then
            echo "Recent deployments:"
            cat "$history_file" 2>/dev/null | jq -r '.[] | "  \(.timestamp) - \(.version) to \(.environment) (ID: \(.deployment_id))"' 2>/dev/null || \
                echo "  No deployment history available"
        else
            echo "  No deployment history file found"
        fi
    else
        echo "  No deployment state directory found"
        echo "  Deploy a version first to start tracking history"
    fi
    
    echo ""
    show_version_info
}

rollback_to_version() {
    local target_version="$1"
    
    log "🔄 Rolling back to version $target_version..."
    
    if ! is_system_running; then
        error "System is not running. Please start the system first."
        return 1
    fi
    
    local current_env
    current_env=$(get_active_environment)
    
    # Find which environment has the target version
    local target_env=""
    for env in blue green; do
        local port
        [[ "$env" == "green" ]] && port=3002 || port=3001
        
        if check_service_health "$env server" "http://localhost:$port/health" 1; then
            local version
            version=$(curl -fsS "http://localhost:$port/version" 2>/dev/null | jq -r '.version' 2>/dev/null || echo "unknown")
            
            if [[ "$version" == "$target_version" ]]; then
                target_env="$env"
                break
            fi
        fi
    done
    
    if [[ -n "$target_env" ]]; then
        if [[ "$target_env" == "$current_env" ]]; then
            log "✅ Version $target_version is already active in $current_env environment"
        else
            log "🔄 Rolling back by switching to $target_env environment (version $target_version)"
            switch_traffic "$target_env"
        fi
    else
        warn "⚠️  Version $target_version not found in any environment"
        log "🚀 Deploying version $target_version to inactive environment..."
        
        local inactive_env
        [[ "$current_env" == "blue" ]] && inactive_env="green" || inactive_env="blue"
        
        deploy_to_environment "$inactive_env" "$target_version" && \
        switch_traffic "$inactive_env"
    fi
}

# Zero-downtime deployment test
test_zero_downtime() {
    local duration="${1:-30}"
    
    if ! is_system_running; then
        error "System is not running. Please start the system first."
        return 1
    fi
    
    log "🧪 Starting zero-downtime test (duration: ${duration}s)..."
    
    local start_time
    start_time=$(date +%s)
    
    local total_checks=0
    local failed_checks=0
    local current_env
    local switches=0
    
    current_env=$(get_active_environment)
    log "🎯 Starting with $current_env environment active"
    
    # Background monitoring
    while [[ $(($(date +%s) - start_time)) -lt $duration ]]; do
        total_checks=$((total_checks + 1))
        
        if check_service_health "System" "http://localhost:80/status" 1; then
            # Occasionally log success
            if [[ $((total_checks % 50)) -eq 0 ]]; then
                info "📊 Service available - checks: $total_checks, failures: $failed_checks"
            fi
        else
            failed_checks=$((failed_checks + 1))
            error "❌ DOWNTIME DETECTED - Check #$total_checks failed"
        fi
        
        # Switch environments every 15 seconds
        if [[ $((total_checks % 100)) -eq 0 ]] && [[ $switches -lt 2 ]]; then
            local next_env
            [[ "$current_env" == "blue" ]] && next_env="green" || next_env="blue"
            
            log "🔄 Testing deployment switch: $current_env → $next_env"
            
            if switch_traffic "$next_env"; then
                current_env="$next_env"
                switches=$((switches + 1))
                log "✅ Switch completed successfully"
            else
                error "❌ Switch failed"
            fi
        fi
        
        sleep 0.1
    done
    
    local end_time
    end_time=$(date +%s)
    local actual_duration=$((end_time - start_time))
    
    # Results
    log ""
    log "📊 Zero-Downtime Test Results:"
    log "   Duration: ${actual_duration} seconds"
    log "   Total checks: $total_checks"
    log "   Failed checks: $failed_checks"
    log "   Deployment switches: $switches"
    
    if [[ $failed_checks -eq 0 ]]; then
        log "🎉 ✅ ZERO-DOWNTIME TEST PASSED"
        log "   Perfect availability: 100%"
        return 0
    else
        local availability
        availability=$(echo "scale=2; (1 - $failed_checks/$total_checks)*100" | bc -l 2>/dev/null || echo "99")
        error "❌ ZERO-DOWNTIME TEST FAILED"
        error "   Failed checks: $failed_checks"
        error "   Availability: ${availability}%"
        return 1
    fi
}

# Main command handling
main() {
    case "${1:-help}" in
        "start")
            start_system
            ;;
        "stop")
            stop_system
            ;;
        "status")
            show_status
            ;;
        "switch")
            if [[ -n "${2:-}" ]]; then
                switch_traffic "$2"
            else
                error "Usage: $0 switch {blue|green}"
                exit 1
            fi
            ;;
        "deploy")
            if [[ -n "${2:-}" ]]; then
                deploy_to_environment "$2" "${3:-latest}"
            else
                error "Usage: $0 deploy {blue|green} [version]"
                exit 1
            fi
            ;;
        "test")
            test_zero_downtime "${2:-30}"
            ;;
        "bluegreen")
            # Full blue-green deployment flow with version support
            local version="${2:-latest}"
            local current_env
            current_env=$(get_active_environment)
            
            if [[ "$current_env" == "system_down" ]]; then
                log "Starting system for first time..."
                start_system
                current_env="blue"  # Default after startup
            fi
            
            local target_env
            [[ "$current_env" == "blue" ]] && target_env="green" || target_env="blue"
            
            log "🚀 Executing full Blue-Green deployment flow"
            log "   Version: $version"
            log "   Current: $current_env → Target: $target_env"
            
            deploy_to_environment "$target_env" "$version" && \
            switch_traffic "$target_env" && \
            log "🎉 Blue-Green deployment completed successfully!"
            ;;
        "version")
            # Version management commands
            case "${2:-show}" in
                "show")
                    show_version_info
                    ;;
                "list")
                    list_deployed_versions
                    ;;
                "rollback")
                    if [[ -n "${3:-}" ]]; then
                        rollback_to_version "$3"
                    else
                        error "Usage: $0 version rollback {version}"
                        exit 1
                    fi
                    ;;
                *)
                    error "Usage: $0 version {show|list|rollback} [version]"
                    exit 1
                    ;;
            esac
            ;;
        "help"|*)
            echo "True Blue-Green Deployment Management v2.1"
            echo "Usage: $0 {command} [options]"
            echo ""
            echo "System Commands:"
            echo "  start                      - Start the entire Blue-Green system"
            echo "  stop                       - Stop the entire system"
            echo "  status                     - Show system and service status"
            echo "  test [duration]            - Run zero-downtime test (default: 30s)"
            echo ""
            echo "Deployment Commands:"
            echo "  deploy {color} [version]   - Deploy specific version to environment"
            echo "  switch {color}             - Switch traffic to blue or green"
            echo "  bluegreen [version]        - Execute full Blue-Green deployment"
            echo ""
            echo "Version Management:"
            echo "  version show               - Show current deployed versions"
            echo "  version list               - List deployment history"
            echo "  version rollback {version} - Rollback to specific version"
            echo ""
            echo "Examples:"
            echo "  $0 start                     # Start the system"
            echo "  $0 status                    # Check system status"
            echo "  $0 deploy green 2.1.0        # Deploy version 2.1.0 to green"
            echo "  $0 switch green              # Switch traffic to green"
            echo "  $0 bluegreen 2.1.0           # Full deployment with version 2.1.0"
            echo "  $0 version show              # Show current versions"
            echo "  $0 version rollback 2.0.0    # Rollback to version 2.0.0"
            echo "  $0 test 60                   # 60-second zero-downtime test"
            ;;
    esac
}

# Execute main function
main "$@"