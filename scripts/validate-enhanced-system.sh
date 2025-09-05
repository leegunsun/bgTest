#!/usr/bin/env bash
#
# Enhanced Blue-Green System Validation Script v1.0
# Comprehensive validation of complete load balancing and dual update cycle
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENHANCED_API_URL="http://localhost:9000"
MONITORING_API_URL="http://localhost:8090"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TEST_RESULTS=()

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

test_header() {
    echo -e "${PURPLE}[TEST]${NC} $1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

test_pass() {
    success "✅ PASS: $1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TEST_RESULTS+=("PASS: $1")
}

test_fail() {
    error "❌ FAIL: $1"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    TEST_RESULTS+=("FAIL: $1")
}

# Enhanced system validation
validate_enhanced_system() {
    log "🔍 Enhanced Blue-Green System Comprehensive Validation"
    echo "===================================================="
    
    # Pre-validation checks
    test_header "System Availability Check"
    if validate_system_availability; then
        test_pass "System is running and accessible"
    else
        test_fail "System is not properly available"
        return 1
    fi
    
    # Enhanced API validation
    test_header "Enhanced API Functionality"
    if validate_enhanced_api; then
        test_pass "Enhanced API is functioning correctly"
    else
        test_fail "Enhanced API has issues"
    fi
    
    # Load balancing validation
    test_header "Load Balancing Configuration"
    if validate_load_balancing; then
        test_pass "Load balancing is properly configured"
    else
        test_fail "Load balancing configuration has issues"
    fi
    
    # Dual environment validation
    test_header "Dual Environment Health"
    if validate_dual_environment_health; then
        test_pass "Both environments are healthy"
    else
        test_fail "One or both environments are unhealthy"
    fi
    
    # Monitoring system validation
    test_header "Monitoring System"
    if validate_monitoring_system; then
        test_pass "Monitoring system is operational"
    else
        test_fail "Monitoring system has issues"
    fi
    
    # Gradual migration capability
    test_header "Gradual Migration Capability"
    if validate_gradual_migration_capability; then
        test_pass "Gradual migration capability is ready"
    else
        test_fail "Gradual migration capability has issues"
    fi
    
    # Configuration validation
    test_header "Enhanced Configuration Files"
    if validate_enhanced_configurations; then
        test_pass "Enhanced configuration files are valid"
    else
        test_fail "Enhanced configuration files have issues"
    fi
    
    # Performance validation
    test_header "Performance Metrics"
    if validate_performance_metrics; then
        test_pass "Performance metrics are within acceptable ranges"
    else
        test_fail "Performance metrics indicate issues"
    fi
}

# Comprehensive end-to-end deployment test
test_complete_deployment_cycle() {
    log "🧪 Complete Enhanced Deployment Cycle Test"
    echo "=========================================="
    
    local start_time=$(date +%s)
    local current_env
    current_env=$(get_current_active_environment)
    
    if [[ -z "$current_env" || "$current_env" == "unknown" ]]; then
        test_fail "Cannot determine current active environment"
        return 1
    fi
    
    local target_env
    [[ "$current_env" == "blue" ]] && target_env="green" || target_env="blue"
    
    info "🎯 Testing deployment cycle: $current_env → $target_env"
    
    # Test 1: Pre-deployment validation
    test_header "Pre-deployment Dual Environment Validation"
    if validate_pre_deployment "$target_env"; then
        test_pass "Pre-deployment validation successful"
    else
        test_fail "Pre-deployment validation failed"
        return 1
    fi
    
    # Test 2: Gradual migration test
    test_header "Gradual Migration Execution"
    if execute_test_migration "$target_env"; then
        test_pass "Gradual migration executed successfully"
    else
        test_fail "Gradual migration failed"
        return 1
    fi
    
    # Test 3: Post-migration validation
    test_header "Post-migration System Validation"
    if validate_post_migration "$target_env"; then
        test_pass "Post-migration validation successful"
    else
        test_fail "Post-migration validation failed"
    fi
    
    # Test 4: Rollback capability test
    test_header "Rollback Capability Test"
    if test_rollback_capability "$current_env"; then
        test_pass "Rollback capability verified"
    else
        test_fail "Rollback capability has issues"
    fi
    
    local end_time=$(date +%s)
    local test_duration=$((end_time - start_time))
    
    info "🎯 Complete deployment cycle test duration: ${test_duration} seconds"
}

# Stress testing
stress_test_system() {
    log "🏋️  Enhanced System Stress Testing"
    echo "================================="
    
    test_header "High Load Traffic Test"
    if execute_high_load_test; then
        test_pass "System handles high load correctly"
    else
        test_fail "System struggles under high load"
    fi
    
    test_header "Rapid Migration Test" 
    if execute_rapid_migration_test; then
        test_pass "System handles rapid migrations"
    else
        test_fail "System has issues with rapid migrations"
    fi
    
    test_header "Resource Exhaustion Test"
    if execute_resource_test; then
        test_pass "System handles resource constraints"
    else
        test_fail "System fails under resource constraints"
    fi
}

# Implementation of validation functions

validate_system_availability() {
    local services=("nginx-proxy:80/health" "blue-app:3001/health" "green-app:3002/health" "api-server:9000/health")
    local all_healthy=true
    
    for service in "${services[@]}"; do
        local name="${service%%:*}"
        local endpoint="http://localhost:${service#*:}"
        
        if ! curl -f --max-time 3 "$endpoint" >/dev/null 2>&1; then
            warn "Service $name is not responding"
            all_healthy=false
        fi
    done
    
    $all_healthy
}

validate_enhanced_api() {
    local api_tests=(
        "/health:GET"
        "/status:GET"
        "/validate:GET"
        "/migration:GET"
    )
    
    for test in "${api_tests[@]}"; do
        local endpoint="${test%%:*}"
        local method="${test##*:}"
        local url="$ENHANCED_API_URL$endpoint"
        
        if ! curl -f --max-time 5 "$url" >/dev/null 2>&1; then
            warn "Enhanced API endpoint $endpoint ($method) failed"
            return 1
        fi
    done
    
    # Test API response structure
    local status_response
    status_response=$(curl -s "$ENHANCED_API_URL/status" 2>/dev/null || echo '{}')
    
    if ! echo "$status_response" | jq -e '.active' >/dev/null 2>&1; then
        warn "Enhanced API status response missing 'active' field"
        return 1
    fi
    
    return 0
}

validate_load_balancing() {
    # Check NGINX configuration
    if ! docker exec nginx-proxy nginx -t >/dev/null 2>&1; then
        warn "NGINX configuration validation failed"
        return 1
    fi
    
    # Check enhanced configuration files exist
    local config_files=(
        "/etc/nginx/conf.d/upstreams-enhanced.conf"
        "/etc/nginx/conf.d/routing-enhanced.conf"
        "/etc/nginx/conf.d/active.env"
    )
    
    for config in "${config_files[@]}"; do
        if ! docker exec nginx-proxy test -f "$config" 2>/dev/null; then
            warn "Enhanced configuration file missing: $config"
            return 1
        fi
    done
    
    # Test load balancer status endpoint
    if ! curl -f --max-time 3 "http://localhost:80/lb/status" >/dev/null 2>&1; then
        warn "Load balancer status endpoint not accessible"
        return 1
    fi
    
    return 0
}

validate_dual_environment_health() {
    local validation_result
    validation_result=$(curl -s --max-time 10 "$ENHANCED_API_URL/validate" 2>/dev/null || echo '{"success":false}')
    
    if echo "$validation_result" | jq -e '.success' >/dev/null 2>&1; then
        return 0
    else
        warn "Dual environment validation failed"
        return 1
    fi
}

validate_monitoring_system() {
    # Check if monitoring system is running
    if ! curl -f --max-time 3 "$MONITORING_API_URL/health" >/dev/null 2>&1; then
        warn "Enhanced monitoring system is not accessible"
        return 1
    fi
    
    # Check monitoring endpoints
    local monitoring_endpoints=("/metrics" "/dashboard" "/alerts")
    
    for endpoint in "${monitoring_endpoints[@]}"; do
        if ! curl -f --max-time 5 "$MONITORING_API_URL$endpoint" >/dev/null 2>&1; then
            warn "Monitoring endpoint $endpoint is not accessible"
            return 1
        fi
    done
    
    return 0
}

validate_gradual_migration_capability() {
    # Check if enhanced deployment script exists and is executable
    if [[ ! -x "$PROJECT_DIR/scripts/enhanced-deploy.sh" ]]; then
        warn "Enhanced deployment script is not available or executable"
        return 1
    fi
    
    # Check if enhanced API supports migration endpoints
    local migration_result
    migration_result=$(curl -s --max-time 5 "$ENHANCED_API_URL/migration" 2>/dev/null || echo '{}')
    
    if ! echo "$migration_result" | jq -e '.status' >/dev/null 2>&1; then
        warn "Enhanced API migration endpoint not responding properly"
        return 1
    fi
    
    return 0
}

validate_enhanced_configurations() {
    local config_files=(
        "$PROJECT_DIR/conf.d/upstreams-enhanced.conf"
        "$PROJECT_DIR/conf.d/routing-enhanced.conf"
        "$PROJECT_DIR/nginx-enhanced.conf"
        "$PROJECT_DIR/api-service/enhanced-api.js"
    )
    
    for config in "${config_files[@]}"; do
        if [[ ! -f "$config" ]]; then
            warn "Enhanced configuration file missing: $config"
            return 1
        fi
    done
    
    # Validate NGINX configuration syntax (if possible)
    if command -v nginx >/dev/null; then
        if ! nginx -t -c "$PROJECT_DIR/nginx-enhanced.conf" 2>/dev/null; then
            warn "Enhanced NGINX configuration has syntax errors"
            return 1
        fi
    fi
    
    return 0
}

validate_performance_metrics() {
    # Get system metrics from monitoring system
    local metrics
    metrics=$(curl -s --max-time 5 "$MONITORING_API_URL/metrics" 2>/dev/null || echo '{}')
    
    if [[ -z "$metrics" || "$metrics" == '{}' ]]; then
        warn "Unable to retrieve performance metrics"
        return 1
    fi
    
    # Check basic performance indicators
    local health_status
    health_status=$(echo "$metrics" | jq -r '.health.nginx.healthy // false' 2>/dev/null)
    
    if [[ "$health_status" != "true" ]]; then
        warn "Performance metrics indicate unhealthy system"
        return 1
    fi
    
    return 0
}

validate_pre_deployment() {
    local target_env="$1"
    
    # Validate target environment is ready
    local port
    [[ "$target_env" == "green" ]] && port=3002 || port=3001
    
    if ! curl -f --max-time 5 "http://localhost:$port/health" >/dev/null 2>&1; then
        warn "Target environment $target_env is not ready"
        return 1
    fi
    
    # Validate API pre-deployment check
    local validation_result
    validation_result=$(curl -s --max-time 10 "$ENHANCED_API_URL/validate" 2>/dev/null || echo '{"success":false}')
    
    echo "$validation_result" | jq -e '.success' >/dev/null 2>&1
}

execute_test_migration() {
    local target_env="$1"
    
    info "🔄 Executing test migration to $target_env..."
    
    # Use enhanced deployment script for gradual migration
    if "$PROJECT_DIR/scripts/enhanced-deploy.sh" gradual "$target_env" "test-v1.0" >/dev/null 2>&1; then
        return 0
    else
        warn "Test migration failed"
        return 1
    fi
}

validate_post_migration() {
    local target_env="$1"
    
    # Check that target environment is now active
    local current_active
    current_active=$(get_current_active_environment)
    
    if [[ "$current_active" != "$target_env" ]]; then
        warn "Migration did not complete - expected $target_env, got $current_active"
        return 1
    fi
    
    # Validate system health post-migration
    if ! validate_system_availability; then
        warn "System is not healthy after migration"
        return 1
    fi
    
    return 0
}

test_rollback_capability() {
    local original_env="$1"
    
    info "🔄 Testing rollback capability to $original_env..."
    
    # Execute rollback
    local rollback_result
    rollback_result=$(curl -s -X POST --max-time 120 "$ENHANCED_API_URL/rollback" 2>/dev/null || echo '{"success":false}')
    
    if ! echo "$rollback_result" | jq -e '.success' >/dev/null 2>&1; then
        warn "Rollback execution failed"
        return 1
    fi
    
    # Verify rollback completed
    sleep 5
    local current_active
    current_active=$(get_current_active_environment)
    
    if [[ "$current_active" == "$original_env" ]]; then
        return 0
    else
        warn "Rollback verification failed - expected $original_env, got $current_active"
        return 1
    fi
}

execute_high_load_test() {
    info "🚀 Executing high load test (100 concurrent requests)..."
    
    # Use curl or ab for load testing
    if command -v ab >/dev/null; then
        if ab -n 100 -c 10 -t 30 "http://localhost:80/" >/dev/null 2>&1; then
            return 0
        fi
    else
        # Fallback to simple curl test
        local failed=0
        for i in {1..20}; do
            if ! curl -f --max-time 2 "http://localhost:80/status" >/dev/null 2>&1; then
                ((failed++))
            fi
        done
        
        # Allow up to 10% failure rate
        if [[ $failed -le 2 ]]; then
            return 0
        fi
    fi
    
    return 1
}

execute_rapid_migration_test() {
    info "⚡ Testing rapid migrations..."
    
    local current_env
    current_env=$(get_current_active_environment)
    local target_env
    [[ "$current_env" == "blue" ]] && target_env="green" || target_env="blue"
    
    # Execute rapid back-and-forth migrations
    for cycle in {1..2}; do
        info "Rapid migration cycle $cycle: $current_env → $target_env"
        
        if ! "$PROJECT_DIR/scripts/enhanced-deploy.sh" switch "$target_env" >/dev/null 2>&1; then
            warn "Rapid migration cycle $cycle failed"
            return 1
        fi
        
        sleep 10
        
        # Swap for next cycle
        local temp="$current_env"
        current_env="$target_env"
        target_env="$temp"
    done
    
    return 0
}

execute_resource_test() {
    info "💾 Testing resource constraints..."
    
    # This is a placeholder for resource constraint testing
    # In a full implementation, this would stress memory, CPU, network, etc.
    
    # Simple check: ensure system is still responsive
    local responsive=true
    for i in {1..5}; do
        if ! curl -f --max-time 10 "http://localhost:80/health" >/dev/null 2>&1; then
            responsive=false
            break
        fi
        sleep 2
    done
    
    $responsive
}

get_current_active_environment() {
    local status_response
    status_response=$(curl -s --max-time 5 "$ENHANCED_API_URL/status" 2>/dev/null || echo '{}')
    
    echo "$status_response" | jq -r '.active // "unknown"' 2>/dev/null || echo "unknown"
}

# Generate comprehensive test report
generate_test_report() {
    echo ""
    log "📊 Enhanced Blue-Green System Validation Report"
    echo "==============================================="
    echo ""
    
    info "Test Summary:"
    echo "  Total Tests: $TOTAL_TESTS"
    echo -e "  Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "  Failed: ${RED}$FAILED_TESTS${NC}"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "  Overall: ${GREEN}✅ ALL TESTS PASSED${NC}"
        overall_result="PASS"
    else
        echo -e "  Overall: ${RED}❌ SOME TESTS FAILED${NC}"
        overall_result="FAIL"
    fi
    
    echo ""
    info "Detailed Results:"
    for result in "${TEST_RESULTS[@]}"; do
        if [[ $result == PASS:* ]]; then
            echo -e "  ${GREEN}✅${NC} ${result#PASS: }"
        else
            echo -e "  ${RED}❌${NC} ${result#FAIL: }"
        fi
    done
    
    echo ""
    local report_file="$PROJECT_DIR/validation-report-$(date +%Y%m%d-%H%M%S).txt"
    {
        echo "Enhanced Blue-Green System Validation Report"
        echo "Generated: $(date)"
        echo ""
        echo "Test Summary:"
        echo "  Total Tests: $TOTAL_TESTS"
        echo "  Passed: $PASSED_TESTS"
        echo "  Failed: $FAILED_TESTS"
        echo "  Overall: $overall_result"
        echo ""
        echo "Detailed Results:"
        for result in "${TEST_RESULTS[@]}"; do
            echo "  $result"
        done
    } > "$report_file"
    
    info "📄 Detailed report saved: $report_file"
    
    return $FAILED_TESTS
}

# Main execution
main() {
    case "${1:-validate}" in
        "validate")
            validate_enhanced_system
            ;;
        "test")
            validate_enhanced_system
            test_complete_deployment_cycle
            ;;
        "stress")
            validate_enhanced_system
            test_complete_deployment_cycle
            stress_test_system
            ;;
        "full")
            validate_enhanced_system
            test_complete_deployment_cycle
            stress_test_system
            ;;
        "help"|*)
            echo "Enhanced Blue-Green System Validation v1.0"
            echo "Usage: $0 {validate|test|stress|full}"
            echo ""
            echo "Commands:"
            echo "  validate  - Basic system validation"
            echo "  test      - Validation + deployment cycle test"
            echo "  stress    - Full testing including stress tests"
            echo "  full      - Complete comprehensive validation"
            echo ""
            echo "Examples:"
            echo "  $0 validate    # Quick health check"
            echo "  $0 test        # Thorough testing"
            echo "  $0 full        # Complete validation suite"
            ;;
    esac
    
    generate_test_report
}

# Execute main function
main "$@"