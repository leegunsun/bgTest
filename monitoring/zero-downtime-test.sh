#!/bin/bash

# Zero-Downtime Test Script
# Tests blue-green deployment switching without service interruption

set -euo pipefail

# Configuration
TEST_DURATION=${TEST_DURATION:-60}
TEST_INTERVAL=${TEST_INTERVAL:-1}
NGINX_URL=${NGINX_URL:-"http://nginx-proxy:80"}
API_URL=${API_URL:-"http://api-server:9000"}

# Counters
TOTAL_REQUESTS=0
SUCCESSFUL_REQUESTS=0
FAILED_REQUESTS=0
RESPONSE_TIMES=()

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Test single request
test_request() {
    local start_time=$(date +%s.%3N)
    
    if curl -f -s --max-time 5 "$NGINX_URL" >/dev/null 2>&1; then
        local end_time=$(date +%s.%3N)
        local response_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0.000")
        
        SUCCESSFUL_REQUESTS=$((SUCCESSFUL_REQUESTS + 1))
        RESPONSE_TIMES+=("$response_time")
        return 0
    else
        FAILED_REQUESTS=$((FAILED_REQUESTS + 1))
        return 1
    fi
}

# Get current active environment
get_active_env() {
    curl -s --max-time 5 "$API_URL/status" | jq -r .current_deployment 2>/dev/null || echo "unknown"
}

# Calculate statistics
calculate_stats() {
    if [ ${#RESPONSE_TIMES[@]} -gt 0 ]; then
        local sum=0
        local count=${#RESPONSE_TIMES[@]}
        
        for time in "${RESPONSE_TIMES[@]}"; do
            sum=$(echo "$sum + $time" | bc -l 2>/dev/null || echo "$sum")
        done
        
        local avg=$(echo "scale=3; $sum / $count" | bc -l 2>/dev/null || echo "0.000")
        echo "$avg"
    else
        echo "0.000"
    fi
}

# Main test function
run_zero_downtime_test() {
    local start_time=$(date +%s)
    local end_time=$((start_time + TEST_DURATION))
    local last_env=""
    local env_switches=0
    
    log "🧪 Starting zero-downtime test..."
    log "⚙️  Configuration: duration=${TEST_DURATION}s, interval=${TEST_INTERVAL}s"
    log "🎯 Target: $NGINX_URL"
    
    # Initial environment check
    last_env=$(get_active_env)
    log "📊 Initial active environment: $last_env"
    
    # Test loop
    while [ $(date +%s) -lt $end_time ]; do
        TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
        
        # Test request
        if test_request; then
            echo -n "✅"
        else
            echo -n "❌"
            log "⚠️  Request failed (total failures: $FAILED_REQUESTS)"
        fi
        
        # Check for environment switches
        current_env=$(get_active_env)
        if [ "$current_env" != "$last_env" ] && [ "$current_env" != "unknown" ] && [ "$last_env" != "unknown" ]; then
            env_switches=$((env_switches + 1))
            log ""
            log "🔄 Environment switch detected: $last_env → $current_env"
            last_env="$current_env"
        fi
        
        # Progress indicator
        if [ $((TOTAL_REQUESTS % 10)) -eq 0 ]; then
            echo " [$TOTAL_REQUESTS]"
        fi
        
        sleep $TEST_INTERVAL
    done
    
    echo ""
    log "🏁 Test completed!"
    
    # Calculate results
    local success_rate=0
    if [ $TOTAL_REQUESTS -gt 0 ]; then
        success_rate=$(echo "scale=2; $SUCCESSFUL_REQUESTS * 100 / $TOTAL_REQUESTS" | bc -l 2>/dev/null || echo "0")
    fi
    
    local avg_response_time=$(calculate_stats)
    
    # Results
    log "📊 Test Results:"
    log "   Total Requests: $TOTAL_REQUESTS"
    log "   Successful: $SUCCESSFUL_REQUESTS"
    log "   Failed: $FAILED_REQUESTS"
    log "   Success Rate: ${success_rate}%"
    log "   Average Response Time: ${avg_response_time}s"
    log "   Environment Switches: $env_switches"
    log "   Final Active Environment: $(get_active_env)"
    
    # Zero-downtime validation
    if [ $FAILED_REQUESTS -eq 0 ]; then
        log "✅ ZERO-DOWNTIME TEST PASSED: No requests failed during deployment"
        return 0
    else
        log "❌ ZERO-DOWNTIME TEST FAILED: $FAILED_REQUESTS requests failed"
        return 1
    fi
}

# Signal handlers
cleanup() {
    log "🛑 Test interrupted by user"
    exit 1
}

trap cleanup SIGTERM SIGINT

# Main execution
if [ "${1:-}" = "test" ]; then
    run_zero_downtime_test
else
    log "🔧 Zero-downtime test script loaded"
    log "💡 Usage: $0 test"
    log "💡 Or source this script and call: run_zero_downtime_test"
fi