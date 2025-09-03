#!/usr/bin/env bash
set -e

# Environment configuration
ENV_NAME="${ENV_NAME:-blue}"
SERVER_PORT="${SERVER_PORT:-3001}"

echo "🚀 Starting ${ENV_NAME} application server on port ${SERVER_PORT}..."

# Determine which server to start based on environment
if [[ "$ENV_NAME" == "green" ]]; then
    echo "🟢 Starting Green server..."
    export PORT=$SERVER_PORT
    node /app/green-server/app.js
elif [[ "$ENV_NAME" == "blue" ]]; then
    echo "🔵 Starting Blue server..."
    export PORT=$SERVER_PORT
    node /app/blue-server/app.js
else
    echo "❌ Invalid ENV_NAME: $ENV_NAME. Must be 'blue' or 'green'."
    exit 1
fi