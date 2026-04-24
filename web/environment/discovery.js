/**
 * discovery.js
 *
 * Discovers Bang & Olufsen Mozart speakers on the local network via Bonjour
 * (mDNS) and registers them in the House.
 *
 * ── Architecture ──────────────────────────────────────────────────────────────
 *
 * Browsers cannot send or receive multicast DNS packets, so this class acts as
 * a WebSocket client to a local Node.js discovery server (discovery-server.js)
 * that does the mDNS work. The server must be running before StartDiscovery()
 * is called:
 *
 *   node discovery-server.js          # default port 3001
 *
 * ── Usage ──────────────────────────────────────────────────────────────────────
 *
 *   const house     = new House('My Home');
 *   const discovery = new Discovery(house);
 *
 *   const speakers = await discovery.StartDiscovery({
 *       onFound: (speaker) => console.log('Found:', speaker.name, speaker.host),
 *   });
 *
 *   console.log(`Found ${speakers.length} speaker(s)`);
 *
 *   // Stay connected to receive speakers that come online later:
 *   // omit the await and handle onFound instead.
 *
 * ── Message protocol (from discovery-server.js) ───────────────────────────────
 *
 *   { type: "found", speaker: { name, host, port } }
 *   { type: "lost",  host: "<ip>" }
 */

import { Speaker } from './speaker.js';

// How long StartDiscovery() waits for the initial mDNS burst before resolving.
// Devices already cached by the server are delivered immediately; this window
// allows time for fresh advertisements to arrive on the network.
const DEFAULT_SCAN_WINDOW_MS = 10_000;

export class Discovery {
    /**
     * @param {import('./house.js').House} house
     *   The House instance that discovered speakers will be added to.
     * @param {{ serverUrl?: string }} [opts]
     *   serverUrl – WebSocket URL of the discovery server.
     *               Defaults to ws://localhost:3001.
     */
    constructor(house, { serverUrl = 'ws://localhost:3001' } = {}) {
        this._house     = house;
        this._serverUrl = serverUrl;
        this._ws        = null;
        this._running   = false;
    }

    // ── Public interface ───────────────────────────────────────────────────────

    /**
     * Connects to the local Bonjour discovery server and collects all Mozart
     * speakers found within the scan window.
     *
     * Speakers announced by the server are wrapped in a Speaker instance,
     * initialised (fetches live state + starts WebSocket event stream), and
     * added to the House. The onFound callback fires immediately per speaker
     * so the caller can react without waiting for the window to close.
     *
     * The method resolves with all speakers found during the window. The
     * underlying WebSocket stays open after the method resolves so speakers
     * that come online later are still added automatically — call
     * stopDiscovery() to tear it down.
     *
     * @param {{
     *   onFound?:       (speaker: import('./speaker.js').Speaker) => void,
     *   scanWindowMs?:  number
     * }} [opts]
     *
     *   onFound      – Called each time a speaker is discovered.
     *   scanWindowMs – Duration (ms) to wait before resolving. Default: 10 000.
     *
     * @returns {Promise<import('./speaker.js').Speaker[]>}
     *   Speakers found during the scan window.
     *
     * @throws {Error} If a scan is already running.
     * @throws {Error} If the discovery server cannot be reached.
     */
    async StartDiscovery({ onFound, scanWindowMs = DEFAULT_SCAN_WINDOW_MS } = {}) {
        if (this._running) {
            throw new Error('Discovery is already running. Call stopDiscovery() first.');
        }
        this._running = true;

        return new Promise((resolve, reject) => {
            const discovered = [];
            let windowTimer  = null;

            const ws = new WebSocket(this._serverUrl);
            this._ws = ws;

            ws.addEventListener('open', () => {
                // Resolve after the scan window regardless of how many devices
                // have been found. The WebSocket stays open after resolve.
                windowTimer = setTimeout(() => resolve(discovered), scanWindowMs);
            });

            ws.addEventListener('message', async ({ data }) => {
                let msg;
                try { msg = JSON.parse(data); } catch { return; }

                if (msg.type === 'found') {
                    await this._handleFound(msg.speaker, { discovered, onFound });
                } else if (msg.type === 'lost') {
                    this._handleLost(msg.host);
                }
            });

            ws.addEventListener('error', () => {
                clearTimeout(windowTimer);
                this._running = false;
                this._ws = null;
                reject(new Error(
                    `Could not connect to discovery server at ${this._serverUrl}. ` +
                    'Make sure discovery-server.js is running: node discovery-server.js'
                ));
            });

            ws.addEventListener('close', () => {
                // If the server closes while we are still in the window, resolve
                // with whatever was found rather than hanging.
                clearTimeout(windowTimer);
                if (this._running) {
                    this._running = false;
                    this._ws = null;
                    resolve(discovered);
                }
            });
        });
    }

    /**
     * Closes the WebSocket connection to the discovery server and stops
     * receiving new speaker announcements.
     * Already-discovered speakers remain in the House.
     */
    stopDiscovery() {
        this._running = false;
        if (this._ws) {
            this._ws.close();
            this._ws = null;
        }
    }

    /**
     * Asks the discovery server to re-query the network.
     * Useful if a speaker was powered on after StartDiscovery() was called.
     */
    refresh() {
        if (this._ws?.readyState === WebSocket.OPEN) {
            this._ws.send(JSON.stringify({ command: 'refresh' }));
        }
    }

    /** @returns {boolean} True while connected to the discovery server. */
    get isRunning() {
        return this._running;
    }

    // ── Internal ───────────────────────────────────────────────────────────────

    /**
     * Handles a "found" message from the discovery server.
     * Skips the host if it is already registered in the House.
     *
     * @param {{ name: string, host: string, port: number }} descriptor
     * @param {{ discovered: Speaker[], onFound?: Function }} ctx
     */
    async _handleFound(descriptor, { discovered, onFound }) {
        const { host } = descriptor;

        // Guard: skip if already in house from a previous discovery run.
        if (this._house.getSpeaker(host)) return;

        try {
            const speaker = new Speaker(host);
            await speaker.initialize();

            this._house.addSpeaker(speaker);
            discovered.push(speaker);
            onFound?.(speaker);
        } catch {
            // The device was advertised via mDNS but its REST API is unreachable.
            // This can happen briefly after a speaker powers on — ignore silently.
        }
    }

    /**
     * Handles a "lost" message from the discovery server.
     * Removes the speaker from the House and disposes its event stream.
     *
     * @param {string} host
     */
    _handleLost(host) {
        this._house.removeSpeaker(host);
    }
}
