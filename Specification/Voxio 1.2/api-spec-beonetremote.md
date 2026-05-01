# API Specification: BeoNetRemote (BNR) — ASE Platform
**Version:** 1.0  
**Status:** Reference  
**Date:** 2026-05-01  
**Source:** Reverse-engineered from community implementations; cross-referenced against official B&O BeoNetRemote Client API (Postman: `documenter.getpostman.com/view/1053298/T1LTe4Lt`) and the BeoLiving Intelligence BNR driver documentation.

---

## Overview

The BeoNetRemote (BNR) API is Bang & Olufsen's local REST API for **ASE-platform products** (Audio Streaming Engine, 2014–2020). It is distinct from the Mozart Open API used by post-2020 products. There is no official public OpenAPI document; this spec is reconstructed from the official Postman collection and verified community implementations.

### Transport

| Property | Value |
|---|---|
| Protocol | HTTP/1.1 |
| Port | **8080** |
| Base URL | `http://{device-ip}:8080` |
| Authentication | None — local network only |
| Content-Type | `application/json` |
| Discovery | Bonjour/mDNS — service type `_beoremote._tcp` |

### Notification Channel

State changes are delivered via **long-poll** (not WebSocket). The client opens a persistent GET to `/BeoNotify/Notifications` and receives newline-delimited JSON event objects as they occur. The connection must be re-established immediately after each received event or on timeout.

```
GET http://{device-ip}:8080/BeoNotify/Notifications
```

Notification events have the shape:

```json
{
  "notification": {
    "type": "VOLUME",
    "timestamp": { "year": 2024, "month": 4, "mday": 28, "hour": 14, "minute": 5, "second": 30, "utc": 1714309530 },
    "data": { ... }
  }
}
```

---

## Supported Devices

### Audio Systems (ASE)

Beosound Stage · Beosound 35 · Beosound Essence 2nd Gen · Beosound Core · Beosound Shape · Beosound Edge · Beosound 1 (1st / 2nd Gen) · Beosound 2 (1st / 2nd Gen) · Beoplay A9 (2nd / 3rd / 4th Gen) · Beoplay A6 · Beoplay M5 · Beoplay M3 · Beolink Converter NL/ML

### Active Loudspeakers (ASE)

BeoLab 90 · BeoLab 50

### TVs (ASE)

Beovision Harmony · Beovision Eclipse · Beovision Contour · Beovision 14 / 11 · Beovision Avant · Beoplay V1 · Beosystem 4

> **Note:** This spec focuses on audio speaker functionality. TV-specific endpoints (picture mode, cinema mode, stand position) are listed but not detailed.

---

## Endpoint Reference

### Device Information

---

#### `GET /BeoDevice`

Returns device identity and product metadata.

**Response `200 OK`:**
```json
{
  "beoDevice": {
    "productFriendlyName": {
      "productFriendlyName": "Beoplay M5 in kitchen"
    },
    "productId": {
      "serialNumber": "12345678",
      "typeNumber": "1200304",
      "itemNumber": "28096178"
    }
  }
}
```

**Fields:**

| Field | Type | Description |
|---|---|---|
| `productFriendlyName` | string | Human-readable device name as set in the B&O app |
| `serialNumber` | string | Device serial number |
| `typeNumber` | string | Product type identifier |
| `itemNumber` | string | Product item number |

The Beolink JID of the device is composed as: `{typeNumber}.{serialNumber}.{itemNumber}@products.bang-olufsen.com`

---

### Power Management

---

#### `GET /BeoDevice/powerManagement/standby`

Returns current power state.

**Response `200 OK`:**
```json
{
  "standby": {
    "powerState": "on"
  }
}
```

`powerState` values: `"on"` | `"standby"`

---

#### `PUT /BeoDevice/powerManagement/standby`

Sets device power state.

**Request body — power on:**
```json
{
  "standby": { "powerState": "on" }
}
```

**Request body — standby:**
```json
{
  "standby": { "powerState": "standby" }
}
```

**Request body — all standby (all NetworkLink devices):**
```json
{
  "standby": { "powerState": "allStandby" }
}
```

**Response:** `200 OK` (empty body on success)

---

### Volume

---

#### `GET /BeoZone/Zone/Sound/Volume/Speaker`

Returns current volume state including level, mute, and range.

**Response `200 OK`:**
```json
{
  "speaker": {
    "level": 3500,
    "muted": false,
    "range": {
      "minimum": 0,
      "maximum": 9000
    }
  }
}
```

> **Important:** Volume is expressed as an integer on a **0–9000 scale** (not 0–100). Divide by 100 to get a percentage. The `maximum` field reflects the device's configured maximum volume, which may be less than 9000.

---

#### `PUT /BeoZone/Zone/Sound/Volume/Speaker/Level`

Sets absolute volume level.

**Request body:**
```json
{
  "level": 3500
}
```

The `level` value must be an integer in the range `0`–`9000` (0–90 in user-facing percentage terms, since each unit = 0.01%). To convert from a 0–100 user percentage: multiply by 100.

**Response:** `200 OK`

---

#### `PUT /BeoZone/Zone/Sound/Volume/Speaker/Muted`

Sets mute state.

**Request body — mute:**
```json
{
  "muted": true
}
```

**Request body — unmute:**
```json
{
  "muted": false
}
```

**Response:** `200 OK`

---

### Playback Control

All playback commands use a **press + release** pattern. Both the press and the release POST must be sent for the command to register correctly.

---

#### `POST /BeoZone/Zone/Stream/Play` + `POST /BeoZone/Zone/Stream/Play/Release`

Resumes playback.

**Request body:** empty  
**Response:** `200 OK`

---

#### `POST /BeoZone/Zone/Stream/Pause` + `POST /BeoZone/Zone/Stream/Pause/Release`

Pauses playback.

**Request body:** empty  
**Response:** `200 OK`

---

#### `POST /BeoZone/Zone/Stream/Stop` + `POST /BeoZone/Zone/Stream/Stop/Release`

Stops playback.

**Request body:** empty  
**Response:** `200 OK`

---

#### `POST /BeoZone/Zone/Stream/Forward` + `POST /BeoZone/Zone/Stream/Forward/Release`

Skips to next track.

**Request body:** empty  
**Response:** `200 OK`

---

#### `POST /BeoZone/Zone/Stream/Backward` + `POST /BeoZone/Zone/Stream/Backward/Release`

Returns to previous track.

**Request body:** empty  
**Response:** `200 OK`

---

### Sources

---

#### `GET /BeoZone/Zone/Sources`

Returns all sources available on the device, including borrowed (multiroom) sources.

**Response `200 OK`:**
```json
{
  "sources": [
    [
      "radio:2714.1200304.28096178@products.bang-olufsen.com",
      {
        "id": "radio:2714.1200304.28096178@products.bang-olufsen.com",
        "sourceType": { "type": "RADIO" },
        "category": "RADIO",
        "friendlyName": "B&O Radio",
        "inUse": true,
        "borrowed": false,
        "multiroom": "listener",
        "product": {
          "friendlyName": "Beoplay M5 in kitchen",
          "jid": "2714.1200304.28096178@products.bang-olufsen.com"
        }
      }
    ],
    [
      "bluetooth:2714.1200304.28096178@products.bang-olufsen.com",
      {
        "id": "bluetooth:2714.1200304.28096178@products.bang-olufsen.com",
        "sourceType": { "type": "BLUETOOTH" },
        "category": "BLUETOOTH",
        "friendlyName": "Bluetooth",
        "inUse": true,
        "borrowed": false
      }
    ]
  ]
}
```

Each source entry is a two-element array: `[sourceId, sourceObject]`.

**Source object fields:**

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique source identifier; used in `ActiveSources` POST |
| `sourceType.type` | string | `RADIO`, `BLUETOOTH`, `TUNEIN`, `DEEZER`, `DLNA`, `USB_PLAYBACK`, etc. |
| `category` | string | Grouping category |
| `friendlyName` | string | Human-readable name shown in apps |
| `inUse` | boolean | Whether the source is currently enabled on this device |
| `borrowed` | boolean | `true` if the source originates on another device (multiroom) |

---

#### `GET /BeoZone/Zone/ActiveSources`

Returns the currently active (playing or selected) source.

**Response `200 OK`:**
```json
{
  "activeSources": {
    "primaryExperience": {
      "source": {
        "id": "radio:2714.1200304.28096178@products.bang-olufsen.com",
        "friendlyName": "B&O Radio",
        "category": "RADIO",
        "sourceType": { "type": "RADIO" }
      },
      "state": "play"
    }
  }
}
```

`state` values: `"play"` | `"pause"` | `"stop"` | `"buffering"`

---

#### `POST /BeoZone/Zone/ActiveSources`

Activates a source by ID (switches to that source, powering on if needed).

**Request body:**
```json
{
  "primaryExperience": {
    "source": {
      "id": "radio:2714.1200304.28096178@products.bang-olufsen.com"
    }
  }
}
```

**Response:** `200 OK`

---

#### `DELETE /BeoZone/Zone/ActiveSources/primaryExperience`

Deactivates the current source (leaves the Beolink experience / stops multiroom participation).

**Request body:** empty  
**Response:** `200 OK`

---

### Favorites

The BNR API does not expose a dedicated favorites endpoint. Favorites are accessed via the **sources list** — source IDs that correspond to preset/favorite entries are identified by their `sourceType.type` value (e.g. `"TUNEIN"`, `"RADIO"`) and the content set via the Play Queue API. Preset-style favorites configured in the B&O app are stored on the device and activated by selecting their source ID.

> **Practical approach for favorites:** Fetch `/BeoZone/Zone/Sources`, filter by `inUse == true` and `borrowed == false`, present the `friendlyName` list to the user, and activate via `POST /BeoZone/Zone/ActiveSources` with the chosen `id`.

---

### Play Queue (Content Injection)

---

#### `POST /BeoZone/Zone/PlayQueue`

Adds content to the play queue. Supports TuneIn, Deezer, DLNA, and B&O Radio.

**Request body — TuneIn station:**
```json
{
  "playQueueItem": {
    "behaviour": "planned",
    "station": {
      "tuneIn": {
        "stationId": "s37309"
      }
    }
  }
}
```

**Request body — DLNA/URL:**
```json
{
  "playQueueItem": {
    "behaviour": "planned",
    "track": {
      "dlna": {
        "url": "http://192.168.1.10/music/track.mp3"
      }
    }
  }
}
```

---

#### `DELETE /BeoZone/Zone/PlayQueue`

Clears the play queue.

**Request body:** empty  
**Response:** `200 OK`

---

### Multiroom (Beolink)

---

#### `POST /BeoZone/Zone/Device/OneWayJoin`

Joins the device to the current active Beolink experience on the network (equivalent to pressing the Join button on a remote).

**Request body:** empty  
**Response:** `200 OK`

---

## Notification Events

The long-poll endpoint `/BeoNotify/Notifications` delivers these event types:

### `VOLUME`

Fires when volume or mute state changes.

```json
{
  "notification": {
    "type": "VOLUME",
    "data": {
      "speaker": {
        "level": 3500,
        "muted": false,
        "range": {
          "minimum": 0,
          "maximum": 9000
        }
      }
    }
  }
}
```

---

### `SOURCE`

Fires when the active source changes.

```json
{
  "notification": {
    "type": "SOURCE",
    "data": {
      "primaryExperience": {
        "source": {
          "id": "radio:2714.1200304.28096178@products.bang-olufsen.com",
          "friendlyName": "B&O Radio",
          "category": "RADIO"
        },
        "state": "play"
      }
    }
  }
}
```

---

### `PROGRESS_INFORMATION`

Fires when playback state changes.

```json
{
  "notification": {
    "type": "PROGRESS_INFORMATION",
    "data": {
      "state": "play",
      "position": 45,
      "totalDuration": 240
    }
  }
}
```

`state` values: `"play"` | `"pause"` | `"stop"` | `"buffering"` | `"completed"`

---

### `NOW_PLAYING_NET_RADIO`

Fires when radio metadata updates.

```json
{
  "notification": {
    "type": "NOW_PLAYING_NET_RADIO",
    "data": {
      "name": "DR P8 JAZZ",
      "liveDescription": "Melissa Aldana - No pidas imposibles",
      "image": [
        { "url": "http://...", "size": "medium" }
      ]
    }
  }
}
```

---

### `NOW_PLAYING_STORED_MUSIC`

Fires when a local/DLNA track's metadata is available.

```json
{
  "notification": {
    "type": "NOW_PLAYING_STORED_MUSIC",
    "data": {
      "name": "Blue in Green",
      "artist": "Miles Davis",
      "album": "Kind of Blue",
      "trackImage": [
        { "url": "http://...", "size": "medium" }
      ]
    }
  }
}
```

---

## Key Differences vs. Mozart API

| Concern | BeoNetRemote (ASE) | Mozart Open API |
|---|---|---|
| **Port** | 8080 | 443 (HTTPS) or 8443 |
| **Discovery** | mDNS `_beoremote._tcp` | mDNS `_bangolufsen._tcp` |
| **Volume scale** | 0–9000 (divide by 100 for %) | 0–100 (direct %) |
| **Notification channel** | Long-poll HTTP GET | WebSocket |
| **Playback commands** | Press + Release pair | Single POST |
| **Favorites** | Via sources list, no dedicated endpoint | Dedicated `/presets` endpoint |
| **Auth** | None | None (local network) |
| **OpenAPI spec** | No official spec | Yes — `bang-olufsen/mozart-open-api` |

---

## Error Handling

The BNR API does not return structured error bodies. Failure is indicated by HTTP status code only.

| Status | Meaning |
|---|---|
| `200 OK` | Success |
| `404 Not Found` | Endpoint not supported on this device/firmware |
| `501 Not Implemented` | Feature not available; some devices return 501 but still execute the command |
| No response / timeout | Device is in deep standby, offline, or unreachable |

> **Note on 501:** Several community implementations report that certain `PUT` endpoints (e.g. sound adjustment) return `501 Not Implemented` but execute the command successfully. Treat `501` as a soft warning rather than a hard failure for write operations.

---

## Device Discovery

BNR devices announce themselves on the local network via Bonjour/mDNS.

```
Service type: _beoremote._tcp
Port: 8080
```

On iOS, use `NWBrowser` or `NetServiceBrowser` to discover devices with service type `_beoremote._tcp.local.`. The resolved hostname and port 8080 form the base URL.

---

## Reference Sources

| Source | URL | Notes |
|---|---|---|
| Official Postman collection | `documenter.getpostman.com/view/1053298/T1LTe4Lt` | Render-blocked; listed for reference |
| B&O official product list | `support.bang-olufsen.com/hc/en-us/articles/360049859212` | Authoritative device-to-API mapping |
| BeoLiving Intelligence BNR driver | `khimo.github.io/help_drivers/BeoLink/` | Command reference |
| `martonborzak/ha-beoplay` | `github.com/martonborzak/ha-beoplay` | Python implementation; endpoint source |
| `connectjunkie/homebridge-beoplay` | `github.com/connectjunkie/homebridge-beoplay` | Node.js implementation |
| `tlk/beoplay-macos-remote-cli` | `github.com/tlk/beoplay-macos-remote-cli` | Swift CLI; notification model source |
| `giachello/beoplay` | `github.com/giachello/beoplay` | HA integration; multiroom commands |
