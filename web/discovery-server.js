/**
 * discovery-server.js
 *
 * Node.js companion server that discovers Bang & Olufsen Mozart speakers
 * via Bonjour/mDNS and streams results to the browser over WebSocket.
 *
 * ── Starting ──────────────────────────────────────────────────────────────────
 *
 *   node discovery-server.js            # default port 3001
 *   node discovery-server.js --port 3001
 *
 * ── mDNS service type ─────────────────────────────────────────────────────────
 *
 * Mozart platform speakers advertise "_bangolufsen._tcp" on port 80.
 * If no speakers appear, check the raw mDNS log printed below — every
 * PTR record on the network is logged so you can see the actual service
 * types your devices are using.
 *
 * ── WebSocket protocol ────────────────────────────────────────────────────────
 *
 *   Server → client:  { type: "found", speaker: { name, host, port } }
 *                     { type: "lost",  host: "<ip>" }
 *   Client → server:  { command: "refresh" }
 */

import { createServer }             from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { Bonjour }                  from 'bonjour-service';
import MDNS                         from 'multicast-dns';

// ── Configuration ─────────────────────────────────────────────────────────────

const PORT = (() => {
    const idx = process.argv.indexOf('--port');
    return idx !== -1 ? parseInt(process.argv[idx + 1], 10) : 3001;
})();

const BONJOUR_TYPE = 'bangolufsen';

// ── State ─────────────────────────────────────────────────────────────────────

/** Active speakers keyed by resolved IPv4. @type {Map<string, {name,host,port}>} */
const activeSpeakers = new Map();

// ── Raw mDNS listener — logs EVERYTHING on the network ───────────────────────
//
// This runs alongside the structured Bonjour browser and prints every PTR
// record seen via multicast DNS. Use this to confirm what service types your
// speakers actually advertise if they do not appear in the Bonjour results.

const mdns = MDNS();

mdns.on('response', (response) => {
    const ptrs = response.answers.filter(r => r.type === 'PTR');
    const srvs = response.answers.filter(r => r.type === 'SRV');
    const as   = response.answers.filter(r => r.type === 'A');

    for (const ptr of ptrs) {
        console.log(`[mDNS] PTR  ${ptr.name.padEnd(45)} → ${ptr.data}`);
    }
    for (const srv of srvs) {
        console.log(`[mDNS] SRV  ${srv.name.padEnd(45)} → ${srv.data?.target}:${srv.data?.port}`);
    }
    for (const a of as) {
        console.log(`[mDNS] A    ${a.name.padEnd(45)} → ${a.data}`);
    }
});

mdns.on('query', (query) => {
    for (const q of query.questions) {
        // Only log queries that look B&O / audio related to reduce noise.
        const n = q.name.toLowerCase();
        if (n.includes('bang') || n.includes('beo') || n.includes('olufsen') ||
            n.includes('mozart') || n.includes('audio') || n.includes('music')) {
            console.log(`[mDNS] Query  ${q.type} ${q.name}`);
        }
    }
});

// ── Bonjour browser — structured _bangolufsen._tcp ────────────────────────────

const bonjour = new Bonjour();

console.log(`[Bonjour] Starting browser for _${BONJOUR_TYPE}._tcp`);
const browser = bonjour.find({ type: BONJOUR_TYPE });

browser.on('up', (service) => {
    const ipv4 = service.addresses?.find(a => /^\d+\.\d+\.\d+\.\d+$/.test(a));
    const host = ipv4 ?? service.host.replace(/\.$/, '');

    const speaker = { name: service.name, host, port: service.port ?? 80 };
    activeSpeakers.set(host, speaker);

    console.log([
        `[Bonjour] ↑ Found:      "${service.name}"`,
        `            type:       _${service.type}._${service.protocol}`,
        `            host:       ${host}`,
        `            port:       ${speaker.port}`,
        `            addresses:  ${(service.addresses ?? []).join(', ') || '(none)'}`,
        `            subtypes:   ${(service.subtypes ?? []).join(', ') || '(none)'}`,
        `            txt:        ${JSON.stringify(service.txt ?? {})}`,
        `            active:     ${activeSpeakers.size} speaker(s)`,
    ].join('\n'));

    broadcast({ type: 'found', speaker });
});

browser.on('down', (service) => {
    const ipv4 = service.addresses?.find(a => /^\d+\.\d+\.\d+\.\d+$/.test(a));
    const host = ipv4 ?? service.host.replace(/\.$/, '');

    if (activeSpeakers.delete(host)) {
        console.log([
            `[Bonjour] ↓ Lost:       "${service.name}"`,
            `            host:       ${host}`,
            `            active:     ${activeSpeakers.size} speaker(s)`,
        ].join('\n'));
        broadcast({ type: 'lost', host });
    }
});

// Log a summary every 30 s so you can confirm the browser is still running.
setInterval(() => {
    console.log(`[Bonjour] Heartbeat — ${activeSpeakers.size} speaker(s) active: ${
        activeSpeakers.size
            ? [...activeSpeakers.values()].map(s => `"${s.name}" (${s.host})`).join(', ')
            : '(none)'
    }`);
    // Re-query to pick up any speakers that missed the initial advertisement.
    browser.update();
}, 30_000);

// ── WebSocket server ──────────────────────────────────────────────────────────

const httpServer = createServer((req, res) => {
    res.writeHead(204, { 'Access-Control-Allow-Origin': '*' });
    res.end();
});

const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (ws) => {
    console.log(`[Bonjour] Client connected (${wss.clients.size} active) — replaying ${activeSpeakers.size} cached speaker(s)`);

    for (const speaker of activeSpeakers.values()) {
        console.log(`[Bonjour]   → replaying "${speaker.name}" (${speaker.host})`);
        send(ws, { type: 'found', speaker });
    }

    ws.on('message', (raw) => {
        try {
            const { command } = JSON.parse(raw);
            if (command === 'refresh') {
                console.log('[Bonjour] Refresh requested — re-querying mDNS');
                browser.update();
            }
        } catch { /* ignore malformed messages */ }
    });

    ws.on('close', () => {
        console.log(`[Bonjour] Client disconnected (${wss.clients.size} remaining)`);
    });
});

httpServer.listen(PORT, () => {
    console.log(`[Bonjour] WebSocket server on ws://localhost:${PORT}`);
    console.log(`[Bonjour] Raw mDNS listener active — all PTR/SRV/A records will be logged`);
    console.log(`[Bonjour] Heartbeat every 30 s, browser.update() re-queries on each tick`);
});

// ── Helpers ───────────────────────────────────────────────────────────────────

function send(ws, payload) {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(payload));
}

function broadcast(payload) {
    for (const ws of wss.clients) send(ws, payload);
}

// ── Shutdown ──────────────────────────────────────────────────────────────────

process.on('SIGINT', () => {
    console.log('\n[Bonjour] Shutting down…');
    mdns.destroy();
    bonjour.destroy();
    httpServer.close();
    process.exit(0);
});
