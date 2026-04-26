/**
 * discovery-client.js  (browser)
 *
 * Subscribes to the server's /api/events SSE stream and translates
 * found/lost events into Speaker objects added to the House.
 *
 * EventSource reconnects automatically on drop — no manual backoff needed.
 */

import { Speaker } from './speaker.js';

export class Discovery {
    /**
     * @param {import('./house.js').House} house
     * @param {{ eventsUrl?: string }} [opts]
     */
    constructor(house, { eventsUrl = '/api/events' } = {}) {
        this._house     = house;
        this._eventsUrl = eventsUrl;
        this._es        = null;
        this._onFound   = () => {};
        this._running   = false;
    }

    /**
     * Opens the SSE connection and starts receiving speaker events.
     * @param {{ onFound?: (speaker: Speaker) => void }} [opts]
     */
    StartDiscovery({ onFound } = {}) {
        if (this._running) throw new Error('Discovery is already running.');
        this._running = true;
        this._onFound = onFound ?? (() => {});
        console.log('[Discovery] Connecting to SSE stream…');
        this._connect();
    }

    stopDiscovery() {
        this._running = false;
        this._es?.close();
        this._es = null;
        console.log('[Discovery] Stopped');
    }

    /** @returns {boolean} */
    get isRunning() { return this._running; }

    // ── Internal ───────────────────────────────────────────────────────────────

    _connect() {
        const es = new EventSource(this._eventsUrl);
        this._es = es;

        es.addEventListener('open', () => {
            console.log('[Discovery] SSE connected');
        });

        es.addEventListener('message', async ({ data }) => {
            let msg;
            try { msg = JSON.parse(data); } catch { return; }
            if      (msg.type === 'found') await this._handleFound(msg.speaker);
            else if (msg.type === 'lost')  this._handleLost(msg.host);
        });

        es.addEventListener('error', () => {
            // EventSource reconnects automatically — no action needed.
        });
    }

    async _handleFound({ name, host, port }) {
        if (this._house.getSpeaker(host)) {
            console.log(`[Discovery] Already registered: "${name}" (${host}) — skipping`);
            return;
        }
        console.log(`[Discovery] Speaker announced: "${name}" at ${host}:${port}`);
        try {
            const speaker = new Speaker(host);
            await speaker.initialize();
            this._house.addSpeaker(speaker);
            console.log(`[Discovery] Speaker ready: "${speaker.name}" (${host})`);
            this._onFound(speaker);
        } catch (err) {
            console.warn(`[Discovery] "${name}" (${host}) API unreachable:`, err.message);
        }
    }

    _handleLost(host) {
        const speaker = this._house.getSpeaker(host);
        if (!speaker) return;
        console.log(`[Discovery] Speaker offline: "${speaker.name}" (${host})`);
        this._house.removeSpeaker(host);
    }
}
