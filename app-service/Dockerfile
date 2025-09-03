FROM node:18-alpine

# Install curl for health checks
RUN apk add --no-cache curl dos2unix

WORKDIR /app

# Copy unified application server
COPY app-server/ ./app-server/

# Copy legacy servers for compatibility (optional)
COPY blue-server/ ./blue-server/
COPY green-server/ ./green-server/

# Windows → Linux compatibility: line ending conversion and execution permissions
RUN dos2unix ./app-server/app.js ./blue-server/app.js ./green-server/app.js

# Unified application launcher
COPY app-service/start-app.sh ./start-app.sh
RUN dos2unix ./start-app.sh && chmod +x ./start-app.sh

# Create deployment metadata directory
RUN mkdir -p /app/deployment

# Expose ports for both blue and green
EXPOSE 3001 3002

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 --start-period=30s \
  CMD curl -f http://localhost:${SERVER_PORT:-3001}/health || exit 1

CMD ["./start-app.sh"]