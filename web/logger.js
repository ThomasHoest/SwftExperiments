'use strict';

const Level = { VERBOSE: 0, INFO: 1, ERROR: 2 };

// ── Change this to adjust what gets printed ───────────────────────────────────
const CURRENT_LEVEL = Level.INFO;

function log(level, ...args) {
    if (level < CURRENT_LEVEL) return;
    if (level === Level.ERROR) console.error(...args);
    else                       console.log(...args);
}

export const logger = {
    verbose : (...args) => log(Level.VERBOSE, ...args),
    info    : (...args) => log(Level.INFO,    ...args),
    error   : (...args) => log(Level.ERROR,   ...args),
};
