const http = require('http');
const fs = require('fs').promises;
const { exec } = require('child_process');
const { promisify } = require('util');
const execAsync = promisify(exec);

const PORT = 9000;
const ACTIVE_ENV_FILE = '/etc/nginx/conf.d/active.env';

const server = http.createServer(async (req, res) => {
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
    
    if (req.url === '/status') {
        try {
            const currentActive = await getCurrentActiveEnvironment();
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ 
                current_deployment: currentActive,
                timestamp: new Date().toISOString(),
                service: 'api-server'
            }));
        } catch (error) {
            console.error(`Error getting status: ${error}`);
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ 
                error: error.message,
                current_deployment: 'unknown'
            }));
        }
        return;
    }
    
    if ((req.url === '/switch/blue' || req.url === '/switch/green') && req.method === 'POST') {
        const targetEnv = req.url === '/switch/blue' ? 'blue' : 'green';
        console.log(`Switching to ${targetEnv.toUpperCase()} deployment`);
        
        try {
            // Check current environment
            const currentActive = await getCurrentActiveEnvironment();
            
            if (currentActive === targetEnv) {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ 
                    success: true, 
                    deployment: targetEnv,
                    message: `${targetEnv.toUpperCase()} environment is already active`,
                    was_already_active: true
                }));
                return;
            }
            
            // Perform the switch
            await switchEnvironment(targetEnv);
            
            console.log(`Successfully switched to ${targetEnv.toUpperCase()}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ 
                success: true, 
                deployment: targetEnv,
                previous_deployment: currentActive,
                message: `Successfully switched to ${targetEnv.toUpperCase()} deployment`,
                timestamp: new Date().toISOString()
            }));
            
        } catch (error) {
            console.error(`Error switching to ${targetEnv}: ${error}`);
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ 
                success: false, 
                error: error.message,
                deployment: targetEnv
            }));
        }
        
    } else {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Not found' }));
    }
});

// Get current active environment from file
async function getCurrentActiveEnvironment() {
    try {
        const content = await fs.readFile(ACTIVE_ENV_FILE, 'utf8');
        const match = content.match(/set\s+\$active\s+"([^"]+)"/);
        return match ? match[1] : 'unknown';
    } catch (error) {
        console.error(`Error reading active environment file: ${error.message}`);
        return 'unknown';
    }
}

// Switch environment by updating active.env file and reloading NGINX
async function switchEnvironment(targetEnv) {
    try {
        // Create new configuration content
        const newContent = `set $active "${targetEnv}";`;
        
        // Write to file atomically using temporary file
        const tempFile = `${ACTIVE_ENV_FILE}.tmp`;
        await fs.writeFile(tempFile, newContent + '\n', 'utf8');
        
        // Atomic move (rename)
        await fs.rename(tempFile, ACTIVE_ENV_FILE);
        
        console.log(`Updated active environment file to: ${targetEnv}`);
        
        // Reload NGINX configuration using Docker network call
        try {
            await execAsync('docker exec nginx-proxy nginx -t');
            console.log('NGINX configuration validation passed');
            
            await execAsync('docker exec nginx-proxy nginx -s reload');
            console.log('NGINX configuration reloaded successfully');
            
        } catch (nginxError) {
            console.error(`NGINX operation failed: ${nginxError.message}`);
            // Try to rollback the file change
            try {
                const previousEnv = targetEnv === 'blue' ? 'green' : 'blue';
                const rollbackContent = `set $active "${previousEnv}";`;
                await fs.writeFile(ACTIVE_ENV_FILE, rollbackContent + '\n', 'utf8');
                console.log(`Rolled back configuration to: ${previousEnv}`);
            } catch (rollbackError) {
                console.error(`Rollback failed: ${rollbackError.message}`);
            }
            throw nginxError;
        }
        
    } catch (error) {
        console.error(`Environment switch failed: ${error.message}`);
        throw error;
    }
}

server.listen(PORT, '0.0.0.0', () => {
    console.log(`🔧 API Server running on port ${PORT}`);
    console.log(`📡 Health check: http://localhost:${PORT}/health`);
    console.log(`📊 Status: http://localhost:${PORT}/status`);
    console.log(`🔵 Switch to Blue: POST http://localhost:${PORT}/switch/blue`);
    console.log(`🟢 Switch to Green: POST http://localhost:${PORT}/switch/green`);
    console.log(`📁 Active env file: ${ACTIVE_ENV_FILE}`);
});