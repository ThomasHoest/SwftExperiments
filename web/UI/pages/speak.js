'use strict';

import { House }          from '../../environment/house.js';
import { Speaker }        from '../../environment/speaker.js';
import { Discovery }      from '../../environment/discovery.js';
import { addSpeakerCard } from '../components/speakercard.js';

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
            addSpeakerCard(speaker, speakerList, discoveryHint);
        } catch (err) {
            console.warn(`[Dev] ${host} unreachable:`, err.message);
        }
    }

    // discovery.StartDiscovery({ onFound: addSpeakerCard });
}

// ─── Page init ────────────────────────────────────────────────────────────────

async function initMic() {
    if (!navigator.mediaDevices) {
        micStatusEl.innerHTML =
            `Microphone requires a secure context — open ` +
            `<a class="btn-mic-retry" href="https://localhost:${location.port}${location.pathname}">localhost</a> instead.`;
        return;
    }

    micStatusEl.textContent = 'Requesting microphone…';
    try {
        await setupAudio();
        micStatusEl.textContent = '';
        startOrbLoop();
        startRecognition();
    } catch {
        micStatusEl.innerHTML =
            'Microphone access denied. ' +
            '<button class="btn-mic-retry">Grant access</button>';
        micStatusEl.querySelector('.btn-mic-retry')
            .addEventListener('click', () => initMic(), { once: true });
    }
}

(async () => {
    await initMic();
    probeLan();
    startDiscovery();
})();
