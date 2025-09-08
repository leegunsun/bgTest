#!/bin/bash
set -euo pipefail
LOGFILE=/var/log/codedeploy/hooks-before_install.log
exec 2>>${LOGFILE}
exec 1>>${LOGFILE}

echo "=== BeforeInstall Hook Started: $(date) ===" >> ${LOGFILE}

# Backup current release (optional)
if [ -d /opt/bluegreen-app ]; then
    timestamp=$(date +%Y%m%d%H%M%S)
    echo "Backing up current deployment to /opt/bluegreen-app.backup.${timestamp}" >> ${LOGFILE}
    mv /opt/bluegreen-app /opt/bluegreen-app.backup.${timestamp} || true
fi

# Create destination directory
echo "Creating application directory..." >> ${LOGFILE}
mkdir -p /opt/bluegreen-app/{logs,temp,config}
chown -R ec2-user:ec2-user /opt/bluegreen-app || true

# Ensure log directory permissions
mkdir -p /var/log/codedeploy
chmod 755 /var/log/codedeploy

echo "BeforeInstall complete: $(date)" >> ${LOGFILE}
echo "=== BeforeInstall Hook Finished: $(date) ===" >> ${LOGFILE}