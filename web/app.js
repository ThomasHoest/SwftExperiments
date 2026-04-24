'use strict';

// ─── View switching ───────────────────────────────────────────────────────────

function showView(id) {
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    document.getElementById(id).classList.add('active');
}

document.getElementById('btn-try').addEventListener('click', () => {
    showView('view-experience');
    startExperience();
});

document.getElementById('btn-back').addEventListener('click', () => {
    stopExperience();
    showView('view-landing');
});

// ─── Audio analysis (drives orb) ─────────────────────────────────────────────

let audioCtx   = null;
let analyser   = null;
let micStream  = null;
let rafId      = null;

async function setupAudio() {
    micStream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
    audioCtx  = new (window.AudioContext || window.webkitAudioContext)();
    analyser  = audioCtx.createAnalyser();
    analyser.fftSize = 512;
    analyser.smoothingTimeConstant = 0.78;

    const source = audioCtx.createMediaStreamSource(micStream);
    source.connect(analyser);
}

function startOrbLoop() {
    const orb   = document.getElementById('orb');
    const stage = document.getElementById('orb-stage');
    const data  = new Uint8Array(analyser.frequencyBinCount);

    function tick() {
        analyser.getByteFrequencyData(data);

        // RMS energy, normalised to 0–1
        let sum = 0;
        for (let i = 0; i < data.length; i++) sum += data[i] * data[i];
        const energy = Math.min(Math.sqrt(sum / data.length) / 38, 1);

        orb.style.setProperty('--energy', energy.toFixed(3));

        const speaking = energy > 0.1;
        orb.classList.toggle('live', speaking);
        stage.classList.toggle('speaking', speaking);

        rafId = requestAnimationFrame(tick);
    }

    tick();
}

function stopAudio() {
    if (rafId)      { cancelAnimationFrame(rafId); rafId = null; }
    if (micStream)  { micStream.getTracks().forEach(t => t.stop()); micStream = null; }
    if (audioCtx)   { audioCtx.close(); audioCtx = null; }
    analyser = null;

    const orb   = document.getElementById('orb');
    const stage = document.getElementById('orb-stage');
    orb.style.setProperty('--energy', '0');
    orb.classList.remove('live');
    stage.classList.remove('speaking');
}

// ─── Speech recognition (transcript) ─────────────────────────────────────────

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
            scheduleClear(5000);
        } else if (interim) {
            setTranscript(interim, true);
            clearTimeout(clearTimer);
        }
    };

    recognition.onerror = () => {};
    recognition.onend   = () => { if (recognition) recognition.start(); };

    recognition.start();
}

function stopRecognition() {
    if (recognition) {
        recognition.onend = null;
        recognition.stop();
        recognition = null;
    }
    clearTimeout(clearTimer);
    clearTranscript();
}

function setTranscript(text, isInterim) {
    const el = document.getElementById('transcript');
    el.textContent = text;
    el.className = 'transcript show' + (isInterim ? ' interim' : '');
}

function clearTranscript() {
    const el = document.getElementById('transcript');
    el.className = 'transcript';
    setTimeout(() => { if (!el.className.includes('show')) el.textContent = ''; }, 300);
}

function scheduleClear(ms) {
    clearTimeout(clearTimer);
    clearTimer = setTimeout(clearTranscript, ms);
}

// ─── Experience lifecycle ─────────────────────────────────────────────────────

async function startExperience() {
    const status = document.getElementById('mic-status');
    status.textContent = 'Requesting microphone…';

    try {
        await setupAudio();
        status.textContent = '';
        startOrbLoop();
        startRecognition();
    } catch {
        status.textContent = 'Microphone access denied — allow it in browser settings';
    }
}

function stopExperience() {
    stopAudio();
    stopRecognition();
    document.getElementById('mic-status').textContent = '';
}
