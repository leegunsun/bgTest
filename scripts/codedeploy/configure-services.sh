#!/bin/bash

# CodeDeploy BeforeStart Hook
# Configure NGINX and application services

set -e

LOG_FILE="/var/log/codedeploy/configure-services.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log "Starting BeforeStart hook..."

# Function to configure NGINX for ALB integration
configure_nginx() {
    log "Configuring NGINX for ALB integration..."
    
    # Copy the new NGINX configuration if it exists
    if [[ -f "/opt/bluegreen-app/nginx-alb.conf" ]]; then
        log "Installing enhanced NGINX configuration..."
        cp /opt/bluegreen-app/nginx-alb.conf /etc/nginx/nginx.conf
        
        # Copy upstream configuration
        if [[ -f "/opt/bluegreen-app/conf.d/upstreams-alb.conf" ]]; then
            cp /opt/bluegreen-app/conf.d/upstreams-alb.conf /etc/nginx/conf.d/upstreams-alb.conf
            log "Upstream configuration installed"
        fi
    else
        log "Using existing NGINX configuration"
    fi
    
    # Ensure NGINX configuration directory exists
    mkdir -p /etc/nginx/conf.d
    
    # Test NGINX configuration
    if nginx -t; then
        log "NGINX configuration test passed"
    else
        error "NGINX configuration test failed"
        return 1
    fi
    
    # Enable and start NGINX
    systemctl enable nginx
    
    # Restart NGINX to load new configuration
    if systemctl is-active nginx &>/dev/null; then
        log "Reloading NGINX configuration..."
        systemctl reload nginx
    else
        log "Starting NGINX..."
        systemctl start nginx
    fi
    
    # Verify NGINX is running
    if systemctl is-active nginx &>/dev/null; then
        log "NGINX configured and running successfully"
    else
        error "NGINX failed to start"
        return 1
    fi
}

# Function to configure CloudWatch logs agent
configure_cloudwatch_logs() {
    log "Configuring CloudWatch logs agent..."
    
    # Create CloudWatch agent configuration
    local config_file="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
    
    if command -v /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl &> /dev/null; then
        cat > "$config_file" << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/opt/bluegreen-app/logs/app-*.log",
                        "log_group_name": "/aws/ec2/bluegreen-app",
                        "log_stream_name": "{instance_id}/application/{hostname}",
                        "timestamp_format": "%Y-%m-%d %H:%M:%S"
                    },
                    {
                        "file_path": "/var/log/nginx/access.log",
                        "log_group_name": "/aws/ec2/nginx",
                        "log_stream_name": "{instance_id}/access/{hostname}",
                        "timestamp_format": "[%d/%b/%Y:%H:%M:%S %z]"
                    },
                    {
                        "file_path": "/var/log/nginx/error.log",
                        "log_group_name": "/aws/ec2/nginx",
                        "log_stream_name": "{instance_id}/error/{hostname}",
                        "timestamp_format": "%Y/%m/%d %H:%M:%S"
                    },
                    {
                        "file_path": "/var/log/codedeploy/*.log",
                        "log_group_name": "/aws/codedeploy/deployment",
                        "log_stream_name": "{instance_id}/{hostname}",
                        "timestamp_format": "[%Y-%m-%d %H:%M:%S]"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "BlueGreen/Application",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "/"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF
        
        # Start CloudWatch agent with new configuration
        /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
            -a fetch-config \
            -m ec2 \
            -s \
            -c file:"$config_file" &>/dev/null || log "CloudWatch agent configuration applied"
            
        log "CloudWatch logs agent configured"
    else
        log "CloudWatch agent not found, skipping logs configuration"
    fi
}

# Function to configure system limits for Node.js applications
configure_system_limits() {
    log "Configuring system limits for Node.js applications..."
    
    # Set up limits for ec2-user (Node.js processes)
    cat > /etc/security/limits.d/nodejs.conf << EOF
# Limits for Node.js applications
ec2-user    soft    nofile    65536
ec2-user    hard    nofile    65536
ec2-user    soft    nproc     4096
ec2-user    hard    nproc     4096
EOF
    
    # Configure systemd limits for PM2
    mkdir -p /etc/systemd/system/pm2-ec2-user.service.d
    cat > /etc/systemd/system/pm2-ec2-user.service.d/limits.conf << EOF
[Service]
LimitNOFILE=65536
LimitNPROC=4096
EOF
    
    # Reload systemd
    systemctl daemon-reload
    
    log "System limits configured"
}

# Function to setup monitoring scripts
setup_monitoring() {
    log "Setting up monitoring scripts..."
    
    # Create monitoring script directory
    mkdir -p /opt/bluegreen-app/monitoring
    
    # Create instance monitoring script
    cat > /opt/bluegreen-app/monitoring/instance-monitor.sh << 'EOF'
#!/bin/bash
# Instance monitoring script

LOG_FILE="/opt/bluegreen-app/logs/monitor.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check disk usage
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $DISK_USAGE -gt 80 ]]; then
    log "WARNING: Disk usage is at ${DISK_USAGE}%"
fi

# Check memory usage
MEM_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
if [[ $MEM_USAGE -gt 80 ]]; then
    log "WARNING: Memory usage is at ${MEM_USAGE}%"
fi

# Check PM2 processes
PM2_STATUS=$(pm2 list --no-daemon | grep -c "online" || echo "0")
if [[ $PM2_STATUS -lt 4 ]]; then
    log "WARNING: Only $PM2_STATUS/4 PM2 processes are online"
fi

# Check NGINX status
if ! systemctl is-active nginx &>/dev/null; then
    log "ERROR: NGINX is not running"
fi

log "Monitor check completed - Disk: ${DISK_USAGE}%, Mem: ${MEM_USAGE}%, PM2: ${PM2_STATUS}/4"
EOF
    
    chmod +x /opt/bluegreen-app/monitoring/instance-monitor.sh
    chown ec2-user:ec2-user /opt/bluegreen-app/monitoring/instance-monitor.sh
    
    # Create cron job for monitoring (every 5 minutes)
    cat > /etc/cron.d/bluegreen-monitor << EOF
# Monitor Blue-Green application every 5 minutes
*/5 * * * * ec2-user /opt/bluegreen-app/monitoring/instance-monitor.sh
EOF
    
    log "Monitoring scripts configured"
}

# Function to configure firewall if needed
configure_firewall() {
    log "Checking firewall configuration..."
    
    # Check if firewalld is running (Amazon Linux 2 uses iptables by default)
    if systemctl is-active firewalld &>/dev/null; then
        log "Configuring firewalld..."
        
        # Allow HTTP traffic
        firewall-cmd --permanent --add-service=http
        
        # Allow application ports (internal only)
        for port in 3001 3002 3003 3004; do
            firewall-cmd --permanent --add-port="$port/tcp" --zone=internal
        done
        
        # Reload firewalld
        firewall-cmd --reload
        
        log "Firewalld configured"
    else
        log "Firewalld not active, using default iptables configuration"
    fi
}

# Function to prepare deployment metadata
prepare_deployment_metadata() {
    log "Preparing deployment metadata..."
    
    local metadata_file="/opt/bluegreen-app/deployment-info.json"
    
    # Get instance metadata from EC2
    local instance_id
    instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
    
    local instance_type
    instance_type=$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "unknown")
    
    local az
    az=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo "unknown")
    
    # Create comprehensive deployment metadata
    cat > "$metadata_file" << EOF
{
    "deployment": {
        "id": "${DEPLOYMENT_ID:-unknown}",
        "group": "${DEPLOYMENT_GROUP_NAME:-unknown}",
        "application": "${APPLICATION_NAME:-bluegreen-app}",
        "version": "${APPLICATION_VERSION:-1.0.0}",
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "codedeploy_deployment_id": "${CODEDEPLOY_DEPLOYMENT_ID:-unknown}"
    },
    "instance": {
        "id": "$instance_id",
        "type": "$instance_type",
        "availability_zone": "$az",
        "private_ip": "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo 'unknown')",
        "public_ip": "$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'none')"
    },
    "configuration": {
        "nginx_config": "/etc/nginx/nginx.conf",
        "pm2_ecosystem": "/opt/bluegreen-app/ecosystem.config.js",
        "log_directory": "/opt/bluegreen-app/logs",
        "application_ports": [3001, 3002, 3003, 3004]
    },
    "health_endpoints": {
        "nginx": "http://localhost/health",
        "application_deep": "http://localhost/health/deep",
        "instances": [
            "http://localhost:3001/health/deep",
            "http://localhost:3002/health/deep",
            "http://localhost:3003/health/deep",
            "http://localhost:3004/health/deep"
        ]
    }
}
EOF
    
    chown ec2-user:ec2-user "$metadata_file"
    chmod 644 "$metadata_file"
    
    log "Deployment metadata prepared: $metadata_file"
}

# Main execution
main() {
    log "BeforeStart hook started"
    
    # Configure NGINX
    configure_nginx
    
    # Configure CloudWatch logs
    configure_cloudwatch_logs
    
    # Configure system limits
    configure_system_limits
    
    # Setup monitoring
    setup_monitoring
    
    # Configure firewall
    configure_firewall
    
    # Prepare deployment metadata
    prepare_deployment_metadata
    
    log "BeforeStart hook completed successfully"
}

# Execute main function
main "$@"