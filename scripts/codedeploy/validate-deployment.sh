#!/bin/bash

# CodeDeploy ValidateService Hook
# Comprehensive deployment validation for Blue-Green application

set -e

LOG_FILE="/var/log/codedeploy/validate-deployment.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1" | tee -a "$LOG_FILE"
}

success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1" | tee -a "$LOG_FILE"
}

log "Starting ValidateService hook..."

# Global variables for tracking validation status
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# Function to increment error count
increment_error() {
    ((VALIDATION_ERRORS++))
}

# Function to increment warning count
increment_warning() {
    ((VALIDATION_WARNINGS++))
}

# Function to validate PM2 processes
validate_pm2_processes() {
    log "Validating PM2 processes..."
    
    # Run as ec2-user
    local pm2_output
    pm2_output=$(su - ec2-user -c "pm2 list --no-daemon" 2>/dev/null || echo "PM2_ERROR")
    
    if [[ "$pm2_output" == "PM2_ERROR" ]]; then
        error "Failed to get PM2 process list"
        increment_error
        return 1
    fi
    
    # Check each expected process
    local expected_processes=("bluegreen-app-1" "bluegreen-app-2" "bluegreen-app-3" "bluegreen-app-4")
    local online_count=0
    
    for process in "${expected_processes[@]}"; do
        if echo "$pm2_output" | grep -q "$process.*online"; then
            log "✅ $process is online"
            ((online_count++))
        else
            error "❌ $process is not online"
            increment_error
        fi
    done
    
    log "PM2 processes online: $online_count/4"
    
    if [[ $online_count -eq 4 ]]; then
        success "All PM2 processes are online"
        return 0
    else
        error "Not all PM2 processes are online"
        return 1
    fi
}

# Function to validate application ports
validate_application_ports() {
    log "Validating application ports..."
    
    local ports=(3001 3002 3003 3004)
    local listening_count=0
    
    for port in "${ports[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            log "✅ Port $port is listening"
            ((listening_count++))
        else
            error "❌ Port $port is not listening"
            increment_error
        fi
    done
    
    log "Listening ports: $listening_count/4"
    
    if [[ $listening_count -eq 4 ]]; then
        success "All application ports are listening"
        return 0
    else
        error "Not all application ports are listening"
        return 1
    fi
}

# Function to validate application health endpoints
validate_health_endpoints() {
    log "Validating application health endpoints..."
    
    local ports=(3001 3002 3003 3004)
    local healthy_count=0
    local max_retries=3
    
    for port in "${ports[@]}"; do
        log "Testing health endpoint on port $port..."
        
        local success=false
        for ((retry=1; retry<=max_retries; retry++)); do
            local http_status
            http_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/health/deep" --max-time 10 2>/dev/null || echo "000")
            
            if [[ "$http_status" == "200" ]]; then
                log "✅ Port $port health check: HTTP $http_status (attempt $retry)"
                ((healthy_count++))
                success=true
                break
            else
                log "❌ Port $port health check: HTTP $http_status (attempt $retry/$max_retries)"
                if [[ $retry -lt $max_retries ]]; then
                    log "Retrying health check for port $port in 5 seconds..."
                    sleep 5
                fi
            fi
        done
        
        if [[ "$success" == "false" ]]; then
            error "Health check failed for port $port after $max_retries attempts"
            increment_error
        fi
    done
    
    log "Healthy endpoints: $healthy_count/4"
    
    if [[ $healthy_count -eq 4 ]]; then
        success "All health endpoints are responding"
        return 0
    else
        error "Not all health endpoints are healthy"
        return 1
    fi
}

# Function to validate NGINX configuration and status
validate_nginx() {
    log "Validating NGINX..."
    
    # Check if NGINX is running
    if systemctl is-active nginx &>/dev/null; then
        log "✅ NGINX service is active"
    else
        error "❌ NGINX service is not active"
        increment_error
        return 1
    fi
    
    # Test NGINX configuration
    if nginx -t &>/dev/null; then
        log "✅ NGINX configuration is valid"
    else
        error "❌ NGINX configuration has errors"
        increment_error
        return 1
    fi
    
    # Test NGINX health endpoint
    local nginx_health
    nginx_health=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/health" --max-time 5 2>/dev/null || echo "000")
    
    if [[ "$nginx_health" == "200" ]]; then
        log "✅ NGINX health endpoint: HTTP $nginx_health"
    else
        error "❌ NGINX health endpoint: HTTP $nginx_health"
        increment_error
    fi
    
    # Test NGINX deep health endpoint (should proxy to application)
    local nginx_deep_health
    nginx_deep_health=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/health/deep" --max-time 10 2>/dev/null || echo "000")
    
    if [[ "$nginx_deep_health" == "200" ]]; then
        log "✅ NGINX deep health endpoint: HTTP $nginx_deep_health"
    else
        error "❌ NGINX deep health endpoint: HTTP $nginx_deep_health"
        increment_error
    fi
    
    success "NGINX validation completed"
}

# Function to validate system resources
validate_system_resources() {
    log "Validating system resources..."
    
    # Check disk usage
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ $disk_usage -lt 80 ]]; then
        log "✅ Disk usage: ${disk_usage}%"
    elif [[ $disk_usage -lt 90 ]]; then
        warn "Disk usage is at ${disk_usage}%"
        increment_warning
    else
        error "Disk usage is critically high: ${disk_usage}%"
        increment_error
    fi
    
    # Check memory usage
    local mem_usage
    mem_usage=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
    
    if [[ $mem_usage -lt 80 ]]; then
        log "✅ Memory usage: ${mem_usage}%"
    elif [[ $mem_usage -lt 90 ]]; then
        warn "Memory usage is at ${mem_usage}%"
        increment_warning
    else
        error "Memory usage is critically high: ${mem_usage}%"
        increment_error
    fi
    
    # Check load average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local load_threshold="2.0"
    
    if (( $(echo "$load_avg < $load_threshold" | bc -l) )); then
        log "✅ Load average: $load_avg"
    else
        warn "Load average is high: $load_avg"
        increment_warning
    fi
    
    success "System resources validation completed"
}

# Function to validate application response content
validate_application_content() {
    log "Validating application response content..."
    
    local ports=(3001 3002 3003 3004)
    local content_valid_count=0
    
    for port in "${ports[@]}"; do
        log "Testing application content on port $port..."
        
        # Test main endpoint
        local response
        response=$(curl -s "http://localhost:$port/" --max-time 10 2>/dev/null || echo "ERROR")
        
        if [[ "$response" == "ERROR" ]]; then
            error "Failed to get response from port $port"
            increment_error
            continue
        fi
        
        # Check if response contains expected content
        if echo "$response" | grep -q "True Blue-Green Deployment"; then
            log "✅ Port $port: Content validation passed"
            ((content_valid_count++))
        else
            error "❌ Port $port: Content validation failed"
            increment_error
        fi
        
        # Test version endpoint
        local version_response
        version_response=$(curl -s "http://localhost:$port/version" --max-time 5 2>/dev/null || echo "ERROR")
        
        if [[ "$version_response" != "ERROR" ]] && echo "$version_response" | grep -q '"version"'; then
            log "✅ Port $port: Version endpoint working"
        else
            warn "Port $port: Version endpoint not working properly"
            increment_warning
        fi
    done
    
    log "Content validation: $content_valid_count/4 instances"
    
    if [[ $content_valid_count -eq 4 ]]; then
        success "All application instances are serving correct content"
        return 0
    else
        error "Not all instances are serving correct content"
        return 1
    fi
}

# Function to validate deployment metadata
validate_deployment_metadata() {
    log "Validating deployment metadata..."
    
    local metadata_file="/opt/bluegreen-app/deployment-info.json"
    local startup_status="/opt/bluegreen-app/startup-status.json"
    
    # Check deployment metadata file
    if [[ -f "$metadata_file" ]]; then
        log "✅ Deployment metadata file exists"
        
        # Validate JSON format
        if jq empty "$metadata_file" 2>/dev/null; then
            log "✅ Deployment metadata is valid JSON"
        else
            error "❌ Deployment metadata is not valid JSON"
            increment_error
        fi
    else
        warn "Deployment metadata file not found"
        increment_warning
    fi
    
    # Check startup status file
    if [[ -f "$startup_status" ]]; then
        log "✅ Startup status file exists"
        
        # Check startup status
        local startup_status_val
        startup_status_val=$(jq -r '.startup.status' "$startup_status" 2>/dev/null || echo "unknown")
        
        if [[ "$startup_status_val" == "completed" ]]; then
            log "✅ Startup status: $startup_status_val"
        else
            error "❌ Startup status: $startup_status_val"
            increment_error
        fi
    else
        warn "Startup status file not found"
        increment_warning
    fi
    
    success "Deployment metadata validation completed"
}

# Function to run load test
run_basic_load_test() {
    log "Running basic load test..."
    
    local test_url="http://localhost/health"
    local test_duration=10
    local concurrent_requests=5
    
    log "Load testing $test_url for ${test_duration}s with $concurrent_requests concurrent requests..."
    
    # Simple concurrent request test
    local pids=()
    local start_time=$(date +%s)
    local end_time=$((start_time + test_duration))
    local request_count=0
    local success_count=0
    
    # Start concurrent workers
    for ((i=1; i<=concurrent_requests; i++)); do
        {
            while [[ $(date +%s) -lt $end_time ]]; do
                if curl -s -o /dev/null -w "%{http_code}" "$test_url" --max-time 2 | grep -q "200"; then
                    ((success_count++))
                fi
                ((request_count++))
                sleep 0.1
            done
        } &
        pids+=($!)
    done
    
    # Wait for all workers to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    local success_rate=0
    if [[ $request_count -gt 0 ]]; then
        success_rate=$(( (success_count * 100) / request_count ))
    fi
    
    log "Load test results: $success_count/$request_count requests successful (${success_rate}%)"
    
    if [[ $success_rate -ge 95 ]]; then
        log "✅ Load test passed with ${success_rate}% success rate"
    elif [[ $success_rate -ge 90 ]]; then
        warn "Load test passed with ${success_rate}% success rate (below optimal)"
        increment_warning
    else
        error "Load test failed with ${success_rate}% success rate"
        increment_error
    fi
    
    success "Basic load test completed"
}

# Function to validate CodeDeploy agent
validate_codedeploy_agent() {
    log "Validating CodeDeploy agent..."
    
    if systemctl is-active codedeploy-agent &>/dev/null; then
        log "✅ CodeDeploy agent is running"
    else
        error "❌ CodeDeploy agent is not running"
        increment_error
        return 1
    fi
    
    # Check CodeDeploy agent logs for any recent errors
    local agent_log="/var/log/aws/codedeploy-agent/codedeploy-agent.log"
    if [[ -f "$agent_log" ]]; then
        local recent_errors
        recent_errors=$(tail -100 "$agent_log" | grep -i error | tail -5)
        
        if [[ -n "$recent_errors" ]]; then
            warn "Recent CodeDeploy agent errors found:"
            echo "$recent_errors" | while read -r line; do
                warn "  $line"
            done
            increment_warning
        else
            log "✅ No recent errors in CodeDeploy agent log"
        fi
    fi
    
    success "CodeDeploy agent validation completed"
}

# Function to send CloudWatch metrics
send_cloudwatch_metrics() {
    log "Sending deployment validation metrics to CloudWatch..."
    
    local namespace="BlueGreen/Deployment"
    local instance_id
    instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'unknown')
    
    # Send validation success metric
    local validation_success=1
    if [[ $VALIDATION_ERRORS -gt 0 ]]; then
        validation_success=0
    fi
    
    aws cloudwatch put-metric-data \
        --namespace "$namespace" \
        --metric-name "DeploymentValidationSuccess" \
        --value $validation_success \
        --dimensions Instance="$instance_id",DeploymentGroup="${DEPLOYMENT_GROUP_NAME:-unknown}" \
        2>/dev/null || log "Failed to send CloudWatch metrics (this is non-critical)"
    
    # Send error count
    aws cloudwatch put-metric-data \
        --namespace "$namespace" \
        --metric-name "ValidationErrors" \
        --value $VALIDATION_ERRORS \
        --dimensions Instance="$instance_id",DeploymentGroup="${DEPLOYMENT_GROUP_NAME:-unknown}" \
        2>/dev/null || true
    
    # Send warning count
    aws cloudwatch put-metric-data \
        --namespace "$namespace" \
        --metric-name "ValidationWarnings" \
        --value $VALIDATION_WARNINGS \
        --dimensions Instance="$instance_id",DeploymentGroup="${DEPLOYMENT_GROUP_NAME:-unknown}" \
        2>/dev/null || true
    
    log "CloudWatch metrics sent (errors: $VALIDATION_ERRORS, warnings: $VALIDATION_WARNINGS)"
}

# Function to generate validation report
generate_validation_report() {
    log "Generating validation report..."
    
    local report_file="/opt/bluegreen-app/validation-report.json"
    
    cat > "$report_file" << EOF
{
    "validation": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "deployment_id": "${DEPLOYMENT_ID:-unknown}",
        "deployment_group": "${DEPLOYMENT_GROUP_NAME:-unknown}",
        "status": "$([ $VALIDATION_ERRORS -eq 0 ] && echo 'passed' || echo 'failed')",
        "errors": $VALIDATION_ERRORS,
        "warnings": $VALIDATION_WARNINGS
    },
    "checks": {
        "pm2_processes": "$(validate_pm2_processes &>/dev/null && echo 'passed' || echo 'failed')",
        "application_ports": "$(validate_application_ports &>/dev/null && echo 'passed' || echo 'failed')",
        "health_endpoints": "$(validate_health_endpoints &>/dev/null && echo 'passed' || echo 'failed')",
        "nginx": "$(validate_nginx &>/dev/null && echo 'passed' || echo 'failed')",
        "system_resources": "$(validate_system_resources &>/dev/null && echo 'passed' || echo 'failed')"
    },
    "instance": {
        "id": "$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'unknown')",
        "private_ip": "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo 'unknown')"
    }
}
EOF
    
    chown ec2-user:ec2-user "$report_file"
    chmod 644 "$report_file"
    
    log "Validation report created: $report_file"
}

# Main validation execution
main() {
    log "ValidateService hook started"
    log "Comprehensive deployment validation beginning..."
    
    # Run all validation checks
    log "=== Starting validation checks ==="
    
    validate_pm2_processes
    validate_application_ports  
    validate_health_endpoints
    validate_nginx
    validate_system_resources
    validate_application_content
    validate_deployment_metadata
    validate_codedeploy_agent
    
    # Run basic load test
    run_basic_load_test
    
    # Send metrics to CloudWatch
    send_cloudwatch_metrics
    
    # Generate validation report
    generate_validation_report
    
    # Final validation summary
    log "=== Validation Summary ==="
    log "Errors: $VALIDATION_ERRORS"
    log "Warnings: $VALIDATION_WARNINGS"
    
    if [[ $VALIDATION_ERRORS -eq 0 ]]; then
        success "🎉 Deployment validation PASSED!"
        success "All critical checks passed successfully"
        
        if [[ $VALIDATION_WARNINGS -gt 0 ]]; then
            warn "Note: $VALIDATION_WARNINGS warnings were found (non-critical)"
        fi
        
        log "ValidateService hook completed successfully"
        exit 0
    else
        error "💥 Deployment validation FAILED!"
        error "$VALIDATION_ERRORS critical errors found"
        error "Deployment may not be functioning correctly"
        
        log "ValidateService hook failed"
        exit 1
    fi
}

# Execute main function
main "$@"