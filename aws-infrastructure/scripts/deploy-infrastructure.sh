#!/bin/bash

# AWS Infrastructure Deployment Script for True Blue-Green Deployment
# This script deploys the CloudFormation template for dual EC2 + AWS ALB architecture

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATE_PATH="${SCRIPT_DIR}/../cloudformation/bluegreen-infrastructure.yaml"

# Default parameters
PROJECT_NAME="bluegreen-deployment"
ENVIRONMENT="production"
REGION="us-east-1"
INSTANCE_TYPE="t3.medium"

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
    echo "  deploy        Deploy the infrastructure"
    echo "  update        Update the existing infrastructure"
    echo "  delete        Delete the infrastructure"
    echo "  status        Check infrastructure status"
    echo "  outputs       Show CloudFormation outputs"
    echo ""
    echo "Options:"
    echo "  -p, --project-name NAME     Project name (default: bluegreen-deployment)"
    echo "  -e, --environment ENV       Environment (default: production)"
    echo "  -r, --region REGION         AWS region (default: us-east-1)"
    echo "  -k, --key-pair KEY          EC2 Key Pair name (required for deploy/update)"
    echo "  -t, --instance-type TYPE    Instance type (default: t3.medium)"
    echo "  -h, --help                  Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -k my-keypair deploy"
    echo "  $0 -e staging -k my-key update"
    echo "  $0 status"
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
    
    # Check if template exists
    if [[ ! -f "$TEMPLATE_PATH" ]]; then
        error "CloudFormation template not found: $TEMPLATE_PATH"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Validate CloudFormation template
validate_template() {
    log "Validating CloudFormation template..."
    
    if aws cloudformation validate-template --template-body file://"$TEMPLATE_PATH" --region "$REGION" &> /dev/null; then
        log "Template validation successful"
    else
        error "Template validation failed"
        exit 1
    fi
}

# Get stack name
get_stack_name() {
    echo "${PROJECT_NAME}-${ENVIRONMENT}-infrastructure"
}

# Check if stack exists
stack_exists() {
    local stack_name="$1"
    aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" &> /dev/null
}

# Deploy infrastructure
deploy_infrastructure() {
    local stack_name
    stack_name=$(get_stack_name)
    
    log "Deploying infrastructure stack: $stack_name"
    
    if [[ -z "$KEY_PAIR" ]]; then
        error "Key pair name is required for deployment. Use -k option."
        exit 1
    fi
    
    if stack_exists "$stack_name"; then
        warn "Stack $stack_name already exists. Use 'update' command instead."
        exit 1
    fi
    
    local parameters=(
        "ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME"
        "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
        "ParameterKey=KeyPairName,ParameterValue=$KEY_PAIR"
        "ParameterKey=InstanceType,ParameterValue=$INSTANCE_TYPE"
    )
    
    log "Creating CloudFormation stack..."
    aws cloudformation create-stack \
        --stack-name "$stack_name" \
        --template-body file://"$TEMPLATE_PATH" \
        --parameters "${parameters[@]}" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION" \
        --tags Key=Project,Value="$PROJECT_NAME" Key=Environment,Value="$ENVIRONMENT" \
        --on-failure ROLLBACK
    
    log "Waiting for stack creation to complete..."
    aws cloudformation wait stack-create-complete \
        --stack-name "$stack_name" \
        --region "$REGION"
    
    if [[ $? -eq 0 ]]; then
        log "Infrastructure deployed successfully!"
        show_outputs "$stack_name"
    else
        error "Stack creation failed or timed out"
        exit 1
    fi
}

# Update infrastructure
update_infrastructure() {
    local stack_name
    stack_name=$(get_stack_name)
    
    log "Updating infrastructure stack: $stack_name"
    
    if ! stack_exists "$stack_name"; then
        error "Stack $stack_name does not exist. Use 'deploy' command instead."
        exit 1
    fi
    
    if [[ -z "$KEY_PAIR" ]]; then
        error "Key pair name is required for update. Use -k option."
        exit 1
    fi
    
    local parameters=(
        "ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME"
        "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
        "ParameterKey=KeyPairName,ParameterValue=$KEY_PAIR"
        "ParameterKey=InstanceType,ParameterValue=$INSTANCE_TYPE"
    )
    
    log "Updating CloudFormation stack..."
    if aws cloudformation update-stack \
        --stack-name "$stack_name" \
        --template-body file://"$TEMPLATE_PATH" \
        --parameters "${parameters[@]}" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION" &> /dev/null; then
        
        log "Waiting for stack update to complete..."
        aws cloudformation wait stack-update-complete \
            --stack-name "$stack_name" \
            --region "$REGION"
        
        if [[ $? -eq 0 ]]; then
            log "Infrastructure updated successfully!"
            show_outputs "$stack_name"
        else
            error "Stack update failed or timed out"
            exit 1
        fi
    else
        warn "No updates are to be performed (stack may be up to date)"
    fi
}

# Delete infrastructure
delete_infrastructure() {
    local stack_name
    stack_name=$(get_stack_name)
    
    log "Deleting infrastructure stack: $stack_name"
    
    if ! stack_exists "$stack_name"; then
        error "Stack $stack_name does not exist."
        exit 1
    fi
    
    echo -n "Are you sure you want to delete the infrastructure? (y/N): "
    read -r confirmation
    
    if [[ "$confirmation" =~ ^[Yy]$ ]]; then
        log "Deleting CloudFormation stack..."
        aws cloudformation delete-stack \
            --stack-name "$stack_name" \
            --region "$REGION"
        
        log "Waiting for stack deletion to complete..."
        aws cloudformation wait stack-delete-complete \
            --stack-name "$stack_name" \
            --region "$REGION"
        
        log "Infrastructure deleted successfully!"
    else
        log "Deletion cancelled"
    fi
}

# Check infrastructure status
check_status() {
    local stack_name
    stack_name=$(get_stack_name)
    
    log "Checking infrastructure status: $stack_name"
    
    if stack_exists "$stack_name"; then
        aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$REGION" \
            --query 'Stacks[0].{StackName:StackName,StackStatus:StackStatus,CreationTime:CreationTime,LastUpdatedTime:LastUpdatedTime}' \
            --output table
        
        # Check Auto Scaling Groups
        log "Checking Auto Scaling Groups..."
        local blue_asg="${PROJECT_NAME}-${ENVIRONMENT}-blue-asg"
        local green_asg="${PROJECT_NAME}-${ENVIRONMENT}-green-asg"
        
        echo -e "\n${BLUE}Blue Auto Scaling Group:${NC}"
        aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$blue_asg" \
            --region "$REGION" \
            --query 'AutoScalingGroups[0].{GroupName:AutoScalingGroupName,DesiredCapacity:DesiredCapacity,MinSize:MinSize,MaxSize:MaxSize}' \
            --output table 2>/dev/null || echo "Blue ASG not found"
        
        echo -e "\n${BLUE}Green Auto Scaling Group:${NC}"
        aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$green_asg" \
            --region "$REGION" \
            --query 'AutoScalingGroups[0].{GroupName:AutoScalingGroupName,DesiredCapacity:DesiredCapacity,MinSize:MinSize,MaxSize:MaxSize}' \
            --output table 2>/dev/null || echo "Green ASG not found"
            
        # Check ALB Target Groups
        log "Checking ALB Target Groups health..."
        show_target_group_health
    else
        warn "Stack $stack_name does not exist"
    fi
}

# Show target group health
show_target_group_health() {
    local blue_tg="${PROJECT_NAME}-${ENVIRONMENT}-blue-tg"
    local green_tg="${PROJECT_NAME}-${ENVIRONMENT}-green-tg"
    
    echo -e "\n${BLUE}Blue Target Group Health:${NC}"
    local blue_tg_arn
    blue_tg_arn=$(aws elbv2 describe-target-groups \
        --names "$blue_tg" \
        --region "$REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null)
    
    if [[ "$blue_tg_arn" != "None" && "$blue_tg_arn" != "" ]]; then
        aws elbv2 describe-target-health \
            --target-group-arn "$blue_tg_arn" \
            --region "$REGION" \
            --query 'TargetHealthDescriptions[].{Target:Target.Id,Health:TargetHealth.State,Description:TargetHealth.Description}' \
            --output table
    else
        echo "Blue target group not found"
    fi
    
    echo -e "\n${BLUE}Green Target Group Health:${NC}"
    local green_tg_arn
    green_tg_arn=$(aws elbv2 describe-target-groups \
        --names "$green_tg" \
        --region "$REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null)
    
    if [[ "$green_tg_arn" != "None" && "$green_tg_arn" != "" ]]; then
        aws elbv2 describe-target-health \
            --target-group-arn "$green_tg_arn" \
            --region "$REGION" \
            --query 'TargetHealthDescriptions[].{Target:Target.Id,Health:TargetHealth.State,Description:TargetHealth.Description}' \
            --output table
    else
        echo "Green target group not found"
    fi
}

# Show CloudFormation outputs
show_outputs() {
    local stack_name="${1:-$(get_stack_name)}"
    
    log "CloudFormation Stack Outputs:"
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs' \
        --output table
    
    # Show ALB DNS name prominently
    local alb_dns
    alb_dns=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ApplicationLoadBalancerDNSName`].OutputValue' \
        --output text)
    
    if [[ "$alb_dns" != "None" && "$alb_dns" != "" ]]; then
        echo ""
        echo -e "${GREEN}🚀 Application Load Balancer URL: ${BLUE}http://$alb_dns${NC}"
        echo ""
    fi
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
        -k|--key-pair)
            KEY_PAIR="$2"
            shift 2
            ;;
        -t|--instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        deploy|update|delete|status|outputs)
            COMMAND="$1"
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

# Main execution
main() {
    log "Starting AWS Infrastructure Management"
    log "Project: $PROJECT_NAME"
    log "Environment: $ENVIRONMENT"
    log "Region: $REGION"
    log "Command: $COMMAND"
    
    check_prerequisites
    
    case "$COMMAND" in
        deploy)
            validate_template
            deploy_infrastructure
            ;;
        update)
            validate_template
            update_infrastructure
            ;;
        delete)
            delete_infrastructure
            ;;
        status)
            check_status
            ;;
        outputs)
            show_outputs
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