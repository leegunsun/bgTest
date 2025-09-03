# 🔍 상세 디버깅 로깅 추가 완료

## 📋 추가된 디버깅 기능

### 1. 컨테이너 상태 모니터링
```bash
# 컨테이너 상태, 포트, 상태 확인
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### 2. 네트워크 진단
```bash
# Docker 네트워크 정보
docker network ls
docker network inspect bluegreen-network

# 네트워크 내 컨테이너 연결 상태
jq ".[0].Containers"
```

### 3. 시스템 리소스 모니터링
```bash
# 메모리 사용량 (t2.micro 핵심)
free -h

# 디스크 사용량
df -h
```

### 4. 헬스체크 상세 로깅
- **매 헬스체크마다**: HTTP 응답 코드, 에러 메시지 확인
- **5, 15, 30번째**: 컨테이너 로그 자세히 출력
- **포트 상태**: netstat으로 포트 리스닝 상태 확인
- **컨테이너 프로세스**: 내부 프로세스 상태 확인

### 5. 연결성 테스트
```bash
# 포트 연결 테스트
nc -z localhost $TARGET_PORT

# 컨테이너 내부 프로세스 확인
docker exec green-app ps aux
```

## 📊 디버깅 타임라인

| 시점 | 확인 항목 | 목적 |
|------|----------|------|
| 배포 직후 | 컨테이너 상태, 네트워크, 리소스 | 기본 환경 확인 |
| 5번째 체크 | 모든 컨테이너 로그 | 초기 시작 로그 |
| 15번째 체크 | 모든 컨테이너 로그 | 중간 상태 로그 |
| 30번째 체크 | 모든 컨테이너 로그 | 최종 상태 로그 |
| 매 체크마다 | HTTP 응답, 포트 상태, 프로세스 | 실시간 상태 |
| 실패 시 | 최종 진단 정보 | 완전한 로그 덤프 |

## 🎯 다음 배포에서 확인할 정보

### ✅ 성공 지표:
1. **컨테이너 시작**: "Created" → "Started" → "Up" 상태
2. **포트 리스닝**: netstat에서 3002 포트 LISTEN 확인
3. **프로세스 실행**: node 프로세스 정상 실행
4. **HTTP 응답**: 200 OK 응답
5. **메모리**: OOMKilled 없음

### ❌ 실패 시나리오별 진단:
1. **컨테이너 실행 실패**: Docker 로그에서 시작 에러
2. **포트 미리스닝**: 앱이 시작되지 않음
3. **메모리 부족**: OOMKilled, restart 반복
4. **HTTP 오류**: 5xx, 4xx 응답 코드
5. **프로세스 크래시**: 내부 프로세스 없음

## 🚀 배포 및 확인

```bash
git add .
git commit -m "Add: 상세 디버깅 로깅 시스템 구현"
git push origin main
```

## 📋 예상 로그 출력

성공적인 경우:
```
🔍 [DEBUG] Container status check:
green-app    Up 2 minutes    0.0.0.0:3002->3002/tcp

🔍 [DEBUG] Health check attempt 1/40 for green on port 3002
✅ Port 3002 is open and accepting connections
🔍 [DEBUG] HTTP Response: {"status":"healthy"...}HTTPSTATUS:200
✅ green environment is healthy!
```

실패하는 경우에는 구체적인 에러 메시지와 로그가 출력되어 정확한 원인을 알 수 있을 것입니다!

## 💡 이제 정확한 문제를 찾을 수 있습니다!

다음 배포에서 나오는 상세 로그를 통해 어느 단계에서 실패하는지 명확하게 알 수 있을 것입니다.