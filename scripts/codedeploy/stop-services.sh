#!/bin/bash

# CodeDeploy ApplicationStop Hook
# Stop running application services before new deployment

set -e

LOG_FILE="/var/log/codedeploy/stop-services.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log "Starting ApplicationStop hook..."

# Function to safely stop PM2 processes
stop_pm2_processes() {
    log "Stopping PM2 processes..."
    
    if command -v pm2 &> /dev/null; then
        # Stop specific application processes
        pm2 stop bluegreen-app-1 || log "bluegreen-app-1 was not running"
        pm2 stop bluegreen-app-2 || log "bluegreen-app-2 was not running"
        pm2 stop bluegreen-app-3 || log "bluegreen-app-3 was not running"
        pm2 stop bluegreen-app-4 || log "bluegreen-app-4 was not running"
        
        # Delete processes to ensure clean start
        pm2 delete bluegreen-app-1 || log "bluegreen-app-1 was not in PM2 list"
        pm2 delete bluegreen-app-2 || log "bluegreen-app-2 was not in PM2 list"
        pm2 delete bluegreen-app-3 || log "bluegreen-app-3 was not in PM2 list"
        pm2 delete bluegreen-app-4 || log "bluegreen-app-4 was not in PM2 list"
        
        # Save PM2 configuration
        pm2 save
        
        log "PM2 processes stopped successfully"
    else
        log "PM2 not found, skipping PM2 process stop"
    fi
}

# Function to stop any Node.js processes on our ports
stop_nodejs_processes() {
    log "Checking for Node.js processes on application ports..."
    
    for port in 3001 3002 3003 3004; do
        local pid
        pid=$(lsof -ti:$port 2>/dev/null || true)
        
        if [[ -n "$pid" ]]; then
            log "Found process $pid on port $port, stopping..."
            kill -TERM "$pid" || true
            
            # Wait up to 10 seconds for graceful shutdown
            local count=0
            while kill -0 "$pid" 2>/dev/null && [[ $count -lt 10 ]]; do
                sleep 1
                ((count++))
            done
            
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                log "Process $pid did not stop gracefully, force killing..."
                kill -KILL "$pid" || true
            fi
            
            log "Process on port $port stopped"
        else
            log "No process found on port $port"
        fi
    done
}

# Function to create backup of current deployment
backup_current_deployment() {
    if [[ -d "/opt/bluegreen-app" ]]; then
        log "Creating backup of current deployment..."
        
        local backup_dir="/opt/bluegreen-app-backup-$(date +%Y%m%d-%H%M%S)"
        cp -r "/opt/bluegreen-app" "$backup_dir" || {
            error "Failed to create backup"
            return 1
        }
        
        # Keep only last 3 backups
        local backup_count
        backup_count=$(ls -d /opt/bluegreen-app-backup-* 2>/dev/null | wc -l)
        if [[ $backup_count -gt 3 ]]; then
            ls -d /opt/bluegreen-app-backup-* | head -n $((backup_count - 3)) | xargs rm -rf
            log "Cleaned up old backups"
        fi
        
        log "Backup created: $backup_dir"
    else
        log "No existing deployment found to backup"
    fi
}

# Main execution
main() {
    log "ApplicationStop hook started"
    
    # Stop application processes
    stop_pm2_processes
    
    # Stop any remaining Node.js processes on our ports
    stop_nodejs_processes
    
    # Create backup of current deployment
    backup_current_deployment
    
    # Wait a moment for processes to fully terminate
    sleep 2
    
    # Verify no processes are running on our ports
    local active_processes=false
    for port in 3001 3002 3003 3004; do
        if lsof -ti:$port &>/dev/null; then
            error "Process still running on port $port after stop attempt"
            active_processes=true
        fi
    done
    
    if [[ "$active_processes" == "true" ]]; then
        error "Some processes are still running on application ports"
        exit 1
    fi
    
    log "ApplicationStop hook completed successfully"
}

# Execute main function
main "$@"