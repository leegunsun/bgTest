const http = require('http');
const { exec } = require('child_process');
const PORT = 9000;

const server = http.createServer((req, res) => {
    console.log(`API Server: ${req.method} ${req.url}`);
    
    // CORS 헤더 추가
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    
    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }
    
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
            status: 'healthy', 
            service: 'api-server',
            version: '2.0.0',
            timestamp: new Date().toISOString(),
            architecture: 'separated-containers'
        }));
        return;
    }
    
    // Status endpoint to check current deployment
    if (req.url === '/status') {
        exec('docker exec nginx-proxy cat /etc/nginx/conf.d/active.env', (error, stdout, stderr) => {
            if (error) {
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ 
                    success: false, 
                    error: 'Cannot determine current deployment status' 
                }));
                return;
            }
            
            const activeMatch = stdout.match(/set \$active "(\w+)"/);
            const currentActive = activeMatch ? activeMatch[1] : 'unknown';
            
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                success: true,
                current_deployment: currentActive,
                timestamp: new Date().toISOString()
            }));
        });
        return;
    }
    
    if (req.url === '/switch/blue' && req.method === 'POST') {
        console.log('🔵 Initiating switch to BLUE deployment');
        
        // Execute nginx-switch script inside nginx container
        exec('docker exec nginx-proxy /usr/local/bin/nginx-switch.sh blue', (error, stdout, stderr) => {
            if (error) {
                console.error(`❌ Error switching to blue: ${error}`);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ 
                    success: false, 
                    error: error.message,
                    stderr: stderr
                }));
                return;
            }
            
            console.log('✅ Successfully switched to BLUE');
            console.log('Switch output:', stdout);
            
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ 
                success: true, 
                deployment: 'blue',
                message: 'Successfully switched to BLUE deployment',
                details: stdout
            }));
        });
        
    } else if (req.url === '/switch/green' && req.method === 'POST') {
        console.log('🟢 Initiating switch to GREEN deployment');
        
        // Execute nginx-switch script inside nginx container
        exec('docker exec nginx-proxy /usr/local/bin/nginx-switch.sh green', (error, stdout, stderr) => {
            if (error) {
                console.error(`❌ Error switching to green: ${error}`);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ 
                    success: false, 
                    error: error.message,
                    stderr: stderr
                }));
                return;
            }
            
            console.log('✅ Successfully switched to GREEN');
            console.log('Switch output:', stdout);
            
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ 
                success: true, 
                deployment: 'green',
                message: 'Successfully switched to GREEN deployment',
                details: stdout
            }));
        });
        
    } else {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
            error: 'Not found',
            available_endpoints: [
                'GET /health - Service health check',
                'GET /status - Current deployment status',
                'POST /switch/blue - Switch traffic to Blue',
                'POST /switch/green - Switch traffic to Green'
            ]
        }));
    }
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`🔧 API Server v2.0 running on port ${PORT}`);
    console.log(`🏗️  Architecture: Separated Containers`);
    console.log(`📡 Health check: http://localhost:${PORT}/health`);
    console.log(`📊 Deployment status: http://localhost:${PORT}/status`);
    console.log(`🔵 Switch to Blue: POST http://localhost:${PORT}/switch/blue`);
    console.log(`🟢 Switch to Green: POST http://localhost:${PORT}/switch/green`);
    console.log(`ℹ️  Traffic switching via NGINX container communication`);
});