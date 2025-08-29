FROM ubuntu:22.04

# 필요한 패키지 설치
RUN apt-get update && apt-get install -y \
    nginx \
    nginx-extras \
    nodejs \
    npm \
    supervisor \
    curl \
    vim \
    && rm -rf /var/lib/apt/lists/*

# 작업 디렉토리 설정
WORKDIR /app

# 애플리케이션 파일 복사
COPY blue-server/ ./blue-server/
COPY green-server/ ./green-server/
COPY nginx.conf /etc/nginx/nginx.conf
COPY switch-deployment.sh ./switch-deployment.sh
COPY supervisor.conf /etc/supervisor/conf.d/supervisor.conf

# 스크립트 실행 권한 부여
RUN chmod +x switch-deployment.sh

# 로그 디렉토리 생성
RUN mkdir -p /var/log/supervisor

# 포트 노출
EXPOSE 80 8080 3001 3002 9001

# Supervisor로 모든 서비스 시작
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisor.conf"]
