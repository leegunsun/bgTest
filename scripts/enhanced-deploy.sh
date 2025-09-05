#!/usr/bin/env bash
#
# Enhanced Blue-Green Deployment Management Script v3.0
# Complete load balancing with gradual migration and dual update cycle
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
ENHANCED_API_URL="http://localhost:9000"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

progress() {
    echo -e "${PURPLE}[PROGRESS]${NC} $1"
}

# Enhanced system status with load balancing information
show_enhanced_status() {
    info "📊 Enhanced Blue-Green Deployment System Status"
    echo "================================================="
    
    if ! is_system_running; then
        warn "⚠️  System is not running"
        echo ""
        info "To start the system:"
        echo "  ./enhanced-deploy.sh start"
        return
    fi
    
    # Get comprehensive status from enhanced API
    local api_status
    api_status=$(curl -s --max-time 5 "$ENHANCED_API_URL/status" 2>/dev/null || echo '{}')
    
    if [[ -n "$api_status" ]] && echo "$api_status" | jq -e . >/dev/null 2>&1; then
        local active migration_status health_status
        active=$(echo "$api_status" | jq -r '.active // "unknown"')
        migration_status=$(echo "$api_status" | jq -r '.migration.status // "unknown"')
        
        echo -e "🎯 Current Active Environment: ${GREEN}$active${NC}"
        echo -e "🔄 Migration Status: ${PURPLE}$migration_status${NC}"
        
        # Show migration progress if in progress
        if [[ "$migration_status" == "migrating" ]]; then
            local target percentage
            target=$(echo "$api_status" | jq -r '.migration.target // "unknown"')
            percentage=$(echo "$api_status" | jq -r '.migration.percentage // 0')
            echo -e "   Target: $target (${percentage}% complete)"
        fi
        
        echo ""
        info "🏥 Environment Health Status:"
        echo "-----------------------------"
        
        # Check both environments with enhanced validation
        for env in blue green; do
            local port
            [[ "$env" == "green" ]] && port=3002 || port=3001
            
            if validate_environment_health "$env"; then
                local icon
                [[ "$env" == "$active" ]] && icon="🟢 ACTIVE" || icon="🔵 STANDBY"
                echo -e "  ${env^^}: ${GREEN}HEALTHY${NC} $icon"
            else
                echo -e "  ${env^^}: ${RED}UNHEALTHY${NC}"
            fi
        done
        
        echo ""
        info "📈 System Performance:"
        echo "---------------------"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
            nginx-proxy blue-app green-app api-server 2>/dev/null || \
            echo "  Performance data unavailable"
        
    else
        warn "Enhanced API unavailable - falling back to basic status"
        show_basic_status
    fi
}

# Basic status fallback
show_basic_status() {
    local current_active
    current_active=$(get_active_environment)
    
    echo -e "🎯 Active environment: $current_active"
    echo ""
    info "Service Health Status:"
    echo "----------------------"
    
    check_service_health "NGINX Proxy" "http://localhost:80/health" 3 && \
        echo -e "  ✅ NGINX Proxy: ${GREEN}HEALTHY${NC}" || \
        echo -e "  ❌ NGINX Proxy: ${RED}UNHEALTHY${NC}"
        
    check_service_health "Blue App" "http://localhost:3001/health" 3 && \
        echo -e "  ✅ Blue App: ${GREEN}HEALTHY${NC}" || \
        echo -e "  ❌ Blue App: ${RED}UNHEALTHY${NC}"
        
    check_service_health "Green App" "http://localhost:3002/health" 3 && \
        echo -e "  ✅ Green App: ${GREEN}HEALTHY${NC}" || \
        echo -e "  ❌ Green App: ${RED}UNHEALTHY${NC}"
}

# Enhanced environment health validation
validate_environment_health() {
    local env="$1"
    local port
    [[ "$env" == "green" ]] && port=3002 || port=3001
    
    # Multiple validation layers
    local docker_healthy http_healthy performance_good
    
    # Docker health check
    docker_healthy=$(docker inspect --format='{{.State.Health.Status}}' "${env}-app" 2>/dev/null | grep -q "healthy" && echo "true" || echo "false")
    
    # HTTP health check
    http_healthy=$(curl -f --max-time 3 "http://localhost:$port/health" >/dev/null 2>&1 && echo "true" || echo "false")
    
    # Performance check (response time < 1 second)
    local response_time
    response_time=$(curl -w "%{time_total}" -o /dev/null -s "http://localhost:$port/health" 2>/dev/null || echo "999")
    performance_good=$(echo "$response_time < 1.0" | bc -l 2>/dev/null && echo "true" || echo "false")
    
    # All checks must pass
    [[ "$docker_healthy" == "true" && "$http_healthy" == "true" && "$performance_good" == "true" ]]
}

# Enhanced gradual migration deployment
gradual_deployment() {
    local target_env="$1"
    local version="${2:-latest}"
    
    log "🚀 Starting Enhanced Gradual Blue-Green Deployment"
    echo "=================================================="
    log "Target: $target_env | Version: $version"
    
    if ! is_system_running; then
        error "System is not running. Please start the system first."
        return 1
    fi
    
    # Step 1: Pre-deployment validation
    progress "Step 1/6: Pre-deployment validation"
    if ! validate_dual_environments; then
        error "Pre-deployment validation failed"
        return 1
    fi
    
    # Step 2: Deploy to inactive environment
    progress "Step 2/6: Deploying to inactive environment"
    if ! deploy_to_environment "$target_env" "$version"; then
        error "Deployment to inactive environment failed"
        return 1
    fi
    
    # Step 3: Post-deployment health validation
    progress "Step 3/6: Post-deployment health validation"
    sleep 10 # Allow environment to stabilize
    if ! validate_environment_health "$target_env"; then
        error "Post-deployment health validation failed"
        return 1
    fi
    
    # Step 4: Gradual traffic migration via enhanced API
    progress "Step 4/6: Gradual traffic migration"
    if ! perform_gradual_migration "$target_env"; then
        error "Gradual migration failed"
        return 1
    fi
    
    # Step 5: Post-migration validation
    progress "Step 5/6: Post-migration validation"
    if ! validate_migration_success "$target_env"; then
        error "Post-migration validation failed"
        warn "Consider manual rollback if necessary"
        return 1
    fi
    
    # Step 6: Finalization
    progress "Step 6/6: Deployment finalization"
    log_deployment_success "$target_env" "$version"
    
    success "🎉 Enhanced Gradual Deployment Completed Successfully!"
    echo "   Target Environment: $target_env"
    echo "   Version: $version"
    echo "   Migration Type: Gradual (25% → 50% → 75% → 100%)"
    
    return 0
}

# Validate both environments are ready for migration
validate_dual_environments() {
    info "🔍 Validating dual environment readiness..."
    
    # Use enhanced API validation if available
    local validation_result
    validation_result=$(curl -s --max-time 10 "$ENHANCED_API_URL/validate" 2>/dev/null || echo '{"success":false}')
    
    if echo "$validation_result" | jq -e '.success' >/dev/null 2>&1; then
        success "✅ Dual environment validation passed"
        return 0
    else
        local error_msg
        error_msg=$(echo "$validation_result" | jq -r '.error // "Unknown validation error"')
        error "❌ Dual environment validation failed: $error_msg"
        return 1
    fi
}

# Perform gradual migration using enhanced API
perform_gradual_migration() {
    local target_env="$1"
    
    info "🔄 Initiating gradual migration to $target_env environment..."
    
    # Call enhanced API for gradual migration
    local migration_result
    migration_result=$(curl -s -X POST --max-time 300 "$ENHANCED_API_URL/switch/$target_env" 2>/dev/null || echo '{"success":false}')
    
    if echo "$migration_result" | jq -e '.success' >/dev/null 2>&1; then
        success "✅ Gradual migration completed successfully"
        
        # Show migration steps if available
        local steps
        steps=$(echo "$migration_result" | jq -r '.steps[]? | "  \(.percentage)% - \(.timestamp) - \(.status)"' 2>/dev/null || echo "")
        if [[ -n "$steps" ]]; then
            info "Migration steps completed:"
            echo "$steps"
        fi
        
        return 0
    else
        local error_msg
        error_msg=$(echo "$migration_result" | jq -r '.error // "Unknown migration error"')
        error "❌ Gradual migration failed: $error_msg"
        return 1
    fi
}

# Validate migration was successful
validate_migration_success() {
    local target_env="$1"
    
    info "🔍 Validating migration success..."
    
    # Check that target environment is now active
    local current_active
    current_active=$(get_active_environment)
    
    if [[ "$current_active" == "$target_env" ]]; then
        # Additional health validation
        if validate_environment_health "$target_env"; then
            success "✅ Migration validation successful - $target_env is active and healthy"
            return 0
        else
            error "❌ Migration validation failed - $target_env is active but unhealthy"
            return 1
        fi
    else
        error "❌ Migration validation failed - expected $target_env, but $current_active is active"
        return 1
    fi
}

# Enhanced emergency rollback
emergency_rollback() {
    warn "🚨 Initiating Emergency Rollback"
    echo "================================="
    
    # Use enhanced API rollback if available
    local rollback_result
    rollback_result=$(curl -s -X POST --max-time 60 "$ENHANCED_API_URL/rollback" 2>/dev/null || echo '{"success":false}')
    
    if echo "$rollback_result" | jq -e '.success' >/dev/null 2>&1; then
        local rolled_back_to
        rolled_back_to=$(echo "$rollback_result" | jq -r '.rolledBackTo // "unknown"')
        success "✅ Emergency rollback completed - restored to $rolled_back_to environment"
        return 0
    else
        error "❌ Enhanced rollback failed - attempting manual rollback"
        
        # Fallback to manual rollback
        local current_active
        current_active=$(get_active_environment)
        local target_env
        [[ "$current_active" == "blue" ]] && target_env="green" || target_env="blue"
        
        switch_traffic "$target_env"
        return $?
    fi
}

# Log deployment success with metadata
log_deployment_success() {
    local env="$1"
    local version="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Create deployment log entry
    local log_entry
    log_entry=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "environment": "$env", 
  "version": "$version",
  "deployment_type": "gradual_migration",
  "success": true,
  "migration_method": "enhanced_load_balancer"
}
EOF
)
    
    # Append to deployment history if possible
    local history_file="$PROJECT_DIR/deployment_state/deployment_history.json"
    local history_dir
    history_dir=$(dirname "$history_file")
    
    if [[ ! -d "$history_dir" ]]; then
        mkdir -p "$history_dir" 2>/dev/null || true
    fi
    
    if [[ -f "$history_file" ]]; then
        # Append to existing history
        local updated_history
        updated_history=$(jq --argjson entry "$log_entry" '. + [$entry]' "$history_file" 2>/dev/null || echo "[$log_entry]")
        echo "$updated_history" > "$history_file" 2>/dev/null || true
    else
        # Create new history file
        echo "[$log_entry]" > "$history_file" 2>/dev/null || true
    fi
}

# Test enhanced deployment cycle
test_enhanced_deployment() {
    local duration="${1:-60}"
    
    if ! is_system_running; then
        error "System is not running. Please start the system first."
        return 1
    fi
    
    log "🧪 Starting Enhanced Deployment Test (duration: ${duration}s)..."
    
    local start_time
    start_time=$(date +%s)
    local current_env
    current_env=$(get_active_environment)
    
    info "🎯 Starting test with $current_env environment active"
    
    # Determine target environment for test
    local target_env
    [[ "$current_env" == "blue" ]] && target_env="green" || target_env="blue"
    
    # Test gradual deployment
    log "🔄 Testing gradual deployment: $current_env → $target_env"
    if gradual_deployment "$target_env" "test-v1.0"; then
        success "✅ Forward deployment test passed"
    else
        error "❌ Forward deployment test failed"
        return 1
    fi
    
    # Wait a bit
    sleep 10
    
    # Test rollback
    log "🔄 Testing rollback deployment: $target_env → $current_env"
    if gradual_deployment "$current_env" "rollback-test"; then
        success "✅ Rollback deployment test passed"
    else
        error "❌ Rollback deployment test failed"
        return 1
    fi
    
    local end_time
    end_time=$(date +%s)
    local test_duration=$((end_time - start_time))
    
    success "🎉 Enhanced Deployment Test Completed!"
    log "   Test Duration: ${test_duration} seconds"
    log "   Deployments Tested: 2 (forward + rollback)"
    log "   Migration Type: Gradual with health validation"
}

# Include existing functions from original deploy.sh
is_system_running() {
    docker ps --filter "name=nginx-proxy" --format "table {{.Names}}" | grep -q nginx-proxy 2>/dev/null
}

get_active_environment() {
    if is_system_running; then
        docker exec nginx-proxy cat /etc/nginx/conf.d/active.env 2>/dev/null | grep -o "blue\|green" || echo "unknown"
    else
        echo "system_down"
    fi
}

check_service_health() {
    local service_name="$1"
    local url="$2"
    local timeout="${3:-3}"
    
    curl -fsS --max-time "$timeout" --connect-timeout 1 "$url" >/dev/null 2>&1
}

switch_traffic() {
    local target="$1"
    
    if [[ "$target" != "blue" && "$target" != "green" ]]; then
        error "Invalid target: $target. Must be 'blue' or 'green'"
        return 1
    fi
    
    log "🔄 Direct traffic switch to $target environment..."
    
    # Use API to switch traffic
    local response
    response=$(curl -s -X POST "http://localhost:9000/switch/$target" 2>/dev/null || echo '{"success":false,"error":"API call failed"}')
    
    local success
    success=$(echo "$response" | jq -r '.success' 2>/dev/null || echo "false")
    
    if [[ "$success" == "true" ]]; then
        success "✅ Traffic switched to $target"
        return 0
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error' 2>/dev/null || echo "Unknown error")
        error "❌ Traffic switch failed: $error_msg"
        return 1
    fi
}

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
    
    # Stop and rebuild the target environment
    log "🛑 Stopping $env environment..."
    docker-compose -f "$COMPOSE_FILE" stop "${env}-app" 2>/dev/null || true
    docker-compose -f "$COMPOSE_FILE" rm -f "${env}-app" 2>/dev/null || true
    
    log "🏗️  Rebuilding $env environment with version $version..."
    docker-compose -f "$COMPOSE_FILE" build "${env}-app"
    
    log "🚀 Starting $env environment..."
    docker-compose -f "$COMPOSE_FILE" up -d "${env}-app"
    
    # Wait for health check
    log "⏳ Waiting for $env environment to be healthy..."
    local port
    [[ "$env" == "green" ]] && port=3002 || port=3001
    
    sleep 5
    
    for attempt in {1..20}; do
        if check_service_health "$env server" "http://localhost:$port/health" 3; then
            success "✅ $env environment is healthy"
            return 0
        fi
        
        if [[ $attempt -eq 20 ]]; then
            error "❌ $env environment failed to become healthy after 20 attempts"
            return 1
        fi
        
        info "⏳ $env environment not ready yet (attempt $attempt/20)..."
        sleep 5
    done
}

start_system() {
    log "🚀 Starting Enhanced Blue-Green deployment system..."
    
    cd "$PROJECT_DIR"
    
    if is_system_running; then
        warn "⚠️  System is already running"
        show_enhanced_status
        return 0
    fi
    
    log "🏗️  Building and starting all services..."
    docker-compose -f "$COMPOSE_FILE" build
    docker-compose -f "$COMPOSE_FILE" up -d
    
    log "⏳ Waiting for services to be ready..."
    sleep 30
    
    # Verify system health
    local healthy=true
    
    for service in "nginx-proxy:80/health" "blue-app:3001/health" "green-app:3002/health" "api-server:9000/health"; do
        local name="${service%%:*}"
        local endpoint="http://localhost:${service#*:}"
        
        if check_service_health "$name" "$endpoint" 5; then
            success "✅ $name is healthy"
        else
            error "❌ $name failed to start properly"
            healthy=false
        fi
    done
    
    if [[ "$healthy" == "true" ]]; then
        success "🎉 Enhanced system started successfully!"
        show_enhanced_status
    else
        error "❌ System startup had issues"
        return 1
    fi
}

stop_system() {
    log "🛑 Stopping Enhanced Blue-Green deployment system..."
    
    cd "$PROJECT_DIR"
    docker-compose -f "$COMPOSE_FILE" down --timeout 30
    
    success "✅ System stopped"
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
            show_enhanced_status
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
        "gradual")
            if [[ -n "${2:-}" ]]; then
                gradual_deployment "$2" "${3:-latest}"
            else
                error "Usage: $0 gradual {blue|green} [version]"
                exit 1
            fi
            ;;
        "rollback")
            emergency_rollback
            ;;
        "test")
            test_enhanced_deployment "${2:-60}"
            ;;
        "validate")
            validate_dual_environments
            ;;
        "help"|*)
            echo "Enhanced Blue-Green Deployment Management v3.0"
            echo "Usage: $0 {command} [options]"
            echo ""
            echo "System Commands:"
            echo "  start                      - Start the enhanced system"
            echo "  stop                       - Stop the entire system"
            echo "  status                     - Show enhanced system status"
            echo "  test [duration]            - Test enhanced deployment cycle"
            echo ""
            echo "Enhanced Deployment Commands:"
            echo "  gradual {color} [version]  - Gradual migration deployment (RECOMMENDED)"
            echo "  deploy {color} [version]   - Deploy to specific environment"
            echo "  switch {color}             - Direct traffic switch"
            echo "  rollback                   - Emergency rollback"
            echo "  validate                   - Validate dual environment readiness"
            echo ""
            echo "Examples:"
            echo "  $0 start                     # Start enhanced system"
            echo "  $0 status                    # Check enhanced status"
            echo "  $0 gradual green 2.1.0       # Gradual deployment to green"
            echo "  $0 rollback                  # Emergency rollback"
            echo "  $0 test 120                  # 120-second deployment test"
            echo ""
            echo "Enhanced Features:"
            echo "  ✅ Gradual migration (25% → 50% → 75% → 100%)"
            echo "  ✅ Dual environment validation" 
            echo "  ✅ Automatic health monitoring"
            echo "  ✅ Emergency rollback"
            echo "  ✅ Complete deployment tracking"
            ;;
    esac
}

# Execute main function
main "$@"