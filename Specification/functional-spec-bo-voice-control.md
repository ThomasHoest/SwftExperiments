# Functional Specification: Bang & Olufsen Voice Controller
**Version:** 1.2  
**Status:** Draft  
**Date:** 2026-04-28

---

## Overview

A voice-controlled interface for Bang & Olufsen speakers that allows users to start playback from favorites, stop the current session, and adjust volume — all through natural spoken commands. Every command must be prefixed with the speaker's name, and the app always reads back exactly what it is about to do before executing.

---

## Technical Context

| Decision | Choice |
|---|---|
| API | Bang & Olufsen Mozart API |
| Platform | iOS only |
| Background execution | No — active use only |
| Favorites source | Read from the individual speaker via Mozart API |
| Volume scale | 0–100 in 1% steps |
| Speaker addressing | Speaker name must be spoken before every command |
| Confirmation feedback | App reads back the exact action before executing |
| Language | English only (v1) |

---

## Goals

- Provide hands-free control of B&O speakers via voice
- Cover the core playback lifecycle in v1: start, stop, and volume
- Keep the interaction model simple and predictable for everyday use

---

## Out of Scope (v1)

- Browsing or searching for new content
- Multi-room/multi-speaker management
- Playback queue management (skip, shuffle, repeat)
- Speaker settings or EQ configuration
- Pairing or device setup

---

## User Stories

### 0. Speaker Addressing

**US-00 — Address a speaker by name before issuing a command**
> As a user, I want to say the speaker's name at the start of every command so that the app knows which speaker to control.

**Acceptance criteria:**
- Every voice command must begin with the speaker's name as registered in the Mozart API (e.g. *"Beosound, play Jazz Radio"*)
- The app retrieves the list of available speaker names from the Mozart API on launch
- If a command is spoken without a recognized speaker name, the app responds: *"Please start your command with a speaker name"* and lists available speakers
- Speaker name matching is case-insensitive and tolerates minor mispronunciation through fuzzy matching
- If only one speaker is available, that speaker is still addressed by name; there is no implicit default

---

### 1. Start Playback from Favorites

**US-01 — Play a specific favorite**
> As a user, I want to say the speaker name followed by a favorite name so that the correct speaker starts playing it immediately.

**Acceptance criteria:**
- Command format: *"[Speaker name], play [favorite name]"*
- The app fetches the current favorites list from the named speaker via the Mozart API, then maps the spoken name to a match
- Before executing, the app reads back exactly: *"Playing [favorite name] on [speaker name]"*
- User must confirm (*"Yes"*) or cancel (*"No"* / *"Cancel"*) before playback starts
- If the favorite name is not recognized, the app responds: *"[Favorite name] was not found on [speaker name]. Available favorites are: [list]"*
- Playback begins within 3 seconds of the user confirming

---

**US-02 — Play the most recent or default favorite**
> As a user, I want to say a simple play command after the speaker name so that the last-played favorite starts without me having to name it.

**Acceptance criteria:**
- Command format: *"[Speaker name], play music"* or *"[Speaker name], start playing"*
- Triggers the last-played favorite on that speaker, or the first in the favorites list if no history exists
- Before executing, the app reads back: *"Playing [resolved favorite name] on [speaker name]"*
- User must confirm before playback starts

---

**US-03 — Browse available favorites by voice**
> As a user, I want to ask for the favorites on a specific speaker so that I can hear the available options before choosing one.

**Acceptance criteria:**
- Command format: *"[Speaker name], what are my favorites?"*
- The app fetches the favorites list from that speaker via the Mozart API at the time of the request
- The app reads out all favorites stored on the speaker
- After listing, the app prompts: *"Say '[Speaker name], play [favorite name]' to start playing"*

---

### 2. Stop Playback

**US-04 — Stop the current session**
> As a user, I want to say the speaker name followed by a stop command so that playback ends on that specific speaker.

**Acceptance criteria:**
- Command format: *"[Speaker name], stop"*
- Before executing, the app reads back: *"Stopping playback on [speaker name]"*
- User must confirm before the stop is sent
- If nothing is playing, the app responds: *"[Speaker name] is not currently playing anything"*

---

**US-05 — Pause and resume playback**
> As a user, I want to say the speaker name followed by pause or resume so that I can temporarily halt and restart playback without losing my place.

**Acceptance criteria:**
- Command formats: *"[Speaker name], pause"* and *"[Speaker name], resume"*
- Before executing pause: *"Pausing [speaker name]"*; before executing resume: *"Resuming [speaker name]"*
- User must confirm before the action is sent
- Pause halts playback and preserves the current position; resume restarts from the paused position
- If the source does not support pause (e.g. live radio), the app responds: *"[Speaker name] does not support pause for this source. Say '[Speaker name], stop' to stop instead"*

---

### 3. Volume Control

**US-06 — Set volume to a specific level**
> As a user, I want to say the speaker name and a target volume so that the speaker plays at exactly the level I want.

**Acceptance criteria:**
- Command format: *"[Speaker name], set volume to [0–100]"*
- The app accepts integer values from 0 to 100 (each unit = 1%)
- Before executing, the app reads back: *"Setting [speaker name] volume to [value]"*
- User must confirm before the change is applied
- The app confirms completion: *"[Speaker name] volume is now [value]"*

---

**US-07 — Increase or decrease volume by a relative amount**
> As a user, I want to say the speaker name and a relative volume direction so that I can adjust volume without knowing the current level.

**Acceptance criteria:**
- Command formats: *"[Speaker name], volume up [amount]"*, *"[Speaker name], volume down [amount]"*, *"[Speaker name], louder"*, *"[Speaker name], quieter"*
- Relative commands without a number adjust by a default step of 10%
- Named increments adjust by the specified number of percentage points (1–100)
- Before executing, the app reads back: *"Changing [speaker name] volume from [current] to [new value]"*
- User must confirm before the change is applied
- Volume is clamped at 0 and 100; if a limit is reached the app responds: *"[Speaker name] is already at [maximum/minimum] volume"*

---

**US-08 — Mute and unmute**
> As a user, I want to say the speaker name followed by mute or unmute so that I can quickly silence and restore the speaker without changing the set volume.

**Acceptance criteria:**
- Command formats: *"[Speaker name], mute"* and *"[Speaker name], unmute"*
- Before executing mute: *"Muting [speaker name] (currently at volume [value])"*; before executing unmute: *"Unmuting [speaker name], restoring volume to [value]"*
- User must confirm before the action is applied
- Mute silences audio while retaining the previous volume level; unmute restores audio to the pre-mute volume
- Saying *"[Speaker name], mute"* when already muted has no effect and the app responds: *"[Speaker name] is already muted"*

---

## Voice Command Reference (v1)

All commands follow the pattern: **[Speaker name], [command]**

| Intent | Example Commands |
|---|---|
| Address speaker + play favorite | "Beosound, play Jazz Radio" |
| Address speaker + play default | "Beosound, play music", "Beosound, start playing" |
| Address speaker + list favorites | "Beosound, what are my favorites?" |
| Address speaker + stop | "Beosound, stop", "Beosound, stop music" |
| Address speaker + pause | "Beosound, pause" |
| Address speaker + resume | "Beosound, resume", "Beosound, continue playing" |
| Address speaker + set volume | "Beosound, set volume to 50", "Beosound, volume 70" |
| Address speaker + volume up | "Beosound, volume up", "Beosound, louder", "Beosound, volume up 20" |
| Address speaker + volume down | "Beosound, volume down", "Beosound, quieter", "Beosound, volume down 10" |
| Address speaker + mute | "Beosound, mute" |
| Address speaker + unmute | "Beosound, unmute" |
| Confirm action | "Yes" |
| Cancel action | "No", "Cancel" |

---

## Error States

| Scenario | Expected Behavior |
|---|---|
| No speaker name spoken | *"Please start your command with a speaker name"* + list of available speakers |
| Speaker name not recognized | *"[spoken name] was not found. Available speakers are: [list]"* |
| Favorite name not recognized | *"[favorite name] was not found on [speaker name]. Available favorites are: [list]"* |
| Speaker offline or unreachable | *"[Speaker name] could not be reached. Please check the speaker is powered on and connected to the network"* |
| Nothing playing on Stop/Pause | *"[Speaker name] is not currently playing anything"* |
| Volume limit reached | *"[Speaker name] is already at [maximum/minimum] volume"* |
| Source does not support pause | *"[Speaker name] does not support pause for this source. Say '[Speaker name], stop' to stop instead"* |
| Speaker already muted | *"[Speaker name] is already muted"* |
| Voice not recognized | *"Sorry, I didn't catch that. Please repeat your command"* |
| Mozart API timeout | *"Could not reach the Bang & Olufsen service. Please try again"* |

---

## Non-Functional Requirements

- **Response latency:** Voice command to speaker action in under 3 seconds on a normal home network (excluding confirmation round-trip)
- **Platform:** iOS only; targets current and one previous major iOS version
- **API:** All speaker interactions go through the Mozart API; no fallback to other B&O APIs
- **Favorites:** Fetched live from the speaker at request time — not cached locally
- **No background execution:** The app is fully inactive when not in the foreground; no persistent connections or background polling
- **Speaker addressing:** Every command must begin with a recognized speaker name; the app will not execute any action without it
- **Confirmation before execution:** The app always reads back the exact action it is about to perform and waits for the user to say *"Yes"* before sending it to the speaker
- **Language:** English only in v1; voice recognition, command parsing, and all spoken feedback are English
- **Availability:** App should degrade gracefully when the Mozart API is unreachable rather than crash
- **Privacy:** Voice input is processed locally or discarded immediately after command recognition; no audio is stored

---

## Resolved Decisions

| Question | Decision |
|---|---|
| Which B&O API? | Mozart API |
| Where do favorites come from? | Read live from the individual speaker via Mozart API |
| Target platform? | iOS only |
| Background execution? | No |
| Volume step size? | 0–100 scale, 1% steps; default relative step is 10% |
| How are speakers addressed? | Speaker name must be spoken at the start of every command |
| Confirmation before execution? | Yes — app reads back the exact action and waits for user to say *"Yes"* |
| Language? | English only in v1 |
