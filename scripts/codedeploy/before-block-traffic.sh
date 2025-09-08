#!/bin/bash
set -euo pipefail
LOGFILE=/var/log/codedeploy/hooks-before_block_traffic.log
exec 2>>${LOGFILE}
exec 1>>${LOGFILE}

echo "=== BeforeBlockTraffic Hook Started: $(date) ===" >> ${LOGFILE}

# Optional: Flush sessions to external session store
# curl -X POST http://localhost/internal/flush-sessions || true

# Optional: Put application in read-only mode
# curl -X POST http://localhost/internal/readonly-mode || true

# Optional: Disable nginx upstream for graceful drain
# This allows existing connections to complete while preventing new ones
# nginx_config="/etc/nginx/conf.d/upstreams-alb.conf"
# if [ -f "$nginx_config" ]; then
#     sed -i 's/server 127.0.0.1:300[1-4]/server 127.0.0.1:300[1-4] down/g' "$nginx_config"
#     nginx -s reload || true
# fi

echo "BeforeBlockTraffic complete: $(date)" >> ${LOGFILE}
echo "=== BeforeBlockTraffic Hook Finished: $(date) ===" >> ${LOGFILE}