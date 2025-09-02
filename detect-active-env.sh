#!/usr/bin/env bash
#
# Blue-Green Environment Detection and Alternation Script
# Provides intelligent environment detection for true alternating deployments
# Usage: ./detect-active-env.sh {detect|current|next|status}
#

set -euo pipefail

# Configuration
ACTIVE_FILE="/etc/nginx/conf.d/active.env"
CONFIG_DIR="/etc/nginx/conf.d"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') | $1"
}

# Get current active environment from NGINX config
get_current_active() {
    if [[ -f "$ACTIVE_FILE" ]]; then
        # Extract the active environment from the config file
        # Format: set $active "green";
        local current=$(grep 'set.*active' "$ACTIVE_FILE" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "")
        
        if [[ -n "$current" && ( "$current" == "blue" || "$current" == "green" ) ]]; then
            echo "$current"
        else
            echo "blue"  # Default fallback
        fi
    else
        echo "blue"  # Default if file doesn't exist
    fi
}

# Get the opposite environment (for alternation)
get_next_environment() {
    local current="$1"
    
    if [[ "$current" == "blue" ]]; then
        echo "green"
    else
        echo "blue"
    fi
}

# Check environment health
check_environment_health() {
    local env="$1"
    local port
    
    # Determine port based on environment
    if [[ "$env" == "blue" ]]; then
        port=3001
    elif [[ "$env" == "green" ]]; then
        port=3002
    else
        log "${RED}❌ Invalid environment: $env${NC}"
        return 1
    fi
    
    # Health check with timeout
    if curl -fsS --max-time 3 --connect-timeout 1 \
       "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Full environment detection
detect_environment() {
    log "${BLUE}🔍 Detecting Blue-Green Environment Configuration${NC}"
    log "=================================================="
    
    local current_active
    current_active=$(get_current_active)
    local next_env
    next_env=$(get_next_environment "$current_active")
    
    echo
    log "${YELLOW}📊 Environment Status:${NC}"
    log "  Current Active: ${GREEN}$current_active${NC}"
    log "  Next Target:    ${BLUE}$next_env${NC}"
    
    echo
    log "${YELLOW}🏥 Health Check Results:${NC}"
    
    # Check Blue environment
    if check_environment_health "blue"; then
        log "  ${BLUE}Blue Server (3001):  ${GREEN}✅ Healthy${NC}"
    else
        log "  ${BLUE}Blue Server (3001):  ${RED}❌ Unhealthy${NC}"
    fi
    
    # Check Green environment
    if check_environment_health "green"; then
        log "  ${GREEN}Green Server (3002): ${GREEN}✅ Healthy${NC}"
    else
        log "  ${GREEN}Green Server (3002): ${RED}❌ Unhealthy${NC}"
    fi
    
    echo
    log "${YELLOW}📁 Configuration Files:${NC}"
    if [[ -f "$ACTIVE_FILE" ]]; then
        log "  Active Config: ${GREEN}✅ Found${NC} ($ACTIVE_FILE)"
        log "  Content: $(cat "$ACTIVE_FILE" | grep 'set.*active' || echo 'Invalid format')"
    else
        log "  Active Config: ${RED}❌ Missing${NC} ($ACTIVE_FILE)"
    fi
    
    echo
    log "${YELLOW}🎯 Deployment Recommendation:${NC}"
    log "  Deploy to: ${BLUE}$next_env${NC} environment"
    log "  This will enable true Blue-Green alternation"
    
    # Output for CI/CD consumption
    echo
    echo "# CI/CD Variables"
    echo "CURRENT_ACTIVE=$current_active"
    echo "DEPLOY_TARGET=$next_env"
    echo "BLUE_PORT=3001"
    echo "GREEN_PORT=3002"
    
    if [[ "$next_env" == "blue" ]]; then
        echo "TARGET_PORT=3001"
        echo "TARGET_ENV_NAME=blue-dev"
    else
        echo "TARGET_PORT=3002"
        echo "TARGET_ENV_NAME=green-dev"
    fi
}

# Show current active environment only
show_current() {
    local current_active
    current_active=$(get_current_active)
    echo "$current_active"
}

# Show next deployment target only
show_next() {
    local current_active
    current_active=$(get_current_active)
    local next_env
    next_env=$(get_next_environment "$current_active")
    echo "$next_env"
}

# Show detailed status
show_status() {
    log "${BLUE}📊 Blue-Green Deployment Status${NC}"
    log "=================================="
    
    local current_active
    current_active=$(get_current_active)
    local next_env
    next_env=$(get_next_environment "$current_active")
    
    echo
    if [[ "$current_active" == "blue" ]]; then
        log "Current: ${BLUE}●${NC} Blue    Next: ${GREEN}○${NC} Green"
    else
        log "Current: ${BLUE}○${NC} Blue    Next: ${GREEN}●${NC} Green"
    fi
    
    echo
    log "${YELLOW}Environment Health:${NC}"
    local blue_status green_status
    
    if check_environment_health "blue"; then
        blue_status="${GREEN}Healthy${NC}"
    else
        blue_status="${RED}Unhealthy${NC}"
    fi
    
    if check_environment_health "green"; then
        green_status="${GREEN}Healthy${NC}"
    else
        green_status="${RED}Unhealthy${NC}"
    fi
    
    log "  ${BLUE}Blue (3001):${NC}  $blue_status"
    log "  ${GREEN}Green (3002):${NC} $green_status"
    
    echo
    log "${YELLOW}Next Deployment:${NC}"
    log "  Target: ${BLUE}$next_env${NC}"
    log "  Command: git push origin main"
}

# Main function
main() {
    local command="${1:-detect}"
    
    case "$command" in
        "detect")
            detect_environment
            ;;
        "current")
            show_current
            ;;
        "next")
            show_next
            ;;
        "status")
            show_status
            ;;
        *)
            echo "Usage: $0 {detect|current|next|status}" >&2
            echo
            echo "Commands:"
            echo "  detect  - Full environment detection and analysis"
            echo "  current - Show current active environment only"
            echo "  next    - Show next deployment target only" 
            echo "  status  - Show detailed deployment status"
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"