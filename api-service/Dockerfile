FROM node:18-alpine

# Install required tools including Docker CLI for container management
RUN apk add --no-cache curl bash dos2unix docker-cli

WORKDIR /app

# Copy API server files
COPY app-fixed-v2.js ./app.js

# Windows → Linux compatibility and make executable
RUN dos2unix ./app.js && chmod +x ./app.js

# Health check
HEALTHCHECK --interval=15s --timeout=5s --retries=3 --start-period=10s \
  CMD curl -f http://localhost:9000/health || exit 1

EXPOSE 9000

CMD ["node", "app.js"]