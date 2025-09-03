const http = require('http');
const fs = require('fs');
const PORT = 9000;

// Configuration paths
const ACTIVE_ENV_PATH = '/etc/nginx/conf.d/active.env';
const NGINX_ADMIN_BASE_URL = 'http://nginx-proxy:8081/admin';

const server = http.createServer((req, res) => {
    console.log(`API Server: ${req.method} ${req.url}`);
    
    // CORS headers
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    
    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }
    
    // Health check endpoint
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
            status: 'healthy', 
            service: 'api-server',
            version: '3.0.0',
            timestamp: new Date().toISOString(),
            architecture: 'zero-downtime-blue-green',
            communication: 'http-api-based'
        }));
        return;
    }
    
    // Status endpoint - shared volume based (no docker exec)
    if (req.url === '/status') {
        try {
            const activeConfig = fs.readFileSync(ACTIVE_ENV_PATH, 'utf8');
            const activeMatch = activeConfig.match(/set \$active "(\w+)"/);
            const currentActive = activeMatch ? activeMatch[1] : 'blue';
            
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                success: true,
                current_deployment: currentActive,
                timestamp: new Date().toISOString(),
                method: 'shared_volume',
                communication: 'no_docker_exec'
            }));
        } catch (error) {
            console.error('Error reading deployment status:', error);
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ 
                success: false, 
                current_deployment: 'blue', // safe default
                error: 'Cannot read deployment status from shared volume',
                timestamp: new Date().toISOString()
            }));
        }
        return;
    }
    
    // Switch to Blue deployment - HTTP API based
    if (req.url === '/switch/blue' && req.method === 'POST') {
        console.log('🔵 Initiating switch to BLUE deployment via HTTP API');
        
        switchTraffic('blue', (success, result) => {
            if (success) {
                console.log('✅ Successfully switched to BLUE via HTTP API');
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ 
                    success: true, 
                    deployment: 'blue',
                    message: 'Successfully switched to BLUE deployment',
                    method: 'http_api',
                    details: result
                }));
            } else {
                console.error('❌ Failed to switch to BLUE:', result.error);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ 
                    success: false, 
                    error: result.error,
                    method: 'http_api'
                }));
            }
        });
        return;
    }
    
    // Switch to Green deployment - HTTP API based  
    if (req.url === '/switch/green' && req.method === 'POST') {
        console.log('🟢 Initiating switch to GREEN deployment via HTTP API');
        
        switchTraffic('green', (success, result) => {
            if (success) {
                console.log('✅ Successfully switched to GREEN via HTTP API');
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ 
                    success: true, 
                    deployment: 'green',
                    message: 'Successfully switched to GREEN deployment',
                    method: 'http_api',
                    details: result
                }));
            } else {
                console.error('❌ Failed to switch to GREEN:', result.error);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ 
                    success: false, 
                    error: result.error,
                    method: 'http_api'
                }));
            }
        });
        return;
    }
    
    // Default 404 response
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ 
        error: 'Not found',
        available_endpoints: [
            'GET /health - Service health check',
            'GET /status - Current deployment status (shared volume)',
            'POST /switch/blue - Switch traffic to Blue (HTTP API)',
            'POST /switch/green - Switch traffic to Green (HTTP API)'
        ],
        communication_method: 'http_api_based',
        no_docker_exec: true
    }));
});

/**
 * Switch traffic using HTTP API call to NGINX admin endpoint
 * @param {string} target - 'blue' or 'green'
 * @param {function} callback - callback(success, result)
 */
function switchTraffic(target, callback) {
    const switchUrl = `${NGINX_ADMIN_BASE_URL}/switch/${target}`;
    
    const request = http.request(switchUrl, {
        method: 'POST',
        headers: { 
            'Content-Type': 'application/json',
            'User-Agent': 'BlueGreen-API-v3.0'
        },
        timeout: 10000
    }, (response) => {
        let responseData = '';
        
        response.on('data', (chunk) => {
            responseData += chunk;
        });
        
        response.on('end', () => {
            try {
                const result = JSON.parse(responseData);
                callback(response.statusCode === 200, result);
            } catch (parseError) {
                console.error('Error parsing NGINX admin response:', parseError);
                callback(false, { 
                    error: 'Failed to parse NGINX admin response',
                    details: responseData 
                });
            }
        });
    });
    
    request.on('error', (error) => {
        console.error(`HTTP API request error for ${target}:`, error);
        callback(false, { 
            error: `HTTP API communication failed: ${error.message}`,
            target: target
        });
    });
    
    request.on('timeout', () => {
        console.error(`HTTP API request timeout for ${target}`);
        request.destroy();
        callback(false, { 
            error: 'HTTP API request timeout',
            target: target
        });
    });
    
    // Send the request
    request.end(JSON.stringify({ 
        target: target, 
        timestamp: new Date().toISOString(),
        source: 'api-server-v3'
    }));
}

server.listen(PORT, '0.0.0.0', () => {
    console.log(`🔧 Zero-Downtime Blue-Green API Server v3.0 running on port ${PORT}`);
    console.log(`🏗️  Architecture: HTTP API based communication`);
    console.log(`📡 Health check: http://localhost:${PORT}/health`);
    console.log(`📊 Deployment status: http://localhost:${PORT}/status`);
    console.log(`🔵 Switch to Blue: POST http://localhost:${PORT}/switch/blue`);
    console.log(`🟢 Switch to Green: POST http://localhost:${PORT}/switch/green`);
    console.log(`✅ No Docker Socket dependency - Pure HTTP API communication`);
    console.log(`📁 Shared volume path: ${ACTIVE_ENV_PATH}`);
});