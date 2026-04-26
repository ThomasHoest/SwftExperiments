/**
 * mdns-server.js
 *
 * mDNS/Bonjour discovery module for Bang & Olufsen Mozart speakers.
 * Pure Node.js — no HTTP, no WebSocket. Import and call startDiscovery().
 */

import { Bonjour } from 'bonjour-service';
import MDNS        from 'multicast-dns';

const BONJOUR_TYPE = 'bangolufsen';

/**
 * Starts Bonjour browsing and raw mDNS logging.
 * Calls onFound/onLost as speakers appear and disappear.
 *
 * @param {{ onFound: (s: {name,host,port}) => void, onLost: (host: string) => void }} callbacks
 * @returns {{ refresh: () => void, destroy: () => void }}
 */
export function startDiscovery({ onFound, onLost }) {
    console.log('[mDNS] Starting — logging all multicast DNS traffic');

    const mdns = MDNS();

    mdns.on('response', (response) => {
        const all = [...(response.answers ?? []), ...(response.additionals ?? [])];
        if (all.length === 0) return;
        console.log(`[mDNS] ── response (${all.length} record(s)) ─────────────────────`);
        for (const r of all) {
            console.log(`[mDNS]   ${r.type.padEnd(5)} ${String(r.name).padEnd(50)} ${fmt(r)}`);
        }
    });

    mdns.on('query', (query) => {
        if ((query.questions ?? []).length === 0) return;
        console.log(`[mDNS] ── query (${query.questions.length} question(s)) ──────────────────────`);
        for (const q of query.questions) {
            console.log(`[mDNS]   ${q.type.padEnd(5)} ${q.name}`);
        }
    });

    queryAll();
    setInterval(queryAll, 10_000);

    console.log(`[Bonjour] Browser started for _${BONJOUR_TYPE}._tcp`);
    const bonjour = new Bonjour();
    const browser = bonjour.find({ type: BONJOUR_TYPE });

    browser.on('up', (service) => {
        const ipv4    = service.addresses?.find(a => /^\d+\.\d+\.\d+\.\d+$/.test(a));
        const host    = ipv4 ?? service.host.replace(/\.$/, '');
        const speaker = { name: service.name, host, port: service.port ?? 80 };

        console.log([
            `[Bonjour] ↑ Found:      "${service.name}"`,
            `            host:       ${host}`,
            `            port:       ${speaker.port}`,
            `            addresses:  ${(service.addresses ?? []).join(', ') || '(none)'}`,
            `            txt:        ${JSON.stringify(service.txt ?? {})}`,
        ].join('\n'));

        onFound(speaker);
    });

    browser.on('down', (service) => {
        const ipv4 = service.addresses?.find(a => /^\d+\.\d+\.\d+\.\d+$/.test(a));
        const host = ipv4 ?? service.host.replace(/\.$/, '');
        console.log(`[Bonjour] ↓ Lost: "${service.name}" (${host})`);
        onLost(host);
    });

    setInterval(() => {
        console.log(`[Bonjour] Heartbeat — refreshing browser`);
        browser.update();
    }, 30_000);

    function queryAll() {
        console.log('[mDNS] Querying _services._dns-sd._udp.local');
        mdns.query([{ name: '_services._dns-sd._udp.local', type: 'PTR' }]);
        console.log(`[mDNS] Querying _${BONJOUR_TYPE}._tcp.local`);
        mdns.query([{ name: `_${BONJOUR_TYPE}._tcp.local`, type: 'PTR' }]);
    }

    return {
        refresh() { browser.update(); queryAll(); },
        destroy() { mdns.destroy(); bonjour.destroy(); },
    };
}

function fmt(r) {
    const d = r.data;
    if (!d)                      return '';
    if (typeof d === 'string')   return `→ ${d}`;
    if (typeof d === 'number')   return `→ ${d}`;
    if (Buffer.isBuffer(d))      return `→ <buffer ${d.toString('hex').slice(0, 32)}…>`;
    if (d.target !== undefined)  return `→ ${d.target}:${d.port}`;
    if (d.address !== undefined) return `→ ${d.address}`;
    if (Array.isArray(d))        return `→ [${d.join(', ')}]`;
    return `→ ${JSON.stringify(d)}`;
}
