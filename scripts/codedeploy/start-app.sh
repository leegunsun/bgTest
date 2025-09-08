#!/bin/bash
set -euo pipefail
LOGFILE=/var/log/codedeploy/hooks-start.log
exec 2>>${LOGFILE}
exec 1>>${LOGFILE}

echo "=== ApplicationStart Hook Started: $(date) ===" >> ${LOGFILE}

cd /opt/bluegreen-app

# Start app via PM2 ecosystem (환경에 맞게 변경)
if command -v pm2 >/dev/null 2>&1; then
    echo "Starting application with PM2..." >> ${LOGFILE}
    if [ -f ecosystem.config.js ]; then
        pm2 startOrReload ecosystem.config.js --env production
        echo "PM2 ecosystem started successfully" >> ${LOGFILE}
    else
        echo "ecosystem.config.js not found, using fallback startup" >> ${LOGFILE}
        # Fallback: start with basic PM2 configuration
        pm2 start app-server/app.js --name bluegreen-app --instances 4 --env production || {
            echo "PM2 startup failed, trying Node.js directly" >> ${LOGFILE}
            nohup node app-server/app.js &
        }
    fi
    
    # Display PM2 status
    pm2 status >> ${LOGFILE} 2>&1
    
else
    echo "PM2 not found, starting with Node.js directly..." >> ${LOGFILE}
    # Fallback: node server.js &
    nohup node app-server/app.js &
fi

# Restart nginx to pickup config changes
if systemctl is-active --quiet nginx; then
    echo "Restarting NGINX to apply configuration changes..." >> ${LOGFILE}
    systemctl restart nginx || nginx -s reload || true
    echo "NGINX restarted successfully" >> ${LOGFILE}
fi

# Give some time for services to warm up
echo "Waiting for services to warm up..." >> ${LOGFILE}
sleep 3

# Basic service validation
echo "Performing basic health check..." >> ${LOGFILE}
for i in {1..5}; do
    if curl -f http://localhost/health >/dev/null 2>&1; then
        echo "Basic health check passed on attempt $i" >> ${LOGFILE}
        break
    elif [ $i -eq 5 ]; then
        echo "Warning: Basic health check failed after $i attempts" >> ${LOGFILE}
    else
        echo "Health check attempt $i failed, retrying..." >> ${LOGFILE}
        sleep 2
    fi
done

echo "ApplicationStart complete: $(date)" >> ${LOGFILE}
echo "=== ApplicationStart Hook Finished: $(date) ===" >> ${LOGFILE}