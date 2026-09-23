import {createServer} from 'http';
import {appendFileSync} from 'fs';

const LOG_FILE = './majortom.log';

createServer((req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
    }

    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
        const line = `[${new Date().toISOString()}] ${body}\n`;
        appendFileSync(LOG_FILE, line);
        res.writeHead(200);
        res.end('ok');
    });
}).listen(7777, () => console.log('MajorTom log server on :7777'));
