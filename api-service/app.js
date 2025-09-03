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
            version: '1.0.0',
            timestamp: new Date().toISOString()
        }));
        return;
    }
    
    if (req.url === '/switch/blue' && req.method === 'POST') {
        console.log('Switching to BLUE deployment');
        
        exec('/app/switch-deployment.sh blue', (error, stdout, stderr) => {
            if (error) {
                console.error(`Error switching to blue: ${error}`);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, error: error.message }));
                return;
            }
            
            console.log('Successfully switched to BLUE');
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ 
                success: true, 
                deployment: 'blue',
                message: 'Successfully switched to BLUE deployment'
            }));
        });
        
    } else if (req.url === '/switch/green' && req.method === 'POST') {
        console.log('Switching to GREEN deployment');
        
        exec('/app/switch-deployment.sh green', (error, stdout, stderr) => {
            if (error) {
                console.error(`Error switching to green: ${error}`);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, error: error.message }));
                return;
            }
            
            console.log('Successfully switched to GREEN');
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ 
                success: true, 
                deployment: 'green',
                message: 'Successfully switched to GREEN deployment'
            }));
        });
        
    } else {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Not found' }));
    }
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`🔧 API Server running on port ${PORT}`);
    console.log(`📡 Health check: http://localhost:${PORT}/health`);
    console.log(`🔵 Switch to Blue: POST http://localhost:${PORT}/switch/blue`);
    console.log(`🟢 Switch to Green: POST http://localhost:${PORT}/switch/green`);
});