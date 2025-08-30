# NGINX Blue-Green Deployment System v2.0

> **새로운 판단 파일 기반의 공식 NGINX 메커니즘 구현**  
> Atomic File Replacement | Enhanced Health Checks | Graceful Rollback

## 🎯 Project Overview

This project implements a production-ready NGINX Blue-Green deployment system following the **새로운 판단 파일** recommendations, which align with official NGINX best practices for zero-downtime deployments.

### Key Improvements from v1.0

- ✅ **Atomic File Replacement**: Using `mktemp` + `install` for safe configuration updates
- ✅ **Official NGINX Mechanism**: Configuration change → `nginx -t` → `nginx -s reload`
- ✅ **Enhanced Health Checks**: Multi-level validation with timeout controls
- ✅ **Automatic Rollback**: Instant recovery on deployment failures
- ✅ **Separation of Concerns**: Modular configuration files
- ✅ **Real-time Monitoring**: Web-based admin interface

## 🏗️ Architecture

### File Structure

```
v4Temp/
├── 📁 conf.d/
│   ├── upstreams.conf      # Blue/Green upstream definitions
│   ├── active.env          # Active color variable (새로운 판단 파일 방식)
│   ├── routing.conf        # Map $active to $backend  
│   └── active_backend.conf.backup  # Legacy backup
├── 📁 blue-server/         # Version 1.0.0 (Blue)
├── 📁 green-server/        # Version 2.0.0 (Green)
├── 📁 api-server/          # Deployment control API
├── 🔧 nginx.conf           # Main NGINX configuration
├── 🔧 switch-deployment.sh # Enhanced deployment script
├── 🔧 health-check.sh      # Comprehensive health checker
├── 🌐 admin.html           # Web management interface
├── 📋 OPERATIONS_GUIDE.md  # Detailed operations manual
├── 🐳 Dockerfile           # Container configuration
└── 🐳 docker-compose.yml   # Service orchestration
```

### Service Mapping

| Service | Port | Description | Health Endpoint |
|---------|------|-------------|-----------------|
| **NGINX Proxy** | 80 | Main entry point | `/health` |
| **Admin Interface** | 8080 | Management dashboard | - |
| **Blue Server** | 3001 | Version 1.0.0 | `/health` |
| **Green Server** | 3002 | Version 2.0.0 | `/health` |
| **API Server** | 9000 | Deployment control | `/health` |

## 🚀 Quick Start

### 1. Build & Run Container

```bash
# Build the container
docker build -t blue-green-nginx .

# Run with docker-compose (recommended)
docker-compose up -d

# Or run directly
docker run -d \
  -p 80:80 -p 8080:8080 -p 3001:3001 -p 3002:3002 -p 9000:9000 \
  --name blue-green-nginx \
  blue-green-nginx
```

### 2. Access Interfaces

- **Main Site**: http://localhost (current active environment)
- **Admin Dashboard**: http://localhost:8080 (management interface)
- **Blue Environment**: http://localhost/blue/ (direct access)
- **Green Environment**: http://localhost/green/ (direct access)

### 3. Test Deployment

```bash
# Enter container
docker exec -it blue-green-nginx bash

# Switch to Green (새로운 판단 파일 방식)
./switch-deployment.sh green

# Check health status
./health-check.sh

# Switch back to Blue  
./switch-deployment.sh blue
```

## 💻 Deployment Methods

### Method 1: Script-Based (Recommended)

```bash
# Safe deployment with all 새로운 판단 파일 features
./switch-deployment.sh {blue|green}

# Features:
# - Enhanced health check with timeout
# - Atomic file replacement (mktemp + install)
# - NGINX configuration validation
# - Graceful reload with HUP signal
# - Automatic rollback on failure
```

### Method 2: Web Interface

1. Open http://localhost:8080
2. Click **Blue** or **Green** deployment button
3. Monitor real-time deployment logs
4. Verify health status indicators

### Method 3: API-Based

```bash
curl -X POST http://localhost:9000/switch/green
curl -X POST http://localhost:9000/switch/blue
```

## 🔒 Safety Features (새로운 판단 파일 Implementation)

### Atomic File Replacement

```bash
# Traditional approach (UNSAFE)
echo "new config" > /etc/nginx/conf.d/active.env

# 새로운 판단 파일 approach (SAFE)
temp_file=$(mktemp)
echo "new config" > "$temp_file"
install -o root -g root -m 0644 "$temp_file" /etc/nginx/conf.d/active.env
rm -f "$temp_file"
```

### Enhanced Health Checks

- **Multi-attempt validation**: 5 attempts with 2-second timeout
- **Proper error handling**: Connection and HTTP-level checks
- **User-Agent identification**: `nginx-deployment-switch/1.0`
- **Comprehensive reporting**: Color-coded status indicators

### Automatic Rollback

- **Trigger conditions**: Configuration validation failure or reload error
- **Recovery process**: Instant revert to previous active environment
- **Validation**: Post-rollback health check confirmation

## 📊 Monitoring & Health Checks

### Health Check Script

```bash
./health-check.sh           # Full system check
./health-check.sh blue      # Blue server only
./health-check.sh green     # Green server only  
./health-check.sh nginx     # NGINX proxy only
./health-check.sh config    # Configuration validation
```

### Status Indicators

- 🟢 **HEALTHY**: Service responding correctly
- 🔴 **UNHEALTHY**: Service down or error response
- 🟡 **UNKNOWN**: Status check in progress

## 🛠️ Configuration Details

### Core NGINX Configuration (새로운 판단 파일 Style)

```nginx
# Include modular configuration
include /etc/nginx/conf.d/upstreams.conf;  # Upstream definitions
include /etc/nginx/conf.d/routing.conf;    # Map variables

server {
    # Include active environment variable
    include /etc/nginx/conf.d/active.env;   # set $active "color";
    
    location / {
        proxy_pass http://$backend;          # Variable-based routing
    }
}
```

### Active Environment Control

```bash
# /etc/nginx/conf.d/active.env
set $active "blue";    # Current active color
```

### Upstream & Routing Logic

```nginx
# /etc/nginx/conf.d/upstreams.conf
upstream blue { server 127.0.0.1:3001; }
upstream green { server 127.0.0.1:3002; }

# /etc/nginx/conf.d/routing.conf  
map $active $backend {
    default   blue;
    blue      blue;
    green     green;
}
```

## 🔧 Troubleshooting

### Common Issues

1. **Health Check Failed**
   ```bash
   # Check individual services
   ./health-check.sh blue
   ./health-check.sh green
   
   # Restart if needed
   docker restart blue-green-nginx
   ```

2. **Configuration Validation Failed**
   ```bash
   # Manual validation
   nginx -t
   
   # Check file contents
   cat /etc/nginx/conf.d/active.env
   ```

3. **Rollback Failed**
   ```bash
   # Manual recovery
   echo 'set $active "blue";' > /etc/nginx/conf.d/active.env
   nginx -s reload
   ```

### Emergency Recovery

```bash
# Full system reset
docker restart blue-green-nginx
docker exec blue-green-nginx ./health-check.sh
```

## 📋 Pre-Deployment Checklist

### Before Deployment

- [ ] Target environment health check passes
- [ ] Current active environment identified  
- [ ] Backup configuration files exist
- [ ] Rollback plan prepared
- [ ] Monitoring dashboards ready

### During Deployment

- [ ] Health check passes (5 consecutive attempts)
- [ ] Atomic file replacement completed
- [ ] NGINX configuration validation succeeds
- [ ] Graceful reload executed successfully
- [ ] New worker processes started

### After Deployment

- [ ] Full system health check passes
- [ ] Traffic routing verified (actual request test)
- [ ] Performance metrics normal
- [ ] Error logs show no new issues
- [ ] User impact minimized

## 📚 Additional Resources

- **[OPERATIONS_GUIDE.md](./OPERATIONS_GUIDE.md)**: Comprehensive operations manual
- **[새로운 판단 파일](./ningx판단문서.md)**: Original NGINX best practices document
- **Admin Dashboard**: http://localhost:8080 (live monitoring)

## 🏆 새로운 판단 파일 Compliance

This implementation fully adheres to the **새로운 판단 파일** recommendations:

✅ **Official NGINX Mechanism**: Configuration → `nginx -t` → `nginx -s reload`  
✅ **Atomic File Operations**: `mktemp` + `install` for safety  
✅ **Variable-Based Routing**: `set $active` → `map` → `proxy_pass http://$backend`  
✅ **Health Check Priority**: Pre-flight validation before switching  
✅ **Graceful Worker Transition**: HUP signal for zero-downtime  
✅ **Instant Rollback**: Automated failure recovery  
✅ **Modular Configuration**: Separation of concerns with include files  

---

## 📞 Support

For issues or questions:
1. Check the **[OPERATIONS_GUIDE.md](./OPERATIONS_GUIDE.md)** troubleshooting section
2. Use the admin dashboard at http://localhost:8080 for real-time monitoring
3. Review deployment logs in the container

---

*Implemented following **새로운 판단 파일** NGINX Official Best Practices*  
*Version 2.0 - Production-Ready Blue-Green Deployment System*