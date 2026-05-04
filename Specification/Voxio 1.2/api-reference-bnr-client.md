# API Reference: BeoNetRemote (BNR) Client
**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-02
**Source:** `BC.Mobile.BeoNetRemote.BnrClient` namespace

---

## Overview

The BeoNetRemote (BNR) client is a typed, link-driven HTTP client for legacy Bang & Olufsen products — TVs (BeoVision Harmony, Eclipse, Contour, Avant, Avant NG, BeoPlay V1, BeoSystem 4) and pre-Mozart audio systems (BeoSound Stage, 35, Essence 2nd Gen, Core, Shape, Edge, 1, 2, BeoLink Converter NL/ML, BeoPlay A9 / A6 / M5 / M3). It speaks the BNR HTTP protocol against a per-product base URL and consumes a long-lived TCP notification stream for push events.

The client is structured as a tree of services rooted at `BnrProtocolApi`, each service owning a set of resources. Every operation produces a typed `BnrRequest<T>` that the caller executes asynchronously. Responses are typed `BnrResponse<T>` instances that carry either a deserialised model body or a structured `BnrResponseError`.

This document describes the surface of the client as it is implemented today. It does not attempt to document the full BNR HTTP wire protocol — only what this client exposes.

---

## Technical Context

| Aspect | Choice |
|---|---|
| Transport | HTTP/1.1 over the product's local IP address (`ProductInfo.HttpDeviceUrl`) |
| Content type | `application/json`; UTF-8; charset suppressed for products that require it (`BnrCapabilities.RemoveCharSetFromContentTypeInBnr`) |
| Default request timeout | 11 seconds (`BnrProtocolApi` constructor) |
| Connection header | `Connection: close` on every request |
| Notification channel | Persistent TCP stream issuing `GET /BeoNotify/Notifications?timeout=86400` |
| Network preference | Wi-Fi preferred (`PrefersWifi = true`) |
| Authentication | None for most calls; `BeoSecurity` session (RSA + AES) for credential-bearing endpoints |
| JSON library | Newtonsoft.Json with `BnrJsonParser` and per-type converters |

---

## Architectural Model

A BNR-capable product exposes a discoverable tree of services under its HTTP root. The client mirrors that tree in three layers:

**Service layer.** `BnrProtocolApi` is the per-product entry point. It owns a single `IHttpRequestExecutor`, the `ProductInfo` describing the target device, and a composed `Root` containing every named service exposed by BNR: `BeoDevice`, `BeoHome`, `BeoContent`, `BeoZone`, `BeoSecurity`, `BeoOneWay`, `BeoInput`, plus a `Ping` endpoint. Each service is exposed as a property: `DeviceApi`, `HomeApi`, `ContentApi`, `ZoneApi`, `SecurityApi`, `OneWayApi`, `InputApi`. `CommandsApi` is a convenience accessor that forwards to `ZoneApi.CommandsApi`.

**Resource and Group layer.** Inside `ZoneApi`, functionality is grouped into `Group` instances (`SoundGroup`, `PlayQueueGroup`) and `Resource` instances (`SourcesResource`, `ActiveSourcesResource`, `SystemProductsResource`, etc.). Each `Resource` declares the BNR `Feature` it depends on through `GetRequiredFeature()`; callers can check availability against the live feature set returned by `BuildGetAvailableFeaturesRequest()` before invoking. Groups and Resources never make HTTP calls themselves — they build typed request objects.

**Link and Request layer.** Every leaf operation is constructed from a `BnrLink<T>` (a path bound to a typed response) or a `BnrTemplatedLink<T>` (a path with `{placeholder}` segments resolved at call time via `PathBinder`). A link's `GetRequestBuilder()` returns a fluent `Builder<T>` that produces a `BnrRequest<T>`. The request is executed with `request.ExecuteAsync(retries, retryStepbackMs, retryOnBnrResponseError)` and yields a `BnrResponse<T>`.

**Response unwrapping.** BNR consistently wraps response bodies under a single property name (e.g. `{ "volume": { ... } }`). The builder exposes `UnwrapResponse(true, unwrapCount)` to advance the JSON reader past those wrapper layers before deserialising the actual model. Most resources call `UnwrapResponse(true)`; some (notably `ActiveSourcesResource.BuildGetRequest`) opt out with `UnwrapResponse(false)`.

---

## Identity and Routing

Every product is identified by its **JID** (Jabber ID) returned in the `Device-Jid` HTTP header. After every successful response, `DeviceJidEvaluator.ValidateResponse` compares the header to the expected `ProductInfo` and throws `BnrException(BnrErrorCode.IncorrectProductReached)` if they disagree. This is the client's defence against IP-address reuse on a local network — calls must both reach a product and reach the *intended* product.

The `BnrException.IncorrectProductReached` flag is what the retry policy checks before retrying a failed call. A request that landed on the wrong product is never retried.

---

## Top-Level Service Catalogue

The next sections describe each top-level service. Within each, operations are listed by their builder method on the service or resource class. Path values are HTTP paths relative to the product's base URI; templated paths use `{name}` placeholders.

---

### `BeoDevice` — `DeviceApi`

Device identity, peripherals, profiles, and per-platform credentials. Service path: `/BeoDevice/`.

| Operation | Method | Path | Returns |
|---|---|---|---|
| `BuildDeviceRequest` | GET | `/BeoDevice/` | `Device` |
| `BuildModifyFriendlyNameRequest(string)` | PUT | `/BeoDevice/productFriendlyName/...` | `Device` |
| `BuildDevicePeripheralsRequest` | GET | `/BeoDevice/Peripherals` | `DevicePeripherals` |
| `GetCredentialsProfile` | GET | `/BeoDevice/credentials/...` | `CredentialProfile` |
| `GetBeoCloudCredentials` | GET | `/BeoDevice/credentials/.../beoCloud` | `BeoCloud` |
| `GetDeezerCredentials` | GET | `/BeoDevice/credentials/.../deezer` | `Deezer` |
| `GetTuneInCredentials` | GET | `/BeoDevice/credentials/.../tuneIn` | `TuneIn` |
| `GetPowerManagementProfile` | GET | `/BeoDevice/powerManagement/` | `PowerManagementProfile` |
| `GetFactoryResetProfile` | GET | `/BeoDevice/factoryReset/...` | `FactoryResetProfile` |
| `GetSoftwareUpdateProfile` | GET | `BeoDevice/softwareUpdate/` | `SoftwareUpdateProfile` |
| `GetLogReportingProfile` | GET | `/BeoDevice/logReporting/...` | `LogReportingProfile` |
| `GetNetworkSettingsProfile` | GET | `/BeoDevice/networkSettings/...` | `NetworkSettingsProfile` |
| `GetModulesInformationProfile` | GET | `/BeoDevice/modules/...` | `ModulesInformationProfile` |
| `GetRegionalSettingsProfile` | GET | `/BeoDevice/regionalSettings/...` | `RegionalSettingsProfile` |
| `GetTermsAndConditionsProfile` | GET | `/BeoDevice/termsAndConditions/...` | `TermsAndConditionsProfile` |
| `GetRemoteControlPairingProfile` | GET | `/BeoDevice/remoteControlPairing/...` | `RemoteControlPairingProfile` |

Profiles are HAL-style documents: each has a `_links.self` that the client uses to resolve the full URI when binding context. The exact subpaths beyond `/BeoDevice/` are determined by each profile's static `Path` constant — listed in the Profile reference at the end of this document.

#### `Device` model

| Field | Type | Description |
|---|---|---|
| `ProductId` | `ProductId` | Stable identifier (model + serial) |
| `ProductFamily` | `string` | Family name (e.g. `BeoVision`, `BeoPlay`) |
| `ProductFriendlyName` | `FriendlyName` | User-modifiable display name |
| `ProductImage` | `Image` | Product image reference |
| `Software` | `Software` | Current SW version, build, image type |
| `Hardware` | `Hardware` | HW revision and bootloader info |
| `Peripherals` | `Peripherals` | Connected accessories (subset of `DevicePeripherals`) |
| `Profiles` | `List<ProfileRef<BaseProfile>>` | Discoverable profile references |
| `AnonymousProductId` | `string` | Anonymised ID for telemetry use |

---

### `BeoHome` — `HomeApi`

Home automation profiles. Service path: `/BeoHome/`.

| Operation | Method | Path | Returns |
|---|---|---|---|
| `BuildHomeRequest` | GET | `/BeoHome/` | `Home` |
| `GetTriggerProfile` | GET | `/BeoHome/trigger/` | `TriggerProfile` |

The `TriggerProfile` exposes timed and conditional automation: timers, trigger sequences, and `TriggerAction` definitions covering the home actions enumerated in `Home/Trigger/ActionType.cs` — `ActivateSnapshotActionValue`, `AddToPlayQueueActionValue`, `JoinActionValue`, `PausePlayingActionValue`, `SetActiveSourceActionValue`, `SetPowerStateActionValue`, and an `UnknownActionValue` fallback.

---

### `BeoContent` — `ContentApi`

Source content profiles (Deezer, DLNA, DVB, MoodWheel, NetRadio, STB). Service path: `/BeoContent/`.

| Operation | Method | Path | Returns |
|---|---|---|---|
| `BuildContentRequest` | GET | `/BeoContent/` | `Content` |
| `GetNetRadioProfile` | GET | `/BeoContent/netradio/netRadioProfile/` | `ContentFavoriteList` |
| `GetMk1ContentFavoriteList` | GET | `/BeoContent/netradio/netRadioProfile/favoriteList` | `ContentFavoriteList` |

The `Content` body is `{ "sources": [...] }` and contains a `BnrSource` per available content source. Per-provider profiles (`DeezerProfile`, `DlnaProfile`, `DvbProfile`, `MoodWheelProfile`, `NetRadioProfile`, `StbProfile`) are reachable through the source's links once the content document has been fetched. The provider profiles expose paginated lists of albums, artists, genres, playlists, stations, and tracks via the `Content/Pagination/*` types.

The two NetRadio operations exist to handle a generation difference: Mk1 products keep favorites at the legacy path; later products expose them through the profile's discovered self-link. The client picks the correct one at the call site based on `ProductType`.

---

### `BeoZone` — `ZoneApi`

The largest service. Covers every "live" interaction with the product: sources, active sources, playback commands, sound, play queue, system topology. Service path: `/BeoZone/`. Most resource paths are relative to `/BeoZone/Zone/`; system topology lives under `/BeoZone/System`.

#### Discovery

Two requests describe what a given product can do at runtime. The result of these calls determines which `Resource` and `Group` types are usable.

| Operation | Method | Path | Returns |
|---|---|---|---|
| `BuildGetAvailableGroupsRequest` | GET | `/BeoZone/Zone/?list=recursive+groups` | `GroupTypeSet` |
| `BuildGetAvailableFeaturesRequest` | GET | `/BeoZone/Zone/?list=recursive+features` | `FeatureSet` |

`GroupType` enumerates `Sound`, `Device`, `PlayQueue`, `Stream`, and `Unknown`. `Feature` is a much larger enum (around 60 members) covering everything from `Volume` and `Pause` through `RoomCompensation` and `HbbTv`. Each `Resource.GetRequiredFeature()` returns the single feature that gates it.

#### Lazy groups

`SoundGroup` and `PlayQueueGroup` are lazily constructed under a lock the first time they are accessed. Instantiating them eagerly would prematurely build a long list of resources for products that don't support them.

#### Top-level resources (always constructed)

| Property | Type | Required `Feature` |
|---|---|---|
| `SystemProductsResource` | `SystemProductsResource` | `Products` |
| `SystemSettingsResource` | `SystemSettingsResource` | `Products` |
| `SourcesResource` | `SourcesResource` | (none) |
| `ListeningPresetResource` | `ListeningPresetResource` | (none) |
| `ActiveSourcesResource` | `ActiveSourcesResource` | (none) |
| `CommandsApi` | `CommandsApi` | (per-command) |
| `SnapshotResource` | `SnapshotResource` | `Snapshot` |
| `RoomCompensationResource` | `RoomCompensationResource` | `RoomCompensation` |
| `StandResource` | `StandResource` | `Stand` |
| `InputSignalResource` | `InputSignalResource` | (none) |
| `SourceActivationResource` | `SourceActivationResource` | (none) |

##### `SourcesResource` — `/BeoZone/Zone/Sources/`

Manages the catalogue of sources known to the product.

| Operation | Method | Notes |
|---|---|---|
| `BuildGetRequest` | GET | Returns `SourcesList<BnrSource>` |
| `BuildMk1GetRequest` | GET | Returns `SourcesList<LegacySource>` for Mk1 hardware |
| `BuildModifyRequest(string id)` | POST | Activates a source by id |
| `BuildShareUsageDataModifyRequest(id, share)` | PUT | Toggles per-source usage data sharing |
| `BuildTermsAndConditionsModifyRequest(id, terms)` | PUT | Records T&C state for a source |
| `BuildSourceSoundModeModifyRequest(id, soundModeId)` | PUT | Changes the sound mode for a specific source |
| `BuildSourceSoundDelayModifyRequest(id, delay)` | PUT | Adjusts the audio output delay for a source |
| `BuildSourceRemoteListModifyRequest(id, items)` | PUT | Modifies which remote control lists a source belongs to |
| `BuildSourcePositionModifyRequest(id, index)` | POST | Re-orders a source via `move?id={id}&moveto={index}` |
| `BuildSourceNameModifyRequest(id, friendlyName)` | PUT | Renames a source |
| `BuildSourceInUseModifyRequest(id, inUse)` | PUT | Toggles a source's `inUse` flag |

Source ids are URL-encoded with `HttpUtility.UrlEncode` because they may contain colons and other reserved characters (e.g. `radio:1234.tuneIn:411717`).

###### `BnrSource` — the core source model

| Field | Type | Description |
|---|---|---|
| `Id` | `string` | Unique source id |
| `FriendlyName` | `string` | Display name |
| `SourceType` | `SourceTypeInfo` | Type metadata (e.g. `tuneIn`, `lineIn`, `dvb`) |
| `Category` | `SourceCategory?` | Audio / Video / Radio / etc. |
| `InUse` | `bool?` | True if currently active |
| `SignalSensed` | `bool?` | Line-in / HDMI signal detection |
| `Linkable` | `bool?` | Whether the source can be joined / expanded |
| `Product` | `ProductInfo` | Product where this source originates (for linked sources) |
| `Capabilities` | `BnrCapabilities` | Allowed values and ranges |
| `TermsAndConditions` | `SourceTerms?` | T&C state |
| `ShareUsageData` | `bool?` | Telemetry consent |
| `SoundMode` | `int?` | Currently selected sound mode id |
| `SoundDelay` | `int?` | Audio output delay in ms |
| `RemoteList` | `List<RemoteLists>` | Associated remote lists |

`BnrSource.GetLinkableSourceIds()` returns the subset of sources this source can be linked to, sourced from its capabilities.

##### `ActiveSourcesResource` — `/BeoZone/Zone/ActiveSources/`

Controls what the product is currently playing and which other products are listening to it (the multi-room "experience" model).

| Operation | Method | Path | Notes |
|---|---|---|---|
| `BuildGetRequest` | GET | `./ActiveSources/` | Returns `ActiveSources` (no unwrap) |
| `BuildModifyPrimaryExperience(BnrSource)` | POST | `./ActiveSources/` | Set the primary listening experience |
| `BuildModifySecondaryExperience(BnrSource)` | POST | `./ActiveSources/` | Set the secondary experience |
| `BuildModifyExperieces(primary, secondary)` | POST | `./ActiveSources/` | Set both at once |
| `BuildExpandExperienceRequest(string listenerJid)` | POST | `./ActiveSources/primaryExperience/` | **Add a listener** — this is how a Beolink "join" is implemented from the master side |
| `BuildDeleteListenerRequest(string listenerJid)` | DELETE | `./ActiveSources/primaryExperience/?jid={listenerJid}` | Remove a listener |
| `BuildDeletePrimaryExperience` | DELETE | `./ActiveSources/primaryExperience/` | End the primary experience entirely |
| `BuildModifyPrimaryMk1Request(string source)` | POST | `./ActiveSources/` | Mk1-style activation by raw source id |
| `BuildStartRadioExperienceRequest(BnrSource, string radioId)` | POST | `./ActiveSources/` | Start a radio experience with a specific channel id |

The `ActiveSources` body has three top-level shapes depending on protocol version: `primaryExperience` + optional `secondaryExperience` for current products, an `activeSources` legacy block for Mk1, and a `contentId` for radio. The resource builds each shape correctly so callers don't have to.

The expand/delete-listener pair is the BNR-side primitive for multi-room "join". A listener is identified by its JID, the same identifier used in the `Device-Jid` header and elsewhere in the client.

##### `ListeningPresetResource` — `/BeoZone/Zone/Sound/ListeningPreset/`

| Operation | Method | Path | Returns |
|---|---|---|---|
| `BuildGetRequest` | GET | `./Sound/ListeningPreset/` | `ListeningPresetList` |
| `BuildGetActiveRequest` | GET | `./Sound/ListeningPreset/Active/` | `ListeningPresetActive` |

`ListeningPresetActive` reports the active preset's id; the list response carries the catalogue of available presets and their metadata.

##### `SystemProductsResource` — `/BeoZone/System/Products/`

| Operation | Method | Path | Notes |
|---|---|---|---|
| `BuildGetRequest` | GET | `/BeoZone/System/Products/` | Returns `SystemProductList` |
| `BuildDeleteSystemProductRequest(string jid)` | DELETE | `/BeoZone/System/Products/{jid}` | JID is URL-encoded |

##### `SystemSettingsResource` — `/BeoZone/System/Settings/`

| Operation | Method | Returns |
|---|---|---|
| `BuildGetRequest` | GET | `SystemSettings` |

##### Remaining zone resources

Brief overview; each follows the same Builder pattern as those above.

| Resource | Path root | What it controls |
|---|---|---|
| `SnapshotResource` | `./Snapshot/` | "My Buttons" snapshot lists for TV remotes |
| `RoomCompensationResource` | `./Sound/RoomCompensation/` | Room calibration measurements and active profile |
| `StandResource` | `./Stand/` | Motorised TV stand position (for products that have one) |
| `InputSignalResource` | (per source) | Current input signal characteristics (codec, container, channels, Dolby flags) |
| `SourceActivationResource` | (per source) | Strategy and behaviour applied when a source becomes primary |

#### `CommandsApi` — fire-and-forget remote commands

Templated link: `/BeoZone/Zone/{command}` and `/BeoZone/Zone/{command}/Release`.

| Operation | Method | Body | Notes |
|---|---|---|---|
| `BuildRunCommandRequest(Command)` | POST | `{}` | Single-shot command |
| `BuildRunCommandContinuousRequest(Command)` | POST | `{ "toBeReleased": true }` | Press-and-hold; must be released |
| `BuildReleaseCommandRequest(Command)` | POST | `{}` to `.../Release` | Releases a continuous command |
| `BuildDigitCommandRequest(int)` | POST | `{ "digits": <int> }` | Numeric input on `/BeoZone/Zone/Digits/` |

The full `Command` catalogue covers playback (`Play`, `Pause`, `Stop`, `Wind`, `Rewind`, `Forward`, `Backward`), cursor navigation (`CursorUp/Down/Left/Right/Select/Exit/Back/Clear/PageUp/PageDown`), list movement (`ListStepUp/Down/PreviousElement/Shuffle/Repeat`), menu entry (`MenuRoot/Option/Setup/Contents/Favorites/ElectronicProgramGuide/VideoOnDemand/Text/HbbTv`), device controls (`DeviceInformation/Eject/TogglePower/Languages/Subtitles/OneWayJoin/Mots`), record (`Record`), generic colour buttons (`GenericRed/Green/Yellow/Blue`), and the four My Buttons. Each `Command` carries the `Feature` it requires; check it against the available feature set before issuing.

##### `SoundGroup` — under `ZoneApi.SoundGroup`

The sound group is lazily built and exposes one resource per concern. The most operationally important are listed; less-used ones (DSP filters, sound wall setup, speaker enable/disable, tone touch) follow the same pattern.

| Resource | Path | Required `Feature` | Operations |
|---|---|---|---|
| `VolumeResource` | `./Sound/Volume` | `Volume` | `BuildGetRequest` → `Volume`; `BuildModifyVolumeMutedRequest(bool)` PUT to `./Sound/Volume/Speaker/Muted`; `BuildGetSpeakerSensitivityRequest` |
| `VolumeLevelSpeakerResource` | `./Sound/Volume/Speaker/Level` | `VolumeLevel` | `BuildGetRequest` → `VolumeLevel`; `BuildModifyRequest(int)` PUT |
| `VolumeLevelHeadphoneResource` | `./Sound/Volume/Headphone/Level` | `VolumeLevelHeadphone` | Same shape as speaker |
| `VolumeContinuousSpeakerResource` | `./Sound/Volume/Speaker/ContinuousLevelAction` | `VolumeContinuous` | `BuildModifyRequest(Action)` POST with `continuousUp`/`continuousDown`/`none`; `BuildModifyWithTimeoutRequest(Action, int ms)` for explicit timeout (requires `VolumeContinuousTimeout`) |
| `VolumeContinuousHeadphoneResource` | `./Sound/Volume/Headphone/ContinuousLevelAction` | `VolumeContinuousHeadphone` | Same shape |
| `VolumeDefaultLevelResource` | `./Sound/Volume/Speaker/DefaultLevel` | `VolumeDefaultLevel` | Default startup volume |
| `AdjustmentResource` | `./Sound/Adjustment/` | `SoundAdjustment` | `BuildModifyRequest(bass, treble, ecoMode, loudness)` PUT and `BuildResetRequest` POST; both operate on `_links` discovered in the response |
| `SoundModeResource` | `./Sound/Mode/` | `SoundMode` | List, get active, change active mode |
| `SpeakerWirelessSetupResource` / `SpeakerWiredSetupResource` | `./Sound/SpeakerWirelessSetup/` / `./Sound/SpeakerWiredSetup/` | `SpeakerWirelessSetup` / `SpeakerWiredSetup` | Speaker pairing and assignment |
| `SpeakerGroupResource` | `./Sound/SpeakerGroup/` | `SpeakerGroup` | Speaker group definitions and active selection |
| `SoundExploreResource` | `./Sound/Explore/` | (none) | Sound explore presets |
| `BufferSetupResource` | `./Sound/BufferSetup/` | `BufferSetupNetradio` | NetRadio buffer tuning |
| `SoundWallSetupApi` | varies | (none) | Sound Wall configuration and test tones |

###### `Volume` model

| Field | Type | Description |
|---|---|---|
| `Speaker` | `SpeakerInfo` | Range, current level, muted flag, default level, continuous action state |
| `Headphone` | `HeadphoneInfo` | Same shape, headphone-specific |

`SpeakerInfo` exposes `Range`, `Level`, `Muted`, `DefaultLevel`, and `ContinuousLevelAction`, and carries discovered links for `BuildGetVolumeMutedRequest`, `BuildModifyVolumeMutedRequest(bool)`, and `BuildModifyDefaultLevelRequest(int)`.

##### `PlayQueueGroup` — under `ZoneApi.PlayQueueGroup`

Lazily constructed. Exposes:

###### `PlayQueueResource` — `./PlayQueue/`

| Operation | Method | Notes |
|---|---|---|
| `BuildGetRequest()` | GET | Full queue |
| `BuildGetRequest(int offset, int count)` | GET | Paginated via `?offset={...}&count={...}` |
| `BuildClearPlayQueueRequest` | DELETE | Empties the queue |
| `BuildAddRequest(PlayableContent, [behaviour], [playNowOffset])` | POST | Adds one item; multiple overloads cover behaviour and offset combinations |
| `BuildAddAllRequest<T>(List<T>, ContainerMetadata, [behaviour])` | POST | Adds a container of items |
| `BuildAddWithInstantPlayRequest(...)` | POST | Adds *and* starts playback (path: `?instantplay`) |
| `BuildAddAllWithInstantPlayRequest(...)` | POST | Same for collections |
| `BuildAddAllAsPlayNextRequest(..., string insertAfterId)` | POST | Adds with `?id={insertAfterId}&insert=after` |
| `BuildAddWithSeedRequest(MoodWheelItem, behaviour, playNowOffset, playInstant, seedTracks)` | POST | MoodWheel-specific; carries seed tracks |

Items are wrapped in `Wrapper<PlayQueueItem>` under the JSON key `playQueueItem` (see `PlayQueueItem.WrapName`). Concrete content types include `PlayQueueItemTrack`, `PlayQueueItemAlbum`, `PlayQueueItemArtist`, `PlayQueueItemPlayList`, `PlayQueueItemStation`, `PlayQueueItemFavoriteList(Channel|Station)`, and `PlayQueueMoodWheelItem`.

###### `PlayPointerResource` — `./PlayQueue/PlayPointer/`

Controls the queue cursor: which item is the current playback position. Operations follow the same Builder pattern.

---

### `BeoSecurity` — `SecurityApi`

Establishes a per-session encrypted channel for endpoints that handle credentials. Service path: `/BeoSecurity/`.

| Operation | Method | Path | Notes |
|---|---|---|---|
| `CreateSecuritySessionAsync` | POST | `/BeoSecurity/Sessions` | Returns `IBeoSecuritySession` |

The handshake uses RSA-1024:

1. Client generates an `RsaKey(1024)` and exports the public key as PEM.
2. Client posts `{ "publicKey": "<pem>" }` to `/BeoSecurity/Sessions`.
3. Server returns `{ "sessionId": "...", "sessionKeyAndIv": "<base64>" }` where `sessionKeyAndIv` is the AES-128 key + IV (32 bytes total) encrypted with the client's public key.
4. Client RSA-decrypts and constructs a `BeoSecuritySession(sessionId, keyAndIv)` for symmetric encryption of subsequent credential payloads.

`SetSecuritySessionFuncForTesting` is provided for tests to short-circuit the handshake.

---

### `BeoOneWay` — `OneWayApi`

Sends "legacy" remote control commands directly to the product. Service path: `/BeoOneWay/Input/`.

| Operation | Method | Path | Body |
|---|---|---|---|
| `BuildLegacyCommandRequest(LegacyCommand)` | POST | `/BeoOneWay/Input/` | `LegacyCommand` |

`LegacyCommand` is a static catalogue of about 50 named commands. Selected entries:

| Command | Wire value |
|---|---|
| `Play` / `Stop` / `Continue` / `Rewind` / `Wind` | `PLAY` / `STOP` / `CONTINUE` / `REWIND` / `WIND` |
| `VolumeUp` / `VolumeDown` / `Mute` | `VOLUME_UP` / `VOLUME_DOWN` / `MUTE` |
| `CursorUp/Down/Left/Right` / `Select` | `CURSOR_*` / `SELECT` |
| `Digit0` … `Digit9` | `DIGIT_0` … `DIGIT_9` |
| `Red` / `Green` / `Yellow` / `Blue` | `RED` / `GREEN` / `YELLOW` / `BLUE` |
| `Menu` / `Back` / `Edit` / `Text` | `MENU` / `BACK` / `EXIT` / `TEXT` |
| `Stand` / `Speaker` / `SoundMode` | `STAND` / `SPEAKER` / `SOUND_MODE` |
| `Record` / `Track` / `Random` / `Repeat` | `RECORD` / `TRACK` / `RANDOM` / `REPEAT` |
| `PictureFormat` / `PictureMode` / `PictureSize` | `PICTURE_FORMAT` / `PICTURE_MODE` / `PICTURE_SIZE` |
| `PMute` / `PanelOff` | `PMUTE` / `PANEL_OFF` |
| `Format3D` / `Format2D` | `FORMAT_3D` / `FORMAT_2D` |
| `Mots` / `ChannelSwap` / `Sleep` | `MOTS` / `CHANNEL_SWAP` / `SLEEP` |
| **`Join`** | `JOIN` |
| **`AllStandby`** | `ALL_STANDBY` |
| `Release` | `RELEASE` |

`Edit` maps to the wire value `EXIT` (intentional aliasing in the source). `Join` and `AllStandby` are the BNR primitives that map to the legacy "join an experience" and "all-standby" buttons on Bang & Olufsen remotes.

---

### `BeoInput` — `InputApi`

On-screen input (cursor, pointer, scroll, text). Service path: `/BeoInput/`.

| Operation | Method | Path | Body |
|---|---|---|---|
| `BuildControlCommandRequest(ControlCommand)` | POST | `/BeoInput/Control/` | `ControlCommand` |
| `BuildInputCommandRequest(string character)` | POST | `/BeoInput/Control/` | A single character (text input) |
| `BuildPointerMovedRequest(Movement)` | POST | `/BeoInput/PointerMove` | `{ "movement": { "deltaX": x, "deltaY": y } }` |
| `BuildTrackPadClickRequest` | POST | `/BeoInput/TrackpadClick` | `{}` |
| `BuildScrollRequest(Movement)` | POST | `/BeoInput/Scroll` | `{ "movement": { "deltaX": x, "deltaY": y } }` |

`ControlCommand` static instances cover navigation and editing primitives: `Done`, `Backspace`, `Clear`, `Home`, `End`, `CursorUp/Down/Left/Right`, `PreviousField`, `NextField`, `PageUp`, `PageDown`.

`Movement` carries a signed `(deltaX, deltaY)` pair.

---

### `Ping`

Plain reachability check. `BnrProtocolApi.Root.BuildPingRequest()` issues a GET to `/Ping` and resolves to an `EmptyBody` response.

---

## Notification Channel — `BeoNotifyClient`

A persistent, push-style stream of state-change events from the product. Implements `IBeoNotifyClient : IBeoNotifyEvents, IProductNotificationConnection`.

### Connection model

The client opens a raw TCP socket (`INotificationSocketFactory`) to the product and writes a hand-crafted HTTP request:

```
GET /BeoNotify/Notifications?timeout=86400 HTTP/1.1
Host: <product>
Connection: keep-alive
Cache-Control: no-cache
```

The product responds with a never-terminated HTTP body of newline-delimited JSON notification objects. The client parses each line into a `RawNotification`, then converts it to a typed `Notification` subclass via `NotificationType.ConstructFromRawNotification`.

### Lifecycle

| Method / property | Behaviour |
|---|---|
| `StartListening()` | Idempotent; aborts if the product type is not supported |
| `StopListening()` | Cancels the read loop and disposes the underlying stream |
| `IsConnected` | Reflects the current TCP state (nullable internally; `false` until first connect) |
| `IsStarted` | True between `StartListening` and `StopListening` |
| `ConnectivityChanged` | Fires on every state transition; subscribers receive the current state immediately upon subscription |

### Reconnection policy

| Setting | Default |
|---|---|
| `InitialReconnectWaitMs` | 200 ms |
| `MaxReconnectAttempts` | 3 (then enters a longer wait cycle) |
| `MaxRetryWaitMillis` | 2000 ms |
| `MaxWaitOnNoWifiMillis` | 5000 ms |
| `MaxEstablishConnectionTimeoutMillis` | 4000 ms |
| `ReadStreamTimeoutMillis` | 10000 ms |
| `WriteStreamTimeoutMillis` | 2000 ms |
| `ReconnectAttemptsBeforeSilencingLogging` | 2 |

A `_noWifiEvent` `ManualResetEvent` blocks the loop until the device reconnects to Wi-Fi (`INetworkService.OnWifi`), keeping the client from hammering an unreachable target. Wi-Fi loss raises an internal `IsWaitingForWiFi` event; restoration fires `WasPreemptedOnWifiBecomingAvailable`.

### Notification catalogue

The `IBeoNotifyEvents` interface exposes one strongly-typed event per known type, plus a catch-all `Notification` event for cross-cutting handling. The complete typed set:

| Event | Wire type | Data class |
|---|---|---|
| `VolumeNotification` | `VOLUME` | `VolumeNotificationData` (speaker + headphone) |
| `NumberAndNameNotification` | `NUMBER_AND_NAME` | `NumberAndNameNotificationData` |
| `SourceChangedNotification` | `SOURCE` | `SourceChangedNotificationData` |
| `KeyboardNotification` | `KEYBOARD` | `KeyboardNotificationData` |
| `NowPlayingStoredMusicNotification` | `NOW_PLAYING_STORED_MUSIC` | `NowPlayingStoredMusicNotificationData` |
| `NowPlayingNetRadioNotification` | `NOW_PLAYING_NET_RADIO` | `NowPlayingNetRadioNotificationData` |
| `NowPlayingEndedNotification` | `NOW_PLAYING_ENDED` | `NowPlayingEndedNotificationData` |
| `NowPlayingLegacyNotification` | `NOW_PLAYING_LEGACY` | `NowPlayingLegacyNotificationData` |
| `ProgressInformationNotification` | `PROGRESS_INFORMATION` | `ProgressInformationNotificationData` |
| `PlayQueueChangedNotification` | `PLAY_QUEUE_CHANGED` | `PlayQueueChangedNotificationData` |
| `StreamingStatusNotification` | `STREAMING_STATUS` | `StreamingStatusNotificationData` |
| `SoftwareUpdateStateNotification` | `SOFTWARE_UPDATE_STATE` | `SoftwareUpdateStateNotificationData` |
| `ShutdownNotification` | `SHUTDOWN` | `ShutdownNotificationData` |
| `ResourceChangedNotification` | `RESOURCE_CHANGED` | `ResourceChangedNotificationData` |
| `SourceListChangedNotification` | `SOURCE_LIST_CHANGED` | `SourceListChangedNotificationData` |
| `SourceExperienceChangedNotification` | `SOURCE_EXPERIENCE_CHANGED` | `SourceExperienceChangedNotificationData` |
| `SystemProductChangedNotification` | `SYSTEM_PRODUCT_CHANGED` | `SystemProductChangedNotificationData` |
| `SystemSettingsChangedNotification` | `SYSTEM_SETTINGS_CHANGED` | `SystemSettingsChangedNotificationData` |
| `SoundModeChangedNotification` | `SOUND_ACTIVE_MODE_CHANGED` | `SoundModeChangedNotificationData` |
| `ListeningPresetChangedNotification` | `LISTENING_PRESET_CHANGED` | `ListeningPresetChangedNotificationData` |
| `RoomCompensationNotification` | `SOUND_ROOM_COMPENSATION_STATE` | `RoomCompensationStateChangedData` |
| `RemoteControlNotification` | `REMOTE_CONTROL_PAIRING_CHANGED` | `RemoteControlPairingChangedData` |
| `InputSignalNotification` | `INPUT_SIGNAL_CHANGED` | `InputSignalNotificationData` |
| `UnknownNotification` | `UNKNOWN` (or any unrecognised type) | `UnknownNotificationData` |

A number of further wire types (`CONTENT_DLNA_CHANGED`, `CONTENT_DEEZER_CHANGED`, `BUTTON_PUSH`, `MANUAL_LOG_REPORTING`, etc.) are listed but commented out in `NotificationType.cs` — they will currently be delivered as `UnknownNotification`.

### Notification ordering

Each notification carries a monotonic `Id`. `BeoNotifyClient` tracks `_lastNotificationId` and uses it for de-duplication on reconnect.

---

## Request and Response Types

### `BnrRequest<T>`

Returned by every builder method. Immutable once constructed. Executed via:

```csharp
Task<BnrResponse<T>> ExecuteAsync(
    int retries = 0,
    int retryStepbackMs = 100,
    bool retryOnBnrResponseError = false);
```

Internally, requests run through a `BnrPolicyFactory` policy pipeline: a no-op default for `retries == 0`, or `BnrPolicyFactory.GetHttpRetryingPolicy` (configured with the product's `ProductInfo`, the back-off step, the retry count, and an optional flag to retry on BNR-formatted error responses) for `retries > 0`.

When the policy gives up, exceptions are converted to a `BnrResponse<T>` via `BnrResponse<T>.CreateFromException(uri, exception)`. Callers should test `response.IsSuccessful` rather than relying on exceptions.

`BnrRequest<T>` adds `Connection: close` to every outgoing message and serialises bodies through `BnrJsonParser.Instance` with the project's converters and contract resolver. For products with `RemoveCharSetFromContentTypeInBnr`, the `charset=utf-8` segment is stripped from the `Content-Type` header to satisfy stricter parsers.

### `BnrResponse<T>`

| Property / method | Description |
|---|---|
| `IsSuccessful` | True when the HTTP status was 2xx |
| `Body()` | Returns the typed model; throws if `Error` is set |
| `Error` | The structured `BnrResponseError` for failure cases (otherwise null) |

Parsing flow:

1. **Success with empty body** (HTTP 204/205, or `T == EmptyBody`): returns an `_object = default(T)` response.
2. **Success with `PlayQueue`**: dispatches to `BnrJsonParser.ParsePlayQueueResponseAsync` which performs custom logic for the queue's heterogeneous item array.
3. **Success, generic**: reads the body to a string, optionally advances the JSON reader by `unwrapCount * 2` tokens to skip wrapper layers, then deserialises into `T`. The deserialised object is then `BindBnrContext`-bound to the product and the request path so its embedded links (HAL `_links`) become callable.
4. **Failure (4xx / 5xx)**: parses the response into a `BnrResponseErrorModel` if the content type is JSON; otherwise wraps the raw body.
5. **JSON exceptions**: wrapped as `BnrException(BnrErrorCode.ContentParsing)`.
6. **Anything else**: wrapped as `BnrException(BnrErrorCode.UnknownError)`.

The response also extracts the `Device-Jid` header into a `BnrTransportResponse` for the JID validation step described above.

### `BnrResponseError`

| Field | Description |
|---|---|
| `RequestUri` | The URI that produced the error |
| `Message` | Server-supplied message, when available |
| `StatusCode` | HTTP status (0 if the product was never reached) |
| `Type` | Server-supplied error type, or the .NET exception name |
| `BnrException` | Original exception when the failure was network-level |
| `WasProductReached` | True iff `StatusCode > 0` |

`AsBnrException()` converts the error back to a `BnrException` for callers that prefer exception flow.

### `BnrException` and `BnrErrorCode`

| Code | Meaning |
|---|---|
| `UnknownError` | Unclassified failure |
| `NoNetwork` | Local network reported as unavailable |
| `ProductNotReached` | TCP / HTTP could not reach the product |
| `IncorrectProductReached` | JID validation failed — the IP responded but the device behind it is not the expected one |
| `ContentParsing` | Response was malformed JSON |
| `ProductReturnedError` | Product responded with a 4xx/5xx |
| `Timeout` | The request exceeded its timeout (default 11 s) |

`BnrException.RequestCanBeRetried()` returns `false` for `IncorrectProductReached` so the retry policy won't loop on a misrouted request. `ProductReached` distinguishes parse and protocol errors (`true`) from network failures (`false`).

---

## Link System

Three classes implement BNR's HAL-like link model:

**`IBnrLink` / `BnrLink<T>`** — a static path bound to a typed response. Created with a path, then `BindParentContext(protocolApi, parentPath)` resolves it against the product's base URI. `GetRequest()` returns a ready-to-execute `BnrRequest<T>`; `GetRequestBuilder()` returns a `Builder<T>` for further customisation.

**`IBnrTemplatedLink` / `BnrTemplatedLink<T>`** — a path containing `{name}` placeholders. `GetPathBinder()` returns a `PathBinder<T>` that exposes `BindParam(key, value)` (string and nullable-int overloads). Once every placeholder is bound, `GetRequestBuilder()` produces a `Builder<T>`. Trying to access a request from a partially bound binder throws `InvalidOperationException` listing the unbound parameters.

**`Builder<T>`** — fluent request constructor. Methods: `Resolve(string)` (relative path), `AddQueryParameter(name, value)` (with optional URI-escaping), `UseGet`, `UsePost(body)`, `UsePostWrapped<TWrapped>(body, wrapKey)`, `UsePut(body)`, `UsePutWrapped<TWrapped>(body, wrapKey)`, `UseDelete([body])`, and `UnwrapResponse(bool, [count])`. POSTs and PUTs without a body throw `InvalidOperationException`. `Build()` returns the `BnrRequest<T>`.

### Self-modifying responses

Many response models embed their own modification links — for example `Adjustment` deserialises an `_links` dictionary containing `relation/modify` and `relation/reset` links. After parse, `BindBnrContext` walks these links and binds them to the product context, after which `Adjustment.BuildModifyRequest(...)` and `BuildResetRequest()` work without the caller needing to know the path. The same pattern is used in `SpeakerInfo`, `PlayQueue`, and most profile types.

`Wrapper<T>` provides the inverse: when a request needs `{ "key": <object> }`, the builder's `UsePostWrapped` / `UsePutWrapped` helpers wrap the payload through `Wrapper<T>` and the custom `WrapperConverter` handles serialisation.

---

## Convention Reference

### Request shape

| Operation type | HTTP method | Body convention |
|---|---|---|
| Read state | GET | None |
| Activate / fire command | POST | `{}` (`EmptyBody`) or a wrapped value |
| Modify a single field | PUT | A wrapped or single-field object (e.g. `{ "level": 42 }`) |
| Remove an item | DELETE | None, or `{}` for products that require a body |

### Response shape

The default is wrapped: `{ "<resourceName>": { ...actual content... } }`. Builder calls reflect this by calling `UnwrapResponse(true)` (the default) or `UnwrapResponse(false)` for endpoints that return the bare object. Some endpoints (e.g. the security session handshake) wrap twice — those call `UnwrapResponse(true, 3)`-style with explicit counts.

### Path conventions

- Service-rooted: `/BeoDevice/`, `/BeoZone/Zone/`, `/BeoZone/System/`, `/BeoContent/`, `/BeoHome/`, `/BeoSecurity/`, `/BeoOneWay/Input/`, `/BeoInput/...`, `/BeoNotify/Notifications`.
- Resource-relative: `./Sources/`, `./ActiveSources/primaryExperience/`, `./Sound/Volume/Speaker/Level`, `./PlayQueue/`, etc. Resolved against `ZoneApi.ZonePath` (`/BeoZone/Zone/`) or `ZoneApi.SystemPath` (`/BeoZone/System`) at link-bind time.
- URL-encoded segments: source ids (`HttpUtility.UrlEncode`) and JIDs (`Uri.EscapeDataString` / `WebUtility.UrlEncode`) are escaped because they contain colons and other reserved characters.

### Identity

- **Product JID** — returned in the `Device-Jid` header on every response. Validated against `ProductInfo` after every call.
- **Source id** — opaque colon-delimited string (e.g. `radio:1234.tuneIn:411717`), URL-encoded in paths.
- **Listener JID** — the JID of another product subscribing to a primary experience for multi-room.

---

## Profile Path Reference

Each profile in `Device/Profiles/` and `Home/Trigger/` has a static `Path` constant. Listed for quick lookup:

| Profile | Path constant | Service base |
|---|---|---|
| `PowerManagementProfile` | `/BeoDevice/powerManagement/` | absolute |
| `FactoryResetProfile` | (declared in class) | `/BeoDevice/factoryReset/` |
| `SoftwareUpdateProfile` | `BeoDevice/softwareUpdate/` | relative |
| `LogReportingProfile` | (declared in class) | `/BeoDevice/logReporting/` |
| `NetworkSettingsProfile` | (declared in class) | `/BeoDevice/networkSettings/` |
| `ModulesInformationProfile` | (declared in class) | `/BeoDevice/modules/` |
| `RegionalSettingsProfile` | (declared in class) | `/BeoDevice/regionalSettings/` |
| `TermsAndConditionsProfile` | (declared in class) | `/BeoDevice/termsAndConditions/` |
| `RemoteControlPairingProfile` | (declared in class) | `/BeoDevice/remoteControlPairing/` |
| `CredentialProfile` | (declared in class) | `/BeoDevice/credentials/` |
| `BluetoothSettingsProfile` | (declared in class) | `/BeoDevice/bluetooth/` |
| `LineInSettingsProfile` | (declared in class) | `/BeoDevice/lineIn/` |
| `AssociationProfile` | (declared in class) | `/BeoDevice/association/` |
| `TriggerProfile` | `/BeoHome/trigger/` | absolute |

All profiles follow the same construction pattern: `BuildProfileRequest(BnrProtocolApi)` (or `CreateDefaultRequest`) is a static factory that builds a `BnrSelfLink<TProfile>` from the path constant, binds the protocol context, and returns `BuildGetRequest()`. Subsequent modification calls are made through links discovered in the response.

---

## Usage Example: Reading and Setting Speaker Volume

```csharp
// Construct the API for a known product
var api = new BnrProtocolApi(productInfo, httpRequestExecutor);

// Read current volume
var volumeRequest = api.ZoneApi.SoundGroup.VolumeResource.BuildGetRequest();
var volumeResponse = await volumeRequest.ExecuteAsync();

if (!volumeResponse.IsSuccessful)
{
    // Handle failure — see BnrResponseError
    return;
}

var current = volumeResponse.Body().Speaker.Level;

// Set the level (PUT /BeoZone/Zone/Sound/Volume/Speaker/Level)
var modifyRequest = api.ZoneApi.SoundGroup
    .VolumeLevelSpeakerResource
    .BuildModifyRequest(50);

var modifyResponse = await modifyRequest.ExecuteAsync(retries: 2);

// Mute via the volume resource
var muteRequest = api.ZoneApi.SoundGroup
    .VolumeResource
    .BuildModifyVolumeMutedRequest(true);
await muteRequest.ExecuteAsync();
```

## Usage Example: Joining a Listener (Multi-Room)

```csharp
// Master product — add a listener identified by its JID
var join = api.ZoneApi.ActiveSourcesResource
    .BuildExpandExperienceRequest(listenerJid);
await join.ExecuteAsync();

// ...later, remove the listener
var leave = api.ZoneApi.ActiveSourcesResource
    .BuildDeleteListenerRequest(listenerJid);
await leave.ExecuteAsync();
```

For products that respond to the legacy "Join" remote button, the equivalent one-shot call is:

```csharp
await api.OneWayApi
    .BuildLegacyCommandRequest(LegacyCommand.Join)
    .ExecuteAsync();
```

## Usage Example: Subscribing to Volume Changes

```csharp
var notify = new BeoNotifyClient(socketFactory, productInfo, loggerFactory, networkService);

notify.VolumeNotification += (sender, args) =>
{
    var data = args.Notification.Data;
    var level = data.Speaker?.Level;
    var muted = data.Speaker?.Muted;
    // Update UI accordingly
};

notify.ConnectivityChanged += (sender, args) =>
{
    // args.IsConnected reflects the current TCP state
};

notify.StartListening();

// ...later
notify.StopListening();
```

---

## Open Questions

1. **MoodWheel content profile.** `Content/Models/MoodWheel/` defines the model surface but the corresponding `MoodWheelProfile` in `Content/Profiles/` is shallow. Is MoodWheel content read live from the source's profile self-link, or via a dedicated endpoint? The current code only fetches via discovered self-links — no static endpoint is exposed.
2. **`SourceActivationResource` paths.** The class is constructed in `ZoneApi`, but its operations build paths through discovered links rather than constants. Real-world endpoint paths should be confirmed against a live product trace.
3. **Heading change in `BeoSecurity`.** `SecurityApi` has a single endpoint that returns an unwrap-3 response (`UnwrapResponse(true)` then advances 3 layers). This is the only place in the client that uses an explicit unwrap count — other call sites use the default `1`. Worth confirming whether other security endpoints exist on newer firmware.
4. **`OneWayApi` vs `CommandsApi` overlap.** Both can issue `Play`, `Stop`, `Mute`, etc. The legacy API targets `/BeoOneWay/Input/` with a string command name; `CommandsApi` targets `/BeoZone/Zone/{path}` with a typed `Command`. The selection rule in production code is not captured in this client — likely `ProductType.Capabilities` decides.
5. **Notification `_lastNotificationId` semantics on reconnect.** The id is tracked but there is no visible code path that sends it back to the server (e.g. as a `since=` query parameter). De-duplication is therefore client-side only; old events may be re-delivered after a reconnect.
6. **Charset suppression flag.** `RemoveCharSetFromContentTypeInBnr` is read from `BnrCapabilities`, but the flag's source — whether it's hardcoded per `ProductType` or fetched from the product — isn't visible in this slice of the codebase.

---

## Resolved Decisions

| Question | Decision |
|---|---|
| Does the client target Mozart-platform speakers? | No — Mozart products use the separate Mozart Open API |
| What identifies a product across requests? | The JID returned in the `Device-Jid` header, validated on every response |
| Are responses HAL-style with embedded links? | Yes — most resources discover modification/reset links from `_links` in the response and bind them at parse time |
| How is multi-room "join" expressed? | Add or remove `Listener` JIDs against `ActiveSources/primaryExperience/`, or fire `LegacyCommand.Join` via `BeoOneWay` |
| How does the client receive push events? | Long-lived TCP `GET /BeoNotify/Notifications?timeout=86400` parsed into typed `Notification` subclasses |
| What is the default request timeout? | 11 seconds, set in `BnrProtocolApi`'s constructor |
| Does the client retry by default? | No — retries are opt-in per call via `ExecuteAsync(retries, retryStepbackMs, retryOnBnrResponseError)` |
| Are credentials transmitted in clear? | No — `BeoSecurity` establishes an RSA-then-AES session for credential payloads |
