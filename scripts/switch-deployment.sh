#!/bin/bash
# True Blue-Green Deployment Switch Script
# Manual switching between blue and green environments with safety checks

set -e

# Configuration
API_HOST="localhost"
API_PORT="9000"
NGINX_HOST="localhost" 
NGINX_PORT="80"
BLUE_PORT="3001"
GREEN_PORT="3002"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging
log_info() {
    echo -e "${BLUE}ℹ️  INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}❌ ERROR:${NC} $1"
}

# Help function
show_help() {
    cat << EOF
🔄 True Blue-Green Deployment Switch Script

USAGE:
    ./switch-deployment.sh [COMMAND] [OPTIONS]

COMMANDS:
    status              Show current deployment status
    switch blue        Switch traffic to blue environment
    switch green       Switch traffic to green environment
    health             Check health of both environments
    validate           Validate current deployment
    rollback           Rollback to previous environment
    help               Show this help message

OPTIONS:
    --force            Skip confirmation prompts (use with caution)
    --verbose          Enable verbose output
    --dry-run          Show what would be done without executing

EXAMPLES:
    ./switch-deployment.sh status
    ./switch-deployment.sh switch blue
    ./switch-deployment.sh switch green --force
    ./switch-deployment.sh health --verbose
    ./switch-deployment.sh validate

EOF
}

# Parse command line arguments
COMMAND=""
TARGET_ENV=""
FORCE=false
VERBOSE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        status|health|validate|rollback|help)
            COMMAND="$1"
            shift
            ;;
        switch)
            COMMAND="switch"
            shift
            if [[ $# -gt 0 ]] && [[ "$1" =~ ^(blue|green)$ ]]; then
                TARGET_ENV="$1"
                shift
            else
                log_error "Switch command requires target environment (blue|green)"
                exit 1
            fi
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

# Default to status if no command provided
if [[ -z "$COMMAND" ]]; then
    COMMAND="status"
fi

# Verbose logging
verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "$1"
    fi
}

# Check if services are running
check_services() {
    verbose_log "Checking if Docker services are running..."
    
    if ! docker ps --filter "name=nginx-proxy" --format "{{.Names}}" | grep -q nginx-proxy; then
        log_error "NGINX proxy container is not running"
        return 1
    fi
    
    if ! docker ps --filter "name=api-server" --format "{{.Names}}" | grep -q api-server; then
        log_error "API server container is not running"
        return 1
    fi
    
    return 0
}

# Get current active environment
get_current_active() {
    verbose_log "Detecting current active environment..."
    
    # Try API-based detection first
    local api_active
    api_active=$(curl -s --max-time 5 "http://${API_HOST}:${API_PORT}/status" 2>/dev/null | jq -r '.current_deployment' 2>/dev/null || echo "")
    
    if [[ -n "$api_active" && "$api_active" != "null" ]]; then
        echo "$api_active"
        return 0
    fi
    
    # Fallback to file-based detection
    local file_active
    file_active=$(docker exec nginx-proxy cat /etc/nginx/conf.d/active.env 2>/dev/null | grep -o "blue\|green" || echo "")
    
    if [[ -n "$file_active" ]]; then
        echo "$file_active"
        return 0
    fi
    
    # Default fallback
    echo "unknown"
    return 1
}

# Check environment health
check_environment_health() {
    local env="$1"
    local port="$2"
    
    verbose_log "Checking $env environment health on port $port..."
    
    # Check direct container health
    if curl -f --max-time 3 "http://${NGINX_HOST}:${NGINX_PORT}/$env/health" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Show deployment status
show_status() {
    log_info "True Blue-Green Deployment Status"
    echo "=================================="
    
    if ! check_services; then
        log_error "Required services are not running"
        return 1
    fi
    
    local current_active
    current_active=$(get_current_active)
    
    echo -e "🔍 Current Active Environment: ${GREEN}$current_active${NC}"
    
    # Check health of both environments
    echo ""
    echo "🏥 Environment Health Status:"
    
    # Check blue environment
    if docker ps --filter "name=blue-app" --format "{{.Names}}" | grep -q blue-app; then
        if check_environment_health "blue" "$BLUE_PORT"; then
            echo -e "  🔵 Blue Environment:  ${GREEN}HEALTHY${NC}"
        else
            echo -e "  🔵 Blue Environment:  ${RED}UNHEALTHY${NC}"
        fi
    else
        echo -e "  🔵 Blue Environment:  ${YELLOW}NOT RUNNING${NC}"
    fi
    
    # Check green environment
    if docker ps --filter "name=green-app" --format "{{.Names}}" | grep -q green-app; then
        if check_environment_health "green" "$GREEN_PORT"; then
            echo -e "  🟢 Green Environment: ${GREEN}HEALTHY${NC}"
        else
            echo -e "  🟢 Green Environment: ${RED}UNHEALTHY${NC}"
        fi
    else
        echo -e "  🟢 Green Environment: ${YELLOW}NOT RUNNING${NC}"
    fi
    
    # Show version information
    echo ""
    echo "📋 Version Information:"
    
    local blue_version green_version
    blue_version=$(curl -s "http://${NGINX_HOST}:${NGINX_PORT}/blue/version" 2>/dev/null | jq -r '.version' 2>/dev/null || echo "unknown")
    green_version=$(curl -s "http://${NGINX_HOST}:${NGINX_PORT}/green/version" 2>/dev/null | jq -r '.version' 2>/dev/null || echo "unknown")
    
    echo "  🔵 Blue Version:  $blue_version"
    echo "  🟢 Green Version: $green_version"
    
    # Show traffic routing
    echo ""
    echo "🚦 Traffic Routing:"
    if [[ "$current_active" == "blue" ]]; then
        echo -e "  Traffic is routed to: ${BLUE}BLUE${NC} environment"
        echo -e "  Inactive environment: ${GREEN}GREEN${NC}"
    elif [[ "$current_active" == "green" ]]; then
        echo -e "  Traffic is routed to: ${GREEN}GREEN${NC} environment"
        echo -e "  Inactive environment: ${BLUE}BLUE${NC}"
    else
        echo -e "  Traffic routing: ${YELLOW}UNKNOWN${NC}"
    fi
}

# Switch environments
switch_environment() {
    local target="$1"
    
    log_info "Switching to $target environment..."
    
    if ! check_services; then
        log_error "Required services are not running"
        return 1
    fi
    
    # Check target environment health
    local target_port
    if [[ "$target" == "blue" ]]; then
        target_port="$BLUE_PORT"
    else
        target_port="$GREEN_PORT"
    fi
    
    if ! check_environment_health "$target" "$target_port"; then
        log_error "$target environment is not healthy - cannot switch"
        return 1
    fi
    
    # Get current active environment
    local current_active
    current_active=$(get_current_active)
    
    if [[ "$current_active" == "$target" ]]; then
        log_warning "$target environment is already active"
        return 0
    fi
    
    # Confirmation prompt (unless --force is used)
    if [[ "$FORCE" != "true" ]]; then
        echo -e "${YELLOW}⚠️  About to switch from $current_active to $target environment${NC}"
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            return 0
        fi
    fi
    
    # Perform switch
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would switch to $target environment"
        return 0
    fi
    
    verbose_log "Executing switch to $target environment..."
    
    # Call API endpoint
    local switch_response
    switch_response=$(curl -s -X POST "http://${API_HOST}:${API_PORT}/switch/$target" 2>/dev/null || echo '{"success":false}')
    
    if echo "$switch_response" | jq -e '.success' >/dev/null 2>&1; then
        log_success "Traffic successfully switched to $target environment"
        
        # Verify switch
        sleep 3
        local new_active
        new_active=$(get_current_active)
        
        if [[ "$new_active" == "$target" ]]; then
            log_success "Switch verification successful - now serving $target environment"
        else
            log_warning "Switch may not have completed properly (detected: $new_active)"
        fi
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo "Switch response: $switch_response"
        fi
    else
        log_error "Traffic switch failed"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "Error response: $switch_response"
        fi
        return 1
    fi
}

# Comprehensive health check
comprehensive_health_check() {
    log_info "Comprehensive Health Check"
    echo "=========================="
    
    local overall_status=0
    
    # Check services
    if check_services; then
        log_success "Core services are running"
    else
        log_error "Core services check failed"
        overall_status=1
    fi
    
    # Check NGINX
    if curl -f --max-time 3 "http://${NGINX_HOST}:${NGINX_PORT}/health" >/dev/null 2>&1; then
        log_success "NGINX proxy is healthy"
    else
        log_error "NGINX proxy health check failed"
        overall_status=1
    fi
    
    # Check API server
    if curl -f --max-time 3 "http://${API_HOST}:${API_PORT}/health" >/dev/null 2>&1; then
        log_success "API server is healthy"
    else
        log_error "API server health check failed"
        overall_status=1
    fi
    
    # Check blue environment
    if docker ps --filter "name=blue-app" --format "{{.Names}}" | grep -q blue-app; then
        if check_environment_health "blue" "$BLUE_PORT"; then
            log_success "Blue environment is healthy"
        else
            log_error "Blue environment health check failed"
            overall_status=1
        fi
    else
        log_warning "Blue environment is not running"
    fi
    
    # Check green environment
    if docker ps --filter "name=green-app" --format "{{.Names}}" | grep -q green-app; then
        if check_environment_health "green" "$GREEN_PORT"; then
            log_success "Green environment is healthy"
        else
            log_error "Green environment health check failed"
            overall_status=1
        fi
    else
        log_warning "Green environment is not running"
    fi
    
    if [[ $overall_status -eq 0 ]]; then
        log_success "All health checks passed"
    else
        log_error "Some health checks failed"
    fi
    
    return $overall_status
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment configuration..."
    
    local validation_status=0
    
    # Check if both environments are available
    local blue_running green_running
    blue_running=$(docker ps --filter "name=blue-app" --format "{{.Names}}" | grep -q blue-app && echo "true" || echo "false")
    green_running=$(docker ps --filter "name=green-app" --format "{{.Names}}" | grep -q green-app && echo "true" || echo "false")
    
    if [[ "$blue_running" == "true" && "$green_running" == "true" ]]; then
        log_success "Both blue and green environments are running (True Blue-Green)"
    elif [[ "$blue_running" == "true" || "$green_running" == "true" ]]; then
        log_warning "Only one environment is running (Single environment mode)"
    else
        log_error "No application environments are running"
        validation_status=1
    fi
    
    # Check version consistency
    local blue_version green_version
    blue_version=$(curl -s "http://${NGINX_HOST}:${NGINX_PORT}/blue/version" 2>/dev/null | jq -r '.version' 2>/dev/null || echo "unknown")
    green_version=$(curl -s "http://${NGINX_HOST}:${NGINX_PORT}/green/version" 2>/dev/null | jq -r '.version' 2>/dev/null || echo "unknown")
    
    if [[ "$blue_version" != "unknown" && "$green_version" != "unknown" ]]; then
        if [[ "$blue_version" == "$green_version" ]]; then
            log_success "Both environments are running the same version: $blue_version"
        else
            log_info "Environments are running different versions:"
            log_info "  Blue: $blue_version"
            log_info "  Green: $green_version"
        fi
    else
        log_warning "Could not retrieve version information from all environments"
    fi
    
    return $validation_status
}

# Rollback to previous environment
rollback_deployment() {
    log_info "Rolling back to previous environment..."
    
    local current_active
    current_active=$(get_current_active)
    
    local previous_env
    if [[ "$current_active" == "blue" ]]; then
        previous_env="green"
    elif [[ "$current_active" == "green" ]]; then
        previous_env="blue"
    else
        log_error "Cannot determine current environment for rollback"
        return 1
    fi
    
    log_info "Rolling back from $current_active to $previous_env"
    switch_environment "$previous_env"
}

# Main execution
main() {
    case "$COMMAND" in
        status)
            show_status
            ;;
        switch)
            switch_environment "$TARGET_ENV"
            ;;
        health)
            comprehensive_health_check
            ;;
        validate)
            validate_deployment
            ;;
        rollback)
            rollback_deployment
            ;;
        help)
            show_help
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"