/**
 * beo-client.js
 *
 * REST API client for the Bang & Olufsen Mozart Open API.
 *
 * All Mozart-platform speakers (Beolab 28, Beosound A5, A9, A1, Balance,
 * Level, Emerge, Theatre, Premiere, Beoconnect Core, etc.) expose this
 * HTTP API directly on the local network — no cloud, no authentication.
 *
 * Spec:    https://bang-olufsen.github.io/mozart-open-api/
 * GitHub:  https://github.com/bang-olufsen/mozart-open-api
 *
 * ── LAN requirements ──────────────────────────────────────────────────────────
 * The browser and the speaker must be on the same local network.
 * The API listens on port 80 (HTTP). HTTPS is not available on most devices.
 *
 * ── CORS / Private Network Access ─────────────────────────────────────────────
 * Chrome 104+ enforces the Private Network Access specification: a page served
 * from localhost (or any public origin) must receive an explicit
 *   Access-Control-Allow-Private-Network: true
 * header from the device before the browser will allow the request.
 * If the device firmware does not send this header, requests will be blocked.
 * Workarounds: serve the page from the same LAN IP (not localhost), or run a
 * local proxy (e.g. `npx local-cors-proxy`) that adds the required header.
 */

// Base path shared by all REST endpoints.
const API_ROOT = '/api/v1';

export class BeoClient {
    /**
     * @param {string} host  IP address or hostname of the speaker, e.g. "192.168.1.50"
     */
    constructor(host) {
        this.baseUrl = `http://${host}${API_ROOT}`;
    }

    // ── Internal helpers ───────────────────────────────────────────────────────

    /**
     * Thin fetch wrapper that sets JSON headers and throws on non-2xx responses.
     * @param {string} path   Path relative to API_ROOT, e.g. "/sound/volume"
     * @param {RequestInit} [opts]
     * @returns {Promise<any>} Parsed JSON body, or null for 204 No Content.
     */
    async _request(path, opts = {}) {
        const res = await fetch(`${this.baseUrl}${path}`, {
            headers: { 'Content-Type': 'application/json', ...opts.headers },
            ...opts,
        });

        if (!res.ok) {
            const err = await res.json().catch(() => ({}));
            throw Object.assign(
                new Error(err.description ?? `HTTP ${res.status} ${res.statusText}`),
                { status: res.status, code: err.errorCode }
            );
        }

        // 204 No Content — return null instead of trying to parse an empty body.
        if (res.status === 204) return null;
        return res.json();
    }

    _get(path)         { return this._request(path); }
    _put(path, body)   { return this._request(path, { method: 'PUT',  body: JSON.stringify(body) }); }
    _post(path, body)  { return this._request(path, { method: 'POST', body: body ? JSON.stringify(body) : undefined }); }

    // ── Power ──────────────────────────────────────────────────────────────────

    /**
     * Returns the current power state.
     * Possible values: "networkStandby" | "on" | "standby" | "shutdown" | "storage"
     * @returns {Promise<{ state: string }>}
     */
    getPowerState() {
        return this._get('/state/power');
    }

    /**
     * Puts the speaker into standby.
     * The device remains reachable on the network (networkStandby).
     */
    standby() {
        return this._put('/state/standby', {});
    }

    /**
     * Reboots the speaker. The API will be unavailable for ~30 seconds.
     */
    reboot() {
        return this._put('/state/reboot', {});
    }

    /**
     * Returns battery state for portable devices (e.g. Beosound A1).
     * @returns {Promise<{ batteryLevel: number, isCharging: boolean, remainingPlayingTime: number }>}
     */
    getBattery() {
        return this._get('/battery');
    }

    // ── Playback ───────────────────────────────────────────────────────────────

    /**
     * Returns the current playback state.
     * @returns {Promise<{ value: "playing"|"paused"|"stopped"|"buffering"|"unknown" }>}
     */
    getPlaybackState() {
        return this._get('/playback/state');
    }

    /**
     * Returns metadata for the currently playing track
     * (title, artist, album, artwork URL, duration, etc.).
     */
    getPlaybackMetadata() {
        return this._get('/playback/metadata');
    }

    /**
     * Returns playback progress in milliseconds.
     * @returns {Promise<{ position: number, totalDuration: number }>}
     */
    getPlaybackProgress() {
        return this._get('/playback/progress');
    }

    /** Starts or resumes playback. */
    play()     { return this._post('/playback/command/play'); }

    /** Pauses playback. */
    pause()    { return this._post('/playback/command/pause'); }

    /** Stops playback. */
    stop()     { return this._post('/playback/command/stop'); }

    /** Skips to the next track. */
    next()     { return this._post('/playback/command/skip'); }

    /** Returns to the previous track. */
    previous() { return this._post('/playback/command/prev'); }

    /**
     * Seeks to a position in the current track.
     * @param {number} positionMs  Target position in milliseconds.
     */
    seek(positionMs) {
        return this._put('/playback/seek', { positionMs });
    }

    /**
     * Plays a URI directly (e.g. a radio stream URL or a local media URI).
     * @param {string} uri
     */
    playUri(uri) {
        return this._post('/playback/uri', { uri });
    }

    /**
     * Returns queue playback settings (shuffle, repeat, consume mode).
     */
    getQueueSettings() {
        return this._get('/playback/queue/settings');
    }

    /** Clears the playback queue. */
    clearQueue() {
        return this._post('/playback/queue/clear');
    }

    // ── Volume ─────────────────────────────────────────────────────────────────

    /**
     * Returns the current volume state.
     * @returns {Promise<{ volume: { level: number, muted: boolean } }>}
     */
    getVolume() {
        return this._get('/sound/volume');
    }

    /**
     * Sets the volume level.
     * @param {number} level  Integer 0–100.
     */
    setVolume(level) {
        return this._put('/sound/volume/level', { volumeLevel: level });
    }

    /**
     * Mutes or unmutes the speaker.
     * @param {boolean} muted
     */
    setMute(muted) {
        return this._put('/sound/volume/mute', { muted });
    }

    /**
     * Returns volume limits and default settings configured on the device.
     */
    getVolumeSettings() {
        return this._get('/sound/volume/settings');
    }

    // ── Sources ────────────────────────────────────────────────────────────────

    /**
     * Returns all available input sources on this device
     * (Spotify, Deezer, Bluetooth, AirPlay, HDMI, Optical, Line-in, etc.).
     */
    getSources() {
        return this._get('/playback/sources');
    }

    /**
     * Activates a specific source by its ID.
     * Source IDs are returned by getSources().
     * @param {string} sourceId  e.g. "bluetooth", "spotify", "hdmi"
     */
    setSource(sourceId) {
        return this._post(`/playback/sources/active/${encodeURIComponent(sourceId)}`);
    }

    // ── Sound settings ─────────────────────────────────────────────────────────

    /**
     * Returns available sound features supported by this device model.
     */
    getSoundFeatures() {
        return this._get('/sound/features');
    }

    /**
     * Returns available listening modes (e.g. stereo, spatialised, mono).
     */
    getListeningModes() {
        return this._get('/sound/listening-modes');
    }

    /**
     * Activates a listening mode by its ID.
     * IDs are returned by getListeningModes().
     * @param {string} id
     */
    setListeningMode(id) {
        return this._post(`/sound/listening-modes/${encodeURIComponent(id)}/activate`);
    }

    /**
     * Sets bass adjustment.
     * @param {number} level  Typically -6 to +6 dB depending on device model.
     */
    setBass(level) {
        return this._put('/sound/settings/adjustments/bass', { value: level });
    }

    /**
     * Sets treble adjustment.
     * @param {number} level  Typically -6 to +6 dB depending on device model.
     */
    setTreble(level) {
        return this._put('/sound/settings/adjustments/treble', { value: level });
    }

    /**
     * Enables or disables loudness compensation.
     * @param {boolean} enabled
     */
    setLoudness(enabled) {
        return this._put('/sound/settings/adjustments/loudness', { enabled });
    }

    // ── Multi-room (Beolink) ───────────────────────────────────────────────────

    /**
     * Returns this device's Beolink identity (JID, friendly name, etc.).
     */
    getBeolinkSelf() {
        return this._get('/beolink/self');
    }

    /**
     * Discovers other Beolink-capable devices on the same network.
     * @returns {Promise<Array<{ jid: string, friendlyName: string }>>}
     */
    getBeolinkPeers() {
        return this._get('/beolink/peers');
    }

    /**
     * Expands the current audio experience to another Beolink device.
     * @param {string} jid  The JID of the target device (from getBeolinkPeers).
     */
    beolinkExpand(jid) {
        return this._post(`/beolink/expand/${encodeURIComponent(jid)}`);
    }

    /**
     * Joins another device's active Beolink experience.
     */
    beolinkJoin() {
        return this._post('/beolink/join');
    }

    /**
     * Leaves the current Beolink multi-room session.
     */
    beolinkLeave() {
        return this._post('/beolink/leave');
    }

    /**
     * Sends all Beolink-connected devices to standby simultaneously.
     */
    beolinkAllStandby() {
        return this._post('/beolink/allstandby');
    }
}
