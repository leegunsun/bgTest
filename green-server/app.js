const http = require('http');
const PORT = 3002;

const server = http.createServer((req, res) => {
    console.log(`Green Server: ${req.method} ${req.url}`);
    
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'healthy', server: 'green', version: '2.0.0' }));
        return;
    }
    
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`
        <html>
            <body style="background-color: #27ae60; color: white; font-family: Arial;">
                <center>
                    <h1>GREEN SERVER - Version 2.0.0</h1>
                    <p>Timestamp: ${new Date().toISOString()}</p>
                    <p>Port: ${PORT}</p>
                    <p>Process ID: ${process.pid}</p>
                </center>
            </body>
        </html>
    `);
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`Green server running on port ${PORT}`);
});
