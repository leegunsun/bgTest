#!/bin/bash

# CodeDeploy BeforeInstall Hook
# Prepare deployment environment and directories

set -e

LOG_FILE="/var/log/codedeploy/prepare-environment.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log "Starting BeforeInstall hook..."

# Function to create required directories
create_directories() {
    log "Creating required directories..."
    
    local directories=(
        "/opt/bluegreen-app"
        "/opt/bluegreen-app/logs"
        "/opt/bluegreen-app/temp"
        "/opt/bluegreen-app/config"
        "/opt/bluegreen-app/backups"
        "/var/log/bluegreen"
        "/var/log/codedeploy"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log "Created directory: $dir"
        else
            log "Directory already exists: $dir"
        fi
    done
    
    log "All directories created successfully"
}

# Function to set proper ownership and permissions
set_permissions() {
    log "Setting ownership and permissions..."
    
    # Set ownership to ec2-user
    chown -R ec2-user:ec2-user /opt/bluegreen-app
    chown -R ec2-user:ec2-user /var/log/bluegreen
    
    # Set directory permissions
    find /opt/bluegreen-app -type d -exec chmod 755 {} \;
    find /var/log/bluegreen -type d -exec chmod 755 {} \;
    
    # Set file permissions (will be adjusted later for scripts)
    find /opt/bluegreen-app -type f -exec chmod 644 {} \;
    
    log "Permissions set successfully"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Clean up any temporary files from previous deployments
    if [[ -d "/opt/bluegreen-app/temp" ]]; then
        rm -rf /opt/bluegreen-app/temp/*
        log "Temporary files cleaned"
    fi
    
    # Clean up old log files (keep last 7 days)
    if [[ -d "/opt/bluegreen-app/logs" ]]; then
        find /opt/bluegreen-app/logs -name "*.log" -mtime +7 -delete 2>/dev/null || true
        log "Old log files cleaned"
    fi
    
    # Clean up old backups (keep last 5)
    local backup_count
    backup_count=$(ls -d /opt/bluegreen-app-backup-* 2>/dev/null | wc -l)
    if [[ $backup_count -gt 5 ]]; then
        ls -d /opt/bluegreen-app-backup-* | head -n $((backup_count - 5)) | xargs rm -rf
        log "Old backups cleaned up"
    fi
}

# Function to prepare NGINX configuration
prepare_nginx() {
    log "Preparing NGINX configuration..."
    
    # Create NGINX configuration directory if it doesn't exist
    mkdir -p /etc/nginx/conf.d
    
    # Backup existing NGINX configuration
    if [[ -f "/etc/nginx/nginx.conf" ]]; then
        cp /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.backup.$(date +%Y%m%d-%H%M%S)"
        log "NGINX configuration backed up"
    fi
    
    # Ensure NGINX is installed and configured
    if ! command -v nginx &> /dev/null; then
        log "NGINX not found, it should be installed during instance setup"
    else
        # Test NGINX configuration syntax
        nginx -t &>/dev/null || {
            error "NGINX configuration has syntax errors"
            return 1
        }
        log "NGINX configuration syntax is valid"
    fi
}

# Function to check system resources
check_system_resources() {
    log "Checking system resources..."
    
    # Check disk space
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ $disk_usage -gt 85 ]]; then
        error "Disk usage is at ${disk_usage}%, which is too high for deployment"
        return 1
    else
        log "Disk usage: ${disk_usage}% - OK"
    fi
    
    # Check memory
    local mem_available
    mem_available=$(free -m | awk 'NR==2{printf "%.0f", $7*100/$2}')
    
    if [[ $mem_available -lt 10 ]]; then
        error "Available memory is less than 10%, which may cause deployment issues"
        return 1
    else
        log "Available memory: ${mem_available}% - OK"
    fi
    
    # Check if CodeDeploy agent is running
    if systemctl is-active codedeploy-agent &>/dev/null; then
        log "CodeDeploy agent is running - OK"
    else
        error "CodeDeploy agent is not running"
        systemctl start codedeploy-agent || {
            error "Failed to start CodeDeploy agent"
            return 1
        }
        log "CodeDeploy agent started"
    fi
}

# Function to set deployment metadata
set_deployment_metadata() {
    log "Setting deployment metadata..."
    
    local metadata_file="/opt/bluegreen-app/deployment-metadata.json"
    
    # Create deployment metadata
    cat > "$metadata_file" << EOF
{
    "deployment_id": "${DEPLOYMENT_ID:-unknown}",
    "deployment_group": "${DEPLOYMENT_GROUP_NAME:-unknown}",
    "application_name": "${APPLICATION_NAME:-bluegreen-app}",
    "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "codedeploy_deployment_id": "${CODEDEPLOY_DEPLOYMENT_ID:-unknown}",
    "instance_id": "$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'unknown')",
    "availability_zone": "$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo 'unknown')",
    "instance_type": "$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo 'unknown')"
}
EOF
    
    chown ec2-user:ec2-user "$metadata_file"
    log "Deployment metadata created: $metadata_file"
}

# Function to prepare PM2 environment
prepare_pm2() {
    log "Preparing PM2 environment..."
    
    # Switch to ec2-user for PM2 operations
    su - ec2-user -c "
        # Initialize PM2 if not already done
        pm2 startup systemd -u ec2-user --hp /home/ec2-user 2>/dev/null || true
        
        # Create PM2 log directory
        mkdir -p /home/ec2-user/.pm2/logs
        
        # Set PM2 environment
        pm2 set pm2:log-date-format 'YYYY-MM-DD HH:mm:ss Z'
    " 2>&1 | tee -a "$LOG_FILE"
    
    log "PM2 environment prepared"
}

# Main execution
main() {
    log "BeforeInstall hook started"
    
    # Create required directories
    create_directories
    
    # Set proper permissions
    set_permissions
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Prepare NGINX configuration
    prepare_nginx
    
    # Check system resources
    check_system_resources
    
    # Set deployment metadata
    set_deployment_metadata
    
    # Prepare PM2 environment
    prepare_pm2
    
    log "BeforeInstall hook completed successfully"
}

# Execute main function
main "$@"