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
COPY health-check.sh ./health-check.sh
COPY start.sh ./start.sh

# 스크립트 실행 권한 부여
RUN chmod +x ./switch-deployment.sh ./health-check.sh ./start.sh

# nginx 설정 디렉터리 생성 (새로운 판단 파일 구조)
RUN mkdir -p /var/www/html /var/log/nginx /etc/nginx/conf.d

# nginx 설정 파일 복사 (새로운 판단 파일 방식)
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/
COPY admin.html /var/www/html/index.html

# 포트 노출
EXPOSE 80 8080 3001 3002 9000

# 컨테이너 시작 시 실행할 명령
CMD ["/app/start.sh"]