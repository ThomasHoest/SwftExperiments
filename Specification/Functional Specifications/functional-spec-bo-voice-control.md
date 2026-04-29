# Functional Specification: Bang & Olufsen Voice Controller
**Version:** 1.3  
**Status:** Draft  
**Date:** 2026-04-28

---

## Overview

A voice-controlled interface for Bang & Olufsen speakers that allows users to start playback from favorites, stop the current session, and adjust volume — all through natural spoken commands. Every command must be prefixed with the speaker's name, and the app always reads back exactly what it is about to do before executing. The app supports both English (`en-US`) and Danish (`da-DK`); all voice commands, spoken feedback, error messages, and UI labels are available in both languages.

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
| Languages | English (`en-US`) and Danish (`da-DK`) — auto-detected from device; user-overridable |

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
- Every voice command must begin with the speaker's name as registered in the Mozart API (e.g. *"Beosound, play Jazz Radio"* / *"Beosound, afspil Jazz Radio"*)
- The app retrieves the list of available speaker names from the Mozart API on launch
- If a command is spoken without a recognized speaker name, the app responds in the active language: *"Please start your command with a speaker name"* / *"Start din kommando med et højttalernavn"* and lists available speakers
- Speaker name matching is case-insensitive and tolerates minor mispronunciation through fuzzy matching; speaker names are matched regardless of the active language
- If only one speaker is available, that speaker is still addressed by name; there is no implicit default

---

### 1. Start Playback from Favorites

**US-01 — Play a specific favorite**
> As a user, I want to say the speaker name followed by a favorite name so that the correct speaker starts playing it immediately.

**Acceptance criteria:**
- Command format: *"[Speaker name], play [favorite name]"* / *"[Højttalernavn], afspil [favorit]"*
- The app fetches the current favorites list from the named speaker via the Mozart API, then maps the spoken name to a match
- Before executing, the app reads back in the active language: *"Playing [favorite name] on [speaker name]"* / *"Afspiller [favorit] på [højttaler]"*
- User must confirm (*"Yes"* / *"Ja"*) or cancel (*"No"* / *"Cancel"* / *"Nej"* / *"Annuller"*) before playback starts
- If the favorite name is not recognized, the app responds in the active language: *"[Favorite name] was not found on [speaker name]. Available favorites are: [list]"* / *"[Favorit] blev ikke fundet på [højttaler]. Tilgængelige favoritter er: [liste]"*
- Playback begins within 3 seconds of the user confirming

---

**US-01b — Play a favorite by number**
> As a user, I want to say the speaker name followed by "play favorite [number]" so that the speaker plays whatever is stored on that numbered favorite button.

**Acceptance criteria:**
- Command format: *"[Speaker name], play favorite [one|two|three|four]"* / *"[Højttalernavn], afspil favorit [en|to|tre|fire]"*
- Spoken number words (one–four) map to favorite positions 1–4; spoken digits are not supported
- The app fetches the current favorites list from the named speaker via the Mozart API and selects the favorite at the given position
- Before executing, the app reads back in the active language: *"Playing [favorite name] on [speaker name]"* / *"Afspiller [favorit] på [højttaler]"*
- User must confirm (*"Yes"* / *"Ja"*) or cancel (*"No"* / *"Cancel"* / *"Nej"* / *"Annuller"*) before playback starts
- If the requested position exceeds the number of favorites on the speaker, the app responds: *"[Speaker name] does not have a favorite [number]. Available favorites are: [list]"* / *"[Højttaler] har ikke favorit [nummer]. Tilgængelige favoritter er: [liste]"*
- Playback begins within 3 seconds of the user confirming

---

**US-02 — Play the most recent or default favorite**
> As a user, I want to say a simple play command after the speaker name so that the last-played favorite starts without me having to name it.

**Acceptance criteria:**
- Command format: *"[Speaker name], play music"* / *"[Højttalernavn], afspil musik"* or *"[Speaker name], start playing"* / *"[Højttalernavn], spil"*
- Triggers the last-played favorite on that speaker, or the first in the favorites list if no history exists
- Before executing, the app reads back in the active language: *"Playing [resolved favorite name] on [speaker name]"* / *"Afspiller [favorit] på [højttaler]"*
- User must confirm before playback starts

---

**US-03 — Browse available favorites by voice**
> As a user, I want to ask for the favorites on a specific speaker so that I can hear the available options before choosing one.

**Acceptance criteria:**
- Command format: *"[Speaker name], what are my favorites?"* / *"[Højttalernavn], list favoritter"*
- The app fetches the favorites list from that speaker via the Mozart API at the time of the request
- The app reads out all favorites stored on the speaker in the active language
- After listing, the app prompts in the active language: *"Say '[Speaker name], play [favorite name]' to start playing"* / *"Sig '[Højttalernavn], afspil [favorit]' for at starte afspilning"*

---

### 2. Stop Playback

**US-04 — Stop the current session**
> As a user, I want to say the speaker name followed by a stop command so that playback ends on that specific speaker.

**Acceptance criteria:**
- Command format: *"[Speaker name], stop"* (same in Danish)
- Before executing, the app reads back in the active language: *"Stopping playback on [speaker name]"* / *"Stopper afspilning på [højttaler]"*
- User must confirm before the stop is sent
- If nothing is playing, the app responds in the active language: *"[Speaker name] is not currently playing anything"* / *"[Højttaler] afspiller ikke noget i øjeblikket"*

---

**US-05 — Pause and resume playback**
> As a user, I want to say the speaker name followed by pause or resume so that I can temporarily halt and restart playback without losing my place.

**Acceptance criteria:**
- Command formats: *"[Speaker name], pause"* / *"[Højttalernavn], pause"* and *"[Speaker name], resume"* / *"[Højttalernavn], fortsæt"*
- Before executing pause in the active language: *"Pausing [speaker name]"* / *"Pauser [højttaler]"*; before executing resume: *"Resuming [speaker name]"* / *"Genoptager [højttaler]"*
- User must confirm before the action is sent
- Pause halts playback and preserves the current position; resume restarts from the paused position
- If the source does not support pause (e.g. live radio), the app responds in the active language: *"[Speaker name] does not support pause for this source. Say '[Speaker name], stop' to stop instead"* / *"[Højttaler] understøtter ikke pause for denne kilde. Sig [højttaler], stop for at stoppe i stedet"*

---

### 3. Volume Control

**US-06 — Set volume to a specific level**
> As a user, I want to say the speaker name and a target volume so that the speaker plays at exactly the level I want.

**Acceptance criteria:**
- Command format: *"[Speaker name], set volume to [0–100]"* / *"[Højttalernavn], sæt lydstyrke til [0–100]"*
- The app accepts integer values from 0 to 100 (each unit = 1%)
- Before executing in the active language: *"Setting [speaker name] volume to [value]"* / *"Sætter [højttaler] lydstyrke til [værdi]"*
- User must confirm before the change is applied
- The app confirms completion in the active language: *"[Speaker name] volume is now [value]"* / *"[Højttaler] lydstyrke er nu [værdi]"*

---

**US-07 — Increase or decrease volume by a relative amount**
> As a user, I want to say the speaker name and a relative volume direction so that I can adjust volume without knowing the current level.

**Acceptance criteria:**
- Command formats: *"[Speaker name], volume up [amount]"* / *"[Højttalernavn], skru op [beløb]"*, *"[Speaker name], louder"* / *"[Højttalernavn], højere"*, *"[Speaker name], volume down [amount]"* / *"[Højttalernavn], skru ned [beløb]"*, *"[Speaker name], quieter"* / *"[Højttalernavn], lavere"*
- Relative commands without a number adjust by a default step of 10%
- Named increments adjust by the specified number of percentage points (1–100)
- Before executing in the active language: *"Turning [speaker name] volume up/down by [amount]"* / *"Skruer [højttaler] lydstyrke op/ned med [beløb]"*
- User must confirm before the change is applied
- Volume is clamped at 0 and 100; if a limit is reached the app responds in the active language: *"[Speaker name] is already at [maximum/minimum] volume"* / *"[Højttaler] er allerede ved [maksimal|minimal] lydstyrke"*

---

**US-08 — Mute and unmute**
> As a user, I want to say the speaker name followed by mute or unmute so that I can quickly silence and restore the speaker without changing the set volume.

**Acceptance criteria:**
- Command formats: *"[Speaker name], mute"* / *"[Højttalernavn], slå lyden fra"* and *"[Speaker name], unmute"* / *"[Højttalernavn], slå lyden til"*
- Before executing mute in the active language: *"Muting [speaker name] (currently at volume [value])"* / *"Slår [højttaler] fra (lydstyrke [værdi])"*; before executing unmute: *"Unmuting [speaker name]"* / *"Slår [højttaler] til"*
- User must confirm before the action is applied
- Mute silences audio while retaining the previous volume level; unmute restores audio to the pre-mute volume
- Saying mute when already muted has no effect; the app responds in the active language: *"[Speaker name] is already muted"* / *"[Højttaler] er allerede slået fra"*

---

## Voice Command Reference

All commands follow the pattern: **[Speaker name], [command]**

| Intent | English | Danish |
|---|---|---|
| Play specific favorite | "Beosound, play Jazz Radio" | "Beosound, afspil Jazz Radio" |
| Play favorite by number | "Beosound, play favorite one" | "Beosound, afspil favorit en" |
| Play default | "Beosound, play music", "Beosound, start playing" | "Beosound, afspil musik", "Beosound, spil" |
| List favorites | "Beosound, what are my favorites?" | "Beosound, list favoritter" |
| Stop | "Beosound, stop" | "Beosound, stop" |
| Pause | "Beosound, pause" | "Beosound, pause" |
| Resume | "Beosound, resume", "Beosound, continue playing" | "Beosound, fortsæt", "Beosound, genoptag" |
| Set volume | "Beosound, set volume to 50" | "Beosound, sæt lydstyrke til 50" |
| Volume up | "Beosound, volume up", "Beosound, louder", "Beosound, volume up 20" | "Beosound, skru op", "Beosound, højere", "Beosound, skru op 20" |
| Volume down | "Beosound, volume down", "Beosound, quieter", "Beosound, volume down 10" | "Beosound, skru ned", "Beosound, lavere", "Beosound, skru ned 10" |
| Mute | "Beosound, mute" | "Beosound, slå lyden fra" |
| Unmute | "Beosound, unmute" | "Beosound, slå lyden til" |
| Confirm | "Yes", "Yeah", "Sure", "Okay" | "Ja", "Jo" |
| Cancel | "No", "Cancel", "Never mind" | "Nej", "Annuller" |

---

## Language Support

The app supports English (`en-US`) and Danish (`da-DK`). Language behaviour:

- **Auto-detection:** The active language is set to the device's primary language on first launch. If the device is set to Danish or a Danish regional variant, Danish is activated; all other locales default to English.
- **User override:** The user can switch language in app settings at any time. The change takes effect immediately — the speech recogniser restarts and all spoken feedback switches to the new language without requiring an app restart.
- **Coverage:** Every spoken command, TTS read-back, error string, and UI label is available in both languages. There are no English-only or Danish-only features.
- **Speaker names:** Speaker names from the Mozart API are matched regardless of the active language — the same fuzzy matching applies to both.
- **Favorites:** Favorite names on the speaker are as stored in the Mozart API; they are not translated.

---

## Error States

All error responses are spoken and displayed in the active language.

| Scenario | English | Danish |
|---|---|---|
| No speaker name spoken | *"Please start your command with a speaker name. Available speakers are: [list]"* | *"Start din kommando med et højttalernavn. Tilgængelige højttalere er: [liste]"* |
| Speaker name not recognized | *"[spoken name] was not found. Available speakers are: [list]"* | *"[navn] blev ikke fundet. Tilgængelige højttalere er: [liste]"* |
| Favorite name not recognized | *"[favorite name] was not found on [speaker name]. Available favorites are: [list]"* | *"[favorit] blev ikke fundet på [højttaler]. Tilgængelige favoritter er: [liste]"* |
| Speaker offline or unreachable | *"[Speaker name] could not be reached. Please check the speaker is powered on and connected to the network"* | *"[Højttaler] kunne ikke nås. Kontroller at højttaleren er tændt og forbundet til netværket"* |
| Nothing playing on Stop/Pause | *"[Speaker name] is not currently playing anything"* | *"[Højttaler] afspiller ikke noget i øjeblikket"* |
| Volume limit reached | *"[Speaker name] is already at [maximum/minimum] volume"* | *"[Højttaler] er allerede ved [maksimal/minimal] lydstyrke"* |
| Source does not support pause | *"[Speaker name] does not support pause for this source. Say '[Speaker name], stop' to stop instead"* | *"[Højttaler] understøtter ikke pause for denne kilde. Sig [højttaler], stop for at stoppe i stedet"* |
| Speaker already muted | *"[Speaker name] is already muted"* | *"[Højttaler] er allerede slået fra"* |
| Voice not recognized | *"Sorry, I didn't catch that. Please repeat your command"* | *"Undskyld, jeg forstod ikke det. Gentag venligst din kommando"* |
| Mozart API timeout | *"Could not reach the Bang & Olufsen service. Please try again"* | *"Kunne ikke nå Bang & Olufsen servicen. Prøv venligst igen"* |

---

## Non-Functional Requirements

- **Response latency:** Voice command to speaker action in under 3 seconds on a normal home network (excluding confirmation round-trip)
- **Platform:** iOS only; targets current and one previous major iOS version
- **API:** All speaker interactions go through the Mozart API; no fallback to other B&O APIs
- **Favorites:** Fetched live from the speaker at request time — not cached locally
- **No background execution:** The app is fully inactive when not in the foreground; no persistent connections or background polling
- **Speaker addressing:** Every command must begin with a recognized speaker name; the app will not execute any action without it
- **Confirmation before execution:** The app always reads back the exact action it is about to perform and waits for the user to say *"Yes"* before sending it to the speaker
- **Languages:** English (`en-US`) and Danish (`da-DK`) are both fully supported; voice recognition, command parsing, TTS feedback, error strings, and UI labels are available in both. Active language defaults to device primary language; user may override in settings
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
| Confirmation before execution? | Yes — app reads back the exact action and waits for user to say *"Yes"* / *"Ja"* |
| Languages? | English (`en-US`) and Danish (`da-DK`); auto-detected from device, user-overridable |
