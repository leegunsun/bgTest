# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a production-ready True Blue-Green Deployment system implementing identical environments with zero-downtime switching. The system follows industry best practices with a **single codebase** (`app-server/app.js`) dynamically configured via environment variables to create identical Blue and Green environments.

## Core Architecture

### Single Application Pattern (True Blue-Green)
- **Primary Application**: `app-server/app.js` - Single Node.js application controlled by environment variables
- **Dynamic Configuration**: Environment variables (`ENV_NAME`, `VERSION`, `SERVER_PORT`, `COLOR_THEME`) control behavior
- **Containerized Deployment**: Both Blue and Green environments run identical containers with different configurations

### Service Architecture
- **NGINX Proxy** (`nginx-proxy`): Traffic router with dynamic configuration switching (Port 80)
- **Blue Environment** (`blue-app`): Blue instance of single application (Port 3001)
- **Green Environment** (`green-app`): Green instance of single application (Port 3002)  
- **API Server** (`api-server`): Deployment control and management API (Port 9000)

### Zero-Downtime Switching Mechanism
- **Configuration File**: `/etc/nginx/conf.d/active.env` contains `set $active "blue|green";`
- **Atomic Updates**: Temporary file ’ validation ’ atomic replacement ’ NGINX reload
- **Variable-Based Routing**: NGINX maps `$active` variable to upstream servers without restart
- **Health Validation**: Multi-layer health checks before traffic switching

## Development Commands

### System Management
```bash
# Build and start complete system
docker-compose build && docker-compose up -d

# System status and monitoring
./scripts/deploy.sh status
docker ps --filter "network=bluegreen-network"

# View service logs
docker logs nginx-proxy
docker logs blue-app
docker logs green-app
docker logs api-server
```

### Deployment Operations
```bash
# Comprehensive deployment management
./scripts/deploy.sh start              # Start entire system
./scripts/deploy.sh switch blue        # Switch traffic to blue
./scripts/deploy.sh switch green       # Switch traffic to green
./scripts/deploy.sh deploy blue 2.0.0  # Deploy version to specific environment
./scripts/deploy.sh bluegreen 2.1.0    # Full Blue-Green deployment cycle
./scripts/deploy.sh test 30            # Zero-downtime validation test

# Manual deployment switching with safety checks
./scripts/switch-deployment.sh status        # Current environment status
./scripts/switch-deployment.sh switch blue   # Switch with validation
./scripts/switch-deployment.sh health        # Comprehensive health check
./scripts/switch-deployment.sh rollback      # Emergency rollback
```

### Health and Version Validation
```bash
# Service health checks
curl http://localhost:80/health          # Main proxy health
curl http://localhost:3001/health        # Blue environment health
curl http://localhost:3002/health        # Green environment health
curl http://localhost:9000/health        # API server health

# Version and deployment information
curl http://localhost:3001/version       # Blue version info
curl http://localhost:3002/version       # Green version info
curl http://localhost:3001/deployment    # Complete deployment metadata

# API-based traffic switching
curl -X POST http://localhost:9000/switch/blue
curl -X POST http://localhost:9000/switch/green
```

## Configuration Management

### Environment Variables (Primary Configuration Method)
```bash
# Blue Environment
ENV_NAME=blue
SERVER_PORT=3001
VERSION=1.0.0
DEPLOYMENT_ID=blue-${CI_COMMIT_SHA}
COLOR_THEME=blue

# Green Environment  
ENV_NAME=green
SERVER_PORT=3002
VERSION=2.0.0
DEPLOYMENT_ID=green-${CI_COMMIT_SHA}
COLOR_THEME=green
```

### Critical Configuration Files
- `conf.d/active.env`: Current active environment (`set $active "blue";`)
- `conf.d/upstreams.conf`: Blue/Green upstream server definitions
- `conf.d/routing.conf`: NGINX variable mapping for dynamic routing
- `nginx.conf`: Main NGINX configuration with modular includes
- `docker-compose.yml`: Service definitions with resource optimization

### NGINX Dynamic Routing Architecture
The system uses NGINX variable-based routing that allows zero-downtime switching:
```nginx
# active.env sets the variable
set $active "blue";

# routing.conf maps variable to upstream
map $active $backend {
    blue    blue-app:3001;
    green   green-app:3002;
}

# Configuration reload (no restart needed)
proxy_pass http://$backend;
```

## Deployment Safety Mechanisms

### Atomic Configuration Updates
All configuration changes use atomic file operations:
1. Create temporary file with new configuration
2. Validate configuration syntax (`nginx -t`)
3. Atomic file replacement (`install` command)
4. Graceful NGINX reload (`nginx -s reload`)
5. Health validation of new configuration
6. Automatic rollback on failure

### Multi-Layer Health Validation
1. **Docker Health**: Container-level health status
2. **Application Health**: Internal service `/health` endpoints
3. **Network Health**: Cross-container communication validation
4. **Proxy Health**: NGINX routing validation
5. **End-to-End**: Complete request flow validation

### Emergency Recovery Procedures
```bash
# Complete system reset
docker-compose down --timeout 30
docker-compose build && docker-compose up -d

# Manual configuration recovery
docker exec nginx-proxy sh -c 'echo "set \$active \"blue\";" > /etc/nginx/conf.d/active.env'
docker exec nginx-proxy nginx -s reload

# Health validation after recovery
./scripts/deploy.sh status
```

## GitLab CI/CD Pipeline

### Pipeline Stages
1. **build-dev**: Node.js 18 build and artifact preparation
2. **test-dev**: Syntax validation for unified application architecture
3. **detect-env-dev**: Active environment detection (API + file fallback)
4. **deploy-inactive-dev**: Zero-downtime deployment to inactive environment
5. **health-check-dev**: Multi-layer health validation
6. **zero-downtime-test-dev**: Availability testing during deployment
7. **switch-traffic-dev**: Manual traffic switching with validation
8. **verify-deployment-dev**: Post-deployment verification
9. **cleanup-dev**: Resource cleanup and optimization

### Dynamic Versioning
- **Version Variables**: `BLUE_VERSION`, `GREEN_VERSION`, `DEPLOYMENT_VERSION`
- **Git Integration**: Uses `${CI_COMMIT_TAG:-${CI_COMMIT_SHORT_SHA}}`
- **Metadata Tracking**: Complete deployment information stored in Docker volumes

## Resource Optimization

### AWS t2.micro Optimization
- **Memory Limits**: nginx-proxy (50MB), apps (120MB each), api-server (80MB)
- **CPU Limits**: Fractional CPU allocation (0.1-0.25 cores)
- **Health Check Intervals**: Extended intervals (30s) for resource conservation
- **Swap Management**: Disabled (`memswap_limit = mem_limit`)

### Network Architecture
- **Internal Network**: `bluegreen-network` (172.25.0.0/16)
- **Service Discovery**: Docker DNS with hostname aliases
- **Port Exposure**: Only port 80 exposed to host (security)
- **Container Communication**: Internal network for all inter-service communication

## Key Architectural Principles

### True Blue-Green Implementation
- **Single Codebase**: One application (`app-server/app.js`) serves both environments
- **Environment Variables**: Dynamic configuration without code duplication  
- **Identical Environments**: Same container, same application, different configuration
- **Zero Downtime**: Traffic switching without service interruption
- **Instant Rollback**: Previous environment always ready for immediate switch

### Production Safety
- **Atomic Operations**: All configuration changes are atomic and validated
- **Health Validation**: Comprehensive health checking before traffic switching
- **Manual Gates**: CI/CD pipeline requires manual approval for production traffic switches
- **Emergency Procedures**: Documented rollback and recovery mechanisms
- **Resource Monitoring**: Built-in resource usage monitoring and limits

When working with this codebase, always prioritize the safety mechanisms and health validation systems. All deployment operations should go through the proper scripts and validation procedures to maintain zero-downtime guarantees.