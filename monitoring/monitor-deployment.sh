#!/bin/bash

# Zero-Downtime Monitoring Service
# Monitors blue-green deployment health and switching

set -euo pipefail

# Configuration
MONITOR_INTERVAL=${MONITOR_INTERVAL:-5}
ALERT_THRESHOLD=${ALERT_THRESHOLD:-3}
NGINX_URL=${NGINX_URL:-"http://nginx-proxy:80"}
BLUE_URL=${BLUE_URL:-"http://blue-app:3001"}
GREEN_URL=${GREEN_URL:-"http://green-app:3002"}
API_URL=${API_URL:-"http://api-server:9000"}

LOG_FILE="/app/data/monitor.log"
PID_FILE="/app/data/monitor.pid"

# Create log directory
mkdir -p /app/data

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Health check function
check_health() {
    local url="$1"
    local service="$2"
    
    if curl -f -s --max-time 5 "$url/health" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Monitor function
monitor_loop() {
    local blue_failures=0
    local green_failures=0
    local nginx_failures=0
    local api_failures=0
    
    while true; do
        # Monitor Blue environment
        if check_health "$BLUE_URL" "blue"; then
            blue_failures=0
            log "✅ Blue environment healthy"
        else
            blue_failures=$((blue_failures + 1))
            log "⚠️  Blue environment unhealthy (failures: $blue_failures)"
        fi
        
        # Monitor Green environment  
        if check_health "$GREEN_URL" "green"; then
            green_failures=0
            log "✅ Green environment healthy"
        else
            green_failures=$((green_failures + 1))
            log "⚠️  Green environment unhealthy (failures: $green_failures)"
        fi
        
        # Monitor NGINX proxy
        if check_health "$NGINX_URL" "nginx"; then
            nginx_failures=0
            log "✅ NGINX proxy healthy"
        else
            nginx_failures=$((nginx_failures + 1))
            log "⚠️  NGINX proxy unhealthy (failures: $nginx_failures)"
        fi
        
        # Monitor API server
        if check_health "$API_URL" "api"; then
            api_failures=0
            log "✅ API server healthy"
        else
            api_failures=$((api_failures + 1))
            log "⚠️  API server unhealthy (failures: $api_failures)"
        fi
        
        # Alert on threshold breaches
        if [ $nginx_failures -ge $ALERT_THRESHOLD ]; then
            log "🚨 ALERT: NGINX proxy failed $nginx_failures times"
        fi
        
        if [ $api_failures -ge $ALERT_THRESHOLD ]; then
            log "🚨 ALERT: API server failed $api_failures times"
        fi
        
        # Log current active environment
        if curl -f -s --max-time 5 "$API_URL/status" | jq -r .current_deployment >/dev/null 2>&1; then
            local active_env=$(curl -s --max-time 5 "$API_URL/status" | jq -r .current_deployment 2>/dev/null || echo "unknown")
            log "📊 Active environment: $active_env"
        fi
        
        sleep $MONITOR_INTERVAL
    done
}

# Signal handlers
cleanup() {
    log "🛑 Monitoring service stopping..."
    rm -f "$PID_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main execution
log "🚀 Starting deployment monitoring service..."
log "⚙️  Configuration: interval=${MONITOR_INTERVAL}s, threshold=${ALERT_THRESHOLD}"

# Write PID file
echo $$ > "$PID_FILE"

# Start monitoring
monitor_loop