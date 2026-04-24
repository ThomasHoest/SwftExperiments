/**
 * discovery-server.js
 *
 * Node.js companion server that discovers Bang & Olufsen Mozart speakers
 * via Bonjour/mDNS and streams results to the browser over WebSocket.
 *
 * Browsers cannot send or receive multicast DNS packets directly, so this
 * server acts as a bridge: it listens for mDNS advertisements from Mozart
 * devices on the local network and pushes structured speaker descriptors
 * to any connected browser client.
 *
 * ── Starting the server ────────────────────────────────────────────────────────
 *
 *   node discovery-server.js
 *   # or:
 *   node discovery-server.js --port 3001
 *
 * ── mDNS service type ─────────────────────────────────────────────────────────
 *
 * Mozart platform speakers (Beolab 28, Beosound A5/A9/A1, Balance, Level,
 * Emerge, Theatre, Premiere, Beoconnect Core) advertise the service type
 * "_bangolufsen._tcp" on port 80. If your device does not appear, inspect
 * the raw mDNS traffic with `dns-sd -B _services._dns-sd._udp` (macOS) or
 * `avahi-browse -a` (Linux) to confirm the advertised type.
 *
 * ── WebSocket message protocol ────────────────────────────────────────────────
 *
 * Server → client:
 *   { type: "found", speaker: { name, host, port } }
 *   { type: "lost",  host: "<ip>" }
 *
 * Client → server:
 *   { command: "refresh" }   — triggers an mDNS re-query
 */

import { createServer }  from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { Bonjour }       from 'bonjour-service';

// ── Configuration ─────────────────────────────────────────────────────────────

// Parse --port <n> from argv, fall back to 3001.
const PORT = (() => {
    const idx = process.argv.indexOf('--port');
    return idx !== -1 ? parseInt(process.argv[idx + 1], 10) : 3001;
})();

// mDNS service type advertised by Mozart platform speakers.
const BONJOUR_TYPE = 'bangolufsen';

// ── State ─────────────────────────────────────────────────────────────────────

/**
 * Registry of all currently active speakers keyed by resolved IPv4 address.
 * Populated as mDNS "up" events arrive; entries are removed on "down".
 * @type {Map<string, { name: string, host: string, port: number }>}
 */
const activeSpeakers = new Map();

// ── mDNS browser ──────────────────────────────────────────────────────────────

const bonjour = new Bonjour();
const browser = bonjour.find({ type: BONJOUR_TYPE });

browser.on('up', (service) => {
    // Prefer the first IPv4 address in the addresses array.
    // Fall back to the .local hostname if no numeric IP is present.
    const ipv4 = service.addresses?.find(a => /^\d+\.\d+\.\d+\.\d+$/.test(a));
    const host = ipv4 ?? service.host.replace(/\.$/, ''); // strip trailing dot

    const speaker = {
        name: service.name,
        host,
        port: service.port ?? 80,
    };

    activeSpeakers.set(host, speaker);

    console.log([
        `[Bonjour] ↑ Found:    "${service.name}"`,
        `          host:       ${host}`,
        `          port:       ${speaker.port}`,
        `          addresses:  ${(service.addresses ?? []).join(', ') || '(none)'}`,
        `          txt:        ${JSON.stringify(service.txt ?? {})}`,
        `          active:     ${activeSpeakers.size} speaker(s)`,
    ].join('\n'));

    broadcast({ type: 'found', speaker });
});

browser.on('down', (service) => {
    const ipv4 = service.addresses?.find(a => /^\d+\.\d+\.\d+\.\d+$/.test(a));
    const host = ipv4 ?? service.host.replace(/\.$/, '');

    if (activeSpeakers.delete(host)) {
        console.log([
            `[Bonjour] ↓ Lost:     "${service.name}"`,
            `          host:       ${host}`,
            `          active:     ${activeSpeakers.size} speaker(s)`,
        ].join('\n'));
        broadcast({ type: 'lost', host });
    }
});

// ── WebSocket server ──────────────────────────────────────────────────────────

// A plain HTTP server is needed so we can add CORS headers for the browser.
const httpServer = createServer((req, res) => {
    res.writeHead(204, { 'Access-Control-Allow-Origin': '*' });
    res.end();
});

const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (ws) => {
    const clientCount = wss.clients.size;
    console.log(`[Bonjour] Client connected (${clientCount} active) — replaying ${activeSpeakers.size} cached speaker(s)`);

    // Immediately replay the current snapshot to the new client so it does not
    // have to wait for the next mDNS advertisement cycle.
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
        console.log(`[Bonjour] Client disconnected (${wss.clients.size} active)`);
    });
});

httpServer.listen(PORT, () => {
    console.log(`[discovery] Server listening on ws://localhost:${PORT}`);
    console.log(`[discovery] Browsing for mDNS type: _${BONJOUR_TYPE}._tcp`);
});

// ── Helpers ───────────────────────────────────────────────────────────────────

function send(ws, payload) {
    if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(payload));
    }
}

function broadcast(payload) {
    for (const ws of wss.clients) send(ws, payload);
}

// ── Shutdown ──────────────────────────────────────────────────────────────────

process.on('SIGINT', () => {
    console.log('\n[discovery] Shutting down…');
    bonjour.destroy();
    httpServer.close();
    process.exit(0);
});
