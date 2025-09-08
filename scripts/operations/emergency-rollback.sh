#!/bin/bash
# Blue-Green Deployment Emergency Rollback Script
# 장애 상황 시 즉시 롤백을 수행하는 응급 스크립트

set -euo pipefail

# 색상 정의
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# 기본 설정
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="/var/log/emergency-rollback-$(date +%Y%m%d_%H%M%S).log"
readonly STATE_FILE="/tmp/rollback-state.json"
readonly BACKUP_DIR="/opt/backups/bluegreen"

# AWS 설정
ALB_DNS_NAME="${ALB_DNS_NAME:-}"
ALB_LISTENER_ARN="${ALB_LISTENER_ARN:-}"
BLUE_TARGET_GROUP_NAME="${BLUE_TARGET_GROUP_NAME:-bluegreen-deployment-production-blue-tg}"
GREEN_TARGET_GROUP_NAME="${GREEN_TARGET_GROUP_NAME:-bluegreen-deployment-production-green-tg}"
CODEDEPLOY_APPLICATION_NAME="${CODEDEPLOY_APPLICATION_NAME:-bluegreen-deployment-production-app}"

# 롤백 설정
ROLLBACK_TIMEOUT=${ROLLBACK_TIMEOUT:-300}    # 5분
HEALTH_CHECK_RETRIES=${HEALTH_CHECK_RETRIES:-10}
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-30}
AUTO_CONFIRM=${AUTO_CONFIRM:-false}
DRY_RUN=${DRY_RUN:-false}

# 상태 변수
declare -A ROLLBACK_STATE
ROLLBACK_SUCCESS=true

# 로깅 함수
log() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') $1"
    echo -e "$message" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_critical() {
    log "${RED}${BOLD}[CRITICAL]${NC} $1"
}

# 상태 저장
save_state() {
    local key="$1"
    local value="$2"
    ROLLBACK_STATE["$key"]="$value"
    
    # JSON 형태로 상태 파일에 저장
    local json_state="{"
    for k in "${!ROLLBACK_STATE[@]}"; do
        json_state+="\\"$k\\": \\"${ROLLBACK_STATE[$k]}\\", "
    done
    json_state="${json_state%, }}"
    json_state+="}"
    
    echo "$json_state" > "$STATE_FILE"
}

# 상태 로드
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        while IFS='=' read -r key value; do
            ROLLBACK_STATE["$key"]="$value"
        done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$STATE_FILE" 2>/dev/null || true)
    fi
}

# 사전 요구사항 확인
check_prerequisites() {
    log_info "Checking prerequisites for emergency rollback..."
    
    local missing_tools=()
    
    # 필수 도구 확인
    for tool in aws curl jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # AWS 자격 증명 확인
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured or expired"
        exit 1
    fi
    
    # 환경 변수 확인
    if [[ -z "$ALB_LISTENER_ARN" ]]; then
        log_error "ALB_LISTENER_ARN environment variable not set"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# 현재 상태 분석
analyze_current_state() {
    log_info "Analyzing current deployment state..."
    
    # 현재 활성 타겟 그룹 확인
    local current_tg_arn
    current_tg_arn=$(aws elbv2 describe-listeners \
        --listener-arns "$ALB_LISTENER_ARN" \
        --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    if [[ "$current_tg_arn" == "UNKNOWN" ]]; then
        log_error "Failed to determine current target group"
        return 1
    fi
    
    save_state "current_target_group_arn" "$current_tg_arn"
    
    # 타겟 그룹 이름으로 환경 식별
    local blue_tg_arn green_tg_arn
    blue_tg_arn=$(aws elbv2 describe-target-groups \
        --names "$BLUE_TARGET_GROUP_NAME" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    green_tg_arn=$(aws elbv2 describe-target-groups \
        --names "$GREEN_TARGET_GROUP_NAME" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    save_state "blue_target_group_arn" "$blue_tg_arn"
    save_state "green_target_group_arn" "$green_tg_arn"
    
    # 현재 환경 식별
    local current_environment
    if [[ "$current_tg_arn" == "$blue_tg_arn" ]]; then
        current_environment="blue"
        save_state "rollback_target_group_arn" "$green_tg_arn"
        save_state "rollback_environment" "green"
    elif [[ "$current_tg_arn" == "$green_tg_arn" ]]; then
        current_environment="green"
        save_state "rollback_target_group_arn" "$blue_tg_arn"
        save_state "rollback_environment" "blue"
    else
        log_error "Unable to identify current environment"
        return 1
    fi
    
    save_state "current_environment" "$current_environment"
    
    log_info "Current active environment: $current_environment"
    log_info "Rollback target environment: ${ROLLBACK_STATE[rollback_environment]}"
    
    # 타겟 그룹 health 확인
    check_target_group_health "$blue_tg_arn" "Blue"
    check_target_group_health "$green_tg_arn" "Green"
}

# 타겟 그룹 Health 확인
check_target_group_health() {
    local tg_arn="$1"
    local tg_name="$2"
    
    if [[ "$tg_arn" == "UNKNOWN" ]]; then
        log_warning "$tg_name target group not found"
        return 1
    fi
    
    local healthy_count unhealthy_count total_count
    healthy_count=$(aws elbv2 describe-target-health \
        --target-group-arn "$tg_arn" \
        --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
        --output text 2>/dev/null || echo "0")
    
    unhealthy_count=$(aws elbv2 describe-target-health \
        --target-group-arn "$tg_arn" \
        --query 'length(TargetHealthDescriptions[?TargetHealth.State==`unhealthy`])' \
        --output text 2>/dev/null || echo "0")
    
    total_count=$((healthy_count + unhealthy_count))
    
    save_state "${tg_name,,}_healthy_targets" "$healthy_count"
    save_state "${tg_name,,}_total_targets" "$total_count"
    
    log_info "$tg_name Target Group: $healthy_count/$total_count healthy targets"
    
    if [[ "$healthy_count" -eq 0 && "$total_count" -gt 0 ]]; then
        log_warning "$tg_name target group has no healthy targets"
        return 1
    fi
    
    return 0
}

# 진행 중인 CodeDeploy 배포 확인
check_ongoing_deployments() {
    log_info "Checking for ongoing CodeDeploy deployments..."
    
    local active_deployments
    active_deployments=$(aws deploy list-deployments \
        --application-name "$CODEDEPLOY_APPLICATION_NAME" \
        --deployment-status-filter "InProgress,Queued,Ready" \
        --query 'deployments' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$active_deployments" && "$active_deployments" != "None" ]]; then
        log_warning "Found active CodeDeploy deployments:"
        for deployment_id in $active_deployments; do
            local deployment_info
            deployment_info=$(aws deploy get-deployment \
                --deployment-id "$deployment_id" \
                --query 'deploymentInfo.{Status:status,Group:deploymentGroupName,Created:createTime}' \
                --output table 2>/dev/null || echo "Error getting deployment info")
            
            log_info "Deployment ID: $deployment_id"
            echo "$deployment_info"
            save_state "active_deployment_$deployment_id" "true"
        done
        
        save_state "has_active_deployments" "true"
        return 1
    else
        save_state "has_active_deployments" "false"
        log_info "No active CodeDeploy deployments found"
        return 0
    fi
}

# 현재 서비스 Health 확인
check_current_service_health() {
    log_info "Checking current service health..."
    
    if [[ -z "$ALB_DNS_NAME" ]]; then
        log_warning "ALB_DNS_NAME not set, skipping health check"
        return 0
    fi
    
    local health_url="http://${ALB_DNS_NAME}/health/deep"
    local http_code response_time
    
    # 5번 재시도
    for i in {1..5}; do
        log_info "Health check attempt $i/5..."
        
        local curl_output
        curl_output=$(curl -s -w "%{http_code} %{time_total}" -o /dev/null \
            --connect-timeout 5 --max-time 15 \
            "$health_url" 2>/dev/null || echo "000 0")
        
        http_code=$(echo "$curl_output" | awk '{print $1}')
        response_time=$(echo "$curl_output" | awk '{print $2}')
        
        if [[ "$http_code" == "200" ]]; then
            log_info "Service health check passed (HTTP $http_code, ${response_time}s)"
            save_state "service_health_status" "healthy"
            save_state "service_response_time" "$response_time"
            return 0
        else
            log_warning "Service health check failed: HTTP $http_code (attempt $i/5)"
            if [[ "$i" -lt 5 ]]; then
                sleep 10
            fi
        fi
    done
    
    save_state "service_health_status" "unhealthy"
    log_error "Service health check failed after 5 attempts"
    return 1
}

# 롤백 대상 환경 검증
validate_rollback_target() {
    log_info "Validating rollback target environment..."
    
    local target_tg_arn="${ROLLBACK_STATE[rollback_target_group_arn]}"
    local target_environment="${ROLLBACK_STATE[rollback_environment]}"
    
    if [[ "$target_tg_arn" == "UNKNOWN" ]]; then
        log_error "Rollback target target group not found"
        return 1
    fi
    
    # 타겟 그룹 health 재확인
    local healthy_targets="${ROLLBACK_STATE[${target_environment}_healthy_targets]}"
    
    if [[ "$healthy_targets" == "0" ]]; then
        log_error "Rollback target ($target_environment) has no healthy targets"
        log_error "Rollback is not possible - would result in service outage"
        return 1
    fi
    
    log_success "Rollback target validation passed"
    log_info "Rolling back to: $target_environment ($healthy_targets healthy targets)"
    
    return 0
}

# 사용자 확인
confirm_rollback() {
    if [[ "$AUTO_CONFIRM" == "true" ]]; then
        log_info "Auto-confirm enabled, proceeding with rollback"
        return 0
    fi
    
    echo ""
    echo -e "${RED}${BOLD}=== EMERGENCY ROLLBACK CONFIRMATION ===${NC}"
    echo ""
    echo -e "Current Environment: ${BOLD}${ROLLBACK_STATE[current_environment]}${NC}"
    echo -e "Rollback Target: ${BOLD}${ROLLBACK_STATE[rollback_environment]}${NC}"
    echo -e "Healthy Targets: ${BOLD}${ROLLBACK_STATE[${ROLLBACK_STATE[rollback_environment]}_healthy_targets]}${NC}"
    echo ""
    echo -e "${YELLOW}This action will immediately switch ALB traffic!${NC}"
    echo -e "${YELLOW}Current users may experience brief interruption.${NC}"
    echo ""
    
    while true; do
        read -p "Are you sure you want to proceed with emergency rollback? (yes/no): " -r response
        case "$response" in
            yes|YES|y|Y)
                log_info "User confirmed rollback"
                return 0
                ;;
            no|NO|n|N)
                log_info "User cancelled rollback"
                echo "Rollback cancelled by user"
                exit 0
                ;;
            *)
                echo "Please enter 'yes' or 'no'"
                ;;
        esac
    done
}

# ALB 트래픽 전환 실행
execute_traffic_switch() {
    log_info "Executing ALB traffic switch..."
    
    local target_tg_arn="${ROLLBACK_STATE[rollback_target_group_arn]}"
    local target_environment="${ROLLBACK_STATE[rollback_environment]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would switch ALB traffic to $target_environment"
        log_info "[DRY RUN] Target Group ARN: $target_tg_arn"
        return 0
    fi
    
    save_state "rollback_start_time" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    # ALB 리스너 규칙 변경
    log_info "Switching ALB listener to $target_environment target group..."
    
    local switch_result
    switch_result=$(aws elbv2 modify-listener \
        --listener-arn "$ALB_LISTENER_ARN" \
        --default-actions Type=forward,TargetGroupArn="$target_tg_arn" \
        2>&1 || echo "ERROR")
    
    if [[ "$switch_result" == "ERROR" ]]; then
        log_error "Failed to switch ALB traffic"
        ROLLBACK_SUCCESS=false
        return 1
    fi
    
    save_state "traffic_switch_time" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log_success "ALB traffic switched to $target_environment environment"
    
    # 전환 확인
    sleep 5
    local current_tg
    current_tg=$(aws elbv2 describe-listeners \
        --listener-arns "$ALB_LISTENER_ARN" \
        --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    if [[ "$current_tg" == "$target_tg_arn" ]]; then
        log_success "Traffic switch verified successfully"
        save_state "traffic_switch_verified" "true"
        return 0
    else
        log_error "Traffic switch verification failed"
        ROLLBACK_SUCCESS=false
        return 1
    fi
}

# 진행 중인 배포 중단
stop_active_deployments() {
    local has_active="${ROLLBACK_STATE[has_active_deployments]:-false}"
    
    if [[ "$has_active" == "false" ]]; then
        log_info "No active deployments to stop"
        return 0
    fi
    
    log_info "Stopping active CodeDeploy deployments..."
    
    for key in "${!ROLLBACK_STATE[@]}"; do
        if [[ "$key" =~ ^active_deployment_ ]]; then
            local deployment_id="${key#active_deployment_}"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would stop deployment: $deployment_id"
                continue
            fi
            
            log_info "Stopping deployment: $deployment_id"
            
            local stop_result
            stop_result=$(aws deploy stop-deployment \
                --deployment-id "$deployment_id" \
                --auto-rollback-enabled \
                2>&1 || echo "ERROR")
            
            if [[ "$stop_result" == "ERROR" ]]; then
                log_warning "Failed to stop deployment: $deployment_id"
            else
                log_success "Deployment stopped: $deployment_id"
            fi
        fi
    done
}

# 롤백 후 Health 검증
verify_rollback_health() {
    log_info "Verifying service health after rollback..."
    
    if [[ -z "$ALB_DNS_NAME" ]]; then
        log_warning "ALB_DNS_NAME not set, skipping post-rollback health check"
        return 0
    fi
    
    local health_url="http://${ALB_DNS_NAME}/health/deep"
    local success_count=0
    
    # 지정된 횟수만큼 health check 재시도
    for i in $(seq 1 $HEALTH_CHECK_RETRIES); do
        log_info "Post-rollback health check $i/$HEALTH_CHECK_RETRIES..."
        
        local http_code response_time
        local curl_output
        curl_output=$(curl -s -w "%{http_code} %{time_total}" -o /dev/null \
            --connect-timeout 5 --max-time 15 \
            "$health_url" 2>/dev/null || echo "000 0")
        
        http_code=$(echo "$curl_output" | awk '{print $1}')
        response_time=$(echo "$curl_output" | awk '{print $2}')
        
        if [[ "$http_code" == "200" ]]; then
            ((success_count++))
            log_success "Health check $i passed (HTTP $http_code, ${response_time}s)"
            
            # 연속 3회 성공 시 완료
            if [[ "$success_count" -ge 3 ]]; then
                save_state "post_rollback_health" "healthy"
                log_success "Post-rollback health verification completed"
                return 0
            fi
        else
            success_count=0
            log_warning "Health check $i failed (HTTP $http_code)"
        fi
        
        if [[ "$i" -lt "$HEALTH_CHECK_RETRIES" ]]; then
            sleep $HEALTH_CHECK_INTERVAL
        fi
    done
    
    save_state "post_rollback_health" "unhealthy"
    log_error "Post-rollback health verification failed"
    ROLLBACK_SUCCESS=false
    return 1
}

# 알림 전송 (Slack, Email 등)
send_rollback_notification() {
    local status="$1"
    local webhook_url="${SLACK_WEBHOOK_URL:-}"
    
    if [[ -z "$webhook_url" ]]; then
        log_info "No notification webhook configured"
        return 0
    fi
    
    local emoji color title
    if [[ "$status" == "SUCCESS" ]]; then
        emoji="✅"
        color="good"
        title="Emergency Rollback Completed Successfully"
    else
        emoji="🚨"
        color="danger"
        title="Emergency Rollback Failed"
    fi
    
    local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "$emoji $title",
            "fields": [
                {
                    "title": "Environment Switched",
                    "value": "${ROLLBACK_STATE[current_environment]} → ${ROLLBACK_STATE[rollback_environment]}",
                    "short": true
                },
                {
                    "title": "Timestamp",
                    "value": "$(date)",
                    "short": true
                },
                {
                    "title": "Host",
                    "value": "$(hostname)",
                    "short": true
                },
                {
                    "title": "ALB DNS",
                    "value": "${ALB_DNS_NAME:-N/A}",
                    "short": true
                }
            ],
            "footer": "Blue-Green Emergency Rollback System"
        }
    ]
}
EOF
    )
    
    curl -s -X POST -H 'Content-type: application/json' \
        --data "$payload" "$webhook_url" > /dev/null || true
    
    log_info "Rollback notification sent"
}

# 완료 보고서 생성
generate_rollback_report() {
    local report_file="/tmp/emergency-rollback-report-$(date +%Y%m%d_%H%M%S).json"
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    cat > "$report_file" << EOF
{
    "rollback_metadata": {
        "execution_time": "$end_time",
        "hostname": "$(hostname)",
        "script_version": "$SCRIPT_NAME",
        "rollback_success": $ROLLBACK_SUCCESS,
        "dry_run": $DRY_RUN
    },
    "environment_switch": {
        "from": "${ROLLBACK_STATE[current_environment]:-unknown}",
        "to": "${ROLLBACK_STATE[rollback_environment]:-unknown}",
        "switch_time": "${ROLLBACK_STATE[traffic_switch_time]:-unknown}",
        "verified": "${ROLLBACK_STATE[traffic_switch_verified]:-false}"
    },
    "health_status": {
        "pre_rollback": "${ROLLBACK_STATE[service_health_status]:-unknown}",
        "post_rollback": "${ROLLBACK_STATE[post_rollback_health]:-unknown}",
        "response_time": "${ROLLBACK_STATE[service_response_time]:-unknown}"
    },
    "target_groups": {
        "blue_healthy_targets": "${ROLLBACK_STATE[blue_healthy_targets]:-0}",
        "green_healthy_targets": "${ROLLBACK_STATE[green_healthy_targets]:-0}",
        "current_target_group": "${ROLLBACK_STATE[current_target_group_arn]:-unknown}",
        "rollback_target_group": "${ROLLBACK_STATE[rollback_target_group_arn]:-unknown}"
    },
    "deployments": {
        "had_active_deployments": "${ROLLBACK_STATE[has_active_deployments]:-false}"
    }
}
EOF
    
    log_success "Rollback report generated: $report_file"
    echo "$report_file"
}

# 최종 결과 요약
show_rollback_summary() {
    echo ""
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}           EMERGENCY ROLLBACK SUMMARY${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo ""
    
    local status_color status_text
    if [[ "$ROLLBACK_SUCCESS" == "true" ]]; then
        status_color="$GREEN"
        status_text="SUCCESS ✅"
    else
        status_color="$RED"
        status_text="FAILED ❌"
    fi
    
    echo -e "${BLUE}Rollback Status:${NC} ${status_color}$status_text${NC}"
    echo -e "${BLUE}Environment Switch:${NC} ${ROLLBACK_STATE[current_environment]:-unknown} → ${ROLLBACK_STATE[rollback_environment]:-unknown}"
    echo -e "${BLUE}Switch Time:${NC} ${ROLLBACK_STATE[traffic_switch_time]:-unknown}"
    echo -e "${BLUE}Health Status:${NC} ${ROLLBACK_STATE[post_rollback_health]:-unknown}"
    echo ""
    
    echo -e "${BLUE}Target Groups:${NC}"
    echo "├── Blue: ${ROLLBACK_STATE[blue_healthy_targets]:-0} healthy targets"
    echo "└── Green: ${ROLLBACK_STATE[green_healthy_targets]:-0} healthy targets"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}Note: This was a DRY RUN - no actual changes were made${NC}"
        echo ""
    fi
    
    echo -e "${BLUE}Log File:${NC} $LOG_FILE"
    echo -e "${BLUE}State File:${NC} $STATE_FILE"
    echo ""
    
    echo -e "${CYAN}================================================================${NC}"
}

# 도움말 표시
show_help() {
    cat << EOF
Blue-Green Deployment Emergency Rollback Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --alb-dns-name NAME           ALB DNS name for health checks
    --alb-listener-arn ARN        ALB listener ARN (required)
    --blue-target-group NAME      Blue target group name
    --green-target-group NAME     Green target group name  
    --codedeploy-app-name NAME    CodeDeploy application name
    --rollback-timeout SECONDS   Maximum rollback timeout (default: 300)
    --health-check-retries NUM    Health check retry count (default: 10)
    --health-check-interval SECS  Health check interval (default: 30)
    --auto-confirm               Skip user confirmation (dangerous!)
    --dry-run                    Show what would be done without executing
    --help                       Show this help message

ENVIRONMENT VARIABLES:
    ALB_DNS_NAME                  ALB DNS name
    ALB_LISTENER_ARN             ALB listener ARN  
    BLUE_TARGET_GROUP_NAME       Blue target group name
    GREEN_TARGET_GROUP_NAME      Green target group name
    CODEDEPLOY_APPLICATION_NAME  CodeDeploy application name
    SLACK_WEBHOOK_URL           Slack notification webhook URL
    AUTO_CONFIRM                 Skip confirmation (true/false)

EXAMPLES:
    $0                           # Interactive rollback
    $0 --dry-run                # Show what would be done
    $0 --auto-confirm           # Automatic rollback (dangerous!)

DESCRIPTION:
    Emergency rollback script for Blue-Green deployments that:
    - Analyzes current deployment state
    - Validates rollback target environment
    - Stops active CodeDeploy deployments
    - Switches ALB traffic to previous environment
    - Verifies service health after rollback
    - Sends notifications and generates reports

EXIT CODES:
    0 - Rollback completed successfully
    1 - Rollback failed or validation error
EOF
}

# 정리 함수
cleanup() {
    log_info "Cleaning up temporary files..."
    
    # 임시 파일 정리 (상태 파일은 유지)
    # rm -f /tmp/concurrent_result_* 2>/dev/null || true
    
    # 알림 전송
    local notification_status
    if [[ "$ROLLBACK_SUCCESS" == "true" ]]; then
        notification_status="SUCCESS"
    else
        notification_status="FAILED"
    fi
    
    send_rollback_notification "$notification_status"
    
    # 최종 보고서 생성
    local report_file
    report_file=$(generate_rollback_report)
    
    # 결과 요약 표시
    show_rollback_summary
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
            --alb-listener-arn)
                ALB_LISTENER_ARN="$2"
                shift 2
                ;;
            --blue-target-group)
                BLUE_TARGET_GROUP_NAME="$2"
                shift 2
                ;;
            --green-target-group)
                GREEN_TARGET_GROUP_NAME="$2"
                shift 2
                ;;
            --codedeploy-app-name)
                CODEDEPLOY_APPLICATION_NAME="$2"
                shift 2
                ;;
            --rollback-timeout)
                ROLLBACK_TIMEOUT="$2"
                shift 2
                ;;
            --health-check-retries)
                HEALTH_CHECK_RETRIES="$2"
                shift 2
                ;;
            --health-check-interval)
                HEALTH_CHECK_INTERVAL="$2"
                shift 2
                ;;
            --auto-confirm)
                AUTO_CONFIRM=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
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
    
    # 정리 함수를 종료 시 실행되도록 설정
    trap cleanup EXIT
    
    log_critical "=== EMERGENCY ROLLBACK INITIATED ==="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No actual changes will be made"
    fi
    
    # 이전 상태 로드 (있는 경우)
    load_state
    
    # 1단계: 사전 요구사항 확인
    check_prerequisites || exit 1
    
    # 2단계: 현재 상태 분석
    analyze_current_state || exit 1
    
    # 3단계: 진행 중인 배포 확인
    check_ongoing_deployments || true
    
    # 4단계: 현재 서비스 Health 확인
    check_current_service_health || true
    
    # 5단계: 롤백 대상 검증
    validate_rollback_target || exit 1
    
    # 6단계: 사용자 확인
    confirm_rollback || exit 1
    
    # 7단계: 진행 중인 배포 중단
    stop_active_deployments
    
    # 8단계: ALB 트래픽 전환
    execute_traffic_switch || exit 1
    
    # 9단계: 롤백 후 Health 검증
    verify_rollback_health || true
    
    if [[ "$ROLLBACK_SUCCESS" == "true" ]]; then
        log_success "=== EMERGENCY ROLLBACK COMPLETED SUCCESSFULLY ==="
    else
        log_error "=== EMERGENCY ROLLBACK COMPLETED WITH ISSUES ==="
        exit 1
    fi
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi