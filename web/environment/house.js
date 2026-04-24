/**
 * house.js
 *
 * Represents the physical home environment that contains one or more
 * Bang & Olufsen speakers.
 *
 * The House is a simple keyed collection. Speakers are indexed by their
 * host (IP address) so the same device is never duplicated. Discovery
 * adds speakers here automatically; callers can also add or remove them
 * manually.
 *
 * Usage:
 *   const house = new House('My Home');
 *   // Speakers are added by Discovery.StartDiscovery() automatically.
 *   console.log(house.getSpeakers());
 *   console.log(house.getPlayingSpeakers());
 */

export class House {
    /**
     * @param {string} [name]  Optional friendly name for this home environment.
     */
    constructor(name = 'Home') {
        /** @type {string} */
        this.name = name;

        /**
         * Internal speaker registry keyed by host (IP address).
         * @type {Map<string, import('./speaker.js').Speaker>}
         */
        this._speakers = new Map();
    }

    // ── Speaker management ─────────────────────────────────────────────────────

    /**
     * Adds a speaker to the house.
     * If a speaker with the same host already exists it is replaced — the old
     * instance is disposed first to clean up its event stream.
     *
     * @param {import('./speaker.js').Speaker} speaker
     */
    addSpeaker(speaker) {
        const existing = this._speakers.get(speaker.host);
        if (existing && existing !== speaker) existing.dispose();
        this._speakers.set(speaker.host, speaker);
    }

    /**
     * Removes a speaker by host and disposes it.
     * A no-op if no speaker with that host is registered.
     *
     * @param {string} host  IP address of the speaker to remove.
     */
    removeSpeaker(host) {
        const speaker = this._speakers.get(host);
        if (!speaker) return;
        speaker.dispose();
        this._speakers.delete(host);
    }

    /**
     * Returns the speaker registered under the given host, or undefined.
     *
     * @param {string} host
     * @returns {import('./speaker.js').Speaker|undefined}
     */
    getSpeaker(host) {
        return this._speakers.get(host);
    }

    /**
     * Returns all speakers currently registered in the house.
     *
     * @returns {import('./speaker.js').Speaker[]}
     */
    getSpeakers() {
        return Array.from(this._speakers.values());
    }

    /**
     * Returns only the speakers that are actively playing audio right now.
     *
     * @returns {import('./speaker.js').Speaker[]}
     */
    getPlayingSpeakers() {
        return this.getSpeakers().filter(s => s.isPlaying);
    }

    /**
     * Returns the number of speakers registered in the house.
     * @type {number}
     */
    get count() {
        return this._speakers.size;
    }

    /**
     * Disposes all speakers and clears the house.
     * Call this on application shutdown or when re-running discovery
     * from scratch.
     */
    clear() {
        for (const speaker of this._speakers.values()) speaker.dispose();
        this._speakers.clear();
    }
}
