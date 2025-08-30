#!/usr/bin/env bash
#
# Comprehensive Health Check Script
# Based on 새로운 판단 파일 recommendations
#

set -euo pipefail

# Configuration
BLUE_PORT=3001
GREEN_PORT=3002
NGINX_PORT=80
API_PORT=9000

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Health check function with enhanced validation
check_service() {
    local service_name="$1"
    local port="$2"
    local endpoint="${3:-/health}"
    local timeout="${4:-3}"
    
    local url="http://127.0.0.1:$port$endpoint"
    
    printf "%-15s " "$service_name:"
    
    # Perform health check with timeout
    if curl -fsS --max-time "$timeout" --connect-timeout 1 \
           -H "User-Agent: health-checker/1.0" \
           "$url" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ HEALTHY${NC}"
        return 0
    else
        echo -e "${RED}✗ UNHEALTHY${NC}"
        return 1
    fi
}

# Check NGINX configuration
check_nginx_config() {
    printf "%-15s " "NGINX Config:"
    
    if nginx -t >/dev/null 2>&1; then
        echo -e "${GREEN}✓ VALID${NC}"
        return 0
    else
        echo -e "${RED}✗ INVALID${NC}"
        return 1
    fi
}

# Get current active environment
get_active_environment() {
    local active_file="/etc/nginx/conf.d/active.env"
    
    if [[ -f "$active_file" ]]; then
        grep 'set.*active' "$active_file" | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Main health check routine
main() {
    echo "🏥 NGINX Blue-Green Deployment Health Check"
    echo "=========================================="
    echo "Time: $(date)"
    echo
    
    local active_env
    active_env=$(get_active_environment)
    echo -e "Active Environment: ${BLUE}$active_env${NC}"
    echo
    
    # Service health checks
    echo "Service Health Status:"
    echo "---------------------"
    
    local blue_status=0
    local green_status=0
    local nginx_status=0
    local api_status=0
    local config_status=0
    
    # Check individual services
    check_service "Blue Server" "$BLUE_PORT" || blue_status=1
    check_service "Green Server" "$GREEN_PORT" || green_status=1
    check_service "NGINX Proxy" "$NGINX_PORT" "/status" || nginx_status=1
    check_service "API Server" "$API_PORT" "/health" || api_status=1
    check_nginx_config || config_status=1
    
    echo
    
    # Summary
    local total_checks=5
    local failed_checks=$((blue_status + green_status + nginx_status + api_status + config_status))
    local healthy_checks=$((total_checks - failed_checks))
    
    echo "Health Summary:"
    echo "---------------"
    echo -e "Healthy Services: ${GREEN}$healthy_checks/$total_checks${NC}"
    
    if [[ $failed_checks -eq 0 ]]; then
        echo -e "Overall Status: ${GREEN}ALL HEALTHY${NC} 🎉"
        exit 0
    elif [[ $failed_checks -le 2 ]]; then
        echo -e "Overall Status: ${YELLOW}DEGRADED${NC} ⚠️"
        echo "Some non-critical services are down"
        exit 1
    else
        echo -e "Overall Status: ${RED}CRITICAL${NC} 🚨"
        echo "Multiple services are down - immediate attention required"
        exit 2
    fi
}

# Handle script arguments
case "${1:-check}" in
    "check"|"")
        main
        ;;
    "blue")
        check_service "Blue Server" "$BLUE_PORT"
        ;;
    "green")
        check_service "Green Server" "$GREEN_PORT"
        ;;
    "nginx")
        check_service "NGINX Proxy" "$NGINX_PORT" "/status"
        ;;
    "config")
        check_nginx_config
        ;;
    *)
        echo "Usage: $0 [check|blue|green|nginx|config]"
        echo "  check  - Full health check (default)"
        echo "  blue   - Check blue server only"
        echo "  green  - Check green server only"
        echo "  nginx  - Check NGINX proxy only"
        echo "  config - Check NGINX configuration only"
        exit 1
        ;;
esac