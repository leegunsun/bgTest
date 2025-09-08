#!/bin/bash

# PM2 Application Management Script
# Manages 4 Node.js application instances for Blue-Green deployment

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ECOSYSTEM_FILE="${PROJECT_ROOT}/ecosystem.config.js"
LOG_DIR="/opt/bluegreen-app/logs"

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
    echo "  start          Start all application instances"
    echo "  stop           Stop all application instances"
    echo "  restart        Restart all application instances"
    echo "  reload         Reload all application instances (zero-downtime)"
    echo "  status         Show status of all instances"
    echo "  logs           Show logs for all instances"
    echo "  logs [1-4]     Show logs for specific instance"
    echo "  health         Check health of all instances"
    echo "  scale [n]      Scale to n instances per port"
    echo "  delete         Delete all PM2 processes"
    echo "  setup          Initial setup and directory creation"
    echo ""
    echo "Options:"
    echo "  -e, --env ENV       Environment (production, staging) [default: production]"
    echo "  -v, --version VER   Deployment version"
    echo "  -g, --group GROUP   Deployment group (blue, green) [default: blue]"
    echo "  -h, --help          Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 start"
    echo "  $0 restart --env production --version 2.0.0 --group green"
    echo "  $0 logs 1"
    echo "  $0 health"
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
    # Check if PM2 is installed
    if ! command -v pm2 &> /dev/null; then
        error "PM2 is not installed. Please install it first:"
        error "npm install -g pm2"
        exit 1
    fi
    
    # Check if ecosystem file exists
    if [[ ! -f "$ECOSYSTEM_FILE" ]]; then
        error "Ecosystem file not found: $ECOSYSTEM_FILE"
        exit 1
    fi
    
    # Check if log directory exists
    if [[ ! -d "$LOG_DIR" ]]; then
        warn "Log directory does not exist: $LOG_DIR"
        info "Creating log directory..."
        sudo mkdir -p "$LOG_DIR"
        sudo chown -R $(whoami):$(whoami) "$LOG_DIR"
    fi
}

# Setup initial directories and permissions
setup() {
    log "Setting up PM2 environment..."
    
    # Create log directory
    sudo mkdir -p "$LOG_DIR"
    sudo chown -R $(whoami):$(whoami) "$LOG_DIR"
    
    # Create application directory if needed
    sudo mkdir -p "/opt/bluegreen-app"
    sudo chown -R $(whoami):$(whoami) "/opt/bluegreen-app"
    
    # Initialize PM2
    pm2 startup systemd -u $(whoami) --hp $(eval echo ~$(whoami)) || true
    
    log "Setup completed successfully"
}

# Start all application instances
start_apps() {
    log "Starting all application instances..."
    
    # Set environment variables
    export DEPLOYMENT_GROUP="${DEPLOYMENT_GROUP:-blue}"
    export DEPLOYMENT_VERSION="${DEPLOYMENT_VERSION:-1.0.0}"
    export DEPLOYMENT_ID="${DEPLOYMENT_ID:-$(date +%Y%m%d-%H%M%S)}"
    
    log "Configuration:"
    log "  Environment: ${ENVIRONMENT}"
    log "  Deployment Group: ${DEPLOYMENT_GROUP}"
    log "  Version: ${DEPLOYMENT_VERSION}"
    log "  Deployment ID: ${DEPLOYMENT_ID}"
    
    # Start with PM2
    pm2 start "$ECOSYSTEM_FILE" --env "${ENVIRONMENT}"
    
    # Save PM2 configuration
    pm2 save
    
    log "All instances started successfully"
}

# Stop all application instances
stop_apps() {
    log "Stopping all application instances..."
    
    pm2 stop "$ECOSYSTEM_FILE" || warn "Some processes may not have been running"
    
    log "All instances stopped"
}

# Restart all application instances
restart_apps() {
    log "Restarting all application instances..."
    
    # Set environment variables
    export DEPLOYMENT_GROUP="${DEPLOYMENT_GROUP:-blue}"
    export DEPLOYMENT_VERSION="${DEPLOYMENT_VERSION:-1.0.0}"
    export DEPLOYMENT_ID="${DEPLOYMENT_ID:-$(date +%Y%m%d-%H%M%S)}"
    
    pm2 restart "$ECOSYSTEM_FILE" --env "${ENVIRONMENT}"
    pm2 save
    
    log "All instances restarted successfully"
}

# Reload all application instances (zero-downtime)
reload_apps() {
    log "Reloading all application instances (zero-downtime)..."
    
    # Set environment variables
    export DEPLOYMENT_GROUP="${DEPLOYMENT_GROUP:-blue}"
    export DEPLOYMENT_VERSION="${DEPLOYMENT_VERSION:-1.0.0}"
    export DEPLOYMENT_ID="${DEPLOYMENT_ID:-$(date +%Y%m%d-%H%M%S)}"
    
    pm2 reload "$ECOSYSTEM_FILE" --env "${ENVIRONMENT}"
    pm2 save
    
    log "All instances reloaded successfully"
}

# Show status of all instances
show_status() {
    log "Application instances status:"
    
    pm2 list --no-daemon
    
    echo ""
    info "Memory usage:"
    pm2 monit --no-daemon | head -20
    
    echo ""
    info "Process details:"
    pm2 show all --no-daemon
}

# Show logs
show_logs() {
    local instance="$1"
    
    if [[ -n "$instance" ]]; then
        if [[ "$instance" =~ ^[1-4]$ ]]; then
            log "Showing logs for instance $instance:"
            pm2 logs "bluegreen-app-$instance" --lines 50
        else
            error "Invalid instance number: $instance. Use 1-4."
            exit 1
        fi
    else
        log "Showing logs for all instances:"
        pm2 logs --lines 20
    fi
}

# Check health of all instances
check_health() {
    log "Checking health of all application instances..."
    
    local all_healthy=true
    
    for i in {1..4}; do
        local port=$((3000 + i))
        local app_name="bluegreen-app-$i"
        
        info "Checking instance $i (port $port)..."
        
        # Check if PM2 process is running
        if pm2 list --no-daemon | grep -q "$app_name.*online"; then
            echo "  ✅ PM2 process: online"
        else
            echo "  ❌ PM2 process: offline"
            all_healthy=false
            continue
        fi
        
        # Check if port is listening
        if netstat -tuln | grep -q ":$port "; then
            echo "  ✅ Port $port: listening"
        else
            echo "  ❌ Port $port: not listening"
            all_healthy=false
            continue
        fi
        
        # Check application health endpoint
        local health_response
        health_response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$port/health/deep --max-time 5 2>/dev/null || echo "000")
        
        if [[ "$health_response" == "200" ]]; then
            echo "  ✅ Health endpoint: healthy"
        else
            echo "  ❌ Health endpoint: unhealthy (HTTP $health_response)"
            all_healthy=false
        fi
        
        echo ""
    done
    
    if [[ "$all_healthy" == "true" ]]; then
        log "✅ All instances are healthy"
        return 0
    else
        error "❌ Some instances are unhealthy"
        return 1
    fi
}

# Scale instances
scale_instances() {
    local scale_count="$1"
    
    if [[ ! "$scale_count" =~ ^[1-4]$ ]]; then
        error "Invalid scale count: $scale_count. Use 1-4."
        exit 1
    fi
    
    log "Scaling to $scale_count instances..."
    
    # Scale each app
    for i in {1..4}; do
        if [[ $i -le $scale_count ]]; then
            pm2 scale "bluegreen-app-$i" 1 --no-daemon || pm2 start "bluegreen-app-$i" --no-daemon || true
        else
            pm2 stop "bluegreen-app-$i" --no-daemon || true
        fi
    done
    
    pm2 save
    log "Scaled to $scale_count instances successfully"
}

# Delete all PM2 processes
delete_apps() {
    log "Deleting all PM2 processes..."
    
    echo -n "Are you sure you want to delete all PM2 processes? (y/N): "
    read -r confirmation
    
    if [[ "$confirmation" =~ ^[Yy]$ ]]; then
        pm2 delete all --no-daemon || warn "No processes to delete"
        pm2 save
        log "All processes deleted"
    else
        log "Deletion cancelled"
    fi
}

# Parse command line arguments
ENVIRONMENT="production"
DEPLOYMENT_GROUP="blue"
DEPLOYMENT_VERSION="1.0.0"

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -v|--version)
            DEPLOYMENT_VERSION="$2"
            shift 2
            ;;
        -g|--group)
            DEPLOYMENT_GROUP="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        start|stop|restart|reload|status|health|setup|delete)
            COMMAND="$1"
            shift
            ;;
        logs)
            COMMAND="logs"
            INSTANCE="$2"
            if [[ "$INSTANCE" =~ ^[1-4]$ ]]; then
                shift 2
            else
                shift
            fi
            ;;
        scale)
            COMMAND="scale"
            SCALE_COUNT="$2"
            shift 2
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

# Export environment variables
export DEPLOYMENT_GROUP
export DEPLOYMENT_VERSION
export DEPLOYMENT_ID="${DEPLOYMENT_ID:-$(date +%Y%m%d-%H%M%S)}"

# Main execution
main() {
    log "PM2 Application Management"
    log "Environment: $ENVIRONMENT"
    log "Command: $COMMAND"
    
    if [[ "$COMMAND" != "setup" ]]; then
        check_prerequisites
    fi
    
    case "$COMMAND" in
        setup)
            setup
            ;;
        start)
            start_apps
            ;;
        stop)
            stop_apps
            ;;
        restart)
            restart_apps
            ;;
        reload)
            reload_apps
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "$INSTANCE"
            ;;
        health)
            check_health
            ;;
        scale)
            scale_instances "$SCALE_COUNT"
            ;;
        delete)
            delete_apps
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