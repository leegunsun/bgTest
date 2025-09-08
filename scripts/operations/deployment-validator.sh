#!/bin/bash
# Blue-Green Deployment Validation Script
# 배포 완료 후 종합적인 검증을 수행합니다

set -euo pipefail

# 색상 정의
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 로그 파일
readonly LOG_FILE="/var/log/deployment-validation-$(date +%Y%m%d_%H%M%S).log"
readonly REPORT_FILE="/tmp/deployment-validation-report-$(date +%Y%m%d_%H%M%S).txt"

# 설정 변수
readonly ALB_DNS_NAME="${ALB_DNS_NAME:-localhost}"
readonly HEALTH_ENDPOINT="http://${ALB_DNS_NAME}/health/deep"
readonly APP_ENDPOINT="http://${ALB_DNS_NAME}/"
readonly MAX_RETRIES=5
readonly RETRY_DELAY=10

# 성공/실패 카운터
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# 로깅 함수
log() {
    echo -e "$1" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
    ((PASSED_CHECKS++))
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
    ((FAILED_CHECKS++))
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
    ((WARNING_CHECKS++))
}

# 체크 결과 기록
record_check() {
    ((TOTAL_CHECKS++))
    echo "[$1] $2" >> "${REPORT_FILE}"
}

# ALB 상태 확인
check_alb_status() {
    log_info "Checking ALB status..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI to check ALB status."
        record_check "FAIL" "ALB Status Check - AWS CLI not available"
        return 1
    fi
    
    # ALB 상태 확인
    ALB_STATE=$(aws elbv2 describe-load-balancers \
        --names "bluegreen-deployment-production-alb" \
        --query 'LoadBalancers[0].State.Code' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$ALB_STATE" == "active" ]]; then
        log_success "ALB is active and running"
        record_check "PASS" "ALB Status Check - Active"
    else
        log_error "ALB is not active. Current state: $ALB_STATE"
        record_check "FAIL" "ALB Status Check - State: $ALB_STATE"
        return 1
    fi
}

# Target Group Health 확인
check_target_group_health() {
    log_info "Checking Target Group health..."
    
    local target_groups=("bluegreen-deployment-production-blue-tg" "bluegreen-deployment-production-green-tg")
    
    for tg in "${target_groups[@]}"; do
        log_info "Checking Target Group: $tg"
        
        # Target Group ARN 조회
        TG_ARN=$(aws elbv2 describe-target-groups \
            --names "$tg" \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$TG_ARN" == "NOT_FOUND" ]]; then
            log_warning "Target Group $tg not found"
            record_check "WARNING" "Target Group $tg - Not Found"
            continue
        fi
        
        # 건강한 타겟 수 확인
        HEALTHY_COUNT=$(aws elbv2 describe-target-health \
            --target-group-arn "$TG_ARN" \
            --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
            --output text 2>/dev/null || echo "0")
        
        TOTAL_COUNT=$(aws elbv2 describe-target-health \
            --target-group-arn "$TG_ARN" \
            --query 'length(TargetHealthDescriptions)' \
            --output text 2>/dev/null || echo "0")
        
        if [[ "$HEALTHY_COUNT" -gt 0 ]]; then
            log_success "Target Group $tg: $HEALTHY_COUNT/$TOTAL_COUNT targets healthy"
            record_check "PASS" "Target Group $tg - $HEALTHY_COUNT/$TOTAL_COUNT healthy"
        else
            log_error "Target Group $tg: No healthy targets ($HEALTHY_COUNT/$TOTAL_COUNT)"
            record_check "FAIL" "Target Group $tg - No healthy targets"
        fi
    done
}

# Health Endpoint 확인
check_health_endpoints() {
    log_info "Checking health endpoints..."
    
    for i in $(seq 1 $MAX_RETRIES); do
        log_info "Health check attempt $i/$MAX_RETRIES"
        
        # Basic health check
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 5 --max-time 10 \
            "http://${ALB_DNS_NAME}/health" || echo "000")
        
        if [[ "$HTTP_CODE" == "200" ]]; then
            log_success "Basic health endpoint responding (HTTP $HTTP_CODE)"
            record_check "PASS" "Basic Health Endpoint - HTTP $HTTP_CODE"
            break
        else
            log_warning "Basic health check failed: HTTP $HTTP_CODE (attempt $i/$MAX_RETRIES)"
            if [[ "$i" -eq "$MAX_RETRIES" ]]; then
                log_error "Basic health endpoint failed after $MAX_RETRIES attempts"
                record_check "FAIL" "Basic Health Endpoint - Failed after $MAX_RETRIES attempts"
            else
                sleep $RETRY_DELAY
            fi
        fi
    done
    
    # Deep health check
    for i in $(seq 1 $MAX_RETRIES); do
        log_info "Deep health check attempt $i/$MAX_RETRIES"
        
        DEEP_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 5 --max-time 15 \
            "$HEALTH_ENDPOINT" || echo "000")
        
        if [[ "$DEEP_HTTP_CODE" == "200" ]]; then
            log_success "Deep health endpoint responding (HTTP $DEEP_HTTP_CODE)"
            record_check "PASS" "Deep Health Endpoint - HTTP $DEEP_HTTP_CODE"
            break
        else
            log_warning "Deep health check failed: HTTP $DEEP_HTTP_CODE (attempt $i/$MAX_RETRIES)"
            if [[ "$i" -eq "$MAX_RETRIES" ]]; then
                log_error "Deep health endpoint failed after $MAX_RETRIES attempts"
                record_check "FAIL" "Deep Health Endpoint - Failed after $MAX_RETRIES attempts"
            else
                sleep $RETRY_DELAY
            fi
        fi
    done
}

# 응용프로그램 기능 확인
check_application_functionality() {
    log_info "Checking application functionality..."
    
    # 메인 페이지 응답 확인
    APP_RESPONSE=$(curl -s --connect-timeout 10 --max-time 20 "$APP_ENDPOINT" || echo "ERROR")
    
    if [[ "$APP_RESPONSE" == "ERROR" ]]; then
        log_error "Failed to get response from application"
        record_check "FAIL" "Application Response - No response"
        return 1
    fi
    
    # 응답 내용 확인
    if echo "$APP_RESPONSE" | grep -q "Blue-Green\|bluegreen"; then
        log_success "Application is serving expected content"
        record_check "PASS" "Application Content - Valid content detected"
    else
        log_warning "Application content may not be as expected"
        record_check "WARNING" "Application Content - Unexpected content"
    fi
    
    # 응답 시간 측정
    RESPONSE_TIME=$(curl -s -w "%{time_total}" -o /dev/null \
        --connect-timeout 5 --max-time 30 \
        "$APP_ENDPOINT" || echo "0")
    
    if (( $(echo "$RESPONSE_TIME < 1.0" | bc -l) )); then
        log_success "Application response time: ${RESPONSE_TIME}s (< 1s)"
        record_check "PASS" "Response Time - ${RESPONSE_TIME}s"
    else
        log_warning "Application response time: ${RESPONSE_TIME}s (> 1s)"
        record_check "WARNING" "Response Time - ${RESPONSE_TIME}s (slow)"
    fi
}

# PM2 프로세스 상태 확인
check_pm2_processes() {
    log_info "Checking PM2 processes..."
    
    if ! command -v pm2 &> /dev/null; then
        log_warning "PM2 not found on this system. Skipping PM2 checks."
        record_check "WARNING" "PM2 Status - PM2 not found"
        return 0
    fi
    
    # PM2 프로세스 목록 조회
    PM2_STATUS=$(pm2 jlist 2>/dev/null || echo "[]")
    
    if [[ "$PM2_STATUS" == "[]" ]]; then
        log_warning "No PM2 processes found"
        record_check "WARNING" "PM2 Processes - None found"
        return 0
    fi
    
    # 온라인 프로세스 수 확인
    ONLINE_COUNT=$(echo "$PM2_STATUS" | jq -r '[.[] | select(.pm2_env.status == "online")] | length' 2>/dev/null || echo "0")
    TOTAL_COUNT=$(echo "$PM2_STATUS" | jq -r 'length' 2>/dev/null || echo "0")
    
    if [[ "$ONLINE_COUNT" -ge 4 ]]; then
        log_success "PM2 processes: $ONLINE_COUNT/$TOTAL_COUNT online (>= 4 required)"
        record_check "PASS" "PM2 Processes - $ONLINE_COUNT/$TOTAL_COUNT online"
    else
        log_error "PM2 processes: $ONLINE_COUNT/$TOTAL_COUNT online (< 4 required)"
        record_check "FAIL" "PM2 Processes - Only $ONLINE_COUNT/$TOTAL_COUNT online"
    fi
}

# NGINX 상태 확인
check_nginx_status() {
    log_info "Checking NGINX status..."
    
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log_success "NGINX service is active"
        record_check "PASS" "NGINX Service - Active"
    else
        log_error "NGINX service is not active"
        record_check "FAIL" "NGINX Service - Inactive"
        return 1
    fi
    
    # NGINX 설정 테스트
    NGINX_TEST=$(nginx -t 2>&1 || echo "failed")
    if echo "$NGINX_TEST" | grep -q "successful"; then
        log_success "NGINX configuration is valid"
        record_check "PASS" "NGINX Configuration - Valid"
    else
        log_error "NGINX configuration test failed: $NGINX_TEST"
        record_check "FAIL" "NGINX Configuration - Invalid"
    fi
}

# 종합 보고서 생성
generate_report() {
    log_info "Generating validation report..."
    
    cat << EOF > "${REPORT_FILE}.summary"
==============================================
Blue-Green Deployment Validation Report
==============================================
Date: $(date)
Validation Duration: $SECONDS seconds

SUMMARY:
--------
Total Checks: $TOTAL_CHECKS
✅ Passed: $PASSED_CHECKS
❌ Failed: $FAILED_CHECKS  
⚠️  Warnings: $WARNING_CHECKS

OVERALL STATUS: $(if [[ $FAILED_CHECKS -eq 0 ]]; then echo "✅ PASSED"; else echo "❌ FAILED"; fi)

DETAILED RESULTS:
-----------------
EOF
    
    cat "${REPORT_FILE}" >> "${REPORT_FILE}.summary"
    
    echo ""
    log_info "Validation complete. Report saved to: ${REPORT_FILE}.summary"
    log_info "Detailed log saved to: ${LOG_FILE}"
    
    # 요약 표시
    echo ""
    echo "========================================"
    echo "           VALIDATION SUMMARY"
    echo "========================================"
    echo "Total Checks: $TOTAL_CHECKS"
    echo "✅ Passed: $PASSED_CHECKS"
    echo "❌ Failed: $FAILED_CHECKS"
    echo "⚠️  Warnings: $WARNING_CHECKS"
    echo ""
    
    if [[ $FAILED_CHECKS -eq 0 ]]; then
        echo -e "${GREEN}🎉 DEPLOYMENT VALIDATION PASSED!${NC}"
        echo "The deployment appears to be successful and ready for production traffic."
        exit 0
    else
        echo -e "${RED}💥 DEPLOYMENT VALIDATION FAILED!${NC}"
        echo "Please review the issues and fix them before proceeding."
        exit 1
    fi
}

# 도움말 표시
show_help() {
    cat << EOF
Blue-Green Deployment Validation Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --alb-dns-name NAME    ALB DNS name to test (default: localhost)
    --max-retries NUM      Maximum retry attempts (default: 5)
    --retry-delay SECS     Delay between retries (default: 10)
    --help                 Show this help message

EXAMPLES:
    $0
    $0 --alb-dns-name my-alb-123456789.us-east-1.elb.amazonaws.com
    $0 --max-retries 3 --retry-delay 5

DESCRIPTION:
    This script performs comprehensive validation of a Blue-Green deployment:
    - ALB status and configuration
    - Target Group health
    - Health endpoints (/health and /health/deep)
    - Application functionality
    - PM2 process status
    - NGINX service status

EXIT CODES:
    0 - All validations passed
    1 - One or more validations failed
EOF
}

# 메인 실행 함수
main() {
    # 파라미터 파싱
    while [[ $# -gt 0 ]]; do
        case $1 in
            --alb-dns-name)
                ALB_DNS_NAME="$2"
                shift 2
                ;;
            --max-retries)
                MAX_RETRIES="$2"
                shift 2
                ;;
            --retry-delay)
                RETRY_DELAY="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 시작 메시지
    log_info "Starting Blue-Green Deployment Validation..."
    log_info "ALB DNS Name: $ALB_DNS_NAME"
    log_info "Max Retries: $MAX_RETRIES"
    log_info "Retry Delay: ${RETRY_DELAY}s"
    echo ""
    
    # 검증 실행
    check_alb_status
    check_target_group_health
    check_health_endpoints
    check_application_functionality
    check_pm2_processes
    check_nginx_status
    
    # 보고서 생성
    generate_report
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi