FROM nginx:alpine

# Install required tools
RUN apk add --no-cache curl bash dos2unix

# Create necessary directories
RUN mkdir -p /var/www/html /var/log/nginx /etc/nginx/conf.d /etc/nginx/dynamic

# Copy NGINX configuration files
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/
COPY admin.html /var/www/html/index.html

# Copy traffic switching scripts
COPY switch-deployment.sh /usr/local/bin/switch-deployment.sh
COPY nginx-service/nginx-switch.sh /usr/local/bin/nginx-switch.sh

# Windows → Linux compatibility and permissions
RUN dos2unix /usr/local/bin/switch-deployment.sh /usr/local/bin/nginx-switch.sh && \
    chmod +x /usr/local/bin/switch-deployment.sh /usr/local/bin/nginx-switch.sh

# Health check for NGINX
HEALTHCHECK --interval=10s --timeout=5s --retries=5 --start-period=10s \
  CMD curl -f http://localhost:80/status || exit 1

EXPOSE 80 8080

# Custom entrypoint for NGINX with configuration management
COPY nginx-service/docker-entrypoint.sh /docker-entrypoint.sh
RUN dos2unix /docker-entrypoint.sh && chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]