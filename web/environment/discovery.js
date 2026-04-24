/**
 * discovery.js
 *
 * Discovers Bang & Olufsen Mozart speakers on the local network via Bonjour
 * (mDNS) and registers them in the House. Discovery runs continuously for
 * the lifetime of the page — speakers are added as they appear and removed
 * when they go offline.
 *
 * ── Architecture ──────────────────────────────────────────────────────────────
 *
 * Browsers cannot send or receive multicast DNS packets, so this class is a
 * WebSocket client to a local Node.js discovery server (discovery-server.js)
 * that does the mDNS work. The connection is kept alive indefinitely and
 * reconnects automatically if it drops.
 *
 * ── Usage ──────────────────────────────────────────────────────────────────────
 *
 *   const house     = new House('My Home');
 *   const discovery = new Discovery(house);
 *
 *   discovery.StartDiscovery({
 *       onFound: (speaker) => console.log('Found:', speaker.name),
 *   });
 *   // Runs forever. Call stopDiscovery() to tear it down.
 */

import { Speaker } from './speaker.js';

// Reconnect backoff: doubles on each failure, capped at 30 s.
const BACKOFF_BASE = 1_000;
const BACKOFF_MAX  = 30_000;

export class Discovery {
    /**
     * @param {import('./house.js').House} house
     * @param {{ serverUrl?: string }} [opts]
     */
    constructor(house, { serverUrl = 'ws://localhost:3001' } = {}) {
        this._house       = house;
        this._serverUrl   = serverUrl;
        this._ws          = null;
        this._running     = false;
        this._retryCount  = 0;
        this._onFound     = () => {};
    }

    // ── Public interface ───────────────────────────────────────────────────────

    /**
     * Starts continuous discovery. Connects to the Bonjour server, processes
     * speaker events, and reconnects automatically if the connection drops.
     * Returns immediately — discovery runs in the background indefinitely.
     *
     * @param {{ onFound?: (speaker: Speaker) => void }} [opts]
     *   onFound – Called each time a new speaker is discovered.
     *
     * @throws {Error} If discovery is already running.
     */
    StartDiscovery({ onFound } = {}) {
        if (this._running) throw new Error('Discovery is already running.');
        this._running = true;
        this._onFound = onFound ?? (() => {});
        console.log('[Discovery] Starting — will reconnect automatically if the server drops');
        this._connect();
    }

    /**
     * Permanently stops discovery and closes the WebSocket.
     * Already-discovered speakers remain in the House.
     */
    stopDiscovery() {
        this._running = false;
        if (this._ws) { this._ws.close(); this._ws = null; }
        console.log('[Discovery] Stopped');
    }

    /**
     * Asks the discovery server to re-query mDNS immediately.
     * Useful when a speaker is powered on but no advertisement has arrived yet.
     */
    refresh() {
        if (this._ws?.readyState === WebSocket.OPEN) {
            this._ws.send(JSON.stringify({ command: 'refresh' }));
            console.log('[Discovery] Sent refresh request to server');
        }
    }

    /** @returns {boolean} */
    get isRunning() { return this._running; }

    // ── Internal ───────────────────────────────────────────────────────────────

    /**
     * Opens a WebSocket to the discovery server. On unexpected close the method
     * schedules itself again with exponential backoff so discovery never stops.
     */
    _connect() {
        if (!this._running) return;

        console.log(`[Discovery] Connecting to ${this._serverUrl}…`);

        const ws = new WebSocket(this._serverUrl);
        this._ws = ws;

        ws.addEventListener('open', () => {
            this._retryCount = 0;
            console.log('[Discovery] Connected to Bonjour server — watching for _bangolufsen._tcp');
        });

        ws.addEventListener('message', ({ data }) => {
            let msg;
            try { msg = JSON.parse(data); } catch { return; }

            if      (msg.type === 'found') this._handleFound(msg.speaker);
            else if (msg.type === 'lost')  this._handleLost(msg.host);
        });

        ws.addEventListener('error', () => {
            // Always followed by 'close' — handle retry there.
        });

        ws.addEventListener('close', () => {
            this._ws = null;
            if (!this._running) return;

            const delay = Math.min(BACKOFF_BASE * 2 ** this._retryCount, BACKOFF_MAX);
            this._retryCount++;
            console.warn(`[Discovery] Connection closed — retrying in ${delay / 1000}s (attempt ${this._retryCount})`);
            setTimeout(() => this._connect(), delay);
        });
    }

    /**
     * Handles a "found" message: creates and initialises a Speaker, adds it
     * to the House, and notifies the caller.
     * @param {{ name: string, host: string, port: number }} descriptor
     */
    async _handleFound({ name, host, port }) {
        if (this._house.getSpeaker(host)) {
            console.log(`[Discovery] Already registered: "${name}" (${host}) — skipping`);
            return;
        }

        console.log(`[Discovery] Speaker announced via Bonjour: "${name}" at ${host}:${port}`);

        try {
            const speaker = new Speaker(host);
            await speaker.initialize();
            this._house.addSpeaker(speaker);
            console.log(`[Discovery] Speaker ready: "${speaker.name}" (${host}) — state: ${speaker.state}`);
            this._onFound(speaker);
        } catch (err) {
            console.warn(`[Discovery] "${name}" (${host}) responded to mDNS but API unreachable:`, err.message);
        }
    }

    /**
     * Handles a "lost" message: removes the speaker from the House.
     * @param {string} host
     */
    _handleLost(host) {
        const speaker = this._house.getSpeaker(host);
        if (!speaker) return;
        console.log(`[Discovery] Speaker offline: "${speaker.name}" (${host})`);
        this._house.removeSpeaker(host);
    }
}
