# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Blue-Green deployment testing repository containing multiple versions of NGINX-based Blue-Green deployment systems. The project demonstrates evolution from basic deployment switching (v1) to production-ready systems with atomic file operations, enhanced health checks, and GitLab CI/CD integration (v5).

## Repository Structure

```
bgTest/
├── v1/                    # Basic blue-green switching
├── v2/                    # Enhanced with docker-compose
├── v3/                    # Improved health checks
├── v4ToWindow/            # Production-ready system (recommended)
├── v5ToWindow/            # GitLab CI/CD integration
└── .git/                  # Git repository
```

## Core Architecture

### Active Version: v4ToWindow (Production-Ready)
- **Main Entry**: Port 80 (NGINX proxy)
- **Blue Server**: Port 3001 (Version 1.0.0)
- **Green Server**: Port 3002 (Version 2.0.0) 
- **Admin Interface**: Port 8080 (Management dashboard)
- **API Server**: Port 9000 (Deployment control)

### Key Components
- `switch-deployment.sh`: Enhanced atomic deployment script
- `health-check.sh`: Comprehensive health validation
- `nginx.conf`: Main NGINX configuration with variable-based routing
- `conf.d/active.env`: Active environment control file (`set $active "color"`)
- `conf.d/upstreams.conf`: Blue/Green upstream definitions
- `conf.d/routing.conf`: Map variables for dynamic routing

## Development Commands

### Build and Run (v4ToWindow recommended)
```bash
cd v4ToWindow
docker build -t blue-green-nginx .
docker-compose up -d
```

### Direct Container Run
```bash
docker run -d \
  -p 80:80 -p 8080:8080 -p 3001:3001 -p 3002:3002 -p 9000:9000 \
  --name blue-green-nginx \
  blue-green-nginx
```

### Testing Deployment
```bash
# Enter container
docker exec -it blue-green-nginx bash

# Switch environments
./switch-deployment.sh green
./switch-deployment.sh blue

# Health checks
./health-check.sh              # Full system check
./health-check.sh blue         # Blue server only
./health-check.sh green        # Green server only
./health-check.sh nginx        # NGINX proxy only
./health-check.sh config       # Configuration validation
```

### API-Based Deployment
```bash
curl -X POST http://localhost:9000/switch/green
curl -X POST http://localhost:9000/switch/blue
```

## Safety Mechanisms (새로운 판단 파일 Implementation)

### Atomic File Replacement Process
1. **Temporary File Creation**: `mktemp` for safe file operations
2. **Configuration Write**: New config to temporary file
3. **Atomic Move**: `install` command for atomic replacement
4. **Validation**: `nginx -t` for syntax validation
5. **Reload**: `nginx -s reload` for zero-downtime application

### Health Check Features
- Multi-attempt validation (5 attempts with 2-second timeout)
- Proper error handling for connection and HTTP-level checks
- User-Agent identification: `nginx-deployment-switch/1.0`
- Color-coded status indicators (🟢 HEALTHY, 🔴 UNHEALTHY, 🟡 UNKNOWN)

### Automatic Rollback
- **Triggers**: Configuration validation failure or reload error
- **Recovery**: Instant revert to previous active environment
- **Validation**: Post-rollback health check confirmation

## Access Points

- **Main Application**: http://localhost (current active environment)
- **Admin Dashboard**: http://localhost:8080 (management interface)
- **Blue Environment**: http://localhost/blue/ (direct access)
- **Green Environment**: http://localhost/green/ (direct access)
- **Health Endpoints**:
  - Blue: `http://localhost:3001/health`
  - Green: `http://localhost:3002/health`
  - NGINX: `http://localhost:80/health`
  - API: `http://localhost:9000/health`

## GitLab CI/CD Integration (v5ToWindow)

### Pipeline Stages
1. **build-dev**: Gradle build with JDK 19
2. **test-dev**: Test execution
3. **deploy-dev**: Blue-Green deployment
4. **health-check-dev**: Target environment validation
5. **switch-traffic-dev**: Traffic switching
6. **verify-dev**: Post-deployment verification
7. **cleanup-dev**: Resource cleanup

### Key CI/CD Features
- Eclipse Temurin JDK 19 support
- Gradle caching and optimization
- SSH-based EC2 deployment
- Automated health checks and rollback
- Ubuntu user and existing path structure preservation

## Configuration Files

### NGINX Configuration Strategy
- **Modular Design**: Separation of concerns with include files
- **Variable-Based Routing**: `set $active` → `map $active $backend` → `proxy_pass http://$backend`
- **Dynamic Upstream Selection**: Blue/Green upstream switching without restart

### Key Configuration Files
- `/etc/nginx/conf.d/active.env`: Active color control
- `/etc/nginx/conf.d/upstreams.conf`: Upstream server definitions
- `/etc/nginx/conf.d/routing.conf`: Variable mapping logic

## Troubleshooting

### Common Issues
1. **Health Check Failed**: Check individual services, restart if needed
2. **Configuration Validation Failed**: Manual `nginx -t`, check file contents
3. **Rollback Failed**: Manual recovery with safe default values
4. **Partial Service Failure**: Priority-based recovery (NGINX → Active → API → Inactive)

### Emergency Recovery
```bash
# Complete system reset
docker restart blue-green-nginx
docker exec blue-green-nginx sh -c 'echo "set \$active \"blue\";" > /etc/nginx/conf.d/active.env'
docker exec blue-green-nginx nginx -s reload
./health-check.sh
```

## Development Guidelines

### When Working with Different Versions
- **v1-v3**: Basic implementations, good for learning concepts
- **v4ToWindow**: Production-ready, use for serious development
- **v5ToWindow**: GitLab integration, use for CI/CD development

### Testing Strategy
- Always validate health checks before switching
- Test both directions (blue → green → blue)
- Verify rollback mechanisms work correctly
- Monitor logs during deployment switches

### Safety Best Practices
- Never bypass atomic file replacement mechanisms
- Always run health checks before traffic switching
- Maintain backup configurations
- Test rollback procedures regularly