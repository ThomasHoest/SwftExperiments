'use strict';

// ─── State ───────────────────────────────────────────────────────────────────

const state = {
    micGranted: false,
    speakerUrl: null,
    speakerConnected: false,
    isRecording: false,
};

// ─── DOM refs ─────────────────────────────────────────────────────────────────

const micCard     = document.getElementById('mic-card');
const micBtn      = document.getElementById('mic-btn');
const networkCard = document.getElementById('network-card');
const networkBtn  = document.getElementById('network-btn');
const networkPanel = document.getElementById('network-panel');
const connectBtn  = document.getElementById('connect-btn');
const speakerIp   = document.getElementById('speaker-ip');
const speakerPort = document.getElementById('speaker-port');
const recordBtn   = document.getElementById('record-btn');
const txText      = document.getElementById('transcription-text');
const statusText  = document.getElementById('status-text');
const connDot     = document.getElementById('conn-dot');
const connLabel   = document.getElementById('conn-label');

// ─── Speech Recognition ───────────────────────────────────────────────────────

const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
let recognition = null;

if (!SpeechRecognition) {
    const warning = document.createElement('div');
    warning.className = 'browser-warning';
    warning.textContent =
        'Speech recognition is not supported in this browser. Please use Chrome or Edge.';
    document.querySelector('.container').insertBefore(
        warning,
        document.querySelector('.permissions')
    );
    recordBtn.disabled = true;
} else {
    recognition = new SpeechRecognition();
    recognition.continuous     = true;
    recognition.interimResults = true;
    recognition.lang           = 'en-US';

    recognition.onresult = (event) => {
        let interim = '';
        let finalChunk = '';

        for (let i = event.resultIndex; i < event.results.length; i++) {
            const transcript = event.results[i][0].transcript;
            if (event.results[i].isFinal) finalChunk += transcript;
            else interim += transcript;
        }

        if (finalChunk) {
            setTranscription(finalChunk, 'has-text');
            if (state.speakerConnected) sendCommandToSpeaker(finalChunk);
        } else if (interim) {
            setTranscription(interim, 'interim');
        }
    };

    recognition.onerror = (event) => {
        if (event.error === 'not-allowed') setMicState('denied');
        setStatus('Error: ' + event.error);
        setRecording(false);
    };

    // Auto-restart so it stays on until the user stops it
    recognition.onend = () => {
        if (state.isRecording) recognition.start();
    };
}

// ─── Microphone permission ────────────────────────────────────────────────────

micBtn.addEventListener('click', requestMicrophone);

async function requestMicrophone() {
    try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        stream.getTracks().forEach(t => t.stop()); // only needed the grant
        setMicState('granted');
    } catch {
        setMicState('denied');
    }
}

function setMicState(status) {
    state.micGranted = status === 'granted';
    micCard.className = 'permission-card ' + status;
    micBtn.className  = 'permission-btn ' + status;

    if (status === 'granted') {
        micBtn.textContent = 'Granted';
        micBtn.removeEventListener('click', requestMicrophone);
    } else if (status === 'denied') {
        micBtn.textContent = 'Denied';
        setStatus('Microphone blocked — allow it in browser settings and reload.');
        recordBtn.disabled = true;
    }

    refreshRecordBtn();
}

// Check existing permission on load
if (navigator.permissions) {
    navigator.permissions.query({ name: 'microphone' }).then((result) => {
        if (result.state !== 'prompt') setMicState(result.state);
        result.onchange = () => setMicState(result.state);
    }).catch(() => {});
}

// ─── Local network / speaker ──────────────────────────────────────────────────

networkBtn.addEventListener('click', () => {
    networkPanel.classList.toggle('hidden');
});

connectBtn.addEventListener('click', connectToSpeaker);

async function connectToSpeaker() {
    const ip   = speakerIp.value.trim();
    const port = speakerPort.value.trim() || '1400';

    if (!ip) {
        speakerIp.focus();
        return;
    }

    state.speakerUrl = `http://${ip}:${port}`;
    setConnectionStatus('connecting', 'Connecting…');
    connectBtn.disabled = true;

    try {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 5000);

        // mode: 'no-cors' triggers the browser's Private Network Access prompt
        // when connecting from a public/localhost context to a private IP.
        await fetch(state.speakerUrl, { method: 'GET', mode: 'no-cors', signal: controller.signal });
        clearTimeout(timer);

        state.speakerConnected = true;
        setConnectionStatus('connected', `Connected to ${state.speakerUrl}`);
        setSpeakerCardGranted();
        networkPanel.classList.add('hidden');
    } catch (err) {
        connectBtn.disabled = false;
        if (err.name === 'AbortError') {
            setConnectionStatus('error', `Timed out — speaker unreachable at ${state.speakerUrl}`);
        } else {
            // A TypeError from 'no-cors' usually means a network-level failure
            setConnectionStatus('error', `Could not reach speaker at ${state.speakerUrl}`);
        }
    }
}

function setSpeakerCardGranted() {
    networkCard.className = 'permission-card granted';
    networkBtn.className  = 'permission-btn granted';
    networkBtn.textContent = 'Connected';
    networkBtn.removeEventListener('click', () => networkPanel.classList.toggle('hidden'));
}

function setConnectionStatus(type, label) {
    connDot.className = 'dot ' + type;
    connLabel.textContent = label;
}

// ─── Recording ────────────────────────────────────────────────────────────────

recordBtn.addEventListener('click', toggleRecording);

function toggleRecording() {
    if (state.isRecording) stopRecording();
    else startRecording();
}

async function startRecording() {
    if (!recognition) return;

    if (!state.micGranted) {
        await requestMicrophone();
        if (!state.micGranted) return;
    }

    try {
        recognition.start();
        setRecording(true);
        setStatus('Listening…');
        setTranscription('', '');
    } catch (err) {
        setStatus('Could not start: ' + err.message);
    }
}

function stopRecording() {
    if (!recognition) return;
    recognition.stop();
    setRecording(false);
    setStatus('Stopped');
}

function setRecording(val) {
    state.isRecording = val;
    refreshRecordBtn();
}

function refreshRecordBtn() {
    if (!state.micGranted && !state.isRecording) {
        recordBtn.disabled = false; // allow click so we can prompt for mic
    }
    if (state.isRecording) {
        recordBtn.textContent = 'Stop Listening';
        recordBtn.className   = 'record-btn recording';
    } else {
        recordBtn.textContent = 'Start Listening';
        recordBtn.className   = 'record-btn';
    }
}

// ─── UI helpers ───────────────────────────────────────────────────────────────

function setTranscription(text, cls) {
    txText.textContent = text || 'Press the button below and start speaking…';
    txText.className   = text ? cls : '';
}

function setStatus(msg) {
    statusText.textContent = msg;
}

// ─── Speaker command (extend with your protocol here) ────────────────────────

async function sendCommandToSpeaker(command) {
    if (!state.speakerUrl) return;
    console.log('[VoiceToMusic] Command:', command);
    // TODO: implement speaker protocol (Sonos UPnP, REST API, etc.)
    // Example: POST to state.speakerUrl + '/command' with { text: command }
}
