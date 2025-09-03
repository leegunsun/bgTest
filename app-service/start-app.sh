#!/usr/bin/env bash
set -e

# Environment configuration with enhanced defaults
ENV_NAME="${ENV_NAME:-blue}"
SERVER_PORT="${SERVER_PORT:-3001}"
VERSION="${VERSION:-1.0.0}"
COLOR_THEME="${COLOR_THEME:-${ENV_NAME}}"
DEPLOYMENT_ID="${DEPLOYMENT_ID:-${ENV_NAME}-$(date +%s)}"

echo "🚀 Starting True Blue-Green Application Server"
echo "   Environment: ${ENV_NAME}"
echo "   Port: ${SERVER_PORT}"
echo "   Version: ${VERSION}"
echo "   Theme: ${COLOR_THEME}"
echo "   Deployment ID: ${DEPLOYMENT_ID}"

# Create deployment metadata if directory exists
if [ -d "/app/deployment" ]; then
    echo "📝 Creating deployment metadata..."
    cat > /app/deployment/metadata.json << EOF
{
    "environment": "${ENV_NAME}",
    "version": "${VERSION}",
    "deployment_id": "${DEPLOYMENT_ID}",
    "build_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "commit_hash": "${CI_COMMIT_SHA:-unknown}",
    "branch": "${CI_COMMIT_BRANCH:-unknown}",
    "pipeline_id": "${CI_PIPELINE_ID:-unknown}",
    "color_theme": "${COLOR_THEME}",
    "port": "${SERVER_PORT}"
}
EOF
fi

# Export environment variables for the unified server
export PORT=$SERVER_PORT
export ENV_NAME
export VERSION
export COLOR_THEME
export DEPLOYMENT_ID

# Validate environment
if [[ "$ENV_NAME" != "blue" && "$ENV_NAME" != "green" ]]; then
    echo "⚠️  Warning: ENV_NAME is '${ENV_NAME}', expected 'blue' or 'green'"
    echo "   Continuing with unified server..."
fi

# Start the unified application server
echo "🌟 Starting unified application server..."
node /app/app-server/app.js