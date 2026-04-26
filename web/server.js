/**
 * server.js
 *
 * Unified HTTP server: serves static files and streams speaker discovery
 * events to the browser via Server-Sent Events (SSE).
 *
 * Discovery starts on the first browser connection to /api/events.
 *
 *   node server.js            # port 3000
 *   node server.js --port 8080
 */

import { createServer }  from 'http';
import { readFile }      from 'fs/promises';
import { join, extname } from 'path';
import { fileURLToPath } from 'url';
import { Discovery }     from './environment/discovery.js';

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

// ── Discovery ─────────────────────────────────────────────────────────────────

const discovery = new Discovery();

// ── HTTP server ───────────────────────────────────────────────────────────────

const httpServer = createServer(async (req, res) => {
    const url = req.url.split('?')[0];

    // ── SSE endpoint ──────────────────────────────────────────────────────────
    if (url === '/api/events') {
        res.writeHead(200, {
            'Content-Type':  'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection':    'keep-alive',
        });

        // Start discovery the first time any browser connects.
        discovery.StartDiscovery();

        // Replay already-known speakers to this new client.
        for (const speaker of discovery.getActiveSpeakers()) {
            res.write(`data: ${JSON.stringify({ type: 'found', speaker })}\n\n`);
        }

        // Forward future events to this client.
        const unsub = discovery.onEvent((event) => {
            res.write(`data: ${JSON.stringify(event)}\n\n`);
        });

        req.on('close', () => {
            unsub();
            console.log('[SSE] Client disconnected');
        });

        console.log('[SSE] Client connected');
        return;
    }

    // ── Refresh endpoint ──────────────────────────────────────────────────────
    if (url === '/api/refresh' && req.method === 'POST') {
        discovery.refresh();
        res.writeHead(204);
        res.end();
        return;
    }

    // ── Static files ──────────────────────────────────────────────────────────
    let filePath = url === '/' ? '/index.html' : url;
    filePath = join(__dirname, filePath);

    const ext      = extname(filePath).toLowerCase();
    const mimeType = MIME[ext] ?? 'application/octet-stream';

    try {
        const data = await readFile(filePath);
        res.writeHead(200, { 'Content-Type': mimeType });
        res.end(data);
    } catch {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not found');
    }
});

// ── Start ─────────────────────────────────────────────────────────────────────

httpServer.listen(PORT, () => {
    console.log(`[Server] http://localhost:${PORT}`);
    console.log(`[Server] Discovery starts when the first browser connects`);
});

process.on('SIGINT', () => {
    console.log('\n[Server] Shutting down…');
    discovery.destroy();
    httpServer.close();
    process.exit(0);
});
