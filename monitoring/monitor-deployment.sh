#!/usr/bin/env bash
#
# Zero-Downtime Deployment Monitor
# Continuously monitors service availability and detects any downtime
#

set -e

MONITOR_INTERVAL="${MONITOR_INTERVAL:-5}"
ALERT_THRESHOLD="${ALERT_THRESHOLD:-3}"
DATA_DIR="/app/data"
LOG_FILE="$DATA_DIR/monitor.log"
PID_FILE="$DATA_DIR/monitor.pid"

# Store PID for health checks
echo $$ > "$PID_FILE"

# Initialize log file
mkdir -p "$DATA_DIR"
echo "🚀 Starting Zero-Downtime Deployment Monitor at $(date)" > "$LOG_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ ERROR: $1" | tee -a "$LOG_FILE"
}

success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1" | tee -a "$LOG_FILE"
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  WARNING: $1" | tee -a "$LOG_FILE"
}

# Service monitoring function
check_service() {
    local service_name="$1"
    local url="$2"
    local timeout="${3:-3}"
    
    if curl -fsS --max-time "$timeout" --connect-timeout 1 "$url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Main monitoring loop
monitor_services() {
    local consecutive_failures=0
    local total_checks=0
    local failed_checks=0
    local last_status="UP"
    
    log "🏥 Starting continuous service monitoring (interval: ${MONITOR_INTERVAL}s)"
    log "📊 Alert threshold: $ALERT_THRESHOLD consecutive failures"
    
    while true; do
        total_checks=$((total_checks + 1))
        current_time=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Check main proxy
        if check_service "NGINX Proxy" "http://nginx-proxy:80/status" 2; then
            if [[ "$last_status" == "DOWN" ]]; then
                success "Service RECOVERED after $consecutive_failures failures"
                
                # Record recovery metrics
                echo "{\"timestamp\": \"$current_time\", \"event\": \"service_recovery\", \"failures\": $consecutive_failures}" >> "$DATA_DIR/events.json"
            fi
            
            consecutive_failures=0
            last_status="UP"
            
            # Periodic success log (every 60 checks to avoid spam)
            if [[ $((total_checks % 60)) -eq 0 ]]; then
                log "📊 Service healthy - Total checks: $total_checks, Failed: $failed_checks ($(echo "scale=2; $failed_checks*100/$total_checks" | bc -l 2>/dev/null || echo "0")%)"
            fi
            
        else
            consecutive_failures=$((consecutive_failures + 1))
            failed_checks=$((failed_checks + 1))
            last_status="DOWN"
            
            error "Service DOWN (failure $consecutive_failures/$ALERT_THRESHOLD)"
            
            # Record failure event
            echo "{\"timestamp\": \"$current_time\", \"event\": \"service_failure\", \"consecutive_failures\": $consecutive_failures}" >> "$DATA_DIR/events.json"
            
            # Alert if threshold exceeded
            if [[ $consecutive_failures -ge $ALERT_THRESHOLD ]]; then
                error "🚨 DOWNTIME ALERT: Service has been down for $consecutive_failures consecutive checks"
                error "🚨 ZERO-DOWNTIME DEPLOYMENT FAILED"
                
                # Create alert file for external monitoring
                echo "{\"alert_time\": \"$current_time\", \"consecutive_failures\": $consecutive_failures, \"status\": \"CRITICAL\"}" > "$DATA_DIR/downtime_alert.json"
                
                # Additional debugging information
                error "🔍 Debugging information:"
                error "   - Total checks: $total_checks"
                error "   - Failed checks: $failed_checks"
                error "   - Failure rate: $(echo "scale=2; $failed_checks*100/$total_checks" | bc -l 2>/dev/null || echo "unknown")%"
                
                # Try to get more information about the failure
                log "🔍 Additional service checks:"
                check_service "Blue App" "http://blue-app:3001/health" 2 && success "Blue app is healthy" || error "Blue app is down"
                check_service "Green App" "http://green-app:3002/health" 2 && success "Green app is healthy" || error "Green app is down"
                check_service "API Server" "http://api-server:9000/health" 2 && success "API server is healthy" || error "API server is down"
            fi
        fi
        
        # Update metrics file
        echo "{\"timestamp\": \"$current_time\", \"total_checks\": $total_checks, \"failed_checks\": $failed_checks, \"consecutive_failures\": $consecutive_failures, \"status\": \"$last_status\"}" > "$DATA_DIR/metrics.json"
        
        sleep "$MONITOR_INTERVAL"
    done
}

# Signal handlers for graceful shutdown
cleanup() {
    log "🛑 Monitoring stopped - Final metrics:"
    if [[ -f "$DATA_DIR/metrics.json" ]]; then
        cat "$DATA_DIR/metrics.json" | tee -a "$LOG_FILE"
    fi
    rm -f "$PID_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Start monitoring
log "🚀 Zero-Downtime Monitor starting..."
log "⏰ Monitor interval: ${MONITOR_INTERVAL} seconds"
log "🚨 Alert threshold: ${ALERT_THRESHOLD} consecutive failures"
log "📁 Data directory: $DATA_DIR"

monitor_services