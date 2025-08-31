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

# Windows → Linux 호환성 처리: 줄바꿈 변환 및 실행 권한 부여
RUN apk add --no-cache dos2unix && \
    dos2unix ./switch-deployment.sh ./health-check.sh ./start.sh && \
    chmod +x ./switch-deployment.sh ./health-check.sh ./start.sh

# nginx 설정 디렉터리 생성 (새로운 판단 파일 구조)
RUN mkdir -p /var/www/html /var/log/nginx /etc/nginx/conf.d

# nginx 설정 파일 복사 (새로운 판단 파일 방식)
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/
COPY admin.html /var/www/html/index.html

# 포트 노출
EXPOSE 80 8080 3001 3002 9000

# 스크립트 존재, 권한, 줄바꿈 형식 확인 (디버깅용)
RUN echo "=== 스크립트 파일 상태 검증 ===" && \
    ls -la /app/*.sh && \
    echo "=== start.sh 내용 검증 ===" && \
    head -1 /app/start.sh | od -c && \
    echo "=== bash 위치 확인 ===" && \
    which bash && \
    echo "=== 스크립트 실행 테스트 ===" && \
    /app/start.sh --version 2>/dev/null || echo "스크립트 실행 준비됨"

# 컨테이너 시작 시 실행할 명령
CMD ["/app/start.sh"]