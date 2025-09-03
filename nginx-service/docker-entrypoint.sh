#!/usr/bin/env bash
set -e

echo "🌐 Starting NGINX Blue-Green Proxy Service..."

# Initialize active environment if not set
if [[ ! -f /etc/nginx/conf.d/active.env ]]; then
    echo "🔵 Initializing with Blue environment as default..."
    echo 'set $active "blue";' > /etc/nginx/conf.d/active.env
fi

# Wait for backend services to be available
echo "⏳ Waiting for backend services..."
sleep 5

# Validate NGINX configuration
echo "🔍 Validating NGINX configuration..."
nginx -t

# Start NGINX in background for health monitoring
echo "🚀 Starting NGINX server..."
exec "$@"