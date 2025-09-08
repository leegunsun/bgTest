#!/bin/bash

# GitLab CI/CD + CodeDeploy Pipeline Management Script
# Hybrid deployment pipeline management for Blue-Green architecture

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
PROJECT_NAME="bluegreen-deployment"
ENVIRONMENT="production"
REGION="us-east-1"
DEPLOYMENT_STRATEGY="hybrid"

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
    echo "  status           Show pipeline and deployment status"
    echo "  deploy blue      Deploy to blue environment"
    echo "  deploy green     Deploy to green environment"
    echo "  switch blue      Switch traffic to blue environment"
    echo "  switch green     Switch traffic to green environment"
    echo "  rollback         Perform emergency rollback"
    echo "  validate         Validate current deployment"
    echo "  cleanup          Clean up old artifacts"
    echo "  setup            Setup pipeline prerequisites"
    echo ""
    echo "Options:"
    echo "  -p, --project-name NAME     Project name (default: bluegreen-deployment)"
    echo "  -e, --environment ENV       Environment (default: production)"
    echo "  -r, --region REGION         AWS region (default: us-east-1)"
    echo "  -s, --strategy STRATEGY     Deployment strategy (hybrid, codedeploy-only, gitlab-only)"
    echo "  -v, --version VERSION       Application version"
    echo "  -h, --help                  Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 deploy blue --version 2.0.0"
    echo "  $0 switch green"
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
    
    # Check if GitLab CI configuration exists
    if [[ ! -f "$PROJECT_ROOT/.gitlab-ci-hybrid.yml" ]]; then
        error "GitLab CI configuration not found: .gitlab-ci-hybrid.yml"
        error "Please ensure the hybrid pipeline configuration is in place"
        exit 1
    fi
    
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
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install it first."
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Get resource names
get_alb_name() {
    echo "${PROJECT_NAME}-${ENVIRONMENT}-alb"
}

get_blue_target_group_name() {
    echo "${PROJECT_NAME}-${ENVIRONMENT}-blue-tg"
}

get_green_target_group_name() {
    echo "${PROJECT_NAME}-${ENVIRONMENT}-green-tg"
}

get_codedeploy_app_name() {
    echo "${PROJECT_NAME}-${ENVIRONMENT}-app"
}

# Get ALB DNS name
get_alb_dns() {
    local alb_name
    alb_name=$(get_alb_name)
    
    aws elbv2 describe-load-balancers \
        --names "$alb_name" \
        --region "$REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null || echo "not-found"
}

# Get current active target group
get_current_target_group() {
    local alb_name
    alb_name=$(get_alb_name)
    
    # Get ALB ARN
    local alb_arn
    alb_arn=$(aws elbv2 describe-load-balancers \
        --names "$alb_name" \
        --region "$REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text 2>/dev/null)
    
    if [[ "$alb_arn" == "None" || -z "$alb_arn" ]]; then
        echo "not-found"
        return
    fi
    
    # Get listener ARN
    local listener_arn
    listener_arn=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$alb_arn" \
        --region "$REGION" \
        --query 'Listeners[?Port==`80`].ListenerArn' \
        --output text)
    
    if [[ "$listener_arn" == "None" || -z "$listener_arn" ]]; then
        echo "not-found"
        return
    fi
    
    # Get current target group ARN
    local current_tg_arn
    current_tg_arn=$(aws elbv2 describe-listeners \
        --listener-arns "$listener_arn" \
        --region "$REGION" \
        --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
        --output text)
    
    # Determine if it's blue or green
    local blue_tg_arn
    local green_tg_arn
    blue_tg_arn=$(aws elbv2 describe-target-groups \
        --names "$(get_blue_target_group_name)" \
        --region "$REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "not-found")
    green_tg_arn=$(aws elbv2 describe-target-groups \
        --names "$(get_green_target_group_name)" \
        --region "$REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "not-found")
    
    if [[ "$current_tg_arn" == "$blue_tg_arn" ]]; then
        echo "blue"
    elif [[ "$current_tg_arn" == "$green_tg_arn" ]]; then
        echo "green"
    else
        echo "unknown"
    fi
}

# Show deployment status
show_status() {
    log "Checking deployment pipeline status..."
    
    echo -e "\n${BLUE}=== Pipeline Configuration ===${NC}"
    echo "Project: $PROJECT_NAME"
    echo "Environment: $ENVIRONMENT"
    echo "Region: $REGION"
    echo "Deployment Strategy: $DEPLOYMENT_STRATEGY"
    
    # Check ALB status
    echo -e "\n${BLUE}=== ALB Status ===${NC}"
    local alb_dns
    alb_dns=$(get_alb_dns)
    
    if [[ "$alb_dns" == "not-found" ]]; then
        warn "ALB not found or not accessible"
    else
        log "ALB DNS: $alb_dns"
        
        # Test ALB health
        local alb_health
        alb_health=$(curl -s -o /dev/null -w "%{http_code}" "http://$alb_dns/health" --max-time 5 || echo "000")
        
        if [[ "$alb_health" == "200" ]]; then
            log "✅ ALB Health: HTTP $alb_health"
        else
            error "❌ ALB Health: HTTP $alb_health"
        fi
    fi
    
    # Show current active environment
    echo -e "\n${BLUE}=== Active Environment ===${NC}"
    local active_tg
    active_tg=$(get_current_target_group)
    
    case "$active_tg" in
        "blue")
            log "🔵 Current Active: BLUE environment"
            ;;
        "green")
            log "🟢 Current Active: GREEN environment"
            ;;
        "unknown")
            warn "⚠️ Current Active: UNKNOWN"
            ;;
        "not-found")
            error "❌ Current Active: NOT FOUND"
            ;;
    esac
    
    # Show target group health
    echo -e "\n${BLUE}=== Target Group Health ===${NC}"
    show_target_group_health
    
    # Show recent CodeDeploy deployments
    echo -e "\n${BLUE}=== Recent CodeDeploy Deployments ===${NC}"
    show_recent_deployments
}

# Show target group health
show_target_group_health() {
    local blue_tg_name
    local green_tg_name
    blue_tg_name=$(get_blue_target_group_name)
    green_tg_name=$(get_green_target_group_name)
    
    # Blue target group
    echo "Blue Target Group ($blue_tg_name):"
    local blue_tg_arn
    blue_tg_arn=$(aws elbv2 describe-target-groups \
        --names "$blue_tg_name" \
        --region "$REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "not-found")
    
    if [[ "$blue_tg_arn" != "not-found" ]]; then
        aws elbv2 describe-target-health \
            --target-group-arn "$blue_tg_arn" \
            --region "$REGION" \
            --query 'TargetHealthDescriptions[].{Target:Target.Id,Health:TargetHealth.State,Description:TargetHealth.Description}' \
            --output table
    else
        echo "  ❌ Blue target group not found"
    fi
    
    echo ""
    
    # Green target group
    echo "Green Target Group ($green_tg_name):"
    local green_tg_arn
    green_tg_arn=$(aws elbv2 describe-target-groups \
        --names "$green_tg_name" \
        --region "$REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "not-found")
    
    if [[ "$green_tg_arn" != "not-found" ]]; then
        aws elbv2 describe-target-health \
            --target-group-arn "$green_tg_arn" \
            --region "$REGION" \
            --query 'TargetHealthDescriptions[].{Target:Target.Id,Health:TargetHealth.State,Description:TargetHealth.Description}' \
            --output table
    else
        echo "  ❌ Green target group not found"
    fi
}

# Show recent CodeDeploy deployments
show_recent_deployments() {
    local app_name
    app_name=$(get_codedeploy_app_name)
    
    # Check if application exists
    if ! aws deploy get-application --application-name "$app_name" --region "$REGION" &>/dev/null; then
        warn "CodeDeploy application '$app_name' not found"
        return
    fi
    
    # Get recent deployments
    local deployments
    deployments=$(aws deploy list-deployments \
        --application-name "$app_name" \
        --region "$REGION" \
        --query 'deployments[:5]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$deployments" ]]; then
        log "No recent deployments found"
        return
    fi
    
    echo "Recent Deployments:"
    for deployment_id in $deployments; do
        local deployment_info
        deployment_info=$(aws deploy get-deployment \
            --deployment-id "$deployment_id" \
            --region "$REGION" \
            --query 'deploymentInfo.{Status:status,CreateTime:createTime,Description:description}' \
            --output text 2>/dev/null || echo "error getting info")
        
        echo "  - $deployment_id: $deployment_info"
    done
}

# Trigger deployment via GitLab API (if available)
trigger_deployment() {
    local target_env="$1"
    local version="$2"
    
    log "Triggering deployment to $target_env environment..."
    
    if [[ -z "$GITLAB_TOKEN" ]]; then
        warn "GITLAB_TOKEN not set. Cannot trigger GitLab pipeline automatically."
        warn "Please manually trigger the deployment in GitLab CI/CD interface."
        warn "Target: deploy-to-${target_env}-production job"
        return 1
    fi
    
    # This would require GitLab API integration
    # Implementation depends on specific GitLab setup
    warn "Automated GitLab pipeline triggering requires GitLab API configuration"
    warn "Please manually trigger the deploy-to-${target_env}-production job"
}

# Switch traffic using ALB
switch_traffic() {
    local target_env="$1"
    
    log "Switching traffic to $target_env environment..."
    
    # Get target group ARN
    local target_tg_name
    if [[ "$target_env" == "blue" ]]; then
        target_tg_name=$(get_blue_target_group_name)
    elif [[ "$target_env" == "green" ]]; then
        target_tg_name=$(get_green_target_group_name)
    else
        error "Invalid target environment: $target_env"
        exit 1
    fi
    
    local target_tg_arn
    target_tg_arn=$(aws elbv2 describe-target-groups \
        --names "$target_tg_name" \
        --region "$REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "not-found")
    
    if [[ "$target_tg_arn" == "not-found" ]]; then
        error "Target group not found: $target_tg_name"
        exit 1
    fi
    
    # Check target group health
    local healthy_count
    healthy_count=$(aws elbv2 describe-target-health \
        --target-group-arn "$target_tg_arn" \
        --region "$REGION" \
        --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
        --output text)
    
    if [[ $healthy_count -lt 1 ]]; then
        error "No healthy targets in $target_env target group"
        exit 1
    fi
    
    log "Found $healthy_count healthy targets in $target_env target group"
    
    # Get ALB listener ARN
    local alb_name
    alb_name=$(get_alb_name)
    
    local alb_arn
    alb_arn=$(aws elbv2 describe-load-balancers \
        --names "$alb_name" \
        --region "$REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    local listener_arn
    listener_arn=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$alb_arn" \
        --region "$REGION" \
        --query 'Listeners[?Port==`80`].ListenerArn' \
        --output text)
    
    # Perform traffic switch
    log "Switching ALB listener to $target_env target group..."
    
    aws elbv2 modify-listener \
        --listener-arn "$listener_arn" \
        --default-actions Type=forward,TargetGroupArn="$target_tg_arn" \
        --region "$REGION" > /dev/null
    
    log "✅ Traffic switched to $target_env environment"
    
    # Verify switch
    sleep 5
    local current_tg
    current_tg=$(get_current_target_group)
    
    if [[ "$current_tg" == "$target_env" ]]; then
        log "✅ Traffic switch verified"
        
        # Test ALB endpoint
        local alb_dns
        alb_dns=$(get_alb_dns)
        if [[ "$alb_dns" != "not-found" ]]; then
            local health_check
            health_check=$(curl -s -o /dev/null -w "%{http_code}" "http://$alb_dns/health/deep" --max-time 10 || echo "000")
            
            if [[ "$health_check" == "200" ]]; then
                log "✅ ALB health check passed after switch"
            else
                warn "⚠️ ALB health check returned HTTP $health_check after switch"
            fi
        fi
    else
        error "❌ Traffic switch verification failed"
        exit 1
    fi
}

# Validate current deployment
validate_deployment() {
    log "Validating current deployment..."
    
    local alb_dns
    alb_dns=$(get_alb_dns)
    
    if [[ "$alb_dns" == "not-found" ]]; then
        error "ALB not found - cannot validate deployment"
        exit 1
    fi
    
    # Test health endpoint
    local health_status
    health_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$alb_dns/health/deep" --max-time 10 || echo "000")
    
    if [[ "$health_status" == "200" ]]; then
        log "✅ Deep health check passed"
    else
        error "❌ Deep health check failed: HTTP $health_status"
        exit 1
    fi
    
    # Test application content
    local response
    response=$(curl -s "http://$alb_dns/" --max-time 10 || echo "ERROR")
    
    if echo "$response" | grep -q "True Blue-Green Deployment"; then
        log "✅ Application content validation passed"
    else
        error "❌ Application content validation failed"
        exit 1
    fi
    
    log "✅ Deployment validation completed successfully"
}

# Setup pipeline prerequisites
setup_pipeline() {
    log "Setting up pipeline prerequisites..."
    
    # Check if GitLab CI configuration is in place
    if [[ ! -f "$PROJECT_ROOT/.gitlab-ci.yml" ]]; then
        log "Copying hybrid GitLab CI configuration..."
        cp "$PROJECT_ROOT/.gitlab-ci-hybrid.yml" "$PROJECT_ROOT/.gitlab-ci.yml"
        log "GitLab CI configuration updated"
    fi
    
    # Verify AWS resources exist
    log "Verifying AWS resources..."
    
    local alb_name
    alb_name=$(get_alb_name)
    
    if ! aws elbv2 describe-load-balancers --names "$alb_name" --region "$REGION" &>/dev/null; then
        error "ALB not found: $alb_name"
        error "Please deploy the AWS infrastructure first using:"
        error "  ./aws-infrastructure/scripts/deploy-infrastructure.sh deploy"
        exit 1
    fi
    
    local app_name
    app_name=$(get_codedeploy_app_name)
    
    if ! aws deploy get-application --application-name "$app_name" --region "$REGION" &>/dev/null; then
        error "CodeDeploy application not found: $app_name"
        error "Please deploy the AWS infrastructure first"
        exit 1
    fi
    
    log "✅ Pipeline prerequisites verified"
}

# Parse command line arguments
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
        -s|--strategy)
            DEPLOYMENT_STRATEGY="$2"
            shift 2
            ;;
        -v|--version)
            APPLICATION_VERSION="$2"
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
        deploy)
            COMMAND="deploy"
            TARGET_ENV="$2"
            shift 2
            ;;
        switch)
            COMMAND="switch"
            TARGET_ENV="$2"
            shift 2
            ;;
        rollback)
            COMMAND="rollback"
            shift
            ;;
        validate)
            COMMAND="validate"
            shift
            ;;
        cleanup)
            COMMAND="cleanup"
            shift
            ;;
        setup)
            COMMAND="setup"
            shift
            ;;
        *)
            error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Check if command was provided
if [[ -z "$COMMAND" ]]; then
    error "No command specified"
    print_usage
    exit 1
fi

# Validate target environment for deploy/switch commands
if [[ "$COMMAND" == "deploy" || "$COMMAND" == "switch" ]]; then
    if [[ "$TARGET_ENV" != "blue" && "$TARGET_ENV" != "green" ]]; then
        error "Target environment must be 'blue' or 'green'"
        exit 1
    fi
fi

# Main execution
main() {
    log "Pipeline Management Tool"
    log "Project: $PROJECT_NAME"
    log "Environment: $ENVIRONMENT"
    log "Command: $COMMAND"
    
    if [[ "$COMMAND" != "setup" ]]; then
        check_prerequisites
    fi
    
    case "$COMMAND" in
        status)
            show_status
            ;;
        deploy)
            trigger_deployment "$TARGET_ENV" "$APPLICATION_VERSION"
            ;;
        switch)
            switch_traffic "$TARGET_ENV"
            ;;
        rollback)
            error "Rollback functionality requires GitLab pipeline integration"
            error "Please use GitLab CI/CD interface to trigger emergency-rollback job"
            exit 1
            ;;
        validate)
            validate_deployment
            ;;
        cleanup)
            log "Cleanup functionality is available in GitLab pipeline"
            log "Run the cleanup-s3-artifacts job manually"
            ;;
        setup)
            setup_pipeline
            ;;
        *)
            error "Unknown command: $COMMAND"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"