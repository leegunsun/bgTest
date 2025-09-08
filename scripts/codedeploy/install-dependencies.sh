#!/bin/bash

# CodeDeploy AfterInstall Hook
# Install application dependencies and prepare for startup

set -e

LOG_FILE="/var/log/codedeploy/install-dependencies.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log "Starting AfterInstall hook..."

# Function to check Node.js and npm installation
check_nodejs() {
    log "Checking Node.js and npm installation..."
    
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed"
        return 1
    fi
    
    if ! command -v npm &> /dev/null; then
        error "npm is not installed"
        return 1
    fi
    
    local node_version
    node_version=$(node --version)
    local npm_version
    npm_version=$(npm --version)
    
    log "Node.js version: $node_version"
    log "npm version: $npm_version"
    
    # Check if Node.js version is acceptable (v16+)
    local major_version
    major_version=$(echo "$node_version" | sed 's/v\([0-9]*\)\..*/\1/')
    
    if [[ $major_version -lt 16 ]]; then
        error "Node.js version $node_version is too old. Need v16 or higher."
        return 1
    fi
    
    log "Node.js version check passed"
}

# Function to install npm dependencies
install_npm_dependencies() {
    log "Installing npm dependencies..."
    
    cd /opt/bluegreen-app
    
    # Check if package.json exists
    if [[ ! -f "package.json" ]]; then
        log "No package.json found, creating minimal one..."
        cat > package.json << 'EOF'
{
  "name": "bluegreen-app",
  "version": "1.0.0",
  "description": "Blue-Green Deployment Application",
  "main": "app-server/app.js",
  "scripts": {
    "start": "node app-server/app.js",
    "pm2": "pm2 start ecosystem.config.js",
    "pm2:stop": "pm2 stop ecosystem.config.js",
    "pm2:reload": "pm2 reload ecosystem.config.js",
    "health": "curl http://localhost:3001/health/deep"
  },
  "dependencies": {},
  "engines": {
    "node": ">=16.0.0"
  }
}
EOF
    fi
    
    # Clean npm cache if needed
    npm cache clean --force 2>/dev/null || true
    
    # Install production dependencies only
    log "Running npm ci for production dependencies..."
    npm ci --only=production --no-audit --no-fund 2>&1 | tee -a "$LOG_FILE"
    
    log "npm dependencies installed successfully"
}

# Function to check and install PM2 globally if needed
check_pm2() {
    log "Checking PM2 installation..."
    
    if ! command -v pm2 &> /dev/null; then
        log "PM2 not found, installing globally..."
        npm install -g pm2@latest 2>&1 | tee -a "$LOG_FILE"
        
        # Verify installation
        if ! command -v pm2 &> /dev/null; then
            error "Failed to install PM2"
            return 1
        fi
    fi
    
    local pm2_version
    pm2_version=$(pm2 --version)
    log "PM2 version: $pm2_version"
    
    # Initialize PM2 for ec2-user if not already done
    su - ec2-user -c "pm2 startup systemd -u ec2-user --hp /home/ec2-user" 2>&1 | tee -a "$LOG_FILE" || true
    
    log "PM2 check completed"
}

# Function to validate ecosystem configuration
validate_ecosystem_config() {
    log "Validating ecosystem configuration..."
    
    local ecosystem_file="/opt/bluegreen-app/ecosystem.config.js"
    
    if [[ ! -f "$ecosystem_file" ]]; then
        error "Ecosystem configuration file not found: $ecosystem_file"
        return 1
    fi
    
    # Test ecosystem configuration syntax
    su - ec2-user -c "cd /opt/bluegreen-app && pm2 prettylist --config ecosystem.config.js" &>/dev/null || {
        error "Ecosystem configuration has syntax errors"
        return 1
    }
    
    log "Ecosystem configuration is valid"
}

# Function to set up log rotation
setup_log_rotation() {
    log "Setting up log rotation..."
    
    # Create logrotate configuration for application logs
    cat > /etc/logrotate.d/bluegreen-app << 'EOF'
/opt/bluegreen-app/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 ec2-user ec2-user
    postrotate
        /usr/bin/pm2 reloadLogs 2>/dev/null || true
    endscript
}

/var/log/bluegreen/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 ec2-user ec2-user
}
EOF
    
    log "Log rotation configured"
}

# Function to prepare application configuration
prepare_app_config() {
    log "Preparing application configuration..."
    
    # Create application configuration directory
    mkdir -p /opt/bluegreen-app/config
    
    # Set deployment environment variables
    local env_file="/opt/bluegreen-app/config/deployment.env"
    cat > "$env_file" << EOF
# Deployment Configuration
DEPLOYMENT_ID=${DEPLOYMENT_ID:-$(date +%Y%m%d-%H%M%S)}
DEPLOYMENT_GROUP=${DEPLOYMENT_GROUP_NAME:-blue}
DEPLOYMENT_VERSION=${APPLICATION_VERSION:-1.0.0}
DEPLOYMENT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'unknown')
AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo 'unknown')

# Application Configuration
NODE_ENV=production
EOF
    
    chown ec2-user:ec2-user "$env_file"
    chmod 644 "$env_file"
    
    log "Application configuration prepared"
}

# Function to create health check script
create_health_check_script() {
    log "Creating health check script..."
    
    local health_script="/opt/bluegreen-app/scripts/health-check.sh"
    mkdir -p "$(dirname "$health_script")"
    
    cat > "$health_script" << 'EOF'
#!/bin/bash
# Application health check script

check_instance() {
    local port="$1"
    local instance_name="$2"
    
    # Check if process is running via PM2
    if ! pm2 list --no-daemon | grep -q "$instance_name.*online"; then
        echo "❌ $instance_name: PM2 process offline"
        return 1
    fi
    
    # Check if port is listening
    if ! netstat -tuln | grep -q ":$port "; then
        echo "❌ $instance_name: Port $port not listening"
        return 1
    fi
    
    # Check health endpoint
    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/health/deep" --max-time 5 || echo "000")
    
    if [[ "$http_status" == "200" ]]; then
        echo "✅ $instance_name: Healthy (HTTP $http_status)"
        return 0
    else
        echo "❌ $instance_name: Unhealthy (HTTP $http_status)"
        return 1
    fi
}

echo "=== Application Health Check ==="
echo "Timestamp: $(date)"
echo ""

all_healthy=true

check_instance 3001 "bluegreen-app-1" || all_healthy=false
check_instance 3002 "bluegreen-app-2" || all_healthy=false
check_instance 3003 "bluegreen-app-3" || all_healthy=false
check_instance 3004 "bluegreen-app-4" || all_healthy=false

echo ""
if [[ "$all_healthy" == "true" ]]; then
    echo "✅ All instances are healthy"
    exit 0
else
    echo "❌ Some instances are unhealthy"
    exit 1
fi
EOF
    
    chmod +x "$health_script"
    chown ec2-user:ec2-user "$health_script"
    
    log "Health check script created: $health_script"
}

# Function to set file permissions
set_file_permissions() {
    log "Setting file permissions..."
    
    # Ensure ec2-user owns the application directory
    chown -R ec2-user:ec2-user /opt/bluegreen-app
    
    # Set executable permissions for scripts
    find /opt/bluegreen-app -name "*.sh" -type f -exec chmod +x {} \;
    
    # Set read-only for configuration files
    find /opt/bluegreen-app -name "*.json" -type f -exec chmod 644 {} \;
    find /opt/bluegreen-app -name "*.yml" -type f -exec chmod 644 {} \;
    find /opt/bluegreen-app -name "*.yaml" -type f -exec chmod 644 {} \;
    
    # Set proper permissions for Node.js files
    find /opt/bluegreen-app -name "*.js" -type f -exec chmod 644 {} \;
    
    # Ensure log directory is writable
    chmod 755 /opt/bluegreen-app/logs
    
    log "File permissions set successfully"
}

# Function to validate installation
validate_installation() {
    log "Validating installation..."
    
    # Check if main application file exists
    if [[ ! -f "/opt/bluegreen-app/app-server/app.js" ]]; then
        error "Main application file not found: /opt/bluegreen-app/app-server/app.js"
        return 1
    fi
    
    # Check if ecosystem config exists and is valid
    if [[ ! -f "/opt/bluegreen-app/ecosystem.config.js" ]]; then
        error "Ecosystem configuration not found"
        return 1
    fi
    
    # Test Node.js syntax of main application
    su - ec2-user -c "cd /opt/bluegreen-app && node -c app-server/app.js" || {
        error "Main application has syntax errors"
        return 1
    }
    
    log "Installation validation passed"
}

# Main execution
main() {
    log "AfterInstall hook started"
    log "Working directory: $(pwd)"
    
    # Switch to application directory
    cd /opt/bluegreen-app
    
    # Check Node.js and npm
    check_nodejs
    
    # Install npm dependencies
    install_npm_dependencies
    
    # Check and install PM2
    check_pm2
    
    # Validate ecosystem configuration
    validate_ecosystem_config
    
    # Set up log rotation
    setup_log_rotation
    
    # Prepare application configuration
    prepare_app_config
    
    # Create health check script
    create_health_check_script
    
    # Set proper file permissions
    set_file_permissions
    
    # Validate installation
    validate_installation
    
    log "AfterInstall hook completed successfully"
}

# Execute main function
main "$@"