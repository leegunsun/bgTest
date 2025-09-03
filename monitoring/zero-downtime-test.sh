#!/usr/bin/env bash
#
# Zero-Downtime Deployment Test
# Tests deployment operations while monitoring for any service interruption
#

set -e

TEST_DURATION="${TEST_DURATION:-60}"
CHECK_INTERVAL=0.1
API_HOST="${API_HOST:-api-server:9000}"
PROXY_HOST="${PROXY_HOST:-nginx-proxy:80}"

log() {
    echo "[$(date '+%H:%M:%S.%3N')] $1"
}

success() {
    echo "[$(date '+%H:%M:%S.%3N')] ✅ $1"
}

error() {
    echo "[$(date '+%H:%M:%S.%3N')] ❌ $1"
}

warn() {
    echo "[$(date '+%H:%M:%S.%3N')] ⚠️  $1"
}

# Check service availability
check_availability() {
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 --connect-timeout 0.5 "http://$PROXY_HOST/status" 2>/dev/null || echo "000")
    
    if [[ "$response" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

# Get current active environment
get_active_environment() {
    local response
    response=$(curl -s --max-time 2 "http://$API_HOST/status" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        echo "$response" | jq -r '.current_deployment' 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Switch deployment environment
switch_deployment() {
    local target="$1"
    
    log "🔄 Initiating switch to $target environment..."
    
    local response
    response=$(curl -s -X POST --max-time 10 "http://$API_HOST/switch/$target" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        local success
        success=$(echo "$response" | jq -r '.success' 2>/dev/null || echo "false")
        
        if [[ "$success" == "true" ]]; then
            success "Switch to $target completed successfully"
            return 0
        else
            error "Switch to $target failed: $response"
            return 1
        fi
    else
        error "Switch to $target failed - API call failed"
        return 1
    fi
}

# Main zero-downtime test
run_zero_downtime_test() {
    log "🚀 Starting Zero-Downtime Deployment Test"
    log "⏰ Test duration: $TEST_DURATION seconds"
    log "📊 Check interval: $CHECK_INTERVAL seconds"
    
    local start_time
    start_time=$(date +%s)
    
    local total_checks=0
    local failed_checks=0
    local downtime_detected=false
    local switch_count=0
    
    # Get initial environment
    local current_env
    current_env=$(get_active_environment)
    log "🎯 Initial active environment: $current_env"
    
    # Background monitoring
    while [[ $(($(date +%s) - start_time)) -lt $TEST_DURATION ]]; do
        total_checks=$((total_checks + 1))
        
        if check_availability; then
            # Periodically log success (every 50 checks)
            if [[ $((total_checks % 50)) -eq 0 ]]; then
                log "📊 Service available - checks: $total_checks, failures: $failed_checks"
            fi
        else
            failed_checks=$((failed_checks + 1))
            error "DOWNTIME DETECTED - Check #$total_checks failed"
            downtime_detected=true
        fi
        
        # Perform deployment switch every 20 seconds
        if [[ $((total_checks % 200)) -eq 0 ]] && [[ $switch_count -lt 3 ]]; then
            local next_env
            [[ "$current_env" == "blue" ]] && next_env="green" || next_env="blue"
            
            log "🔄 Performing deployment switch: $current_env → $next_env"
            
            if switch_deployment "$next_env"; then
                current_env="$next_env"
                switch_count=$((switch_count + 1))
                log "✅ Switch completed - now active: $current_env"
            else
                error "❌ Switch failed - remaining: $current_env"
            fi
        fi
        
        sleep "$CHECK_INTERVAL"
    done
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Test results
    log ""
    log "📊 Zero-Downtime Test Results:"
    log "   Duration: ${duration} seconds"
    log "   Total checks: $total_checks"
    log "   Failed checks: $failed_checks"
    log "   Availability: $(echo "scale=4; (1 - $failed_checks/$total_checks)*100" | bc -l)%"
    log "   Deployment switches: $switch_count"
    
    if [[ $downtime_detected == true ]]; then
        error ""
        error "❌ ZERO-DOWNTIME TEST FAILED"
        error "   Service interruption was detected during the test"
        error "   Failed checks: $failed_checks out of $total_checks"
        
        # Save failure report
        cat > /app/data/test_failure.json << EOF
{
    "test_result": "FAILED",
    "duration": $duration,
    "total_checks": $total_checks,
    "failed_checks": $failed_checks,
    "availability_percent": $(echo "scale=4; (1 - $failed_checks/$total_checks)*100" | bc -l),
    "deployment_switches": $switch_count,
    "timestamp": "$(date -Iseconds)"
}
EOF
        
        return 1
    else
        success ""
        success "✅ ZERO-DOWNTIME TEST PASSED"
        success "   No service interruption detected"
        success "   Perfect availability: 100%"
        
        # Save success report
        cat > /app/data/test_success.json << EOF
{
    "test_result": "PASSED",
    "duration": $duration,
    "total_checks": $total_checks,
    "failed_checks": 0,
    "availability_percent": 100,
    "deployment_switches": $switch_count,
    "timestamp": "$(date -Iseconds)"
}
EOF
        
        return 0
    fi
}

# Command line handling
case "${1:-test}" in
    "test")
        run_zero_downtime_test
        ;;
    "quick")
        TEST_DURATION=30
        run_zero_downtime_test
        ;;
    "extended")
        TEST_DURATION=300
        run_zero_downtime_test
        ;;
    *)
        echo "Usage: $0 [test|quick|extended]"
        echo "  test     - 60 second test (default)"
        echo "  quick    - 30 second test"
        echo "  extended - 300 second test"
        exit 1
        ;;
esac