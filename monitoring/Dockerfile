FROM alpine:latest

# Install monitoring tools
RUN apk add --no-cache curl bash jq dos2unix

WORKDIR /app

# Copy monitoring scripts
COPY monitor-deployment.sh ./monitor-deployment.sh
COPY zero-downtime-test.sh ./zero-downtime-test.sh

# Windows → Linux compatibility
RUN dos2unix ./monitor-deployment.sh ./zero-downtime-test.sh && \
    chmod +x ./monitor-deployment.sh ./zero-downtime-test.sh

# Create data directory
RUN mkdir -p /app/data

# Health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD test -f /app/data/monitor.pid || exit 1

CMD ["./monitor-deployment.sh"]