#!/bin/bash
echo "Starting Blue Server..."
node /app/blue-server/app.js &
echo "Starting Green Server..."
node /app/green-server/app.js &
echo "Starting API Server..."
node /app/api-server/app.js &
echo "Starting Nginx..."
nginx -g "daemon off;" &
wait
