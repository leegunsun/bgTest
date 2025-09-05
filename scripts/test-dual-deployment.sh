#!/usr/bin/env bash
#
# Comprehensive Test Suite for Enhanced Blue-Green Deployment
# Tests dual update cycle, load balancing, and all deployment modes
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$1")
}

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Test helper functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Running: $test_name"
    
    if $test_function; then
        log_success "$test_name"
        return 0
    else
        log_failure "$test_name"
        return 1
    fi
}

wait_for_service() {
    local service_url="$1"
    local timeout="${2:-30}"
    local attempt=0
    
    while [[ $attempt -lt $timeout ]]; do
        if curl -fsS --max-time 3 "$service_url" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}

get_environment_version() {
    local env="$1"
    local port
    [[ "$env" == "blue" ]] && port=3001 || port=3002
    curl -fsS "http://localhost:$port/version" 2>/dev/null | jq -r '.version' 2>/dev/null || echo "unknown"
}

count_environment_responses() {
    local requests="${1:-100}"
    local blue_count=0
    local green_count=0
    local failed_count=0
    
    for i in $(seq 1 "$requests"); do
        local response
        response=$(curl -s --max-time 3 "http://localhost:80/" 2>/dev/null || echo "FAILED")
        
        if echo "$response" | grep -q "BLUE\|blue" 2>/dev/null; then
            blue_count=$((blue_count + 1))
        elif echo "$response" | grep -q "GREEN\|green" 2>/dev/null; then
            green_count=$((green_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
        
        [[ $((i % 20)) -eq 0 ]] && echo -n "."
    done
    echo ""
    
    echo "$blue_count:$green_count:$failed_count"
}

# Individual test functions
test_system_startup() {
    log_step "Testing system startup"
    
    # Stop system if running
    "$DEPLOY_SCRIPT" stop >/dev/null 2>&1 || true
    sleep 5
    
    # Start system
    if "$DEPLOY_SCRIPT" start >/dev/null 2>&1; then
        # Wait for services
        if wait_for_service "http://localhost:80/status" 60; then
            return 0
        fi
    fi
    return 1
}

test_traditional_bluegreen() {
    log_step "Testing traditional Blue-Green deployment"
    
    # Deploy version 1.0.0 to inactive environment
    if ! "$DEPLOY_SCRIPT" bluegreen "1.0.0" >/dev/null 2>&1; then
        return 1
    fi
    
    # Verify deployment
    sleep 10
    if wait_for_service "http://localhost:80/status" 30; then
        return 0
    fi
    return 1
}

test_dual_update_cycle() {
    log_step "Testing complete dual update cycle"
    
    # Run dual deployment
    if ! "$DEPLOY_SCRIPT" dual "2.0.0" >/dev/null 2>&1; then
        return 1
    fi
    
    # Wait for completion
    sleep 30
    
    # Verify both environments have same version
    local blue_version green_version
    blue_version=$(get_environment_version "blue")
    green_version=$(get_environment_version "green")
    
    if [[ "$blue_version" == "2.0.0" && "$green_version" == "2.0.0" ]]; then
        return 0
    fi
    return 1
}

test_load_balancing() {
    log_step "Testing load balancing functionality"
    
    # Enable load balancing
    if ! "$DEPLOY_SCRIPT" loadbalance >/dev/null 2>&1; then
        return 1
    fi
    
    sleep 10
    
    # Test traffic distribution
    log_info "Testing traffic distribution (50 requests)..."
    local results
    results=$(count_environment_responses 50)
    
    local blue_count green_count failed_count
    IFS=':' read -r blue_count green_count failed_count <<< "$results"
    
    log_info "Traffic distribution - Blue: $blue_count, Green: $green_count, Failed: $failed_count"
    
    # Validate load balancing (both environments should receive traffic)
    if [[ $blue_count -gt 10 && $green_count -gt 10 && $failed_count -lt 5 ]]; then
        return 0
    fi
    return 1
}

test_canary_deployment() {
    log_step "Testing canary deployment"
    
    # First ensure we have two different versions for canary test
    "$DEPLOY_SCRIPT" deploy blue "2.0.0" >/dev/null 2>&1
    "$DEPLOY_SCRIPT" deploy green "2.1.0" >/dev/null 2>&1
    sleep 15
    
    # Enable canary with 20% traffic
    if ! "$DEPLOY_SCRIPT" canary 20 >/dev/null 2>&1; then
        return 1
    fi
    
    sleep 10
    
    # Test canary distribution
    log_info "Testing canary distribution (100 requests)..."
    local results
    results=$(count_environment_responses 100)
    
    local blue_count green_count failed_count
    IFS=':' read -r blue_count green_count failed_count <<< "$results"
    
    log_info "Canary distribution - Stable: $blue_count, Canary: $green_count, Failed: $failed_count"
    
    # Validate canary deployment (roughly 80/20 split, with tolerance)
    local total_success=$((blue_count + green_count))
    if [[ $total_success -gt 90 && $green_count -gt 10 && $green_count -lt 40 ]]; then
        return 0
    fi
    return 1
}

test_deployment_modes() {
    log_step "Testing deployment mode switching"
    
    # Test single mode
    if ! "$DEPLOY_SCRIPT" mode single >/dev/null 2>&1; then
        return 1
    fi
    sleep 5
    
    # Test dual mode
    if ! "$DEPLOY_SCRIPT" mode dual >/dev/null 2>&1; then
        return 1
    fi
    sleep 5
    
    # Test HA mode
    if ! "$DEPLOY_SCRIPT" mode ha >/dev/null 2>&1; then
        return 1
    fi
    sleep 5
    
    return 0
}

test_version_synchronization() {
    log_step "Testing version synchronization"
    
    # Synchronize both environments to version 3.0.0
    if ! "$DEPLOY_SCRIPT" sync "3.0.0" >/dev/null 2>&1; then
        return 1
    fi
    
    sleep 30
    
    # Verify synchronization
    local blue_version green_version
    blue_version=$(get_environment_version "blue")
    green_version=$(get_environment_version "green")
    
    if [[ "$blue_version" == "3.0.0" && "$green_version" == "3.0.0" ]]; then
        return 0
    fi
    return 1
}

test_zero_downtime_validation() {
    log_step "Testing zero-downtime during deployment operations"
    
    # Start continuous monitoring
    local monitor_pid
    {
        local failures=0
        for i in $(seq 1 60); do
            if ! curl -fsS --max-time 2 "http://localhost:80/status" >/dev/null 2>&1; then
                failures=$((failures + 1))
            fi
            sleep 1
        done
        echo "$failures" > /tmp/downtime_failures.txt
    } &
    monitor_pid=$!
    
    # Perform deployment operation during monitoring
    "$DEPLOY_SCRIPT" switch blue >/dev/null 2>&1
    sleep 10
    "$DEPLOY_SCRIPT" switch green >/dev/null 2>&1
    
    # Wait for monitoring to complete
    wait $monitor_pid
    
    # Check results
    local failures
    failures=$(cat /tmp/downtime_failures.txt 2>/dev/null || echo "999")
    rm -f /tmp/downtime_failures.txt
    
    if [[ $failures -lt 3 ]]; then
        log_info "Zero-downtime validated: $failures failures in 60 seconds"
        return 0
    else
        log_info "Downtime detected: $failures failures in 60 seconds"
        return 1
    fi
}

test_enhanced_status() {
    log_step "Testing enhanced status display"
    
    # Run status command and check for enhanced information
    local status_output
    status_output=$("$DEPLOY_SCRIPT" status 2>&1)
    
    # Check for enhanced status indicators
    if echo "$status_output" | grep -q "Active Configuration" && \
       echo "$status_output" | grep -q "Deployment Mode" && \
       echo "$status_output" | grep -q "Load Balancing"; then
        return 0
    fi
    return 1
}

# Main test execution
main() {
    echo "🚀 Enhanced Blue-Green Deployment Test Suite"
    echo "=============================================="
    echo ""
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Run test suite
    run_test "System Startup" test_system_startup
    run_test "Traditional Blue-Green" test_traditional_bluegreen
    run_test "Enhanced Status Display" test_enhanced_status
    run_test "Dual Update Cycle" test_dual_update_cycle
    run_test "Load Balancing" test_load_balancing
    run_test "Version Synchronization" test_version_synchronization
    run_test "Deployment Mode Switching" test_deployment_modes
    run_test "Canary Deployment" test_canary_deployment
    run_test "Zero-Downtime Validation" test_zero_downtime_validation
    
    # Test results summary
    echo ""
    echo "📊 Test Results Summary"
    echo "======================"
    echo -e "Total Tests: ${BLUE}$TESTS_RUN${NC}"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo ""
        echo -e "${RED}Failed Tests:${NC}"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $failed_test"
        done
        echo ""
        echo -e "${RED}❌ TEST SUITE FAILED${NC}"
        exit 1
    else
        echo ""
        echo -e "${GREEN}🎉 ✅ ALL TESTS PASSED${NC}"
        echo -e "${GREEN}Enhanced Blue-Green deployment system is working correctly!${NC}"
        exit 0
    fi
}

# Execute main function
main "$@"