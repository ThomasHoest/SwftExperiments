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

import { BeoClient }              from '../api/beo-client.js';
import { BeoEvents, BeoEventType } from '../api/beo-events.js';

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
         * Current volume state.
         * @type {{ level: number, muted: boolean }|null}
         */
        this.volume = null;

        // Internal Mozart API handles — not intended for direct use by callers.
        this._client = new BeoClient(host);
        this._events = new BeoEvents(host, { autoReconnect: true });
    }

    // ── Derived state ──────────────────────────────────────────────────────────

    /** True while the speaker is actively playing audio. */
    get isPlaying() {
        return this.state === 'playing';
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
        const [identity, playbackState, metadata, volume] = await Promise.allSettled([
            this._client.getBeolinkSelf(),       // { jid, friendlyName }
            this._client.getPlaybackState(),      // { value: 'playing'|… }
            this._client.getPlaybackMetadata(),   // { title, artist, album, … }
            this._client.getVolume(),             // { volume: { level, muted } }
        ]);

        if (identity.status      === 'fulfilled') this._applyIdentity(identity.value);
        if (playbackState.status === 'fulfilled') this._applyPlaybackState(playbackState.value);
        if (metadata.status      === 'fulfilled') this._applyMetadata(metadata.value);
        if (volume.status        === 'fulfilled') this._applyVolume(volume.value);

        // Wire up live updates — each event type maps to its local updater.
        this._events
            .on(BeoEventType.PLAYBACK_STATE,    data => this._applyPlaybackState(data))
            .on(BeoEventType.PLAYBACK_METADATA, data => this._applyMetadata(data))
            .on(BeoEventType.VOLUME,            data => this._applyVolume(data));

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
        // The REST response uses "state"; the WebSocket event uses "value".
        const raw = data?.value ?? data?.state;
        if (raw) this.state = raw;
    }

    /**
     * Applies track metadata from either:
     *   REST  GET /api/v1/playback/metadata
     *   Event WebSocketEventPlaybackMetadata
     * @param {object|null} data
     */
    _applyMetadata(data) {
        if (!data) { this.metadata = null; return; }
        this.metadata = {
            title:      data.title              ?? null,
            artist:     data.artist             ?? null,
            album:      data.album              ?? null,
            // trackImage is an array ordered by resolution; take the first entry.
            artworkUrl: data.trackImage?.[0]?.url ?? null,
            durationMs: data.duration           ?? null,
        };
    }

    /**
     * Applies volume state from either:
     *   REST  GET /api/v1/sound/volume  → { volume: { level, muted } }
     *   Event WebSocketEventVolume      → { volume: { level, muted } }
     * @param {object|null} data
     */
    _applyVolume(data) {
        const v = data?.volume ?? data;
        if (v?.level !== undefined) {
            this.volume = { level: v.level, muted: v.muted ?? false };
        }
    }
}
