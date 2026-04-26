/**
 * beo-events.js
 *
 * WebSocket event client for the Bang & Olufsen Mozart Open API.
 *
 * The speaker streams real-time state changes over a persistent WebSocket
 * connection on port 9339. Any number of clients can connect simultaneously.
 *
 * Spec:    https://bang-olufsen.github.io/mozart-open-api/
 * GitHub:  https://github.com/bang-olufsen/mozart-open-api
 *
 * ── Usage ──────────────────────────────────────────────────────────────────────
 *
 *   const events = new BeoEvents('192.168.1.50');
 *
 *   events.on(BeoEventType.VOLUME, ({ volume }) => {
 *       console.log('Volume is now', volume.level);
 *   });
 *
 *   events.connect();
 *   // later…
 *   events.disconnect();
 *
 * ── Message shape ──────────────────────────────────────────────────────────────
 *
 *   Every message from the device is a JSON object:
 *   {
 *     "eventType": "WebSocketEventVolume",
 *     "eventData": { ... }
 *   }
 *
 *   Handlers registered with .on(type, fn) receive only the eventData payload.
 */

// ── Event type constants ───────────────────────────────────────────────────────

/**
 * All event types emitted by the Mozart WebSocket endpoint.
 * Use these as keys with BeoEvents.on() / BeoEvents.off().
 */
import { logger } from '../logger.js';

export const BeoEventType = Object.freeze({
    // Power & hardware
    POWER_STATE:          'WebSocketEventPowerState',
    BATTERY:              'WebSocketEventBattery',
    BUTTON:               'WebSocketEventButton',
    BEO_REMOTE_BUTTON:    'WebSocketEventBeoRemoteButton',

    // Playback
    PLAYBACK_STATE:       'WebSocketEventPlaybackState',
    PLAYBACK_METADATA:    'WebSocketEventPlaybackMetadata',
    PLAYBACK_PROGRESS:    'WebSocketEventPlaybackProgress',
    PLAYBACK_SOURCE:      'WebSocketEventPlaybackSource',
    PLAYBACK_ERROR:       'WebSocketEventPlaybackError',

    // Audio / sound
    VOLUME:               'WebSocketEventVolume',
    LISTENING_MODE:       'WebSocketEventActiveListeningMode',

    // Multi-room
    SPEAKER_GROUP:        'WebSocketEventActiveSpeakerGroup',
    BEOLINK_EXPERIENCE:   'WebSocketEventBeolinkExperience',
    BEOLINK_PEERS:        'WebSocketEventBeolinkPeersUpdate',

    // Timers & alarms
    ALARM_TIMER:          'WebSocketEventAlarmTimer',

    // Connectivity
    BLUETOOTH:            'WebSocketEventBluetooth',
    WIFI:                 'WebSocketEventWifi',

    // Settings
    NOTIFICATION:         'WebSocketEventNotification',
    CONFIGURATION:        'WebSocketEventConfiguration',
    SOFTWARE_UPDATE:      'WebSocketEventSoftwareUpdateState',
    PROXIMITY:            'WebSocketEventProximity',
});

// Reconnect delay sequence (ms): 1s, 2s, 4s, 8s, 16s, then cap at 30s.
const BACKOFF_BASE    = 1_000;
const BACKOFF_MAX     = 30_000;

// The remote control endpoint streams button events from Beo remotes.
const WS_PATH_DEFAULT       = '/';
const WS_PATH_REMOTE        = '/remoteControl';

export class BeoEvents {
    /**
     * @param {string} host        IP address or hostname of the speaker.
     * @param {{ remote?: boolean, autoReconnect?: boolean }} [opts]
     *   remote        – Connect to the remote-control endpoint instead of the
     *                   main event stream (default: false).
     *   autoReconnect – Automatically reconnect on unexpected close (default: true).
     */
    constructor(host, { remote = false, autoReconnect = true } = {}) {
        // Route through the server proxy so wss: pages can reach plain ws: speakers.
        const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
        const path   = remote ? WS_PATH_REMOTE : WS_PATH_DEFAULT;
        this._url    = `${scheme}://${location.host}/ws-proxy/${host}${path}`;
        this._autoReconnect = autoReconnect;
        this._handlers      = new Map();   // eventType → Set<Function>
        this._ws            = null;
        this._retryCount    = 0;
        this._retryTimer    = null;
        this._stopped       = false;       // true after explicit disconnect()
    }

    // ── Public API ─────────────────────────────────────────────────────────────

    /**
     * Opens the WebSocket connection to the speaker.
     * Safe to call multiple times — a no-op if already connected.
     */
    connect() {
        if (this._ws && this._ws.readyState <= WebSocket.OPEN) return;
        this._stopped = false;
        this._open();
    }

    /**
     * Closes the connection and disables auto-reconnect.
     */
    disconnect() {
        this._stopped = true;
        clearTimeout(this._retryTimer);
        if (this._ws) {
            this._ws.onclose = null;   // prevent reconnect loop
            this._ws.close();
            this._ws = null;
        }
    }

    /**
     * Registers a handler for a specific event type.
     * Multiple handlers per type are supported.
     *
     * @param {string}   eventType  One of BeoEventType.*
     * @param {Function} handler    Called with eventData as the sole argument.
     * @returns {this} For chaining.
     *
     * @example
     * events.on(BeoEventType.VOLUME, ({ volume }) => console.log(volume.level));
     */
    on(eventType, handler) {
        if (!this._handlers.has(eventType)) {
            this._handlers.set(eventType, new Set());
        }
        this._handlers.get(eventType).add(handler);
        return this;
    }

    /**
     * Removes a previously registered handler.
     * @param {string}   eventType
     * @param {Function} handler
     * @returns {this}
     */
    off(eventType, handler) {
        this._handlers.get(eventType)?.delete(handler);
        return this;
    }

    /**
     * Removes all handlers for a given event type, or all handlers if no
     * type is specified.
     * @param {string} [eventType]
     */
    offAll(eventType) {
        if (eventType) this._handlers.delete(eventType);
        else this._handlers.clear();
    }

    /** @returns {'connecting'|'open'|'closing'|'closed'|'disconnected'} */
    get status() {
        if (!this._ws) return 'disconnected';
        return ['connecting', 'open', 'closing', 'closed'][this._ws.readyState];
    }

    // ── Internal ───────────────────────────────────────────────────────────────

    _open() {
        this._ws = new WebSocket(this._url);

        this._ws.onopen = () => {
            this._retryCount = 0;    // reset backoff on successful connection
            logger.verbose(`[BeoEvents] connected → ${this._url}`);
            this._emit('_connected', {});
        };

        this._ws.onmessage = ({ data }) => {
            let msg;
            try { msg = JSON.parse(data); } catch { return; }

            const { eventType, eventData } = msg;
            if (!eventType) return;

            logger.verbose(`[BeoEvents] ${eventType}`, eventData ?? {});
            this._emit(eventType, eventData ?? {});
        };

        this._ws.onerror = () => {
            // onerror is always followed by onclose — handle retry there.
        };

        this._ws.onclose = ({ wasClean }) => {
            this._ws = null;
            logger.verbose(`[BeoEvents] disconnected (${wasClean ? 'clean' : 'unclean'}) → ${this._url}`);
            this._emit('_disconnected', { wasClean });

            if (!this._stopped && this._autoReconnect) {
                this._scheduleRetry();
            }
        };
    }

    _emit(eventType, data) {
        this._handlers.get(eventType)?.forEach(fn => {
            try { fn(data); } catch (e) { logger.error('[BeoEvents] handler error', e); }
        });
    }

    _scheduleRetry() {
        // Exponential backoff capped at BACKOFF_MAX.
        const delay = Math.min(BACKOFF_BASE * 2 ** this._retryCount, BACKOFF_MAX);
        this._retryCount++;
        this._retryTimer = setTimeout(() => this._open(), delay);
    }
}
