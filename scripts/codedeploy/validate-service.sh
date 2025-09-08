#!/bin/bash
set -euo pipefail
LOGFILE=/var/log/codedeploy/hooks-validate_service.log
exec 2>>${LOGFILE}
exec 1>>${LOGFILE}

echo "=== ValidateService Hook Started: $(date) ===" >> ${LOGFILE}

# Health check configuration
HEALTH_URL="http://localhost/health"
DEEP_HEALTH_URL="http://localhost/health/deep"
RETRIES=20
SLEEP=3
SUCCESS=false

echo "Starting comprehensive health check validation..." >> ${LOGFILE}

# Basic health endpoint validation
echo "Testing basic health endpoint..." >> ${LOGFILE}
for i in $(seq 1 ${RETRIES}); do
    code=$(curl -s -o /dev/null -w "%{http_code}" ${HEALTH_URL} || echo "000")
    if [ "${code}" == "200" ]; then
        echo "✅ Basic health check passed on attempt ${i}" >> ${LOGFILE}
        SUCCESS=true
        break
    else
        echo "❌ Basic health check failed (HTTP ${code}) - attempt ${i}/${RETRIES}" >> ${LOGFILE}
        if [ "$i" -eq "${RETRIES}" ]; then
            echo "Basic health check failed after ${RETRIES} attempts" >> ${LOGFILE}
            exit 1
        fi
        sleep ${SLEEP}
    fi
done

# Deep health endpoint validation (if available)
echo "Testing deep health endpoint..." >> ${LOGFILE}
for i in $(seq 1 10); do
    code=$(curl -s -o /dev/null -w "%{http_code}" ${DEEP_HEALTH_URL} || echo "000")
    if [ "${code}" == "200" ]; then
        echo "✅ Deep health check passed on attempt ${i}" >> ${LOGFILE}
        break
    else
        echo "⚠️ Deep health check failed (HTTP ${code}) - attempt ${i}/10" >> ${LOGFILE}
        if [ "$i" -eq 10 ]; then
            echo "Warning: Deep health check failed, but continuing with basic validation" >> ${LOGFILE}
        fi
        sleep 2
    fi
done

# PM2 process validation
if command -v pm2 >/dev/null 2>&1; then
    echo "Validating PM2 processes..." >> ${LOGFILE}
    pm2_status=$(pm2 jlist 2>/dev/null | jq -r '.[].pm2_env.status' 2>/dev/null || echo "unknown")
    if echo "$pm2_status" | grep -q "online"; then
        echo "✅ PM2 processes are running" >> ${LOGFILE}
    else
        echo "⚠️ PM2 process status unclear: $pm2_status" >> ${LOGFILE}
    fi
    pm2 status >> ${LOGFILE} 2>&1 || true
fi

# NGINX validation
if systemctl is-active --quiet nginx; then
    echo "✅ NGINX service is running" >> ${LOGFILE}
    
    # Test NGINX upstream connectivity
    nginx_test=$(nginx -t 2>&1 || echo "failed")
    if echo "$nginx_test" | grep -q "successful"; then
        echo "✅ NGINX configuration is valid" >> ${LOGFILE}
    else
        echo "⚠️ NGINX configuration test results: $nginx_test" >> ${LOGFILE}
    fi
else
    echo "❌ NGINX service is not active" >> ${LOGFILE}
    exit 1
fi

# Application response validation
echo "Testing application endpoints..." >> ${LOGFILE}
app_response=$(curl -s http://localhost/ | head -c 100 2>/dev/null || echo "no response")
if [ ${#app_response} -gt 10 ]; then
    echo "✅ Application is responding with content" >> ${LOGFILE}
else
    echo "⚠️ Application response seems minimal: ${app_response}" >> ${LOGFILE}
fi

# Final validation summary
if [ "$SUCCESS" == "true" ]; then
    echo "ValidateService: Service validation successful after deployment" >> ${LOGFILE}
    echo "=== ValidateService Hook Finished Successfully: $(date) ===" >> ${LOGFILE}
    exit 0
else
    echo "ValidateService: Service validation failed" >> ${LOGFILE}
    echo "=== ValidateService Hook Failed: $(date) ===" >> ${LOGFILE}
    exit 1
fi