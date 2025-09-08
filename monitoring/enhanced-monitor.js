const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const MONITOR_PORT = 8090;
const MONITOR_INTERVAL = 10000; // 10 seconds
const HEALTH_LOG_FILE = '/var/log/bluegreen-health.log';
const METRICS_LOG_FILE = '/var/log/bluegreen-metrics.log';
const ALERT_LOG_FILE = '/var/log/bluegreen-alerts.log';

/**
 * Enhanced Monitoring System for Blue-Green Load Balancing
 * Provides comprehensive monitoring, validation, and alerting
 */
class EnhancedMonitoringSystem {
    constructor() {
        this.metrics = {
            health: new Map(),
            performance: new Map(),
            traffic: new Map(),
            deployment: new Map()
        };
        
        this.alerts = [];
        this.thresholds = {
            responseTime: 1000, // 1 second
            errorRate: 0.05,    // 5%
            availability: 0.99, // 99%
            cpuUsage: 0.8,      // 80%
            memoryUsage: 0.9    // 90%
        };
        
        this.isMonitoring = false;
        this.startTime = Date.now();
        
        this.initializeMonitoring();
    }

    initializeMonitoring() {
        console.log('🔍 Initializing Enhanced Blue-Green Monitoring System...');
        
        // Create log directories
        this.ensureLogDirectories();
        
        // Start continuous monitoring
        this.startContinuousMonitoring();
        
        // Start HTTP server for metrics API
        this.startMetricsServer();
        
        console.log('✅ Enhanced monitoring system initialized');
        console.log(`📊 Metrics API: http://localhost:${MONITOR_PORT}`);
        console.log(`📝 Health log: ${HEALTH_LOG_FILE}`);
        console.log(`📈 Metrics log: ${METRICS_LOG_FILE}`);
        console.log(`🚨 Alert log: ${ALERT_LOG_FILE}`);
    }

    ensureLogDirectories() {
        const dirs = ['/var/log', path.dirname(HEALTH_LOG_FILE), path.dirname(METRICS_LOG_FILE)];
        dirs.forEach(dir => {
            if (!fs.existsSync(dir)) {
                fs.mkdirSync(dir, { recursive: true });
            }
        });
    }

    async startContinuousMonitoring() {
        this.isMonitoring = true;
        
        console.log(`🔄 Starting continuous monitoring (interval: ${MONITOR_INTERVAL}ms)`);
        
        while (this.isMonitoring) {
            try {
                await this.collectMetrics();
                await this.validateHealthStatus();
                await this.checkThresholds();
                await this.updateDashboard();
            } catch (error) {
                this.logAlert('MONITORING_ERROR', `Monitoring cycle failed: ${error.message}`, 'HIGH');
            }
            
            await this.sleep(MONITOR_INTERVAL);
        }
    }

    async collectMetrics() {
        const timestamp = new Date().toISOString();
        
        // Collect system metrics
        const systemMetrics = await this.getSystemMetrics();
        const healthMetrics = await this.getHealthMetrics();
        const trafficMetrics = await this.getTrafficMetrics();
        const deploymentMetrics = await this.getDeploymentMetrics();
        
        // Store metrics
        this.metrics.health.set(timestamp, healthMetrics);
        this.metrics.performance.set(timestamp, systemMetrics);
        this.metrics.traffic.set(timestamp, trafficMetrics);
        this.metrics.deployment.set(timestamp, deploymentMetrics);
        
        // Clean old metrics (keep last 1000 entries)
        this.cleanOldMetrics();
        
        // Log metrics
        this.logMetrics(timestamp, {
            system: systemMetrics,
            health: healthMetrics,
            traffic: trafficMetrics,
            deployment: deploymentMetrics
        });
    }

    async getSystemMetrics() {
        try {
            const metrics = {};
            
            // Docker container metrics
            const containers = ['nginx-proxy', 'blue-app', 'green-app', 'api-server'];
            for (const container of containers) {
                const stats = await this.getContainerStats(container);
                metrics[container] = stats;
            }
            
            // System-level metrics
            metrics.system = await this.getSystemStats();
            
            return metrics;
        } catch (error) {
            console.error('Error collecting system metrics:', error.message);
            return { error: error.message };
        }
    }

    async getContainerStats(containerName) {
        return new Promise((resolve) => {
            exec(`docker stats ${containerName} --no-stream --format "{{json .}}"`, (error, stdout) => {
                if (error) {
                    resolve({ error: error.message, running: false });
                    return;
                }
                
                try {
                    const stats = JSON.parse(stdout);
                    resolve({
                        running: true,
                        cpu: parseFloat(stats.CPUPerc?.replace('%', '') || '0'),
                        memory: parseFloat(stats.MemPerc?.replace('%', '') || '0'),
                        memoryUsage: stats.MemUsage,
                        networkIO: stats.NetIO,
                        blockIO: stats.BlockIO
                    });
                } catch (parseError) {
                    resolve({ error: parseError.message, running: false });
                }
            });
        });
    }

    async getSystemStats() {
        return new Promise((resolve) => {
            exec('free -m && df -h /', (error, stdout) => {
                if (error) {
                    resolve({ error: error.message });
                    return;
                }
                
                const lines = stdout.split('\n');
                const memoryLine = lines.find(line => line.startsWith('Mem:'));
                const diskLine = lines.find(line => line.includes('/dev/'));
                
                const memory = memoryLine ? memoryLine.split(/\s+/) : [];
                const disk = diskLine ? diskLine.split(/\s+/) : [];
                
                resolve({
                    memory: {
                        total: memory[1] ? parseInt(memory[1]) : 0,
                        used: memory[2] ? parseInt(memory[2]) : 0,
                        available: memory[6] ? parseInt(memory[6]) : 0
                    },
                    disk: {
                        size: disk[1] || 'unknown',
                        used: disk[2] || 'unknown',
                        available: disk[3] || 'unknown',
                        usage: disk[4] || 'unknown'
                    }
                });
            });
        });
    }

    async getHealthMetrics() {
        try {
            const health = {
                nginx: await this.checkServiceHealth('http://localhost:80/health'),
                blue: await this.checkServiceHealth('http://localhost:3001/health'),
                green: await this.checkServiceHealth('http://localhost:3002/health'),
                api: await this.checkServiceHealth('http://localhost:9000/health')
            };
            
            // Enhanced API health check
            try {
                const apiStatus = await this.httpRequest('http://localhost:9000/status');
                health.loadBalancer = {
                    active: apiStatus.active,
                    migration: apiStatus.migration?.status || 'stable',
                    healthy: true
                };
            } catch (error) {
                health.loadBalancer = {
                    error: error.message,
                    healthy: false
                };
            }
            
            return health;
        } catch (error) {
            console.error('Error collecting health metrics:', error.message);
            return { error: error.message };
        }
    }

    async checkServiceHealth(url) {
        const startTime = Date.now();
        try {
            const response = await this.httpRequest(url, 5000);
            const responseTime = Date.now() - startTime;
            
            return {
                healthy: true,
                responseTime,
                status: response.status || 'unknown',
                timestamp: new Date().toISOString()
            };
        } catch (error) {
            return {
                healthy: false,
                error: error.message,
                responseTime: Date.now() - startTime,
                timestamp: new Date().toISOString()
            };
        }
    }

    async getTrafficMetrics() {
        try {
            // Get NGINX access log metrics (last 100 lines)
            const accessLogMetrics = await this.analyzeAccessLogs();
            
            // Get current active environment
            const activeEnvironment = await this.getCurrentActiveEnvironment();
            
            return {
                activeEnvironment,
                accessLog: accessLogMetrics,
                timestamp: new Date().toISOString()
            };
        } catch (error) {
            console.error('Error collecting traffic metrics:', error.message);
            return { error: error.message };
        }
    }

    async analyzeAccessLogs() {
        return new Promise((resolve) => {
            exec('tail -n 100 /var/log/nginx/access.log 2>/dev/null || echo "No access log"', (error, stdout) => {
                if (error || stdout.includes('No access log')) {
                    resolve({ 
                        totalRequests: 0,
                        errorRequests: 0,
                        errorRate: 0,
                        averageResponseTime: 0
                    });
                    return;
                }
                
                const lines = stdout.trim().split('\n').filter(line => line.length > 0);
                const totalRequests = lines.length;
                const errorRequests = lines.filter(line => /\s(4\d\d|5\d\d)\s/.test(line)).length;
                const errorRate = totalRequests > 0 ? errorRequests / totalRequests : 0;
                
                // Extract response times (simplified parsing)
                const responseTimes = lines.map(line => {
                    const match = line.match(/response_time=(\d+\.?\d*)/);
                    return match ? parseFloat(match[1]) : 0;
                }).filter(time => time > 0);
                
                const averageResponseTime = responseTimes.length > 0 
                    ? responseTimes.reduce((sum, time) => sum + time, 0) / responseTimes.length
                    : 0;
                
                resolve({
                    totalRequests,
                    errorRequests,
                    errorRate: Math.round(errorRate * 10000) / 100, // Percentage with 2 decimals
                    averageResponseTime: Math.round(averageResponseTime * 1000) / 1000 // 3 decimal places
                });
            });
        });
    }

    async getCurrentActiveEnvironment() {
        try {
            const status = await this.httpRequest('http://localhost:9000/status', 3000);
            return {
                active: status.active || 'unknown',
                migration: status.migration || { status: 'stable' }
            };
        } catch (error) {
            return {
                active: 'unknown',
                error: error.message
            };
        }
    }

    async getDeploymentMetrics() {
        try {
            const migration = await this.httpRequest('http://localhost:9000/migration', 3000);
            
            return {
                status: migration.status || 'stable',
                active: migration.active || 'unknown',
                target: migration.target || null,
                percentage: migration.percentage || 0,
                startTime: migration.startTime || null,
                steps: migration.steps || [],
                uptime: Math.floor((Date.now() - this.startTime) / 1000)
            };
        } catch (error) {
            return {
                error: error.message,
                uptime: Math.floor((Date.now() - this.startTime) / 1000)
            };
        }
    }

    async validateHealthStatus() {
        const timestamp = new Date().toISOString();
        const healthMetrics = this.metrics.health.get(timestamp) || 
                             Array.from(this.metrics.health.values()).pop();
        
        if (!healthMetrics || healthMetrics.error) {
            this.logAlert('HEALTH_CHECK_FAILED', 'Unable to collect health metrics', 'HIGH');
            return;
        }
        
        // Check individual service health
        const services = ['nginx', 'blue', 'green', 'api'];
        for (const service of services) {
            const serviceHealth = healthMetrics[service];
            if (!serviceHealth?.healthy) {
                this.logAlert(
                    'SERVICE_UNHEALTHY', 
                    `${service.toUpperCase()} service is unhealthy: ${serviceHealth?.error || 'Unknown error'}`,
                    service === 'nginx' || service === 'api' ? 'CRITICAL' : 'HIGH'
                );
            }
        }
        
        // Log health status
        this.logHealth(timestamp, healthMetrics);
    }

    async checkThresholds() {
        const latestMetrics = this.getLatestMetrics();
        
        if (!latestMetrics) return;
        
        // Check response time thresholds
        if (latestMetrics.traffic?.accessLog?.averageResponseTime > this.thresholds.responseTime) {
            this.logAlert(
                'HIGH_RESPONSE_TIME',
                `Average response time ${latestMetrics.traffic.accessLog.averageResponseTime}ms exceeds threshold ${this.thresholds.responseTime}ms`,
                'MEDIUM'
            );
        }
        
        // Check error rate thresholds
        if (latestMetrics.traffic?.accessLog?.errorRate > this.thresholds.errorRate * 100) {
            this.logAlert(
                'HIGH_ERROR_RATE',
                `Error rate ${latestMetrics.traffic.accessLog.errorRate}% exceeds threshold ${this.thresholds.errorRate * 100}%`,
                'HIGH'
            );
        }
        
        // Check system resource thresholds
        const systemMetrics = latestMetrics.system;
        if (systemMetrics) {
            Object.keys(systemMetrics).forEach(container => {
                const stats = systemMetrics[container];
                if (stats.cpu > this.thresholds.cpuUsage * 100) {
                    this.logAlert(
                        'HIGH_CPU_USAGE',
                        `${container} CPU usage ${stats.cpu}% exceeds threshold ${this.thresholds.cpuUsage * 100}%`,
                        'MEDIUM'
                    );
                }
                
                if (stats.memory > this.thresholds.memoryUsage * 100) {
                    this.logAlert(
                        'HIGH_MEMORY_USAGE',
                        `${container} memory usage ${stats.memory}% exceeds threshold ${this.thresholds.memoryUsage * 100}%`,
                        'MEDIUM'
                    );
                }
            });
        }
    }

    getLatestMetrics() {
        const timestamps = Array.from(this.metrics.health.keys()).sort().reverse();
        if (timestamps.length === 0) return null;
        
        const latest = timestamps[0];
        return {
            health: this.metrics.health.get(latest),
            system: this.metrics.performance.get(latest),
            traffic: this.metrics.traffic.get(latest),
            deployment: this.metrics.deployment.get(latest)
        };
    }

    logAlert(type, message, severity) {
        const alert = {
            timestamp: new Date().toISOString(),
            type,
            message,
            severity
        };
        
        this.alerts.unshift(alert);
        
        // Keep only last 100 alerts
        if (this.alerts.length > 100) {
            this.alerts = this.alerts.slice(0, 100);
        }
        
        // Log to file
        const logEntry = `[${alert.timestamp}] ${severity}: ${type} - ${message}\n`;
        fs.appendFileSync(ALERT_LOG_FILE, logEntry);
        
        // Console output for critical alerts
        if (severity === 'CRITICAL') {
            console.error(`🚨 CRITICAL ALERT: ${message}`);
        } else if (severity === 'HIGH') {
            console.warn(`⚠️  HIGH ALERT: ${message}`);
        }
    }

    logHealth(timestamp, healthMetrics) {
        const logEntry = `[${timestamp}] ${JSON.stringify(healthMetrics)}\n`;
        fs.appendFileSync(HEALTH_LOG_FILE, logEntry);
    }

    logMetrics(timestamp, metrics) {
        const logEntry = `[${timestamp}] ${JSON.stringify(metrics)}\n`;
        fs.appendFileSync(METRICS_LOG_FILE, logEntry);
    }

    cleanOldMetrics() {
        const maxEntries = 1000;
        
        ['health', 'performance', 'traffic', 'deployment'].forEach(metricType => {
            const metric = this.metrics[metricType];
            if (metric.size > maxEntries) {
                const timestamps = Array.from(metric.keys()).sort();
                const toDelete = timestamps.slice(0, metric.size - maxEntries);
                toDelete.forEach(timestamp => metric.delete(timestamp));
            }
        });
    }

    async updateDashboard() {
        // Generate dashboard data
        const dashboard = this.generateDashboardData();
        
        // Write dashboard data to file for web interface
        const dashboardPath = '/tmp/bluegreen-dashboard.json';
        fs.writeFileSync(dashboardPath, JSON.stringify(dashboard, null, 2));
    }

    generateDashboardData() {
        const latest = this.getLatestMetrics();
        const alerts = this.alerts.slice(0, 10); // Last 10 alerts
        
        return {
            timestamp: new Date().toISOString(),
            status: this.getOverallStatus(latest),
            metrics: latest,
            alerts,
            uptime: Math.floor((Date.now() - this.startTime) / 1000),
            thresholds: this.thresholds
        };
    }

    getOverallStatus(metrics) {
        if (!metrics) return 'UNKNOWN';
        
        // Check for critical issues
        if (this.alerts.some(alert => alert.severity === 'CRITICAL' && 
            Date.now() - new Date(alert.timestamp).getTime() < 300000)) { // Last 5 minutes
            return 'CRITICAL';
        }
        
        // Check health status
        const health = metrics.health;
        if (health && !health.nginx?.healthy) return 'CRITICAL';
        if (health && !health.api?.healthy) return 'DEGRADED';
        if (health && (!health.blue?.healthy && !health.green?.healthy)) return 'CRITICAL';
        if (health && (!health.blue?.healthy || !health.green?.healthy)) return 'DEGRADED';
        
        // Check for high severity alerts
        if (this.alerts.some(alert => alert.severity === 'HIGH' && 
            Date.now() - new Date(alert.timestamp).getTime() < 600000)) { // Last 10 minutes
            return 'WARNING';
        }
        
        return 'HEALTHY';
    }

    startMetricsServer() {
        const server = http.createServer((req, res) => {
            res.setHeader('Access-Control-Allow-Origin', '*');
            res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
            res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
            
            if (req.method === 'OPTIONS') {
                res.writeHead(200);
                res.end();
                return;
            }
            
            try {
                if (req.url === '/health') {
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({
                        status: 'healthy',
                        service: 'enhanced-monitoring',
                        uptime: Math.floor((Date.now() - this.startTime) / 1000)
                    }));
                    return;
                }
                
                if (req.url === '/metrics') {
                    const metrics = this.getLatestMetrics();
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify(metrics || {}));
                    return;
                }
                
                if (req.url === '/dashboard') {
                    const dashboard = this.generateDashboardData();
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify(dashboard));
                    return;
                }
                
                if (req.url === '/alerts') {
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify(this.alerts.slice(0, 50)));
                    return;
                }
                
                res.writeHead(404, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Endpoint not found' }));
                
            } catch (error) {
                console.error('Metrics server error:', error);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Internal server error' }));
            }
        });
        
        server.listen(MONITOR_PORT, () => {
            console.log(`📊 Enhanced Monitoring Server running on port ${MONITOR_PORT}`);
            console.log(`   Health: http://localhost:${MONITOR_PORT}/health`);
            console.log(`   Metrics: http://localhost:${MONITOR_PORT}/metrics`);
            console.log(`   Dashboard: http://localhost:${MONITOR_PORT}/dashboard`);
            console.log(`   Alerts: http://localhost:${MONITOR_PORT}/alerts`);
        });
    }

    // Utility methods
    async httpRequest(url, timeout = 5000) {
        return new Promise((resolve, reject) => {
            const request = http.get(url, { timeout }, (response) => {
                let data = '';
                response.on('data', chunk => data += chunk);
                response.on('end', () => {
                    try {
                        const parsed = JSON.parse(data);
                        resolve(parsed);
                    } catch (error) {
                        resolve({ status: 'ok', raw: data });
                    }
                });
            });
            
            request.on('error', reject);
            request.on('timeout', () => {
                request.destroy();
                reject(new Error('Request timeout'));
            });
        });
    }

    sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    stop() {
        console.log('🛑 Stopping Enhanced Monitoring System...');
        this.isMonitoring = false;
    }
}

// Start monitoring system
const monitoringSystem = new EnhancedMonitoringSystem();

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('🛑 Enhanced Monitoring System shutting down...');
    monitoringSystem.stop();
    process.exit(0);
});

process.on('SIGINT', () => {
    console.log('🛑 Enhanced Monitoring System shutting down...');
    monitoringSystem.stop();
    process.exit(0);
});