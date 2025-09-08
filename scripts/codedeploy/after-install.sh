#!/bin/bash
set -euo pipefail
LOGFILE=/var/log/codedeploy/hooks-after_install.log
exec 2>>${LOGFILE}
exec 1>>${LOGFILE}

echo "=== AfterInstall Hook Started: $(date) ===" >> ${LOGFILE}

cd /opt/bluegreen-app || exit 1

# Install dependencies (Node example -- adjust for your stack)
if [ -f package.json ]; then
    echo "Installing Node.js dependencies..." >> ${LOGFILE}
    # Use npm ci for reproducible installs
    npm ci --production
    echo "Node.js dependencies installed successfully" >> ${LOGFILE}
fi

# Apply nginx config if present in artifact
if [ -f nginx-alb.conf ]; then
    echo "Applying NGINX configuration..." >> ${LOGFILE}
    cp nginx-alb.conf /etc/nginx/conf.d/bluegreen_app.conf
    echo "NGINX configuration applied" >> ${LOGFILE}
fi

# Apply upstream configuration if present
if [ -d conf.d ]; then
    echo "Applying NGINX upstream configuration..." >> ${LOGFILE}
    cp conf.d/*.conf /etc/nginx/conf.d/ || true
    echo "NGINX upstream configuration applied" >> ${LOGFILE}
fi

# Set proper ownership
chown -R ec2-user:ec2-user /opt/bluegreen-app || true

# Validate configuration files
if [ -f ecosystem.config.js ]; then
    echo "Validating PM2 ecosystem configuration..." >> ${LOGFILE}
    node -e "require('./ecosystem.config.js'); console.log('✅ Ecosystem config is valid')" >> ${LOGFILE}
fi

echo "AfterInstall complete: $(date)" >> ${LOGFILE}
echo "=== AfterInstall Hook Finished: $(date) ===" >> ${LOGFILE}