const http = require('http');
const PORT = 3001;

const server = http.createServer((req, res) => {
    console.log(`Blue Server: ${req.method} ${req.url}`);
    
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'healthy', server: 'blue', version: '1.0.0' }));
        return;
    }
    
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`
        <html>
            <body style="background-color: #3498db; color: white; font-family: Arial;">
                <center>
                    <h1>BLUE SERVER - Version 1.0.0</h1>
                    <p>Timestamp: ${new Date().toISOString()}</p>
                    <p>Port: ${PORT}</p>
                    <p>Process ID: ${process.pid}</p>
                </center>
            </body>
        </html>
    `);
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`Blue server running on port ${PORT}`);
});
