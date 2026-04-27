'use strict';

/**
 * speakercard.js
 *
 * Creates and keeps speaker cards in sync with live Speaker state.
 *
 * Usage:
 *   import { addSpeakerCard } from './speakercard.js';
 *   addSpeakerCard(speaker, listEl, hintEl);
 */

/**
 * Creates a card for the speaker, appends it to listEl, and wires live updates.
 * Removes hintEl on the first call if it is still in the DOM.
 *
 * @param {import('./environment/speaker.js').Speaker} speaker
 * @param {HTMLElement} listEl
 * @param {HTMLElement|null} hintEl
 */
export function addSpeakerCard(speaker, listEl, hintEl) {
    hintEl?.remove();

    const card = document.createElement('div');
    card.className    = 'speaker-card';
    card.dataset.host = speaker.host;

    card.innerHTML = `
        <div class="speaker-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
                <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/>
                <path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>
                <path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>
            </svg>
        </div>
        <div class="speaker-info">
            <p class="speaker-name"></p>
            <p class="speaker-state"></p>
            <p class="speaker-track"></p>
            <p class="speaker-battery" hidden></p>
        </div>
        <p class="speaker-volume" hidden></p>
    `;

    listEl.appendChild(card);
    renderCard(card, speaker);
    speaker.onStateChange((s) => renderCard(card, s));
}

function renderCard(card, speaker) {
    const icon    = card.querySelector('.speaker-icon');
    const name    = card.querySelector('.speaker-name');
    const state   = card.querySelector('.speaker-state');
    const track   = card.querySelector('.speaker-track');
    const battery = card.querySelector('.speaker-battery');
    const volume  = card.querySelector('.speaker-volume');

    icon.className    = 'speaker-icon' + (speaker.isPlaying ? ' playing' : '');
    name.textContent  = speaker.name;
    state.textContent = speaker.state === 'playing'   ? 'Playing'
                      : speaker.state === 'started'    ? 'Playing'
                      : speaker.state === 'paused'    ? 'Paused'
                      : speaker.state === 'buffering' ? 'Buffering'
                      : 'Idle';

    if (speaker.isPlaying) {
        const { metadata, source } = speaker;
        const primary   = [metadata?.artist, metadata?.title].filter(Boolean);
        const secondary = metadata?.genre ?? metadata?.album ?? null;
        track.textContent = primary.length ? primary.join(' – ')
                          : secondary      ? [metadata?.artist, secondary].filter(Boolean).join(' – ')
                          : source         ? source
                          : '';
    } else {
        track.textContent = '';
    }

    if (speaker.volume !== null) {
        volume.textContent = `Vol ${speaker.volume}`;
        volume.hidden = false;
    } else {
        volume.hidden = true;
    }

    if (speaker.battery) {
        const { level, isCharging } = speaker.battery;
        battery.textContent = isCharging ? `${level}% ⚡` : `${level}%`;
        battery.hidden = false;
    } else {
        battery.hidden = true;
    }
}
