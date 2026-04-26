/**
 * discovery.js  (Node.js — server side)
 *
 * Orchestrates speaker discovery. Calls startDiscovery() from mdns-server
 * directly, maintains the active speaker list, and notifies SSE listeners.
 *
 * Used by server.js to drive the /api/events SSE stream.
 */

import { startDiscovery } from './mdns-server.js';

export class Discovery {
    constructor() {
        this._speakers  = new Map();   // host → {name, host, port}
        this._listeners = new Set();   // SSE notify callbacks
        this._handle    = null;
        this._started   = false;
    }

    /**
     * Starts mDNS discovery. Safe to call multiple times — only runs once.
     */
    StartDiscovery() {
        if (this._started) return;
        this._started = true;

        this._handle = startDiscovery({
            onFound: (speaker) => {
                this._speakers.set(speaker.host, speaker);
                this._emit({ type: 'found', speaker });
            },
            onLost: (host) => {
                if (this._speakers.delete(host)) {
                    this._emit({ type: 'lost', host });
                }
            },
        });
    }

    /** Returns all currently known speakers. */
    getActiveSpeakers() {
        return [...this._speakers.values()];
    }

    /**
     * Registers a listener that receives { type, speaker|host } events.
     * Returns an unsubscribe function.
     * @param {(event: object) => void} fn
     */
    onEvent(fn) {
        this._listeners.add(fn);
        return () => this._listeners.delete(fn);
    }

    refresh() {
        this._handle?.refresh();
    }

    destroy() {
        this._handle?.destroy();
    }

    _emit(event) {
        for (const fn of this._listeners) fn(event);
    }
}
