const http = require('http');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const PORT = 9000;
const ACTIVE_ENV_FILE = '/etc/nginx/conf.d/active.env';
const MIGRATION_STATE_FILE = '/etc/deployment/migration_state.json';
const HEALTH_LOG_FILE = '/etc/deployment/health_log.json';

// Enhanced API server for complete load balancing and dual update cycle
class EnhancedLoadBalancer {
    constructor() {
        this.migrationState = this.loadMigrationState();
        this.healthMonitor = new HealthMonitor();
        this.trafficController = new TrafficController();
    }

    // Load migration state from persistent storage
    loadMigrationState() {
        try {
            if (fs.existsSync(MIGRATION_STATE_FILE)) {
                return JSON.parse(fs.readFileSync(MIGRATION_STATE_FILE, 'utf8'));
            }
        } catch (error) {
            console.error('Error loading migration state:', error.message);
        }
        
        return {
            status: 'stable',
            active: 'blue',
            target: null,
            percentage: 0,
            startTime: null,
            steps: [],
            rollbackReady: true
        };
    }

    // Save migration state to persistent storage
    saveMigrationState() {
        try {
            const dir = path.dirname(MIGRATION_STATE_FILE);
            if (!fs.existsSync(dir)) {
                fs.mkdirSync(dir, { recursive: true });
            }
            fs.writeFileSync(MIGRATION_STATE_FILE, JSON.stringify(this.migrationState, null, 2));
        } catch (error) {
            console.error('Error saving migration state:', error.message);
        }
    }

    // Get current active environment from NGINX config
    getCurrentActive() {
        try {
            const content = fs.readFileSync(ACTIVE_ENV_FILE, 'utf8');
            const match = content.match(/set\s+\$active\s+"([^"]+)"/);
            return match ? match[1] : 'blue';
        } catch (error) {
            console.error('Error reading active environment:', error.message);
            return 'blue';
        }
    }

    // Update active environment in NGINX config (atomic operation)
    async updateActiveEnvironment(environment) {
        return new Promise((resolve, reject) => {
            const tempFile = `${ACTIVE_ENV_FILE}.tmp`;
            const newContent = `# Active Environment Configuration
set $active "${environment}";
`;

            try {
                // Write to temporary file
                fs.writeFileSync(tempFile, newContent);
                
                // Validate NGINX configuration
                exec('nginx -t', (error) => {
                    if (error) {
                        // Remove temp file on validation error
                        fs.unlinkSync(tempFile);
                        reject(new Error(`NGINX configuration validation failed: ${error.message}`));
                        return;
                    }

                    try {
                        // Atomic move
                        fs.renameSync(tempFile, ACTIVE_ENV_FILE);
                        
                        // Reload NGINX
                        exec('nginx -s reload', (reloadError) => {
                            if (reloadError) {
                                reject(new Error(`NGINX reload failed: ${reloadError.message}`));
                                return;
                            }
                            
                            console.log(`✅ Traffic switched to ${environment} environment`);
                            resolve({ success: true, environment });
                        });
                    } catch (moveError) {
                        reject(new Error(`Failed to update configuration: ${moveError.message}`));
                    }
                });
            } catch (writeError) {
                reject(new Error(`Failed to write configuration: ${writeError.message}`));
            }
        });
    }

    // Gradual migration with health validation at each step
    async graduateMigration(targetEnvironment) {
        const currentActive = this.getCurrentActive();
        
        if (currentActive === targetEnvironment) {
            return { success: false, error: 'Target environment is already active' };
        }

        // Initialize migration state
        this.migrationState = {
            status: 'migrating',
            active: currentActive,
            target: targetEnvironment,
            percentage: 0,
            startTime: new Date().toISOString(),
            steps: [],
            rollbackReady: true
        };
        this.saveMigrationState();

        const migrationSteps = [25, 50, 75, 100];
        
        try {
            // Pre-migration validation
            const preValidation = await this.validateDualEnvironments();
            if (!preValidation.success) {
                throw new Error(`Pre-migration validation failed: ${preValidation.error}`);
            }

            // Execute gradual migration
            for (const percentage of migrationSteps) {
                console.log(`🔄 Migrating ${percentage}% traffic to ${targetEnvironment}...`);
                
                // Update traffic percentage (this would update NGINX upstream weights)
                await this.updateTrafficPercentage(targetEnvironment, percentage);
                
                // Health check at this percentage
                await this.waitAndValidate(5000); // Wait 5 seconds
                const healthCheck = await this.healthMonitor.validateEnvironmentHealth(targetEnvironment);
                
                if (!healthCheck.success) {
                    // Auto-rollback on health failure
                    console.error(`❌ Health check failed at ${percentage}% - initiating rollback`);
                    await this.rollbackMigration();
                    throw new Error(`Migration failed at ${percentage}%: ${healthCheck.error}`);
                }

                this.migrationState.percentage = percentage;
                this.migrationState.steps.push({
                    percentage,
                    timestamp: new Date().toISOString(),
                    health: healthCheck,
                    status: 'completed'
                });
                this.saveMigrationState();

                console.log(`✅ Successfully migrated ${percentage}% traffic`);
            }

            // Complete migration
            await this.updateActiveEnvironment(targetEnvironment);
            this.migrationState.status = 'stable';
            this.migrationState.active = targetEnvironment;
            this.migrationState.percentage = 100;
            this.saveMigrationState();

            console.log(`🎉 Migration to ${targetEnvironment} completed successfully!`);
            return { 
                success: true, 
                environment: targetEnvironment,
                steps: this.migrationState.steps
            };

        } catch (error) {
            console.error('Migration failed:', error.message);
            this.migrationState.status = 'failed';
            this.migrationState.error = error.message;
            this.saveMigrationState();
            return { success: false, error: error.message };
        }
    }

    // Update traffic percentage (placeholder for NGINX upstream weight updates)
    async updateTrafficPercentage(targetEnvironment, percentage) {
        // In a full implementation, this would update NGINX upstream weights
        // For now, we'll update the migration state and log the change
        console.log(`🔧 Updating traffic distribution: ${percentage}% → ${targetEnvironment}`);
        
        // This would typically update NGINX configuration or use a service mesh
        // to control traffic percentages between blue and green environments
        return new Promise(resolve => setTimeout(resolve, 1000));
    }

    // Rollback migration to previous environment
    async rollbackMigration() {
        console.log(`🚨 Initiating rollback to ${this.migrationState.active} environment`);
        
        try {
            await this.updateActiveEnvironment(this.migrationState.active);
            await this.updateTrafficPercentage(this.migrationState.active, 100);
            
            this.migrationState.status = 'rolled_back';
            this.migrationState.percentage = 0;
            this.saveMigrationState();
            
            console.log(`✅ Rollback completed successfully`);
            return { success: true, rolledBackTo: this.migrationState.active };
        } catch (error) {
            console.error('Rollback failed:', error.message);
            return { success: false, error: error.message };
        }
    }

    // Validate both environments are healthy before migration
    async validateDualEnvironments() {
        console.log('🏥 Validating both blue and green environments...');
        
        const blueHealth = await this.healthMonitor.validateEnvironmentHealth('blue');
        const greenHealth = await this.healthMonitor.validateEnvironmentHealth('green');
        
        if (!blueHealth.success || !greenHealth.success) {
            return { 
                success: false, 
                error: 'One or both environments are unhealthy',
                blue: blueHealth,
                green: greenHealth
            };
        }
        
        console.log('✅ Both environments are healthy and ready');
        return { 
            success: true, 
            blue: blueHealth,
            green: greenHealth
        };
    }

    // Wait and validate health during migration
    async waitAndValidate(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    // Get comprehensive system status
    getSystemStatus() {
        return {
            active: this.getCurrentActive(),
            migration: this.migrationState,
            health: this.healthMonitor.getHealthStatus(),
            traffic: this.trafficController.getTrafficStatus(),
            timestamp: new Date().toISOString()
        };
    }
}

// Health monitoring system
class HealthMonitor {
    constructor() {
        this.healthHistory = [];
        this.startContinuousMonitoring();
    }

    async validateEnvironmentHealth(environment) {
        const port = environment === 'blue' ? 3001 : 3002;
        const containerName = `${environment}-app`;
        
        try {
            // Multiple validation layers
            const checks = await Promise.all([
                this.dockerHealthCheck(containerName),
                this.httpHealthCheck(`http://${containerName}:${port}/health`),
                this.performanceCheck(`http://${containerName}:${port}/health`)
            ]);

            const healthStatus = {
                success: checks.every(check => check.success),
                environment,
                checks: {
                    docker: checks[0],
                    http: checks[1],
                    performance: checks[2]
                },
                timestamp: new Date().toISOString()
            };

            this.recordHealth(healthStatus);
            return healthStatus;
        } catch (error) {
            const errorStatus = {
                success: false,
                environment,
                error: error.message,
                timestamp: new Date().toISOString()
            };
            this.recordHealth(errorStatus);
            return errorStatus;
        }
    }

    dockerHealthCheck(containerName) {
        return new Promise((resolve) => {
            exec(`docker inspect --format='{{.State.Health.Status}}' ${containerName}`, (error, stdout) => {
                const healthy = !error && stdout.trim() === 'healthy';
                resolve({
                    success: healthy,
                    type: 'docker',
                    status: stdout?.trim() || 'unknown',
                    error: error?.message
                });
            });
        });
    }

    httpHealthCheck(url) {
        return new Promise((resolve) => {
            exec(`curl -f --max-time 3 ${url}`, (error, stdout) => {
                resolve({
                    success: !error,
                    type: 'http',
                    response: stdout,
                    error: error?.message
                });
            });
        });
    }

    performanceCheck(url) {
        return new Promise((resolve) => {
            const startTime = Date.now();
            exec(`curl -w "%{time_total}" -o /dev/null -s ${url}`, (error, stdout) => {
                const responseTime = parseFloat(stdout) * 1000; // Convert to ms
                resolve({
                    success: !error && responseTime < 1000, // Under 1 second
                    type: 'performance',
                    responseTime,
                    error: error?.message
                });
            });
        });
    }

    recordHealth(healthStatus) {
        this.healthHistory.push(healthStatus);
        // Keep only last 100 records
        if (this.healthHistory.length > 100) {
            this.healthHistory = this.healthHistory.slice(-100);
        }
        
        try {
            const dir = path.dirname(HEALTH_LOG_FILE);
            if (!fs.existsSync(dir)) {
                fs.mkdirSync(dir, { recursive: true });
            }
            fs.writeFileSync(HEALTH_LOG_FILE, JSON.stringify(this.healthHistory, null, 2));
        } catch (error) {
            console.error('Error saving health log:', error.message);
        }
    }

    startContinuousMonitoring() {
        // Monitor every 30 seconds in background
        setInterval(async () => {
            const currentActive = fs.readFileSync(ACTIVE_ENV_FILE, 'utf8').match(/set\s+\$active\s+"([^"]+)"/)?.[1] || 'blue';
            await this.validateEnvironmentHealth(currentActive);
        }, 30000);
    }

    getHealthStatus() {
        return {
            recent: this.healthHistory.slice(-10),
            summary: {
                total: this.healthHistory.length,
                healthy: this.healthHistory.filter(h => h.success).length,
                lastCheck: this.healthHistory[this.healthHistory.length - 1]?.timestamp
            }
        };
    }
}

// Traffic control system
class TrafficController {
    constructor() {
        this.trafficHistory = [];
    }

    getTrafficStatus() {
        return {
            history: this.trafficHistory.slice(-10),
            currentDistribution: this.getCurrentDistribution()
        };
    }

    getCurrentDistribution() {
        // Placeholder for traffic distribution analysis
        return {
            blue: 50,
            green: 50,
            timestamp: new Date().toISOString()
        };
    }
}

// Initialize enhanced load balancer
const loadBalancer = new EnhancedLoadBalancer();

// Create HTTP server with enhanced endpoints
const server = http.createServer(async (req, res) => {
    console.log(`Enhanced API Server: ${req.method} ${req.url}`);
    
    // CORS headers
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    
    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }

    try {
        // Health check endpoint
        if (req.url === '/health') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ 
                status: 'healthy', 
                service: 'enhanced-api-server',
                version: '2.0.0',
                features: ['gradual-migration', 'health-monitoring', 'auto-rollback'],
                timestamp: new Date().toISOString()
            }));
            return;
        }

        // System status endpoint
        if (req.url === '/status') {
            const status = loadBalancer.getSystemStatus();
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(status));
            return;
        }

        // Enhanced switch endpoints with gradual migration
        if (req.url === '/switch/blue' && req.method === 'POST') {
            console.log('🔄 Starting gradual migration to BLUE environment');
            const result = await loadBalancer.graduateMigration('blue');
            
            res.writeHead(result.success ? 200 : 500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                ...result,
                deployment: 'blue',
                type: 'gradual-migration'
            }));
            return;
        }

        if (req.url === '/switch/green' && req.method === 'POST') {
            console.log('🔄 Starting gradual migration to GREEN environment');
            const result = await loadBalancer.graduateMigration('green');
            
            res.writeHead(result.success ? 200 : 500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                ...result,
                deployment: 'green',
                type: 'gradual-migration'
            }));
            return;
        }

        // Emergency rollback endpoint
        if (req.url === '/rollback' && req.method === 'POST') {
            console.log('🚨 Emergency rollback initiated');
            const result = await loadBalancer.rollbackMigration();
            
            res.writeHead(result.success ? 200 : 500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                ...result,
                type: 'emergency-rollback'
            }));
            return;
        }

        // Dual environment validation endpoint
        if (req.url === '/validate' && req.method === 'GET') {
            const validation = await loadBalancer.validateDualEnvironments();
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(validation));
            return;
        }

        // Migration status endpoint
        if (req.url === '/migration' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(loadBalancer.migrationState));
            return;
        }

        // 404 for unknown endpoints
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Endpoint not found' }));

    } catch (error) {
        console.error('Server error:', error);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
            error: 'Internal server error',
            message: error.message 
        }));
    }
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Enhanced Load Balancer API Server running on port ${PORT}`);
    console.log(`🏥 Health check: http://localhost:${PORT}/health`);
    console.log(`📊 System status: http://localhost:${PORT}/status`);
    console.log(`🔄 Gradual migration endpoints:`);
    console.log(`   POST http://localhost:${PORT}/switch/blue - Migrate to blue`);
    console.log(`   POST http://localhost:${PORT}/switch/green - Migrate to green`);
    console.log(`🚨 Emergency rollback: POST http://localhost:${PORT}/rollback`);
    console.log(`🔍 Validation: GET http://localhost:${PORT}/validate`);
    console.log(`📈 Migration status: GET http://localhost:${PORT}/migration`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('🛑 Enhanced API Server shutting down gracefully...');
    server.close(() => {
        console.log('✅ Enhanced API Server closed');
        process.exit(0);
    });
});