/**
 * speaker.js
 *
 * Represents a single Bang & Olufsen speaker on the local network.
 *
 * State and metadata are populated on initialise() via the Mozart REST API
 * and then kept live by the Mozart WebSocket event stream. Callers can read
 * the plain properties directly — they are updated in-place as events arrive.
 *
 * Lifecycle:
 *   const speaker = new Speaker('192.168.1.50');
 *   await speaker.initialize();     // fetches state + starts event stream
 *   console.log(speaker.isPlaying); // live thereafter
 *   speaker.dispose();              // call when removing from the house
 */

import { BeoClient }              from '../api/mozart-client.js';
import { BeoEvents, BeoEventType } from '../api/mozart-events.js';
import { logger }                  from '../logger.js';

export class Speaker {
    /**
     * @param {string} host  IP address or hostname of the speaker on the LAN.
     */
    constructor(host) {
        /** @type {string} IP address used to reach this speaker. */
        this.host = host;

        /**
         * Human-readable name reported by the device (e.g. "Living Room").
         * Defaults to the host string until initialize() resolves.
         * @type {string}
         */
        this.name = host;

        /**
         * Current playback state.
         * @type {'playing'|'paused'|'stopped'|'buffering'|'unknown'}
         */
        this.state = 'unknown';

        /**
         * Metadata for the track currently playing.
         * Null when nothing is playing or the device has not reported any.
         * @type {{ title: string|null, artist: string|null, album: string|null, artworkUrl: string|null, durationMs: number|null }|null}
         */
        this.metadata = null;

        /**
         * Current volume level (0–100). Null until the device reports one.
         * @type {number|null}
         */
        this.volume = null;

        /**
         * Battery state for portable devices. Null on mains-powered speakers.
         * @type {{ level: number, isCharging: boolean }|null}
         */
        this.battery = null;

        /**
         * Friendly name of the active source (e.g. "Spotify", "Bluetooth").
         * Null until the device reports one.
         * @type {string|null}
         */
        this.source = null;

        // Internal Mozart API handles — not intended for direct use by callers.
        this._client = new BeoClient(host);
        this._events = new BeoEvents(host, { autoReconnect: true });

        // Registered via onStateChange() — called after any live state update.
        this._changeListeners = new Set();
    }

    // ── Derived state ──────────────────────────────────────────────────────────

    /** True while the speaker is actively playing audio. */
    get isPlaying() {
        return this.state === 'playing' || this.state === 'started';
    }

    /**
     * Registers a callback that fires whenever the speaker's live state changes.
     * The speaker instance itself is passed as the sole argument so the caller
     * can read the latest values directly.
     *
     * @param {(speaker: Speaker) => void} fn
     * @returns {this} For chaining.
     */
    onStateChange(fn) {
        this._changeListeners.add(fn);
        return this;
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    /**
     * Fetches the initial device state and starts the live event stream.
     *
     * All four REST calls run in parallel. Individual failures are tolerated
     * so a speaker with a partial API surface (e.g. no battery endpoint) still
     * initialises correctly.
     *
     * Resolves once the initial state snapshot is applied and the WebSocket
     * connection has been opened (though the first event may arrive later).
     */
    async initialize() {
        // Fetch name, playback state, metadata, and volume concurrently.
        // Promise.allSettled ensures one failure does not abort the others.
        const [identity, playbackState, volume, battery, source] = await Promise.allSettled([
            this._client.getBeolinkSelf(),       // { jid, friendlyName }
            this._client.getPlaybackState(),      // { value: 'playing'|… }
            this._client.getVolume(),             // { volume: { level, muted } }
            this._client.getBattery(),            // { batteryLevel, isCharging, … } — null on mains speakers
            this._client.getActiveSource(),       // { id, friendlyName, … }
        ]);

        if (identity.status      === 'fulfilled') this._applyIdentity(identity.value);
        if (playbackState.status === 'fulfilled') this._applyPlaybackState(playbackState.value);
        if (volume.status        === 'fulfilled') this._applyVolume(volume.value);
        if (battery.status       === 'fulfilled') this._applyBattery(battery.value);
        if (source.status        === 'fulfilled') this._applySource(source.value);

        // Wire up live updates — each event type maps to its local updater.
        this._events
            .on(BeoEventType.PLAYBACK_STATE,    data => this._applyPlaybackState(data))
            .on(BeoEventType.PLAYBACK_METADATA, data => this._applyMetadata(data))
            .on(BeoEventType.VOLUME,            data => this._applyVolume(data))
            .on(BeoEventType.BATTERY,           data => this._applyBattery(data))
            .on(BeoEventType.PLAYBACK_SOURCE,   data => this._applySource(data));

        this._events.connect();
    }

    /**
     * Disconnects the event stream and frees all resources.
     * Must be called before discarding a Speaker instance.
     */
    dispose() {
        this._events.disconnect();
    }

    // ── State appliers (REST response and WebSocket event use the same path) ───

    /**
     * Applies the device identity returned by GET /api/v1/beolink/self.
     * @param {{ friendlyName?: string }} data
     */
    _applyIdentity(data) {
        if (data?.friendlyName) this.name = data.friendlyName;
    }

    /**
     * Applies a playback state value from either:
     *   REST  GET /api/v1/playback/state  → { state: 'playing' }
     *   Event WebSocketEventPlaybackState → { value: 'playing' }
     * @param {{ value?: string, state?: string }|null} data
     */
    _applyPlaybackState(data) {
        const raw = data?.value ?? data?.state;
        if (!raw) return;
        this.state = raw;
        this._notify();
    }

    /**
     * Applies track metadata from either:
     *   REST  GET /api/v1/playback/metadata
     *   Event WebSocketEventPlaybackMetadata
     * @param {object|null} data
     */
    _applyMetadata(data) {
        if (!data) { this.metadata = null; this._notify(); return; }
        this.metadata = {
            title:      data.title              ?? null,
            artist:     data.artist             ?? null,
            album:      data.album              ?? null,
            genre:      data.genre              ?? null,
            // trackImage is an array ordered by resolution; take the first entry.
            artworkUrl: data.trackImage?.[0]?.url ?? null,
            durationMs: data.duration           ?? null,
        };
        this._notify();
    }

    /**
     * Applies volume state from either:
     *   REST  GET /api/v1/sound/volume  → { volume: { level, muted } }
     *   Event WebSocketEventVolume      → { volume: { level, muted } }
     * @param {object|null} data
     */
    _applyVolume(data) {
        const level = data?.volume?.level ?? data?.level ?? data?.volume;
        if (level !== undefined) {
            this.volume = level.level;
            this._notify();
        }
    }

    /**
     * Applies battery state from either:
     *   REST  GET /api/v1/battery         → { batteryLevel, isCharging }
     *   Event WebSocketEventBattery       → { batteryLevel, isCharging }
     * @param {object|null} data
     */
    /**
     * Applies source info from either:
     *   REST  GET /api/v1/playback/sources/active → { id, friendlyName, … }
     *   Event WebSocketEventPlaybackSource        → { id, friendlyName, … }
     * @param {object|null} data
     */
    _applySource(data) {
        const name = data?.friendlyName ?? data?.id ?? null;
        if (name === this.source) return;
        this.source = name;
        this._notify();
    }

    _applyBattery(data) {
        if (!data || data.batteryLevel === undefined) return;
        if (data.batteryLevel === 0 && !data.isCharging) return;
        this.battery = { level: data.batteryLevel, isCharging: data.isCharging ?? false };
        this._notify();
    }

    /** Calls all registered state-change listeners with this speaker instance. */
    _notify() {
        for (const fn of this._changeListeners) {
            try { fn(this); } catch (e) { logger.error('[Speaker] onStateChange handler error', e); }
        }
    }
}
