#!/bin/bash

# ALB Traffic Switching Script for Blue-Green Deployment
# This script switches traffic between Blue and Green target groups

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="bluegreen-deployment"
ENVIRONMENT="production"
REGION="us-east-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  status        Show current ALB configuration and target group health"
    echo "  switch blue   Switch traffic to Blue target group"
    echo "  switch green  Switch traffic to Green target group"
    echo "  rollback      Rollback to previous target group"
    echo "  validate      Validate target group health before switching"
    echo ""
    echo "Options:"
    echo "  -p, --project-name NAME     Project name (default: bluegreen-deployment)"
    echo "  -e, --environment ENV       Environment (default: production)"
    echo "  -r, --region REGION         AWS region (default: us-east-1)"
    echo "  -w, --wait SECONDS          Wait time for health checks (default: 60)"
    echo "  -h, --help                  Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 switch blue"
    echo "  $0 switch green --wait 120"
    echo "  $0 rollback"
}

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Get resource names
get_stack_name() {
    echo "${PROJECT_NAME}-${ENVIRONMENT}-infrastructure"
}

get_blue_target_group_name() {
    echo "${PROJECT_NAME}-${ENVIRONMENT}-blue-tg"
}

get_green_target_group_name() {
    echo "${PROJECT_NAME}-${ENVIRONMENT}-green-tg"
}

# Get ALB ARN and Listener ARN
get_alb_info() {
    local stack_name
    stack_name=$(get_stack_name)
    
    local alb_arn
    alb_arn=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ApplicationLoadBalancerArn`].OutputValue' \
        --output text 2>/dev/null)
    
    if [[ "$alb_arn" == "None" || "$alb_arn" == "" ]]; then
        error "Could not find ALB ARN. Is the infrastructure deployed?"
        exit 1
    fi
    
    echo "$alb_arn"
}

get_listener_arn() {
    local alb_arn="$1"
    
    local listener_arn
    listener_arn=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$alb_arn" \
        --region "$REGION" \
        --query 'Listeners[?Port==`80`].ListenerArn' \
        --output text)
    
    if [[ "$listener_arn" == "None" || "$listener_arn" == "" ]]; then
        error "Could not find ALB listener ARN"
        exit 1
    fi
    
    echo "$listener_arn"
}

# Get target group ARNs
get_target_group_arn() {
    local tg_name="$1"
    
    local tg_arn
    tg_arn=$(aws elbv2 describe-target-groups \
        --names "$tg_name" \
        --region "$REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null)
    
    if [[ "$tg_arn" == "None" || "$tg_arn" == "" ]]; then
        error "Could not find target group: $tg_name"
        exit 1
    fi
    
    echo "$tg_arn"
}

# Get current active target group
get_current_target_group() {
    local listener_arn="$1"
    
    local current_tg_arn
    current_tg_arn=$(aws elbv2 describe-listeners \
        --listener-arns "$listener_arn" \
        --region "$REGION" \
        --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
        --output text)
    
    echo "$current_tg_arn"
}

# Check target group health
check_target_group_health() {
    local tg_arn="$1"
    local tg_name="$2"
    
    info "Checking health of target group: $tg_name"
    
    local health_status
    health_status=$(aws elbv2 describe-target-health \
        --target-group-arn "$tg_arn" \
        --region "$REGION" \
        --query 'TargetHealthDescriptions[].TargetHealth.State' \
        --output text)
    
    if [[ -z "$health_status" ]]; then
        warn "No targets found in $tg_name"
        return 1
    fi
    
    local healthy_count=0
    local total_count=0
    
    for status in $health_status; do
        ((total_count++))
        if [[ "$status" == "healthy" ]]; then
            ((healthy_count++))
        fi
    done
    
    if [[ $healthy_count -gt 0 ]]; then
        log "$tg_name: $healthy_count/$total_count targets are healthy"
        return 0
    else
        error "$tg_name: No healthy targets found ($healthy_count/$total_count)"
        return 1
    fi
}

# Wait for target group to become healthy
wait_for_healthy_targets() {
    local tg_arn="$1"
    local tg_name="$2"
    local wait_time="${3:-60}"
    
    log "Waiting up to $wait_time seconds for $tg_name to become healthy..."
    
    local elapsed=0
    while [[ $elapsed -lt $wait_time ]]; do
        if check_target_group_health "$tg_arn" "$tg_name"; then
            log "$tg_name is healthy"
            return 0
        fi
        
        info "Waiting for healthy targets... (${elapsed}s/${wait_time}s)"
        sleep 10
        ((elapsed += 10))
    done
    
    error "Timeout: $tg_name did not become healthy within $wait_time seconds"
    return 1
}

# Save current state for rollback
save_current_state() {
    local current_tg_arn="$1"
    echo "$current_tg_arn" > "/tmp/bluegreen_previous_target_group.txt"
    log "Current state saved for potential rollback"
}

# Switch traffic to target group
switch_traffic() {
    local target_color="$1"
    local listener_arn="$2"
    local target_tg_arn="$3"
    local current_tg_arn="$4"
    
    if [[ "$target_tg_arn" == "$current_tg_arn" ]]; then
        log "Traffic is already routed to $target_color target group"
        return 0
    fi
    
    # Save current state for rollback
    save_current_state "$current_tg_arn"
    
    log "Switching traffic to $target_color target group..."
    
    aws elbv2 modify-listener \
        --listener-arn "$listener_arn" \
        --default-actions Type=forward,TargetGroupArn="$target_tg_arn" \
        --region "$REGION" > /dev/null
    
    if [[ $? -eq 0 ]]; then
        log "Traffic successfully switched to $target_color"
        
        # Wait a moment for the change to take effect
        sleep 5
        
        # Verify the switch
        local new_current_tg_arn
        new_current_tg_arn=$(get_current_target_group "$listener_arn")
        
        if [[ "$new_current_tg_arn" == "$target_tg_arn" ]]; then
            log "Traffic switch verified successfully"
            return 0
        else
            error "Traffic switch verification failed"
            return 1
        fi
    else
        error "Failed to switch traffic to $target_color"
        return 1
    fi
}

# Show current status
show_status() {
    log "Checking ALB and target group status..."
    
    local alb_arn
    alb_arn=$(get_alb_info)
    
    local listener_arn
    listener_arn=$(get_listener_arn "$alb_arn")
    
    local current_tg_arn
    current_tg_arn=$(get_current_target_group "$listener_arn")
    
    # Get ALB DNS name
    local alb_dns
    alb_dns=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --region "$REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    echo ""
    echo -e "${BLUE}=== ALB Configuration ===${NC}"
    echo "ALB DNS: $alb_dns"
    echo "ALB ARN: $alb_arn"
    echo ""
    
    # Determine current active environment
    local blue_tg_arn
    local green_tg_arn
    blue_tg_arn=$(get_target_group_arn "$(get_blue_target_group_name)")
    green_tg_arn=$(get_target_group_arn "$(get_green_target_group_name)")
    
    local active_environment
    if [[ "$current_tg_arn" == "$blue_tg_arn" ]]; then
        active_environment="BLUE"
    elif [[ "$current_tg_arn" == "$green_tg_arn" ]]; then
        active_environment="GREEN"
    else
        active_environment="UNKNOWN"
    fi
    
    echo -e "${GREEN}Current Active Environment: $active_environment${NC}"
    echo ""
    
    # Show target group health
    echo -e "${BLUE}=== Target Group Health ===${NC}"
    
    echo -e "\n${BLUE}Blue Target Group:${NC}"
    if check_target_group_health "$blue_tg_arn" "$(get_blue_target_group_name)"; then
        echo "✅ Blue environment is healthy"
    else
        echo "❌ Blue environment has issues"
    fi
    
    echo -e "\n${BLUE}Green Target Group:${NC}"
    if check_target_group_health "$green_tg_arn" "$(get_green_target_group_name)"; then
        echo "✅ Green environment is healthy"
    else
        echo "❌ Green environment has issues"
    fi
    
    echo ""
}

# Validate target group before switching
validate_target_group() {
    local target_color="$1"
    
    local tg_name
    if [[ "$target_color" == "blue" ]]; then
        tg_name=$(get_blue_target_group_name)
    elif [[ "$target_color" == "green" ]]; then
        tg_name=$(get_green_target_group_name)
    else
        error "Invalid target color: $target_color"
        exit 1
    fi
    
    local tg_arn
    tg_arn=$(get_target_group_arn "$tg_name")
    
    if wait_for_healthy_targets "$tg_arn" "$tg_name" "${WAIT_TIME:-60}"; then
        log "✅ $target_color environment validation passed"
        return 0
    else
        error "❌ $target_color environment validation failed"
        return 1
    fi
}

# Perform traffic switch
perform_switch() {
    local target_color="$1"
    
    log "Starting traffic switch to $target_color environment..."
    
    # Get ALB and target group information
    local alb_arn
    alb_arn=$(get_alb_info)
    
    local listener_arn
    listener_arn=$(get_listener_arn "$alb_arn")
    
    local current_tg_arn
    current_tg_arn=$(get_current_target_group "$listener_arn")
    
    # Get target group ARN
    local target_tg_name
    if [[ "$target_color" == "blue" ]]; then
        target_tg_name=$(get_blue_target_group_name)
    elif [[ "$target_color" == "green" ]]; then
        target_tg_name=$(get_green_target_group_name)
    else
        error "Invalid target color: $target_color"
        exit 1
    fi
    
    local target_tg_arn
    target_tg_arn=$(get_target_group_arn "$target_tg_name")
    
    # Validate target environment health
    log "Validating $target_color environment health..."
    if ! wait_for_healthy_targets "$target_tg_arn" "$target_tg_name" "${WAIT_TIME:-60}"; then
        error "Cannot switch to $target_color - environment is not healthy"
        exit 1
    fi
    
    # Perform the switch
    if switch_traffic "$target_color" "$listener_arn" "$target_tg_arn" "$current_tg_arn"; then
        log "✅ Traffic successfully switched to $target_color environment"
        
        # Show updated status
        echo ""
        show_status
    else
        error "❌ Failed to switch traffic to $target_color environment"
        exit 1
    fi
}

# Rollback to previous target group
perform_rollback() {
    log "Starting rollback to previous environment..."
    
    if [[ ! -f "/tmp/bluegreen_previous_target_group.txt" ]]; then
        error "No rollback state found. Cannot perform rollback."
        exit 1
    fi
    
    local previous_tg_arn
    previous_tg_arn=$(cat "/tmp/bluegreen_previous_target_group.txt")
    
    if [[ -z "$previous_tg_arn" ]]; then
        error "Invalid rollback state found"
        exit 1
    fi
    
    # Get current ALB configuration
    local alb_arn
    alb_arn=$(get_alb_info)
    
    local listener_arn
    listener_arn=$(get_listener_arn "$alb_arn")
    
    # Determine previous environment color
    local blue_tg_arn
    local green_tg_arn
    blue_tg_arn=$(get_target_group_arn "$(get_blue_target_group_name)")
    green_tg_arn=$(get_target_group_arn "$(get_green_target_group_name)")
    
    local previous_color
    if [[ "$previous_tg_arn" == "$blue_tg_arn" ]]; then
        previous_color="blue"
    elif [[ "$previous_tg_arn" == "$green_tg_arn" ]]; then
        previous_color="green"
    else
        error "Unknown previous target group ARN: $previous_tg_arn"
        exit 1
    fi
    
    log "Rolling back to $previous_color environment..."
    
    # Perform rollback switch
    aws elbv2 modify-listener \
        --listener-arn "$listener_arn" \
        --default-actions Type=forward,TargetGroupArn="$previous_tg_arn" \
        --region "$REGION" > /dev/null
    
    if [[ $? -eq 0 ]]; then
        log "✅ Rollback to $previous_color environment successful"
        
        # Clean up rollback state
        rm -f "/tmp/bluegreen_previous_target_group.txt"
        
        # Show status
        echo ""
        show_status
    else
        error "❌ Rollback failed"
        exit 1
    fi
}

# Parse command line arguments
WAIT_TIME=60

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -w|--wait)
            WAIT_TIME="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        status)
            COMMAND="status"
            shift
            ;;
        switch)
            COMMAND="switch"
            TARGET_COLOR="$2"
            shift 2
            ;;
        validate)
            COMMAND="validate"
            TARGET_COLOR="$2"
            shift 2
            ;;
        rollback)
            COMMAND="rollback"
            shift
            ;;
        *)
            error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate target color for switch command
if [[ "$COMMAND" == "switch" || "$COMMAND" == "validate" ]]; then
    if [[ "$TARGET_COLOR" != "blue" && "$TARGET_COLOR" != "green" ]]; then
        error "Target color must be 'blue' or 'green'"
        print_usage
        exit 1
    fi
fi

# Check if command was provided
if [[ -z "$COMMAND" ]]; then
    error "No command specified"
    print_usage
    exit 1
fi

# Main execution
main() {
    log "Starting ALB Traffic Management"
    log "Project: $PROJECT_NAME"
    log "Environment: $ENVIRONMENT"
    log "Region: $REGION"
    log "Command: $COMMAND"
    
    check_prerequisites
    
    case "$COMMAND" in
        status)
            show_status
            ;;
        switch)
            perform_switch "$TARGET_COLOR"
            ;;
        validate)
            validate_target_group "$TARGET_COLOR"
            ;;
        rollback)
            perform_rollback
            ;;
        *)
            error "Unknown command: $COMMAND"
            print_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"