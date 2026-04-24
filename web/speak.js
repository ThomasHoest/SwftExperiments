'use strict';

import { House }     from './environment/house.js';
import { Discovery } from './environment/discovery.js';

// ─── DOM refs ─────────────────────────────────────────────────────────────────

const orb            = document.getElementById('orb');
const orbStage       = document.getElementById('orb-stage');
const transcriptEl   = document.getElementById('transcript');
const micStatusEl    = document.getElementById('mic-status');
const speakerList    = document.getElementById('speaker-list');
const discoveryHint  = document.getElementById('discovery-hint');

// ─── Microphone + audio analysis (drives orb) ────────────────────────────────

let audioCtx  = null;
let analyser  = null;
let micStream = null;
let rafId     = null;

async function setupAudio() {
    micStream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
    audioCtx  = new (window.AudioContext || window.webkitAudioContext)();
    analyser  = audioCtx.createAnalyser();
    analyser.fftSize = 512;
    analyser.smoothingTimeConstant = 0.78;
    audioCtx.createMediaStreamSource(micStream).connect(analyser);
}

function startOrbLoop() {
    const data = new Uint8Array(analyser.frequencyBinCount);

    function tick() {
        analyser.getByteFrequencyData(data);
        let sum = 0;
        for (let i = 0; i < data.length; i++) sum += data[i] * data[i];
        const energy = Math.min(Math.sqrt(sum / data.length) / 38, 1);

        orb.style.setProperty('--energy', energy.toFixed(3));
        orb.classList.toggle('live', energy > 0.1);
        orbStage.classList.toggle('speaking', energy > 0.1);

        rafId = requestAnimationFrame(tick);
    }
    tick();
}

// ─── Speech recognition ───────────────────────────────────────────────────────

const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
let recognition = null;
let clearTimer  = null;

function startRecognition() {
    if (!SpeechRecognition) return;
    recognition = new SpeechRecognition();
    recognition.continuous     = true;
    recognition.interimResults = true;
    recognition.lang           = 'en-US';

    recognition.onresult = (event) => {
        let interim = '', final = '';
        for (let i = event.resultIndex; i < event.results.length; i++) {
            const t = event.results[i][0].transcript;
            if (event.results[i].isFinal) final += t;
            else interim += t;
        }
        if (final) {
            setTranscript(final, false);
            clearTimer = setTimeout(() => setTranscript('', false), 5000);
        } else if (interim) {
            clearTimeout(clearTimer);
            setTranscript(interim, true);
        }
    };

    recognition.onerror = () => {};
    recognition.onend   = () => { if (recognition) recognition.start(); };
    recognition.start();
}

function setTranscript(text, isInterim) {
    transcriptEl.textContent = text;
    transcriptEl.className   = text
        ? 'transcript show' + (isInterim ? ' interim' : '')
        : 'transcript';
}

// ─── Speaker pane ─────────────────────────────────────────────────────────────

/**
 * Creates a DOM card for a speaker and inserts it into the speaker list.
 * Registers onStateChange so the card updates live whenever the speaker's
 * state or metadata changes.
 *
 * @param {import('./environment/speaker.js').Speaker} speaker
 */
function addSpeakerCard(speaker) {
    // Remove the "Starting discovery…" hint once the first speaker appears.
    if (discoveryHint) discoveryHint.remove();

    const card = document.createElement('div');
    card.className = 'speaker-card';
    card.dataset.host = speaker.host;

    card.innerHTML = `
        <span class="speaker-dot"></span>
        <div class="speaker-info">
            <p class="speaker-name"></p>
            <p class="speaker-track"></p>
        </div>
    `;

    speakerList.appendChild(card);
    renderCard(card, speaker);

    // Live updates: re-render the card whenever state or metadata changes.
    speaker.onStateChange((s) => renderCard(card, s));
}

/**
 * Writes the latest speaker state into an existing card element.
 * @param {HTMLElement} card
 * @param {import('./environment/speaker.js').Speaker} speaker
 */
function renderCard(card, speaker) {
    const dot   = card.querySelector('.speaker-dot');
    const name  = card.querySelector('.speaker-name');
    const track = card.querySelector('.speaker-track');

    dot.className  = 'speaker-dot' + (speaker.isPlaying ? ' playing' : '');
    name.textContent = speaker.name;

    if (speaker.isPlaying && speaker.metadata) {
        const { artist, title } = speaker.metadata;
        track.textContent = [artist, title].filter(Boolean).join(' – ');
    } else {
        track.textContent = '';
    }
}

// ─── Discovery ────────────────────────────────────────────────────────────────

const house     = new House('My Home');
const discovery = new Discovery(house);

function startDiscovery() {
    discovery.StartDiscovery({
        onFound: (speaker) => addSpeakerCard(speaker),
    }).then((speakers) => {
        if (discoveryHint) {
            discoveryHint.textContent = speakers.length === 0
                ? 'No speakers found'
                : '';
        }
    }).catch(() => {
        if (discoveryHint) {
            discoveryHint.textContent = 'Discovery server unavailable';
        }
    });
}

// ─── Page init ────────────────────────────────────────────────────────────────

(async () => {
    micStatusEl.textContent = 'Requesting microphone…';

    try {
        await setupAudio();
        micStatusEl.textContent = '';
        startOrbLoop();
        startRecognition();
    } catch {
        micStatusEl.textContent = 'Microphone access denied — allow it in browser settings';
    }

    startDiscovery();
})();
