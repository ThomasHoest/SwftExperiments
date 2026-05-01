# BeoNetRemote API — Community Reference Material
**Compiled:** 2026-05-01  
**Purpose:** Raw reference material gathered from community implementations and official B&O support pages. Preserved here for offline access and to document the sources behind `api-spec-beonetremote.md`.

---

## Source 1: Official B&O — Drivers for 3rd Party Integration

**URL:** `https://support.bang-olufsen.com/hc/en-us/articles/360049859212-Drivers-for-3rd-Party-integration`

### Products Using BeoNetRemote Client API

**Bang & Olufsen Audio Systems:**
Beosound Stage · Beosound 35 · Beosound Essence 2nd Gen · Beosound Core · Beosound Shape · Beosound Edge · Beosound 1 (1st / 2nd Gen) · Beosound 2 (1st / 2nd Gen) · Beolink Converter NL/ML · Beoplay A9 (2nd / 3rd / 4th Gen) · Beoplay A6 · Beoplay M5 · Beoplay M3

**Bang & Olufsen Active Loudspeakers:**
BeoLab 90 · BeoLab 50

**Bang & Olufsen TVs:**
Beovision Harmony 65/77/83/88/97 · Beovision Eclipse 55/65 (All versions) · Beovision Contour 48/55 · Beovision 14-40/55 · Beovision 11-40/46/55 · Beovision Avant-55/75/85 · Beovision Avant NG-55/75/85 · Beoplay V1-32/40 · Beosystem 4

### Products Using Mozart Platform Open API (NOT BNR):
Beoconnect Core · Beolab 8 · Beolab 28 · Beosound/Beovision Theatre · Beosound Balance · Beosound Emerge · Beosound Level · Beosound Premiere · Beosound 2 3rd Gen · Beosound A9 5th Gen · Beosound A5

**Note from B&O:** "These drivers are for Bang & Olufsen AV product control only. They cannot be used to integrate with lighting control systems such as Lutron, KNX, Dynalite, Philips Hue etc."

---

## Source 2: Official Postman Collection

**URL:** `https://documenter.getpostman.com/view/1053298/T1LTe4Lt`  
**Status:** Page renders via JavaScript — content not machine-fetchable. Must be viewed in browser directly.  
**Description:** "Commands related to using BNR on B&O products"

This is the official B&O-published API reference. The Postman collection covers the full BNR endpoint surface. It is linked from the B&O support page above.

---

## Source 3: BeoLiving Intelligence BNR Driver Reference

**URL:** `https://khimo.github.io/help_drivers/BeoLink/`

### BNR Commands (from BeoLiving Intelligence integration)

The following commands are available via the BNR protocol:

- **All standby** — Sets all NetworkLink products into standby mode
- **Cinema mode** — Sets Cinema mode on product (options are product-dependent)
- **Legacy home control** — Sends legacy home control command
- **Link to source by id** — Links product to a specific source from another product
- **Master volume adjust** — Relative volume control across all multiroom products; command sent to master product
- **Master volume level** — Absolute volume control across all multiroom products; `Volume` parameter is integer 0–90
- **Motorized speaker preset** — Sets motorized speaker to a given preset
- **Picture format** — Sets picture format (TV only)
- **Picture mute** — Freezes video picture (TV only)
- **Picture mode** — Sets Picture mode (product-dependent options)
- **Playqueue add Deezer playlist** — Adds Deezer playlist by Playlist Id
- **Playqueue add TuneIn station** — Adds TuneIn station by Station name or Station Id
- **Playqueue add URL** — Adds audio file by URL
- **Playqueue clean** — Clears the play queue
- **Reboot** — Reboots the product
- **Recall profile** — Activates an existing profile on product
- **Save profile** — Saves profile on product
- **Select channel** — Selects channel in source; uses favourite list delay if configured (default 300ms between digits)
- **Select channel on source by id** — Selects channel in a specific source given its ID
- **Select source** — Plays source; can originate from another product
- **Select source by id** — Plays source by ID; can originate from another product
- **Send command** — Sends miscellaneous commands (cursor control, menu access, flow control)
- **Send digit** — Sends individual digit to the product
- **Set content id** — Sets content identifier directly. Origins:
  - `beoCloud:netRadio` — B&O Radio content (requires B&O Cloud login)
  - `deezer` — Deezer content (playlist or track ID)
  - `dlna` — DLNA/UPnP content (track URL)
  - `tuneId` — TuneIn content (TuneIn radio ID)
- **Set repeat** — Sets playqueue repeat: `All`, `Current`, or `None`
- **Set shuffle** — Sets playqueue shuffle on/off
- **Sound mode** — Sets Sound mode (product-dependent)
- **Speaker group** — Sets Speaker group (product-dependent)
- **Stand position** — Sets stand position; only for products with a motorized stand
- **Standby** — Sets product to standby
- **Volume adjust** — Relative volume control on single product
- **Volume level** — Absolute volume control; `Volume` is integer 0–90

### Notes from BeoLiving Intelligence

- Some products may fail to power up and immediately accept further commands; add small delays between commands if needed
- Products supporting Beo4 navigation can be configured for new commands (`UP`, `DOWN`, `LEFT`, `RIGHT`, `SELECT`, `BACK`) or legacy alternatives (`STEP_UP`, `STEP_DOWN`, `WIND`, `REWIND`, `PLAY`, `EXIT`)
- Speaker groups: one Main product + one or more Followers; a product can only belong to one group

---

## Source 4: martonborzak/ha-beoplay — Python Implementation

**URL:** `https://github.com/martonborzak/ha-beoplay/blob/master/beoplay/__init__.py`  
**Language:** Python  
**Status:** Active

This is the most complete verified endpoint listing available. All endpoints below were confirmed working in this implementation.

### Transport

```
BASE_URL = 'http://{host}:8080/{path}'
TIMEOUT = 5.0 seconds
```

### Notification endpoint

```
GET http://{host}:8080/BeoNotify/Notifications
```
Long-poll; connection is held open; JSON objects delivered as state changes occur.

### Endpoints (verified working)

#### GET — Read state

| Path | Description |
|---|---|
| `BeoDevice` | Device identity: name, serial, type number, item number |
| `BeoDevice/powerManagement/standby` | Power state: `"on"` or `"standby"` |
| `BeoZone/Zone/Sources` | All sources with IDs, names, inUse flag, borrowed flag |

#### PUT — Write state

| Path | Body | Description |
|---|---|---|
| `BeoZone/Zone/Sound/Volume/Speaker/Level` | `{"level": <int>}` | Set volume (0–9000 scale) |
| `BeoZone/Zone/Sound/Volume/Speaker/Muted` | `{"muted": <bool>}` | Mute/unmute |
| `BeoDevice/powerManagement/standby` | `{"standby": {"powerState": "on"\|"standby"\|"allStandby"}}` | Power control |

#### POST — Commands (press + release pattern required)

| Press path | Release path | Description |
|---|---|---|
| `BeoZone/Zone/Stream/Play` | `BeoZone/Zone/Stream/Play/Release` | Resume playback |
| `BeoZone/Zone/Stream/Pause` | `BeoZone/Zone/Stream/Pause/Release` | Pause |
| `BeoZone/Zone/Stream/Stop` | `BeoZone/Zone/Stream/Stop/Release` | Stop |
| `BeoZone/Zone/Stream/Forward` | `BeoZone/Zone/Stream/Forward/Release` | Next track |
| `BeoZone/Zone/Stream/Backward` | `BeoZone/Zone/Stream/Backward/Release` | Previous track |

#### POST — Source selection

| Path | Body | Description |
|---|---|---|
| `BeoZone/Zone/ActiveSources` | `{"primaryExperience": {"source": {"id": "<sourceId>"}}}` | Activate source |
| `BeoZone/Zone/Device/OneWayJoin` | (empty) | Join current Beolink experience |

#### DELETE

| Path | Description |
|---|---|
| `BeoZone/Zone/ActiveSources/primaryExperience` | Leave current experience / deactivate source |

### Notification event types (parsed in implementation)

| Type | Data fields |
|---|---|
| `VOLUME` | `speaker.level` (0–9000), `speaker.muted` (bool), `speaker.range.minimum`, `speaker.range.maximum` |
| `SOURCE` | `primaryExperience.source.friendlyName`, `primaryExperience.source.id` |
| `PROGRESS_INFORMATION` | `state` (play/pause/stop/buffering) |
| `NOW_PLAYING_STORED_MUSIC` | `name`, `artist`, `album`, `trackImage[].url` |
| `NOW_PLAYING_NET_RADIO` | `name`, `liveDescription`, `image[].url` |

### Volume scale note

Volume is stored and transmitted as **0–9000**. The implementation divides by 100 when exposing to Home Assistant (giving 0.0–90.0 as a float). The physical maximum is typically 90 (= 9000 raw), but the device's configured `range.maximum` may be lower.

---

## Source 5: connectjunkie/homebridge-beoplay

**URL:** `https://github.com/connectjunkie/homebridge-beoplay`  
**Language:** JavaScript/Node.js

### Additional confirmed endpoints

```
GET  http://{host}:8080/BeoZone/Zone/ActiveSources
```

Returns current source info including source ID and state. Used to determine what is currently playing and to discover source IDs for configuration.

### Plugin note (critical for scope)

> "This plugin does **NOT** work with B&O devices that use the new Mozart platform such as the Beolab 28, Beosound Balance, Beosound Emerge, Beosound Level or Beosound Theatre."

This confirms the hard split: BNR works only on ASE-platform devices; Mozart API works only on Mozart-platform devices.

### Volume maximum behaviour

The plugin honours the B&O device's configured maximum volume setting. Attempting to set volume higher than the device maximum will be clamped to the configured maximum.

---

## Source 6: tlk/beoplay-macos-remote-cli

**URL:** `https://github.com/tlk/beoplay-macos-remote-cli`  
**Language:** Swift

### Discovery

```
DNS-SD service type: _beoremote._tcp
Default port: 8080
```

Example discovery output:
```
$ beoplay-cli discover
+ "My Beoplay Device"    http://BeoplayDevice.local.:8080
```

### Notification stream sample output

```
RemoteCore.NotificationBridge.DataConnectionNotification(state: connecting)
RemoteCore.NotificationBridge.DataConnectionNotification(state: online)
RemoteCore.Source(
  id: "radio:2714.1200304.28096178@products.bang-olufsen.com",
  type: "BEO RADIO",
  category: "RADIO",
  friendlyName: "B&O Radio",
  productJid: "2714.1200304.28096178@products.bang-olufsen.com",
  productFriendlyName: "My Beoplay Device",
  state: play
)
RemoteCore.NowPlayingRadio(
  stationId: "4338732615578920",
  liveDescription: "Melissa Aldana - No pidas imposibles",
  name: "DR P8 JAZZ"
)
RemoteCore.Progress(playQueueItemId: "beoradio", state: play)
RemoteCore.Volume(volume: 15, muted: false, minimum: 0, maximum: 90)
```

### Volume observation

This Swift implementation exposes volume as 0–90 (integer), which is the raw BNR value divided by 100. This confirms the 0–9000 raw scale in the API, with the physical/UI-facing scale being 0–90.

---

## Source 7: giachello/beoplay (Home Assistant)

**URL:** `https://github.com/giachello/beoplay`

### Additional context

- BeoPlay API described as "the 2nd generation B&O API, after Masterlink Gateway and before Mozart. Supported by devices built from 2015 onwards."
- Supports: TVs, Speakers, BeoLink Converter ML/NL
- Beolink join works across B&O plugins (Mozart, Beoplay, MLGW) via the `OneWayJoin` endpoint
- Generates `beoplay_notification` events for HA automations on state changes

---

## Source 8: beo-beoapi (msinn/beo-beoapi)

**URL:** `https://github.com/msinn/beo-beoapi`  
**Forked from:** `elch2912/beoapi`

### Additional endpoints observed in samples.txt

```
POST  http://{host}:8080/BeoZone/Zone/Stream/Play
PUT   http://{host}:8080/BeoZone/Zone/Sound/Adjustment/  (some devices return 501 but execute)
PUT   http://{host}:8080/BeoDevice/powerManagement/standby
  body: {"standby": {"powerState": "allStandby"}}
```

**Note on 501:** The samples.txt explicitly notes that sound adjustment endpoints may return `501 Not Implemented` but "works fine" on tested hardware. This is a known quirk of the BNR API on some devices/firmware versions.

---

## Beolink JID Format

The Beolink JID (Jabber ID) uniquely identifies a device on the network and is used for multiroom targeting:

```
{typeNumber}.{serialNumber}.{itemNumber}@products.bang-olufsen.com
```

Example from observed data:
```
2714.1200304.28096178@products.bang-olufsen.com
```

Source IDs include the device JID as a suffix:
```
radio:2714.1200304.28096178@products.bang-olufsen.com
bluetooth:2714.1200304.28096178@products.bang-olufsen.com
tunein:2714.1200304.28096178@products.bang-olufsen.com
```

---

## Known Limitations and Quirks

1. **No dedicated favorites endpoint.** Favorites must be managed via the sources list. The B&O app stores preset/favorite configurations on the device; these surface as sources with specific IDs.

2. **Volume scale is 0–9000, not 0–100.** Every community implementation divides by 100 or multiplies by 100 for user-facing display. The device's configured maximum (set in the B&O app) may cap the usable range below 9000.

3. **Press + Release pattern required for playback.** Single POST is not sufficient; both the command and its `/Release` counterpart must be sent. Implementations send them back-to-back with no delay.

4. **Long-poll notification channel, not WebSocket.** The connection to `/BeoNotify/Notifications` blocks until an event arrives, then must be re-opened. This is fundamentally different from Mozart's WebSocket channel.

5. **No authentication.** The API is entirely open on the local network. No API keys, tokens, or pairing required.

6. **Deep standby breaks connectivity.** If Wake-on-LAN and Quickstart are both disabled in device settings, the device cannot be reached from standby. The device must be manually powered on for the first connection.

7. **Some endpoints return 501 but execute.** Treat 501 as a warning on write operations, not a hard failure.

8. **Source IDs are device-scoped.** The source ID includes the device JID, so the same logical source (e.g. TuneIn) has a different ID on each device.
