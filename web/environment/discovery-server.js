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
 * ── WebSocket protocol ────────────────────────────────────────────────────────
 *
 *   Server → client:  { type: "found", speaker: { name, host, port } }
 *                     { type: "lost",  host: "<ip>" }
 *   Client → server:  { command: "refresh" }
 */

import { createServer }               from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { Bonjour }                    from 'bonjour-service';
import MDNS                           from 'multicast-dns';

// ── Configuration ─────────────────────────────────────────────────────────────

const PORT = (() => {
    const idx = process.argv.indexOf('--port');
    return idx !== -1 ? parseInt(process.argv[idx + 1], 10) : 3001;
})();

const BONJOUR_TYPE = 'bangolufsen';

// ── State ─────────────────────────────────────────────────────────────────────

/** Active speakers keyed by resolved IPv4. @type {Map<string, {name,host,port}>} */
const activeSpeakers = new Map();

// ── Raw mDNS — log every packet on the network ───────────────────────────────

const mdns = MDNS();

mdns.on('response', (response) => {
    const all = [...(response.answers ?? []), ...(response.additionals ?? [])];
    if (all.length === 0) return;

    console.log(`[mDNS] ── response (${all.length} record(s)) ─────────────────────`);
    for (const r of all) {
        const data = formatRecord(r);
        console.log(`[mDNS]   ${r.type.padEnd(5)} ${String(r.name).padEnd(50)} ${data}`);
    }
});

mdns.on('query', (query) => {
    if ((query.questions ?? []).length === 0) return;
    console.log(`[mDNS] ── query (${query.questions.length} question(s)) ──────────────────────`);
    for (const q of query.questions) {
        console.log(`[mDNS]   ${q.type.padEnd(5)} ${q.name}`);
    }
});

/** Formats the data field of an mDNS record into a readable string. */
function formatRecord(r) {
    const d = r.data;
    if (!d)                         return '';
    if (typeof d === 'string')      return `→ ${d}`;
    if (typeof d === 'number')      return `→ ${d}`;
    if (Buffer.isBuffer(d))         return `→ <buffer ${d.toString('hex').slice(0, 32)}…>`;
    if (d.target !== undefined)     return `→ ${d.target}:${d.port}`;
    if (d.address !== undefined)    return `→ ${d.address}`;
    if (Array.isArray(d))           return `→ [${d.join(', ')}]`;
    return `→ ${JSON.stringify(d)}`;
}

// Actively query for all service types every 10 s so devices that missed
// the initial probe get a chance to respond.
function queryAll() {
    console.log('[mDNS] Sending query for all service types (_services._dns-sd._udp.local)');
    mdns.query([{ name: '_services._dns-sd._udp.local', type: 'PTR' }]);

    console.log(`[mDNS] Sending query for _${BONJOUR_TYPE}._tcp.local`);
    mdns.query([{ name: `_${BONJOUR_TYPE}._tcp.local`, type: 'PTR' }]);
}

queryAll();
setInterval(queryAll, 10_000);

// ── Bonjour browser ───────────────────────────────────────────────────────────

const bonjour = new Bonjour();

console.log(`[Bonjour] Browser started for _${BONJOUR_TYPE}._tcp`);
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
        console.log(`[Bonjour] ↓ Lost: "${service.name}" (${host}) — ${activeSpeakers.size} remaining`);
        broadcast({ type: 'lost', host });
    }
});

setInterval(() => {
    console.log(`[Bonjour] Heartbeat — ${activeSpeakers.size} speaker(s) active${activeSpeakers.size ? ': ' + [...activeSpeakers.values()].map(s => `"${s.name}"@${s.host}`).join(', ') : ''}`);
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
                console.log('[Bonjour] Refresh requested');
                browser.update();
                queryAll();
            }
        } catch { /* ignore malformed messages */ }
    });

    ws.on('close', () => {
        console.log(`[Bonjour] Client disconnected (${wss.clients.size} remaining)`);
    });
});

httpServer.listen(PORT, () => {
    console.log(`[Bonjour] WebSocket server on ws://localhost:${PORT}`);
    console.log(`[mDNS]    Logging ALL multicast DNS traffic — queries and responses`);
});

// ── Helpers ───────────────────────────────────────────────────────────────────

function send(ws, payload) {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(payload));
}

function broadcast(payload) {
    for (const ws of wss.clients) send(ws, payload);
}

process.on('SIGINT', () => {
    console.log('\n[Bonjour] Shutting down…');
    mdns.destroy();
    bonjour.destroy();
    httpServer.close();
    process.exit(0);
});
