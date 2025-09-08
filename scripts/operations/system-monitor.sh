#!/bin/bash
# Blue-Green Deployment System Monitoring Script
# 실시간 시스템 상태 모니터링 및 알림

set -euo pipefail

# 색상 정의
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# 설정 변수
readonly CONFIG_FILE="${CONFIG_FILE:-/etc/bluegreen-monitor.conf}"
readonly LOG_FILE="${LOG_FILE:-/var/log/system-monitor.log}"
readonly ALERT_LOG="${ALERT_LOG:-/var/log/system-alerts.log}"
readonly PID_FILE="/var/run/system-monitor.pid"

# 기본 임계값
CPU_THRESHOLD=${CPU_THRESHOLD:-80}
MEMORY_THRESHOLD=${MEMORY_THRESHOLD:-85}
DISK_THRESHOLD=${DISK_THRESHOLD:-90}
RESPONSE_TIME_THRESHOLD=${RESPONSE_TIME_THRESHOLD:-2}
ERROR_RATE_THRESHOLD=${ERROR_RATE_THRESHOLD:-5}

# ALB 설정
ALB_DNS_NAME="${ALB_DNS_NAME:-localhost}"
HEALTH_ENDPOINT="http://${ALB_DNS_NAME}/health/deep"

# 모니터링 주기 (초)
MONITOR_INTERVAL=${MONITOR_INTERVAL:-30}
ALERT_COOLDOWN=${ALERT_COOLDOWN:-300}

# 알림 설정
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
EMAIL_RECIPIENTS="${EMAIL_RECIPIENTS:-}"
ALERT_ENABLED=${ALERT_ENABLED:-true}

# 상태 변수
declare -A LAST_ALERT_TIME
declare -A CURRENT_STATUS

# 로깅 함수
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "${LOG_FILE}"
}

log_alert() {
    local message="$1"
    log "${RED}[ALERT]${NC} $message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ALERT] $message" >> "${ALERT_LOG}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[OK]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

# 설정 파일 로드
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log_info "Configuration loaded from $CONFIG_FILE"
    else
        log_warning "Configuration file not found: $CONFIG_FILE. Using defaults."
    fi
}

# 알림 전송
send_alert() {
    local title="$1"
    local message="$2"
    local severity="${3:-WARNING}"
    local current_time=$(date +%s)
    
    # 쿨다운 체크
    local last_alert="${LAST_ALERT_TIME[$title]:-0}"
    if (( current_time - last_alert < ALERT_COOLDOWN )); then
        return 0
    fi
    
    LAST_ALERT_TIME[$title]=$current_time
    log_alert "$title: $message"
    
    if [[ "$ALERT_ENABLED" == "true" ]]; then
        # Slack 알림
        if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
            send_slack_alert "$title" "$message" "$severity"
        fi
        
        # 이메일 알림
        if [[ -n "$EMAIL_RECIPIENTS" ]]; then
            send_email_alert "$title" "$message" "$severity"
        fi
    fi
}

# Slack 알림 전송
send_slack_alert() {
    local title="$1"
    local message="$2"
    local severity="$3"
    
    local color="warning"
    local emoji="⚠️"
    
    case "$severity" in
        "CRITICAL") color="danger"; emoji="🚨" ;;
        "WARNING") color="warning"; emoji="⚠️" ;;
        "INFO") color="good"; emoji="ℹ️" ;;
    esac
    
    local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "$emoji Blue-Green System Alert",
            "fields": [
                {
                    "title": "$title",
                    "value": "$message",
                    "short": false
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
                }
            ]
        }
    ]
}
EOF
    )
    
    curl -s -X POST -H 'Content-type: application/json' \
        --data "$payload" "$SLACK_WEBHOOK_URL" > /dev/null || true
}

# 이메일 알림 전송
send_email_alert() {
    local title="$1"
    local message="$2"
    local severity="$3"
    
    local subject="[$severity] Blue-Green System Alert: $title"
    local body="$(cat <<EOF
Blue-Green Deployment System Alert

Title: $title
Severity: $severity
Message: $message

Timestamp: $(date)
Host: $(hostname)
ALB DNS: $ALB_DNS_NAME

--
Automated monitoring system
EOF
    )"
    
    echo "$body" | mail -s "$subject" "$EMAIL_RECIPIENTS" 2>/dev/null || true
}

# CPU 사용률 확인
check_cpu_usage() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\\([0-9.]*\\)%* id.*/\\1/" | awk '{print 100 - $1}')
    cpu_usage=${cpu_usage%.*}  # 소수점 제거
    
    CURRENT_STATUS["cpu"]=$cpu_usage
    
    if (( cpu_usage > CPU_THRESHOLD )); then
        send_alert "High CPU Usage" "CPU usage is ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)" "WARNING"
        return 1
    else
        log_info "CPU usage: ${cpu_usage}% (OK)"
        return 0
    fi
}

# 메모리 사용률 확인
check_memory_usage() {
    local memory_info=$(free | grep Mem)
    local total=$(echo $memory_info | awk '{print $2}')
    local used=$(echo $memory_info | awk '{print $3}')
    local memory_usage=$(( used * 100 / total ))
    
    CURRENT_STATUS["memory"]=$memory_usage
    
    if (( memory_usage > MEMORY_THRESHOLD )); then
        send_alert "High Memory Usage" "Memory usage is ${memory_usage}% (threshold: ${MEMORY_THRESHOLD}%)" "WARNING"
        return 1
    else
        log_info "Memory usage: ${memory_usage}% (OK)"
        return 0
    fi
}

# 디스크 사용률 확인
check_disk_usage() {
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    CURRENT_STATUS["disk"]=$disk_usage
    
    if (( disk_usage > DISK_THRESHOLD )); then
        send_alert "High Disk Usage" "Disk usage is ${disk_usage}% (threshold: ${DISK_THRESHOLD}%)" "CRITICAL"
        return 1
    else
        log_info "Disk usage: ${disk_usage}% (OK)"
        return 0
    fi
}

# PM2 프로세스 상태 확인
check_pm2_status() {
    if ! command -v pm2 &> /dev/null; then
        log_warning "PM2 not found. Skipping PM2 checks."
        return 0
    fi
    
    local pm2_status=$(pm2 jlist 2>/dev/null || echo "[]")
    local online_count=$(echo "$pm2_status" | jq -r '[.[] | select(.pm2_env.status == "online")] | length' 2>/dev/null || echo "0")
    local total_count=$(echo "$pm2_status" | jq -r 'length' 2>/dev/null || echo "0")
    
    CURRENT_STATUS["pm2_online"]=$online_count
    CURRENT_STATUS["pm2_total"]=$total_count
    
    if [[ "$online_count" -lt 4 ]]; then
        send_alert "PM2 Process Down" "Only $online_count/$total_count PM2 processes are online (minimum: 4)" "CRITICAL"
        return 1
    else
        log_info "PM2 processes: $online_count/$total_count online (OK)"
        return 0
    fi
}

# NGINX 상태 확인
check_nginx_status() {
    if systemctl is-active --quiet nginx 2>/dev/null; then
        CURRENT_STATUS["nginx"]="active"
        log_info "NGINX service: Active (OK)"
        return 0
    else
        CURRENT_STATUS["nginx"]="inactive"
        send_alert "NGINX Service Down" "NGINX service is not active" "CRITICAL"
        return 1
    fi
}

# ALB Health Check 확인
check_alb_health() {
    local response_time
    local http_code
    
    # 응답 시간과 HTTP 코드 동시 측정
    local curl_output=$(curl -s -w "%{time_total} %{http_code}" -o /dev/null \
        --connect-timeout 5 --max-time 10 "$HEALTH_ENDPOINT" 2>/dev/null || echo "0 000")
    
    response_time=$(echo "$curl_output" | awk '{print $1}')
    http_code=$(echo "$curl_output" | awk '{print $2}')
    
    CURRENT_STATUS["response_time"]=$response_time
    CURRENT_STATUS["http_code"]=$http_code
    
    # HTTP 코드 확인
    if [[ "$http_code" != "200" ]]; then
        send_alert "Health Check Failed" "Health endpoint returned HTTP $http_code" "CRITICAL"
        return 1
    fi
    
    # 응답 시간 확인
    if (( $(echo "$response_time > $RESPONSE_TIME_THRESHOLD" | bc -l) )); then
        send_alert "Slow Response Time" "Response time is ${response_time}s (threshold: ${RESPONSE_TIME_THRESHOLD}s)" "WARNING"
        return 1
    fi
    
    log_info "Health check: HTTP $http_code, ${response_time}s (OK)"
    return 0
}

# AWS 서비스 상태 확인
check_aws_services() {
    if ! command -v aws &> /dev/null; then
        log_warning "AWS CLI not found. Skipping AWS service checks."
        return 0
    fi
    
    # ALB 상태 확인
    local alb_state=$(aws elbv2 describe-load-balancers \
        --names "bluegreen-deployment-production-alb" \
        --query 'LoadBalancers[0].State.Code' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    CURRENT_STATUS["alb_state"]=$alb_state
    
    if [[ "$alb_state" != "active" ]]; then
        send_alert "ALB Not Active" "ALB state is $alb_state (expected: active)" "CRITICAL"
        return 1
    fi
    
    # Target Group Health 확인
    local tg_arns=(
        $(aws elbv2 describe-target-groups --names "bluegreen-deployment-production-blue-tg" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
        $(aws elbv2 describe-target-groups --names "bluegreen-deployment-production-green-tg" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
    )
    
    local healthy_targets=0
    for arn in "${tg_arns[@]}"; do
        if [[ -n "$arn" && "$arn" != "None" ]]; then
            local count=$(aws elbv2 describe-target-health --target-group-arn "$arn" \
                --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
                --output text 2>/dev/null || echo "0")
            healthy_targets=$((healthy_targets + count))
        fi
    done
    
    CURRENT_STATUS["healthy_targets"]=$healthy_targets
    
    if [[ "$healthy_targets" -eq 0 ]]; then
        send_alert "No Healthy Targets" "No healthy targets found in any target group" "CRITICAL"
        return 1
    fi
    
    log_info "AWS services: ALB $alb_state, $healthy_targets healthy targets (OK)"
    return 0
}

# 상태 대시보드 출력
show_dashboard() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}           Blue-Green Deployment System Monitor${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo ""
    echo -e "${BLUE}Last Update:${NC} $(date)"
    echo -e "${BLUE}Monitor Interval:${NC} ${MONITOR_INTERVAL}s"
    echo -e "${BLUE}ALB DNS:${NC} $ALB_DNS_NAME"
    echo ""
    
    # 시스템 리소스
    echo -e "${YELLOW}System Resources:${NC}"
    echo "├── CPU Usage: ${CURRENT_STATUS[cpu]:-N/A}% (threshold: ${CPU_THRESHOLD}%)"
    echo "├── Memory Usage: ${CURRENT_STATUS[memory]:-N/A}% (threshold: ${MEMORY_THRESHOLD}%)"
    echo "└── Disk Usage: ${CURRENT_STATUS[disk]:-N/A}% (threshold: ${DISK_THRESHOLD}%)"
    echo ""
    
    # 애플리케이션 서비스
    echo -e "${YELLOW}Application Services:${NC}"
    echo "├── PM2 Processes: ${CURRENT_STATUS[pm2_online]:-N/A}/${CURRENT_STATUS[pm2_total]:-N/A} online"
    echo "└── NGINX Service: ${CURRENT_STATUS[nginx]:-N/A}"
    echo ""
    
    # 네트워크 및 Health
    echo -e "${YELLOW}Network & Health:${NC}"
    echo "├── Health Check: HTTP ${CURRENT_STATUS[http_code]:-N/A}"
    echo "├── Response Time: ${CURRENT_STATUS[response_time]:-N/A}s (threshold: ${RESPONSE_TIME_THRESHOLD}s)"
    echo "└── Healthy Targets: ${CURRENT_STATUS[healthy_targets]:-N/A}"
    echo ""
    
    # AWS 서비스
    echo -e "${YELLOW}AWS Services:${NC}"
    echo "└── ALB State: ${CURRENT_STATUS[alb_state]:-N/A}"
    echo ""
    
    echo -e "${CYAN}================================================================${NC}"
    echo "Press Ctrl+C to stop monitoring"
    echo ""
}

# 모든 체크 실행
run_all_checks() {
    local check_results=()
    
    check_cpu_usage && check_results+=("cpu:OK") || check_results+=("cpu:FAIL")
    check_memory_usage && check_results+=("memory:OK") || check_results+=("memory:FAIL")
    check_disk_usage && check_results+=("disk:OK") || check_results+=("disk:FAIL")
    check_pm2_status && check_results+=("pm2:OK") || check_results+=("pm2:FAIL")
    check_nginx_status && check_results+=("nginx:OK") || check_results+=("nginx:FAIL")
    check_alb_health && check_results+=("health:OK") || check_results+=("health:FAIL")
    check_aws_services && check_results+=("aws:OK") || check_results+=("aws:FAIL")
    
    # 전체 상태 요약
    local failed_count=0
    for result in "${check_results[@]}"; do
        if [[ "$result" == *":FAIL" ]]; then
            ((failed_count++))
        fi
    done
    
    if [[ "$failed_count" -eq 0 ]]; then
        CURRENT_STATUS["overall"]="HEALTHY"
        log_success "All system checks passed"
    else
        CURRENT_STATUS["overall"]="DEGRADED"
        log_warning "$failed_count system checks failed"
    fi
}

# 데몬 모드로 실행
run_daemon() {
    log_info "Starting system monitor in daemon mode (PID: $$)"
    echo $$ > "$PID_FILE"
    
    # 종료 시그널 핸들러
    trap 'log_info "Stopping system monitor"; rm -f "$PID_FILE"; exit 0' TERM INT
    
    while true; do
        run_all_checks
        sleep "$MONITOR_INTERVAL"
    done
}

# 대화형 모드로 실행
run_interactive() {
    log_info "Starting system monitor in interactive mode"
    
    # 종료 시그널 핸들러
    trap 'log_info "Stopping system monitor"; exit 0' TERM INT
    
    while true; do
        run_all_checks
        show_dashboard
        sleep "$MONITOR_INTERVAL"
    done
}

# 단일 실행 모드
run_once() {
    log_info "Running system monitor once"
    run_all_checks
    show_dashboard
}

# 도움말 표시
show_help() {
    cat << EOF
Blue-Green Deployment System Monitor

USAGE:
    $0 [OPTIONS] [MODE]

MODES:
    --daemon       Run as background daemon
    --interactive  Run with real-time dashboard (default)
    --once         Run checks once and exit
    --stop         Stop running daemon

OPTIONS:
    --config FILE              Configuration file path
    --interval SECONDS         Monitor interval (default: 30)
    --cpu-threshold PERCENT    CPU usage threshold (default: 80)
    --memory-threshold PERCENT Memory usage threshold (default: 85)
    --disk-threshold PERCENT   Disk usage threshold (default: 90)
    --response-threshold SECS  Response time threshold (default: 2)
    --alb-dns-name NAME        ALB DNS name to monitor
    --help                     Show this help message

CONFIGURATION:
    Settings can be configured via environment variables or config file.
    Config file location: $CONFIG_FILE

EXAMPLES:
    $0                                    # Interactive mode
    $0 --daemon                          # Daemon mode
    $0 --once                           # Single run
    $0 --interactive --interval 60      # Interactive with 60s interval
    $0 --daemon --cpu-threshold 90      # Daemon with custom CPU threshold

EXIT CODES:
    0 - Success
    1 - Error or checks failed
EOF
}

# 데몬 중지
stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping daemon with PID $pid"
            kill -TERM "$pid"
            rm -f "$PID_FILE"
            echo "Daemon stopped successfully"
        else
            echo "Daemon not running (stale PID file removed)"
            rm -f "$PID_FILE"
        fi
    else
        echo "Daemon not running (no PID file found)"
    fi
}

# 메인 실행 함수
main() {
    local mode="interactive"
    
    # 파라미터 파싱
    while [[ $# -gt 0 ]]; do
        case $1 in
            --daemon)
                mode="daemon"
                shift
                ;;
            --interactive)
                mode="interactive"
                shift
                ;;
            --once)
                mode="once"
                shift
                ;;
            --stop)
                stop_daemon
                exit 0
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --interval)
                MONITOR_INTERVAL="$2"
                shift 2
                ;;
            --cpu-threshold)
                CPU_THRESHOLD="$2"
                shift 2
                ;;
            --memory-threshold)
                MEMORY_THRESHOLD="$2"
                shift 2
                ;;
            --disk-threshold)
                DISK_THRESHOLD="$2"
                shift 2
                ;;
            --response-threshold)
                RESPONSE_TIME_THRESHOLD="$2"
                shift 2
                ;;
            --alb-dns-name)
                ALB_DNS_NAME="$2"
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
    
    # 설정 로드
    load_config
    
    # 로그 디렉토리 생성
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$(dirname "$ALERT_LOG")"
    
    # 모드에 따라 실행
    case "$mode" in
        "daemon")
            run_daemon
            ;;
        "interactive")
            run_interactive
            ;;
        "once")
            run_once
            ;;
    esac
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi