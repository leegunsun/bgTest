#!/bin/bash
set -euo pipefail
LOGFILE=/var/log/codedeploy/hooks-stop.log
exec 2>>${LOGFILE}
exec 1>>${LOGFILE}

echo "=== ApplicationStop Hook Started: $(date) ===" >> ${LOGFILE}

# Graceful stop: PM2 기준
if command -v pm2 >/dev/null 2>&1; then
    echo "Gracefully stopping PM2 processes..." >> ${LOGFILE}
    pm2 gracefulReload all || pm2 stop all || true
    echo "PM2 processes stopped" >> ${LOGFILE}
else
    echo "PM2 not found, skipping PM2 shutdown" >> ${LOGFILE}
fi

# NGINX reload to remove old upstreams if config changed
if systemctl is-active --quiet nginx; then
    echo "Reloading NGINX configuration..." >> ${LOGFILE}
    nginx -s reload || true
    echo "NGINX configuration reloaded" >> ${LOGFILE}
fi

# Wait short period for connections to drain
echo "Waiting for connection drain..." >> ${LOGFILE}
sleep 5

echo "ApplicationStop complete: $(date)" >> ${LOGFILE}
echo "=== ApplicationStop Hook Finished: $(date) ===" >> ${LOGFILE}