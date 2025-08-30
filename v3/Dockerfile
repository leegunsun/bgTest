FROM node:18-alpine

# nginx 설치
RUN apk add --no-cache nginx curl bash

# 작업 디렉터리 설정
WORKDIR /app

# 애플리케이션 파일들 복사
COPY blue-server/ ./blue-server/
COPY green-server/ ./green-server/
COPY api-server/ ./api-server/
COPY switch-deployment.sh ./switch-deployment.sh

# 스크립트 실행 권한 부여
RUN chmod +x ./switch-deployment.sh

# nginx 설정 디렉터리 생성
RUN mkdir -p /var/www/html /var/log/nginx

# nginx 설정 파일 복사
COPY nginx.conf /etc/nginx/nginx.conf
COPY admin.html /var/www/html/index.html

# 포트 노출
EXPOSE 80 8080 3001 3002 9000

# 시작 스크립트 생성
RUN echo '#!/bin/bash' > /app/start.sh && \
    echo 'echo "Starting Blue Server..."' >> /app/start.sh && \
    echo 'node /app/blue-server/app.js &' >> /app/start.sh && \
    echo 'echo "Starting Green Server..."' >> /app/start.sh && \
    echo 'node /app/green-server/app.js &' >> /app/start.sh && \
    echo 'echo "Starting API Server..."' >> /app/start.sh && \
    echo 'node /app/api-server/app.js &' >> /app/start.sh && \
    echo 'echo "Starting Nginx..."' >> /app/start.sh && \
    echo 'nginx -g "daemon off;" &' >> /app/start.sh && \
    echo 'wait' >> /app/start.sh && \
    chmod +x /app/start.sh

CMD ["/app/start.sh"]