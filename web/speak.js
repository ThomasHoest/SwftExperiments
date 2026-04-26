'use strict';

import { House }     from './environment/house.js';
import { Speaker }   from './environment/speaker.js';
import { Discovery } from './environment/discovery.js';

// ─── DOM refs ─────────────────────────────────────────────────────────────────

const orb            = document.getElementById('orb');
const orbStage       = document.getElementById('orb-stage');
const transcriptEl   = document.getElementById('transcript');
const micStatusEl    = document.getElementById('mic-status');
const speakerList    = document.getElementById('speaker-list');
const discoveryHint  = document.getElementById('discovery-hint');

// ─── Microphone + audio analysis (drives orb) ────────────────────────────────

let audioCtx = null;
let analyser = null;

async function setupAudio() {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
    audioCtx     = new (window.AudioContext || window.webkitAudioContext)();
    analyser     = audioCtx.createAnalyser();
    analyser.fftSize = 512;
    analyser.smoothingTimeConstant = 0.78;
    audioCtx.createMediaStreamSource(stream).connect(analyser);
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

        requestAnimationFrame(tick);
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

function addSpeakerCard(speaker) {
    if (discoveryHint) discoveryHint.remove();

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
            <p class="speaker-source" hidden></p>
            <p class="speaker-track"></p>
            <p class="speaker-battery" hidden></p>
        </div>
    `;

    speakerList.appendChild(card);
    renderCard(card, speaker);
    speaker.onStateChange((s) => renderCard(card, s));
}

function renderCard(card, speaker) {
    const icon    = card.querySelector('.speaker-icon');
    const name    = card.querySelector('.speaker-name');
    const state   = card.querySelector('.speaker-state');
    const source  = card.querySelector('.speaker-source');
    const track   = card.querySelector('.speaker-track');
    const battery = card.querySelector('.speaker-battery');

    icon.className  = 'speaker-icon' + (speaker.isPlaying ? ' playing' : '');
    name.textContent  = speaker.name;
    state.textContent = speaker.state === 'playing'   ? 'Playing'
                      : speaker.state === 'paused'    ? 'Paused'
                      : speaker.state === 'buffering' ? 'Buffering'
                      : 'Idle';

    if (speaker.isPlaying && speaker.source) {
        source.textContent = speaker.source;
        source.hidden = false;
    } else {
        source.hidden = true;
    }

    if (speaker.isPlaying && speaker.metadata) {
        const { artist, title } = speaker.metadata;
        track.textContent = [artist, title].filter(Boolean).join(' – ');
    } else {
        track.textContent = '';
    }

    if (speaker.battery) {
        const { level, isCharging } = speaker.battery;
        battery.textContent = isCharging ? `${level}% ⚡` : `${level}%`;
        battery.hidden = false;
    } else {
        battery.hidden = true;
    }
}

// ─── LAN permission ───────────────────────────────────────────────────────────

function probeLan() {
    const ctrl = new AbortController();
    setTimeout(() => ctrl.abort(), 2000);
    fetch('http://192.168.1.1', { mode: 'no-cors', signal: ctrl.signal }).catch(() => {});
}

// ─── Discovery ────────────────────────────────────────────────────────────────

const house     = new House('My Home');
const discovery = new Discovery(house);

const DEV_SPEAKERS = ['192.168.0.71', '192.168.0.66', '192.168.0.42'];

async function startDiscovery() {
    if (discoveryHint) { discoveryHint.textContent = 'Discovering…'; discoveryHint.hidden = false; }

    for (const host of DEV_SPEAKERS) {
        try {
            const speaker = new Speaker(host);
            await speaker.initialize();
            house.addSpeaker(speaker);
            addSpeakerCard(speaker);
        } catch (err) {
            console.warn(`[Dev] ${host} unreachable:`, err.message);
        }
    }

    // discovery.StartDiscovery({ onFound: addSpeakerCard });
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

    probeLan();
    startDiscovery();
})();
