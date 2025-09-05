FROM node:18-alpine

# Install curl for health checks
RUN apk add --no-cache curl dos2unix

# True Blue-Green Deployment Container
# Single application deployed to identical environments with environment variables

WORKDIR /app

# Copy single unified application (True Blue-Green Pattern)
COPY app-server/ ./app-server/

# Windows → Linux compatibility: line ending conversion and execution permissions
RUN dos2unix ./app-server/app.js

# Unified application launcher
COPY app-service/start-app.sh ./start-app.sh
RUN dos2unix ./start-app.sh && chmod +x ./start-app.sh

# Create deployment metadata directory
RUN mkdir -p /app/deployment

# Expose dynamic port (controlled by SERVER_PORT environment variable)
EXPOSE 3001 3002

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 --start-period=30s \
  CMD curl -f http://localhost:${SERVER_PORT:-3001}/health || exit 1

CMD ["./start-app.sh"]