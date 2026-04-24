/**
 * discovery.js
 *
 * Discovers Bang & Olufsen Mozart speakers on the local area network and
 * registers them in the House.
 *
 * ── How discovery works ────────────────────────────────────────────────────────
 *
 * The Mozart API is a per-device REST API — there is no broadcast or
 * multicast discovery protocol accessible from a browser. Instead this
 * service uses two steps:
 *
 *   1. Subnet detection — A silent WebRTC peer connection is created to
 *      extract the browser's local IPv4 address from an ICE candidate.
 *      The /24 subnet is derived from that address (e.g. "192.168.1").
 *      If WebRTC detection fails the caller can supply the subnet manually.
 *
 *   2. Parallel host probing — All 254 addresses on the subnet are probed
 *      concurrently in batches. Each probe sends GET /api/v1/beolink/self
 *      with a short timeout. A valid JSON response confirms a Mozart device;
 *      the probe creates a Speaker, initialises it, and adds it to the House.
 *
 * ── CORS / Private Network Access ─────────────────────────────────────────────
 *
 * Chrome 104+ requires the target device to respond with the header
 *   Access-Control-Allow-Private-Network: true
 * on CORS preflight requests from a localhost or public origin.
 * If the device firmware does not send this header, probes will be silently
 * blocked by the browser. Running the web app from a local network IP
 * (not localhost) or using a local CORS proxy resolves the issue.
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
 *   console.log(`Scan complete — ${speakers.length} speaker(s) found`);
 */

import { Speaker } from './speaker.js';

// Milliseconds to wait for a response before treating a host as absent.
// LAN round-trips are typically < 5 ms; 1 500 ms covers slow/loaded devices.
const PROBE_TIMEOUT_MS = 1_500;

// Number of hosts probed simultaneously.
// Higher = faster scan. Too high may hit browser connection-per-host limits.
const CONCURRENCY = 25;

export class Discovery {
    /**
     * @param {import('./house.js').House} house
     *   The House instance that discovered speakers will be added to.
     */
    constructor(house) {
        this._house          = house;
        this._running        = false;
        this._abortController = null;
    }

    // ── Public interface ───────────────────────────────────────────────────────

    /**
     * Starts a LAN scan and adds every discovered B&O speaker to the House.
     *
     * The method resolves once the full subnet has been scanned. Speakers are
     * added to the House — and onFound is called — as they are discovered,
     * so callers can react in real time without waiting for the scan to finish.
     *
     * @param {{
     *   onFound?: (speaker: import('./speaker.js').Speaker) => void,
     *   subnet?:  string
     * }} [opts]
     *
     *   onFound  – Called immediately each time a speaker is found during
     *              the scan. Receives the fully initialised Speaker instance.
     *
     *   subnet   – Override auto-detected subnet, e.g. "192.168.1".
     *              Useful when WebRTC is blocked or returns a VPN/tunnel IP.
     *
     * @returns {Promise<import('./speaker.js').Speaker[]>}
     *   Array of all speakers discovered during this scan run.
     *
     * @throws {Error} If a scan is already in progress.
     * @throws {Error} If subnet detection fails and no subnet override is given.
     */
    async StartDiscovery({ onFound, subnet } = {}) {
        if (this._running) {
            throw new Error('Discovery is already in progress. Call stopDiscovery() first.');
        }

        this._running         = true;
        this._abortController = new AbortController();
        const discovered      = [];

        try {
            const resolvedSubnet = subnet ?? await this._detectSubnet();

            if (!resolvedSubnet) {
                throw new Error(
                    'Could not determine local subnet automatically. ' +
                    'Pass a subnet option to StartDiscovery(), e.g. { subnet: "192.168.1" }.'
                );
            }

            await this._scanSubnet(resolvedSubnet, {
                signal: this._abortController.signal,
                onFound: (speaker) => {
                    discovered.push(speaker);
                    onFound?.(speaker);
                },
            });
        } finally {
            this._running         = false;
            this._abortController = null;
        }

        return discovered;
    }

    /**
     * Aborts an in-progress scan.
     * Already-discovered speakers remain in the House.
     * Safe to call even when no scan is running.
     */
    stopDiscovery() {
        this._abortController?.abort();
    }

    /** @returns {boolean} True while a scan is running. */
    get isRunning() {
        return this._running;
    }

    // ── Internal ───────────────────────────────────────────────────────────────

    /**
     * Detects the local /24 subnet by inspecting a WebRTC ICE candidate.
     *
     * The RTCPeerConnection is created with no ICE servers so no STUN/TURN
     * traffic is sent. It is used only to surface the host's local IP from
     * the browser's network stack.
     *
     * Returns null if the local IP cannot be determined within 3 seconds or
     * if the browser blocks the RTCPeerConnection API.
     *
     * @returns {Promise<string|null>}  e.g. "192.168.1", or null on failure.
     */
    _detectSubnet() {
        return new Promise((resolve) => {
            let settled = false;
            const finish = (val) => { if (!settled) { settled = true; resolve(val); } };

            try {
                const pc = new RTCPeerConnection({ iceServers: [] });
                pc.createDataChannel('');
                pc.createOffer()
                    .then(o => pc.setLocalDescription(o))
                    .catch(() => finish(null));

                pc.onicecandidate = ({ candidate }) => {
                    if (!candidate) { pc.close(); finish(null); return; }

                    // ICE candidate SDP contains the local IP, e.g.:
                    //   "candidate:... 192.168.1.42 ..."
                    // Capture only private ranges (10.x, 172.16-31.x, 192.168.x).
                    const match = /\b((10|192\.168|172\.(1[6-9]|2\d|3[01]))\.\d{1,3})\.\d{1,3}\b/
                        .exec(candidate.candidate);

                    if (match) { pc.close(); finish(match[1]); }
                };

                // Fallback: if no private IP candidate surfaces within 3 s, give up.
                setTimeout(() => { pc.close(); finish(null); }, 3_000);
            } catch {
                finish(null);
            }
        });
    }

    /**
     * Probes all 254 host addresses on a /24 subnet in parallel batches.
     *
     * @param {string} subnet  e.g. "192.168.1"
     * @param {{ signal: AbortSignal, onFound: Function }} opts
     */
    async _scanSubnet(subnet, { signal, onFound }) {
        // Build the full list of candidates: <subnet>.1 … <subnet>.254
        const hosts = Array.from({ length: 254 }, (_, i) => `${subnet}.${i + 1}`);

        for (let i = 0; i < hosts.length; i += CONCURRENCY) {
            if (signal.aborted) break;

            const batch = hosts.slice(i, i + CONCURRENCY);
            // All hosts in the batch run concurrently; the batch itself is awaited
            // before starting the next one to keep concurrency bounded.
            await Promise.all(
                batch.map(ip => this._probeHost(ip, { signal, onFound }))
            );
        }
    }

    /**
     * Attempts to identify a Mozart speaker at the given IP address.
     *
     * Uses GET /api/v1/beolink/self as the detection fingerprint — it is a
     * lightweight endpoint that all Mozart devices expose and returns JSON
     * that no generic HTTP server would produce.
     *
     * On a confirmed match the method creates a Speaker, fully initialises it
     * (which connects the WebSocket and fetches initial state), registers it
     * in the House, and calls onFound.
     *
     * All network errors and timeouts are silently swallowed — a failed probe
     * simply means "not a B&O device at this address".
     *
     * @param {string} ip
     * @param {{ signal: AbortSignal, onFound: Function }} opts
     */
    async _probeHost(ip, { signal, onFound }) {
        if (signal.aborted) return;

        // Skip addresses already registered to avoid redundant initialisation.
        if (this._house.getSpeaker(ip)) return;

        try {
            // Each probe uses its own AbortController so we can time it out
            // independently of the outer scan abort signal.
            const probeAbort = new AbortController();
            const timer = setTimeout(() => probeAbort.abort(), PROBE_TIMEOUT_MS);

            const res = await fetch(`http://${ip}/api/v1/beolink/self`, {
                signal: probeAbort.signal,
                mode: 'cors',
            });
            clearTimeout(timer);

            // Any non-2xx response means the path exists but returned an error —
            // not a device we want to interact with.
            if (!res.ok) return;

            const data = await res.json().catch(() => null);
            // Require at minimum a valid JSON body; friendlyName is optional.
            if (!data) return;

            // Abort check after the async work above.
            if (signal.aborted) return;

            const speaker = new Speaker(ip);
            await speaker.initialize();

            this._house.addSpeaker(speaker);
            onFound(speaker);
        } catch {
            // Covers: network error, timeout (AbortError), JSON parse failure,
            // CORS block, Private Network Access rejection. All are expected for
            // the ~253 hosts that are not B&O speakers.
        }
    }
}
