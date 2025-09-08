#!/bin/bash

# CodeDeploy ApplicationStart Hook
# Start application services using PM2

set -e

LOG_FILE="/var/log/codedeploy/start-services.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log "Starting ApplicationStart hook..."

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set deployment-specific environment variables
    export DEPLOYMENT_ID="${DEPLOYMENT_ID:-$(date +%Y%m%d-%H%M%S)}"
    export DEPLOYMENT_GROUP="${DEPLOYMENT_GROUP_NAME:-blue}"
    export DEPLOYMENT_VERSION="${APPLICATION_VERSION:-1.0.0}"
    export NODE_ENV="production"
    
    # Get instance metadata
    export INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'unknown')
    export AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo 'unknown')
    
    log "Environment variables set:"
    log "  DEPLOYMENT_ID: $DEPLOYMENT_ID"
    log "  DEPLOYMENT_GROUP: $DEPLOYMENT_GROUP"
    log "  DEPLOYMENT_VERSION: $DEPLOYMENT_VERSION"
    log "  INSTANCE_ID: $INSTANCE_ID"
    log "  AVAILABILITY_ZONE: $AVAILABILITY_ZONE"
}

# Function to start PM2 applications
start_pm2_applications() {
    log "Starting PM2 applications..."
    
    # Change to application directory
    cd /opt/bluegreen-app
    
    # Export environment variables for PM2
    export DEPLOYMENT_GROUP
    export DEPLOYMENT_VERSION  
    export DEPLOYMENT_ID
    export NODE_ENV
    
    # Run as ec2-user
    su - ec2-user << 'EOF'
        set -e
        
        # Change to application directory
        cd /opt/bluegreen-app
        
        # Export environment variables
        export DEPLOYMENT_GROUP="${DEPLOYMENT_GROUP}"
        export DEPLOYMENT_VERSION="${DEPLOYMENT_VERSION}"
        export DEPLOYMENT_ID="${DEPLOYMENT_ID}"
        export NODE_ENV="${NODE_ENV}"
        
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting PM2 applications as ec2-user..."
        
        # Start applications with PM2
        pm2 start ecosystem.config.js --env production
        
        # Save PM2 configuration
        pm2 save
        
        # Show PM2 status
        pm2 list
        
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] PM2 applications started successfully"
EOF
    
    log "PM2 applications started successfully"
}

# Function to wait for applications to become ready
wait_for_applications() {
    log "Waiting for applications to become ready..."
    
    local max_wait=120  # 2 minutes
    local wait_interval=5
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local healthy_count=0
        
        # Check each application port
        for port in 3001 3002 3003 3004; do
            if curl -s -f http://localhost:$port/health >/dev/null 2>&1; then
                ((healthy_count++))
            fi
        done
        
        log "Health check: $healthy_count/4 instances responding"
        
        if [[ $healthy_count -eq 4 ]]; then
            log "All applications are ready!"
            return 0
        fi
        
        log "Waiting for applications to be ready... (${elapsed}s/${max_wait}s)"
        sleep $wait_interval
        ((elapsed += wait_interval))
    done
    
    error "Applications did not become ready within $max_wait seconds"
    return 1
}

# Function to verify PM2 processes
verify_pm2_processes() {
    log "Verifying PM2 processes..."
    
    # Run verification as ec2-user
    su - ec2-user << 'EOF'
        set -e
        
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Checking PM2 process status..."
        
        # Check if all 4 processes are online
        local online_count
        online_count=$(pm2 list --no-daemon | grep -c "online" || echo "0")
        
        if [[ $online_count -eq 4 ]]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] All 4 PM2 processes are online"
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Only $online_count/4 PM2 processes are online"
            pm2 list --no-daemon
            exit 1
        fi
        
        # Check individual process status
        for i in {1..4}; do
            local app_name="bluegreen-app-$i"
            if pm2 list --no-daemon | grep -q "$app_name.*online"; then
                echo "[$(date +'%Y-%m-%d %H:%M:%S')] $app_name: Online ✅"
            else
                echo "[$(date +'%Y-%m-%d %H:%M:%S')] $app_name: Offline ❌"
                exit 1
            fi
        done
EOF
    
    log "PM2 process verification completed successfully"
}

# Function to verify port accessibility
verify_port_accessibility() {
    log "Verifying port accessibility..."
    
    local failed_ports=()
    
    for port in 3001 3002 3003 3004; do
        if netstat -tuln | grep -q ":$port "; then
            log "Port $port: Listening ✅"
        else
            log "Port $port: Not listening ❌"
            failed_ports+=($port)
        fi
    done
    
    if [[ ${#failed_ports[@]} -gt 0 ]]; then
        error "Some ports are not accessible: ${failed_ports[*]}"
        return 1
    fi
    
    log "All ports are accessible"
}

# Function to create startup status file
create_startup_status() {
    log "Creating startup status file..."
    
    local status_file="/opt/bluegreen-app/startup-status.json"
    
    cat > "$status_file" << EOF
{
    "startup": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "status": "completed",
        "deployment_id": "$DEPLOYMENT_ID",
        "deployment_group": "$DEPLOYMENT_GROUP",
        "version": "$DEPLOYMENT_VERSION"
    },
    "services": {
        "pm2_processes": 4,
        "nginx": "$(systemctl is-active nginx)",
        "codedeploy_agent": "$(systemctl is-active codedeploy-agent)"
    },
    "ports": {
        "3001": "$(netstat -tuln | grep -q ':3001 ' && echo 'listening' || echo 'not-listening')",
        "3002": "$(netstat -tuln | grep -q ':3002 ' && echo 'listening' || echo 'not-listening')",
        "3003": "$(netstat -tuln | grep -q ':3003 ' && echo 'listening' || echo 'not-listening')",
        "3004": "$(netstat -tuln | grep -q ':3004 ' && echo 'listening' || echo 'not-listening')"
    }
}
EOF
    
    chown ec2-user:ec2-user "$status_file"
    chmod 644 "$status_file"
    
    log "Startup status file created: $status_file"
}

# Function to enable PM2 startup
enable_pm2_startup() {
    log "Enabling PM2 startup on system boot..."
    
    # Run as ec2-user to set up PM2 startup
    su - ec2-user << 'EOF'
        # Generate startup script
        pm2 startup systemd -u ec2-user --hp /home/ec2-user
        
        # Save current PM2 configuration
        pm2 save
        
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] PM2 startup configuration saved"
EOF
    
    # Enable the PM2 systemd service
    systemctl enable pm2-ec2-user || log "PM2 systemd service may already be enabled"
    
    log "PM2 startup enabled successfully"
}

# Function to start essential system services
start_system_services() {
    log "Starting essential system services..."
    
    # Ensure NGINX is running
    if ! systemctl is-active nginx &>/dev/null; then
        log "Starting NGINX..."
        systemctl start nginx
    fi
    
    # Ensure CodeDeploy agent is running
    if ! systemctl is-active codedeploy-agent &>/dev/null; then
        log "Starting CodeDeploy agent..."
        systemctl start codedeploy-agent
    fi
    
    # Start CloudWatch agent if available
    if command -v /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl &> /dev/null; then
        /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a start || log "CloudWatch agent start attempted"
    fi
    
    log "System services started"
}

# Function to run post-startup validation
run_post_startup_validation() {
    log "Running post-startup validation..."
    
    # Run the health check script
    if [[ -f "/opt/bluegreen-app/scripts/health-check.sh" ]]; then
        log "Running comprehensive health check..."
        su - ec2-user -c "/opt/bluegreen-app/scripts/health-check.sh" 2>&1 | tee -a "$LOG_FILE"
        
        if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
            log "Health check passed ✅"
        else
            error "Health check failed ❌"
            return 1
        fi
    else
        log "Health check script not found, performing basic checks..."
        
        # Basic PM2 check
        verify_pm2_processes
        
        # Basic port check
        verify_port_accessibility
    fi
}

# Main execution
main() {
    log "ApplicationStart hook started"
    
    # Set environment variables
    set_environment_variables
    
    # Start system services
    start_system_services
    
    # Start PM2 applications
    start_pm2_applications
    
    # Wait for applications to become ready
    wait_for_applications
    
    # Verify PM2 processes
    verify_pm2_processes
    
    # Verify port accessibility
    verify_port_accessibility
    
    # Enable PM2 startup
    enable_pm2_startup
    
    # Create startup status file
    create_startup_status
    
    # Run post-startup validation
    run_post_startup_validation
    
    log "ApplicationStart hook completed successfully"
    log "🚀 Blue-Green application is now running with 4 instances"
    
    # Display final status
    log "Final status:"
    su - ec2-user -c "pm2 list" 2>&1 | tee -a "$LOG_FILE"
}

# Execute main function
main "$@"