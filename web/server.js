/**
 * server.js
 *
 * Static file server + transparent HTTP proxy for speaker API calls.
 *
 * B&O speakers don't send CORS headers, so the browser can't call their
 * REST API directly. Requests to /proxy/<host>/... are forwarded server-side
 * where CORS doesn't apply, and the response is returned to the browser.
 *
 *   node server.js            # port 3000
 *   node server.js --port 8080
 */

import { createServer }        from 'http';
import { readFile }            from 'fs/promises';
import { join, extname }       from 'path';
import { fileURLToPath }       from 'url';
import { networkInterfaces }   from 'os';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

const PORT = (() => {
    const idx = process.argv.indexOf('--port');
    return idx !== -1 ? parseInt(process.argv[idx + 1], 10) : 3000;
})();

const MIME = {
    '.html':  'text/html; charset=utf-8',
    '.js':    'application/javascript; charset=utf-8',
    '.css':   'text/css; charset=utf-8',
    '.json':  'application/json',
    '.png':   'image/png',
    '.jpg':   'image/jpeg',
    '.svg':   'image/svg+xml',
    '.ico':   'image/x-icon',
    '.woff2': 'font/woff2',
    '.woff':  'font/woff',
};

const CORS_HEADERS = {
    'Access-Control-Allow-Origin':  '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
};

const httpServer = createServer(async (req, res) => {
    const url = req.url.split('?')[0];

    // ── CORS preflight ────────────────────────────────────────────────────────
    if (req.method === 'OPTIONS') {
        res.writeHead(204, CORS_HEADERS);
        res.end();
        return;
    }

    // ── Speaker API proxy: /proxy/<host>/api/v1/... ───────────────────────────
    if (url.startsWith('/proxy/')) {
        const target = 'http://' + url.slice('/proxy/'.length);

        try {
            // Read request body for PUT/POST.
            let body;
            if (req.method !== 'GET' && req.method !== 'HEAD') {
                const chunks = [];
                for await (const chunk of req) chunks.push(chunk);
                body = Buffer.concat(chunks);
            }

            const upstream = await fetch(target, {
                method:  req.method,
                headers: { 'Content-Type': 'application/json' },
                body,
            });

            const data = await upstream.arrayBuffer();
            res.writeHead(upstream.status, {
                'Content-Type': upstream.headers.get('content-type') ?? 'application/json',
                ...CORS_HEADERS,
            });
            res.end(Buffer.from(data));
        } catch (err) {
            res.writeHead(502, { 'Content-Type': 'text/plain', ...CORS_HEADERS });
            res.end(`Proxy error: ${err.message}`);
        }
        return;
    }

    // ── Static files ──────────────────────────────────────────────────────────
    let filePath = url === '/' ? '/index.html' : url;
    filePath = join(__dirname, filePath);

    const ext      = extname(filePath).toLowerCase();
    const mimeType = MIME[ext] ?? 'application/octet-stream';

    try {
        const data = await readFile(filePath);
        res.writeHead(200, {
            'Content-Type':  mimeType,
            'Cache-Control': 'no-store',
        });
        res.end(data);
    } catch {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not found');
    }
});

httpServer.listen(PORT, () => {
    console.log(`[Server] http://localhost:${PORT}`);

    const lanIp = Object.values(networkInterfaces())
        .flat()
        .find(i => i.family === 'IPv4' && !i.internal)
        ?.address;

    if (lanIp) {
        console.log(`[Server] http://${lanIp}:${PORT}  ← open this for LAN access (no CORS)`);
    }
});
