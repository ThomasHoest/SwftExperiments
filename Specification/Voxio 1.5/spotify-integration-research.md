# Spotify Integration Research — Voxio 1.3

## Summary

Three distinct Spotify integration surfaces exist for an iOS app: the **App Remote SDK** (controls the installed Spotify app on the same iPhone), the **Web API** (cloud REST for search/browse/metadata and Spotify Connect playback transfer), and **Spotify Connect** itself (built into B&O Mozart speakers natively).

**Critical finding:** Spotify's Developer Policy **explicitly prohibits voice-enabled SDAs** — a voice-controlled Spotify integration is policy-barred, not just technically difficult. Additionally, as of early 2026 Spotify has tightened developer access to 5 test users maximum and Premium-account-only requirements, making broad public distribution gated behind a 250,000-MAU extended quota review that now requires a registered business entity.

---

## Key Findings

### B&O Mozart Speaker & Spotify Connect
- B&O Mozart speakers are **natively Spotify Connect devices**. They appear in the Spotify app's Connect device list when active on the same network and support Spotify Lossless on the Mozart platform.
- The Mozart Open API does **not** have native Spotify URI playback. The `POST /playback/uri` endpoint accepts direct stream URLs, and the `/scenes` (Favorites) system can trigger presets that may include Spotify sources, but there is no documented `spotify:track:` URI support. Deezer and Tidal have explicit integration; Spotify does not.

### Spotify Web API
- Can **list available Spotify Connect devices** (`GET /v1/me/player/devices`) and **transfer playback to them** (`PUT /v1/me/player`).
- Requires the `user-modify-playback-state` scope and a Spotify **Premium** account.
- Device IDs are ephemeral — they rotate at least daily and only appear when the device is active. Must be resolved by name at command time, not cached.
- Search and browse: `GET /v1/search`, `GET /v1/me/top/{type}`, `GET /v1/browse/featured-playlists`, etc.
- Playback metadata: `GET /v1/me/player/currently-playing` returns track, artist, album, artwork URL.

### Spotify iOS App Remote SDK
- Controls the **Spotify app on the same iPhone**, not an external speaker.
- Requires the Spotify app to be installed and a **Premium** account for on-demand playback (free tier gets shuffle-only).
- Cannot independently push audio to a B&O speaker.

### Voice-SDA Policy Prohibition
- Spotify's Developer Policy explicitly states: *"Do not create a voice-enabled SDA that enables a user to control Spotify with their voice, or any kind of voice assistant that provides voice-control functionality."*
- This directly bars Voxio's intended use case. Voice commands that trigger Spotify *search UI* (not direct playback) may be a grey area — policy review with Spotify would be needed before shipping.

### Authorization
- **PKCE** is the correct OAuth flow for iOS — no backend required. Spotify ended implicit grant support in November 2025.
- Custom URL scheme redirect (`voxio://spotify-callback`) works entirely client-side.
- Access tokens are valid for 60 minutes; refresh tokens are provided for silent renewal.
- Required scopes: `user-read-playback-state`, `user-modify-playback-state`, `user-read-currently-playing`, `user-read-private` (Premium check), `user-library-read`, `user-top-read`.

### Developer Access Restrictions (2026)
- Development mode is now limited to **5 users** (down from 25) and requires the app owner to hold a Spotify Premium subscription.
- Extended quota access (unlimited users) requires a **legally registered business** with 250,000+ monthly active users. Individual developer applications are no longer accepted as of May 2025.
- This means Voxio as an indie project is permanently capped at 5 users unless these policies change.

### Rate Limits
- Rolling 30-second window. Returns HTTP 429 with `Retry-After` header when exceeded.
- Development mode has lower limits than extended quota mode; exact numbers not published.

---

## Integration Paths (Ranked by Feasibility)

### Path 1 — Favorites as a Spotify Bridge (Lowest Risk, Works Today) ⭐ Recommended
The safest Spotify integration requires zero Spotify API work. If a user has configured a Spotify playlist as a B&O Favorite/Scene on their speaker, Voxio's existing `playFavorite(presetIndex:)` call already triggers it. A voice command "play jazz" that maps to a Spotify-backed Favorite is fully outside Spotify's API policy scope.

**Pros:** No API, no auth, no policy risk, works today.  
**Cons:** User must pre-configure Spotify content as B&O Favorites manually.

---

### Path 2 — Spotify Connect Transfer via Web API (Moderate Risk) ⭐ Best Expansion Path
Uses only the Web API (not the streaming SDK), so the non-commercial streaming restriction does not apply.

**Flow:**
1. Authenticate with PKCE.
2. `GET /v1/search` — let users browse/search Spotify content.
3. `GET /v1/me/player/devices` — find the B&O speaker by friendly name.
4. `PUT /v1/me/player` — transfer playback to the speaker.
5. `PUT /v1/me/player/play` — start a specific track/playlist/album.
6. Poll `GET /v1/me/player/currently-playing` for metadata display.

**Voice integration (policy-safe variant):** Voice commands trigger a Spotify *search UI* that the user confirms before playback starts — this avoids direct voice-to-playback triggering and may sidestep the voice-SDA prohibition.

**Pros:** Full browse/search, rich metadata, works with native Spotify Connect on the speaker.  
**Cons:** Requires Premium, 5-user dev cap, ephemeral device IDs, policy grey area on voice triggers.

---

### Path 3 — App Remote SDK (High Policy Risk, Not Recommended)
Control the Spotify app on the user's iPhone, then rely on the user to have already connected their iPhone to the B&O speaker via Spotify Connect before entering Voxio.

**Cons:** High policy risk with voice commands, requires Spotify app installed, Premium only, no direct speaker control. Not recommended.

---

## Open Questions

1. **Voice SDA policy ambiguity.** Does a voice command that *opens a search UI* (rather than directly triggering Spotify playback) violate the policy? Legal/policy review needed before shipping.
2. **Mozart API Spotify URI support is unconfirmed.** `POST /playback/uri` with a `spotify:album:XXXX` URI may work since B&O speakers are native Connect devices, but this is undocumented. Requires testing on a real device.
3. **Premium gating.** The app should detect Premium status via `GET /v1/me` and gracefully gate the Spotify feature for free-tier users.
4. **Extended quota is closed for individuals.** The 5-user cap is permanent for an indie project under current Spotify policy.
5. **App Store review.** Use of the Spotify brand/logo requires the "Play on Spotify" button treatment per [Spotify Brand Guidelines](https://developer.spotify.com/documentation/design).

---

## Sources

| Resource | URL |
|---|---|
| Spotify iOS SDK Overview | https://developer.spotify.com/documentation/ios |
| Spotify iOS SDK Getting Started | https://developer.spotify.com/documentation/ios/getting-started |
| Spotify Web API Overview | https://developer.spotify.com/documentation/web-api |
| Transfer Playback endpoint | https://developer.spotify.com/documentation/web-api/reference/transfer-a-users-playback |
| Get Available Devices endpoint | https://developer.spotify.com/documentation/web-api/reference/get-a-users-available-devices |
| Authorization Code with PKCE | https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow |
| OAuth Migration (Nov 2025) | https://developer.spotify.com/blog/2025-10-14-reminder-oauth-migration-27-nov-2025 |
| Quota Modes | https://developer.spotify.com/documentation/web-api/concepts/quota-modes |
| Rate Limits | https://developer.spotify.com/documentation/web-api/concepts/rate-limits |
| Spotify Developer Policy | https://developer.spotify.com/policy |
| Extended Access Criteria Update | https://developer.spotify.com/blog/2025-04-15-updating-the-criteria-for-web-api-extended-access |
| Spotify Brand Guidelines | https://developer.spotify.com/documentation/design |
| B&O Support — Spotify Connect | https://support.bang-olufsen.com/hc/en-us/articles/360043650871-How-do-I-use-Spotify-Connect |
| Mozart Open API (GitHub) | https://github.com/bang-olufsen/mozart-open-api |
| Scopes Reference | https://developer.spotify.com/documentation/web-api/concepts/scopes |
