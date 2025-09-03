#!/usr/bin/env bash
#
# NGINX Traffic Switching Script for Blue-Green Deployment
# This script runs inside the NGINX container
#

set -euo pipefail

ACTIVE_FILE="/etc/nginx/conf.d/active.env"
TARGET_COLOR="${1:-}"

# Validate input
if [[ "$TARGET_COLOR" != "blue" && "$TARGET_COLOR" != "green" ]]; then
    echo "Usage: $0 {blue|green}" >&2
    exit 1
fi

echo "🔄 Switching NGINX traffic to $TARGET_COLOR environment..."

# Health check target environment first
check_backend_health() {
    local color="$1"
    local port
    
    [[ "$color" == "green" ]] && port=3002 || port=3001
    
    echo "🏥 Checking $color backend health (port $port)..."
    
    for attempt in {1..10}; do
        if curl -fsS --max-time 2 --connect-timeout 1 "http://${color}-app:$port/health" >/dev/null 2>&1; then
            echo "✅ $color backend is healthy"
            return 0
        fi
        
        echo "⏳ $color backend not ready, attempt $attempt/10"
        [[ $attempt -lt 10 ]] && sleep 2
    done
    
    echo "❌ $color backend health check failed"
    return 1
}

# Check target environment health
if ! check_backend_health "$TARGET_COLOR"; then
    echo "❌ Cannot switch to $TARGET_COLOR - backend not healthy"
    exit 1
fi

# Get current active environment
get_current_active() {
    if [[ -f "$ACTIVE_FILE" ]]; then
        grep 'set.*active' "$ACTIVE_FILE" | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "blue"
    else
        echo "blue"
    fi
}

current_active=$(get_current_active)

# Skip if already active
if [[ "$TARGET_COLOR" == "$current_active" ]]; then
    echo "ℹ️  $TARGET_COLOR environment is already active"
    exit 0
fi

# Create atomic configuration update
temp_file=$(mktemp)
cat > "$temp_file" << EOF
# Active Environment Configuration
# This file controls which upstream group is active
# Current active: $TARGET_COLOR
set \$active "$TARGET_COLOR";
EOF

# Atomic replacement
if install -o root -g root -m 0644 "$temp_file" "$ACTIVE_FILE"; then
    echo "✅ Configuration updated atomically"
    rm -f "$temp_file"
else
    echo "❌ Failed to update configuration"
    rm -f "$temp_file"
    exit 1
fi

# Validate and reload NGINX
echo "🔍 Validating NGINX configuration..."
if nginx -t 2>/dev/null; then
    echo "✅ Configuration valid"
else
    echo "❌ Configuration validation failed, rolling back..."
    echo "set \$active \"$current_active\";" > "$ACTIVE_FILE"
    exit 1
fi

echo "🔄 Reloading NGINX..."
if nginx -s reload; then
    echo "✅ NGINX reloaded successfully"
    echo "🎉 Traffic switched from $current_active to $TARGET_COLOR"
else
    echo "❌ NGINX reload failed, rolling back..."
    echo "set \$active \"$current_active\";" > "$ACTIVE_FILE"
    nginx -s reload
    exit 1
fi

# Verify the switch worked
sleep 2
echo "🔍 Verifying traffic switch..."
if curl -fsS --max-time 3 "http://localhost:80/status" >/dev/null 2>&1; then
    echo "✅ Traffic switch verification successful"
    echo "📊 Active environment: $TARGET_COLOR"
else
    echo "⚠️  Traffic switch completed but verification had issues"
fi