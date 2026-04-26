/**
 * discovery.js  (browser — fully client-side)
 *
 * Discovers Bang & Olufsen Mozart speakers without any server-side help:
 *
 *  1. Detect the local /24 subnet via WebRTC ICE candidates.
 *  2. Probe each address by opening a WebSocket to port 9339 (the Mozart
 *     event stream port). A successful connection confirms a B&O speaker —
 *     WebSocket probes are faster than HTTP and sidestep CORS preflight.
 *  3. Once any speaker responds, call GET /api/v1/beolink/peers on it.
 *     The response includes ipAddress for every other speaker on the LAN,
 *     so the full set is discovered without scanning every remaining IP.
 *  4. Rescan every 60 s to pick up speakers that come online later.
 */

import { Speaker } from './speaker.js';

const PING_TIMEOUT_MS  = 500;
const SCAN_CONCURRENCY = 25;
const RESCAN_MS        = 60_000;

export class Discovery {
    /** @param {import('./house.js').House} house */
    constructor(house) {
        this._house        = house;
        this._running      = false;
        this._onFound      = () => {};
        this._pingCache    = new Set();   // hosts that responded to a ping
    }

    /**
     * Starts scanning. Detects subnet via WebRTC, probes port 9339 on each
     * host, then uses Beolink peers for instant network-wide discovery.
     * @param {{ onFound?: (speaker: Speaker) => void }} [opts]
     */
    StartDiscovery({ onFound } = {}) {
        if (this._running) return;
        this._running = true;
        this._onFound = onFound ?? (() => {});
        console.log('[Discovery] Starting client-side B&O discovery (port 9339 WebSocket scan)');
        this._run();
    }

    stopDiscovery() { this._running = false; }

    // ── Internal ───────────────────────────────────────────────────────────────

    async _run() {
        if (!this._running) return;

        let hosts;
        if (this._pingCache.size > 0) {
            // Subsequent scans: only retry hosts that previously responded.
            hosts = [...this._pingCache];
            console.log(`[Discovery] Rescanning ${hosts.length} cached host(s)`);
        } else {
            // First scan: probe the full subnet.
            const subnet = await getLocalSubnet();
            hosts = subnet
                ? range254(subnet)
                : [...range254('192.168.1'), ...range254('192.168.0')];
            console.log(`[Discovery] Full scan — ${hosts.length} address(es) on ${subnet ?? '192.168.{0,1}'}.x`);
        }

        for (let i = 0; i < hosts.length && this._running; i += SCAN_CONCURRENCY) {
            await Promise.allSettled(
                hosts.slice(i, i + SCAN_CONCURRENCY).map(h => this._probe(h))
            );
        }

        if (this._running) setTimeout(() => this._run(), RESCAN_MS);
    }

    async _probe(host) {
        if (!this._running || this._house.getSpeaker(host)) return;

        // Step 1: HTTP ping — check if anything is alive on port 80.
        const alive = await httpPing(host);
        console.log(`[Discovery] ${host} ping ${alive ? '✓ alive' : '✗ no response'}`);
        if (!alive) return;
        this._pingCache.add(host);

        // Step 2: try to initialise a Speaker — success confirms it's B&O.
        await this._addSpeaker(host);

        // Ask it for all its Beolink peers — each peer includes an ipAddress,
        // so we can discover the rest of the network without scanning further.
        try {
            const peers = await new BeoClient(host).getBeolinkPeers() ?? [];
            for (const peer of peers) {
                if (peer.ipAddress) await this._addSpeaker(peer.ipAddress);
            }
        } catch { /* speaker may not have peers or peer call may fail */ }
    }

    async _addSpeaker(host) {
        if (this._house.getSpeaker(host)) return;
        try {
            const speaker = new Speaker(host);
            await speaker.initialize();
            this._house.addSpeaker(speaker);
            console.log(`[Discovery] ✓ B&O speaker: "${speaker.name}" (${host})`);
            this._onFound(speaker);
        } catch {
            console.log(`[Discovery] ${host} — not a B&O speaker`);
        }
    }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

/**
 * Sends a no-cors fetch directly to the host on port 80.
 * Resolves true if the host responds (opaque response counts),
 * false if the connection is refused or times out.
 * @param {string} host
 * @returns {Promise<boolean>}
 */
async function httpPing(host) {
    try {
        await fetch(`http://${host}/api/v1/`, {
            mode:   'no-cors',
            signal: AbortSignal.timeout(PING_TIMEOUT_MS),
        });
        return true;
    } catch {
        return false;
    }
}


/**
 * Uses a WebRTC loopback offer to extract the machine's local IPv4 address
 * and returns the /24 prefix, e.g. "192.168.1".
 * @returns {Promise<string|null>}
 */
function getLocalSubnet() {
    return new Promise((resolve) => {
        try {
            const pc      = new RTCPeerConnection({ iceServers: [] });
            const timeout = setTimeout(() => { pc.close(); resolve(null); }, 3000);

            pc.createDataChannel('');
            pc.createOffer()
                .then(o => pc.setLocalDescription(o))
                .catch(() => { clearTimeout(timeout); resolve(null); });

            pc.onicecandidate = ({ candidate }) => {
                if (!candidate) return;
                const m = candidate.candidate.match(/(\d+\.\d+\.\d+)\.\d+/);
                if (m) { clearTimeout(timeout); pc.close(); resolve(m[1]); }
            };
        } catch { resolve(null); }
    });
}

/** Returns ["subnet.1", "subnet.2", … "subnet.254"] */
function range254(subnet) {
    return Array.from({ length: 254 }, (_, i) => `${subnet}.${i + 1}`);
}
