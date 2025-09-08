const http = require('http');
const fs = require('fs');
const path = require('path');

// Environment configuration from environment variables
const PORT = process.env.SERVER_PORT || process.env.PORT || 3001;
const ENV_NAME = process.env.ENV_NAME || 'blue';
const VERSION = process.env.VERSION || '1.0.0';
const COLOR_THEME = process.env.COLOR_THEME || ENV_NAME;
const DEPLOYMENT_ID = process.env.DEPLOYMENT_ID || `${ENV_NAME}-default`;

// Color themes configuration
const THEMES = {
    blue: {
        name: 'BLUE',
        background: '#3498db',
        primary: '#2980b9',
        icon: '🔵'
    },
    green: {
        name: 'GREEN', 
        background: '#27ae60',
        primary: '#229954',
        icon: '🟢'
    }
};

// Get deployment metadata if available
function getDeploymentMetadata() {
    try {
        const metadataPath = '/app/deployment/metadata.json';
        if (fs.existsSync(metadataPath)) {
            return JSON.parse(fs.readFileSync(metadataPath, 'utf8'));
        }
    } catch (error) {
        console.log('No deployment metadata available:', error.message);
    }
    return null;
}

// Get current theme
const currentTheme = THEMES[COLOR_THEME] || THEMES.blue;
const deploymentMetadata = getDeploymentMetadata();

// Enhanced health check functions for ALB integration
async function checkDatabaseConnection() {
    // Simulate database connectivity check
    // In real implementation, this would check actual database connectivity
    return new Promise((resolve) => {
        setTimeout(() => {
            resolve(true);
        }, 10);
    });
}

async function checkExternalServices() {
    // Simulate external service checks
    // In real implementation, this would check dependent services
    return new Promise((resolve) => {
        setTimeout(() => {
            resolve(true);
        }, 10);
    });
}

async function performDeepHealthCheck() {
    try {
        // Database connectivity check
        const dbHealthy = await checkDatabaseConnection();
        
        // Memory usage check
        const memUsage = process.memoryUsage();
        const memHealthy = memUsage.heapUsed < memUsage.heapTotal * 0.9;
        
        // External services check
        const extServicesHealthy = await checkExternalServices();
        
        // Process uptime check (should be running for at least 10 seconds)
        const uptimeHealthy = process.uptime() > 10;
        
        // Response time check (simulate application response time)
        const startTime = process.hrtime();
        await new Promise(resolve => setTimeout(resolve, 1));
        const [seconds, nanoseconds] = process.hrtime(startTime);
        const responseTime = seconds * 1000 + nanoseconds / 1000000;
        const responseTimeHealthy = responseTime < 100; // Less than 100ms
        
        const checks = {
            database: dbHealthy ? 'ok' : 'failed',
            memory: memHealthy ? 'ok' : 'failed',
            externalServices: extServicesHealthy ? 'ok' : 'failed',
            uptime: uptimeHealthy ? 'ok' : 'failed',
            responseTime: responseTimeHealthy ? 'ok' : 'failed',
            details: {
                memoryUsage: memUsage,
                uptime: process.uptime(),
                responseTimeMs: responseTime.toFixed(2)
            }
        };
        
        const allHealthy = dbHealthy && memHealthy && extServicesHealthy && uptimeHealthy && responseTimeHealthy;
        
        return {
            healthy: allHealthy,
            checks: checks
        };
        
    } catch (error) {
        return {
            healthy: false,
            checks: {
                error: error.message
            }
        };
    }
}

const server = http.createServer(async (req, res) => {
    console.log(`${currentTheme.name} Server (${VERSION}): ${req.method} ${req.url}`);
    
    // Basic health check endpoint (NGINX level)
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end('healthy\n');
        return;
    }

    // Deep health check endpoint for ALB integration
    if (req.url === '/health/deep') {
        try {
            const healthStatus = await performDeepHealthCheck();
            
            if (healthStatus.healthy) {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({
                    status: 'healthy',
                    timestamp: new Date().toISOString(),
                    environment: ENV_NAME,
                    version: VERSION,
                    deployment_id: DEPLOYMENT_ID,
                    port: PORT,
                    checks: healthStatus.checks
                }));
            } else {
                res.writeHead(503, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({
                    status: 'unhealthy',
                    timestamp: new Date().toISOString(),
                    environment: ENV_NAME,
                    version: VERSION,
                    checks: healthStatus.checks
                }));
            }
        } catch (error) {
            res.writeHead(503, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                status: 'error',
                timestamp: new Date().toISOString(),
                environment: ENV_NAME,
                message: error.message
            }));
        }
        return;
    }

    // Legacy health endpoint with full information (backward compatibility)
    if (req.url === '/health/legacy') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
            status: 'healthy', 
            environment: ENV_NAME,
            server: ENV_NAME,
            version: VERSION,
            deployment_id: DEPLOYMENT_ID,
            theme: COLOR_THEME,
            port: PORT,
            timestamp: new Date().toISOString(),
            metadata: deploymentMetadata
        }));
        return;
    }

    // Version endpoint for deployment verification
    if (req.url === '/version') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            version: VERSION,
            deployment_id: DEPLOYMENT_ID,
            environment: ENV_NAME,
            build_time: deploymentMetadata?.build_time || 'Unknown',
            commit_hash: deploymentMetadata?.commit_hash || 'Unknown'
        }));
        return;
    }

    // Deployment info endpoint
    if (req.url === '/deployment') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            environment: ENV_NAME,
            version: VERSION,
            deployment_id: DEPLOYMENT_ID,
            color_theme: COLOR_THEME,
            port: PORT,
            process_id: process.pid,
            uptime: process.uptime(),
            memory_usage: process.memoryUsage(),
            metadata: deploymentMetadata,
            timestamp: new Date().toISOString()
        }));
        return;
    }
    
    // Main page with dynamic theming
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>True Blue-Green Deployment - ${currentTheme.name}</title>
            <style>
                body {
                    background: linear-gradient(135deg, ${currentTheme.background}, ${currentTheme.primary});
                    color: white;
                    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                    margin: 0;
                    padding: 20px;
                    min-height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                .container {
                    text-align: center;
                    background: rgba(255,255,255,0.1);
                    padding: 40px;
                    border-radius: 15px;
                    backdrop-filter: blur(10px);
                    box-shadow: 0 8px 32px rgba(0,0,0,0.1);
                    max-width: 600px;
                }
                .server-info {
                    background: rgba(255,255,255,0.2);
                    padding: 20px;
                    border-radius: 10px;
                    margin: 20px 0;
                    text-align: left;
                }
                .deployment-info {
                    background: rgba(0,0,0,0.2);
                    padding: 15px;
                    border-radius: 8px;
                    margin: 15px 0;
                    font-family: monospace;
                    text-align: left;
                }
                .status-indicator {
                    display: inline-block;
                    width: 12px;
                    height: 12px;
                    background: #2ecc71;
                    border-radius: 50%;
                    margin-right: 8px;
                    animation: pulse 2s infinite;
                }
                @keyframes pulse {
                    0% { opacity: 1; }
                    50% { opacity: 0.5; }
                    100% { opacity: 1; }
                }
                .links {
                    margin-top: 30px;
                }
                .links a {
                    color: white;
                    text-decoration: none;
                    margin: 0 10px;
                    padding: 8px 16px;
                    border: 1px solid rgba(255,255,255,0.3);
                    border-radius: 5px;
                    transition: all 0.3s ease;
                }
                .links a:hover {
                    background: rgba(255,255,255,0.2);
                    border-color: white;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>${currentTheme.icon} ${currentTheme.name} ENVIRONMENT</h1>
                <h2>True Blue-Green Deployment - Version ${VERSION}</h2>
                <div class="status-indicator"></div>
                <span>Environment Active & Healthy</span>
                
                <div class="server-info">
                    <h3>Server Information</h3>
                    <p><strong>Environment:</strong> ${ENV_NAME}</p>
                    <p><strong>Version:</strong> ${VERSION}</p>
                    <p><strong>Deployment ID:</strong> ${DEPLOYMENT_ID}</p>
                    <p><strong>Port:</strong> ${PORT}</p>
                    <p><strong>Process ID:</strong> ${process.pid}</p>
                    <p><strong>Uptime:</strong> ${Math.floor(process.uptime())} seconds</p>
                    <p><strong>Timestamp:</strong> ${new Date().toISOString()}</p>
                </div>

                ${deploymentMetadata ? `
                <div class="deployment-info">
                    <h3>Deployment Metadata</h3>
                    <p><strong>Build Time:</strong> ${deploymentMetadata.build_time || 'Unknown'}</p>
                    <p><strong>Commit Hash:</strong> ${deploymentMetadata.commit_hash || 'Unknown'}</p>
                    <p><strong>Branch:</strong> ${deploymentMetadata.branch || 'Unknown'}</p>
                    ${deploymentMetadata.pipeline_id ? `<p><strong>Pipeline:</strong> ${deploymentMetadata.pipeline_id}</p>` : ''}
                </div>
                ` : ''}

                <div class="links">
                    <a href="/health">Health Check</a>
                    <a href="/version">Version Info</a>
                    <a href="/deployment">Deployment Details</a>
                </div>

                <div style="margin-top: 30px; font-size: 14px; opacity: 0.8;">
                    <p>🚀 <strong>True Blue-Green Deployment</strong></p>
                    <p>Identical environments • Dynamic versioning • Zero-downtime switching</p>
                </div>
            </div>
        </body>
        </html>
    `);
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 ${currentTheme.icon} ${currentTheme.name} Server started successfully`);
    console.log(`   Environment: ${ENV_NAME}`);
    console.log(`   Version: ${VERSION}`);
    console.log(`   Deployment ID: ${DEPLOYMENT_ID}`);
    console.log(`   Port: ${PORT}`);
    console.log(`   Color Theme: ${COLOR_THEME}`);
    console.log(`   Health Check: http://localhost:${PORT}/health`);
    console.log(`   Version Info: http://localhost:${PORT}/version`);
    console.log(`   Deployment Info: http://localhost:${PORT}/deployment`);
    
    if (deploymentMetadata) {
        console.log(`   📦 Deployment metadata loaded`);
        console.log(`      Build: ${deploymentMetadata.build_time || 'Unknown'}`);
        console.log(`      Commit: ${deploymentMetadata.commit_hash || 'Unknown'}`);
    } else {
        console.log(`   📦 No deployment metadata found`);
    }
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log(`🛑 ${currentTheme.name} Server shutting down gracefully...`);
    server.close(() => {
        console.log(`✅ ${currentTheme.name} Server closed`);
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    console.log(`🛑 ${currentTheme.name} Server shutting down gracefully...`);
    server.close(() => {
        console.log(`✅ ${currentTheme.name} Server closed`);
        process.exit(0);
    });
});