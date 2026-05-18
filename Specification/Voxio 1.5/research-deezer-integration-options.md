# Deezer — integration options and possibilities

**Date:** 4 May 2026
**Project:** B&O Voice Control (iOS, Mozart API)
**Question:** What are the realistic ways our app could integrate with Deezer, and what would each cost us in terms of policy exposure, engineering, and user experience?

---

## TL;DR

Deezer is the most permissive of the major streaming services on paper — there is no explicit voice-control prohibition in their developer terms, unlike Spotify and Tidal. But the practical picture is the opposite of what that suggests: Deezer's developer platform is older, less actively maintained, and **deliberately limits third-party playback to 30-second previews for legal reasons.** Their Native SDK is deprecated. The only modern playback path is the JavaScript Web SDK (web only) or a commercial partnership.

The order of preference for our app is:

1. **Stay on Mozart-only** (current architecture). Full Deezer playback, zero policy exposure, already implemented. Mozart handles Deezer playlists, Deezer Flow, albums, and tracks via the speaker firmware.
2. **Mozart + Deezer Public API as a metadata enricher.** Use Deezer's REST API for catalog/search to support a future "play any Deezer track by voice" feature, with playback always routed back through Mozart's `play_media` action which already accepts Deezer URIs. Lower policy risk than Tidal because no voice prohibition exists in the terms; quota and OAuth costs comparable.
3. **Deezer JavaScript SDK in a hybrid web view.** Theoretically feasible but architecturally awful — embedding a JS SDK in an iOS voice app to get full playback bypasses the speaker entirely, defeating the product.
4. **Direct partnership.** As with Tidal, only realistic via B&O.

The body of this paper expands each, with particular emphasis on the API surface (which is broader and more open than Tidal's) and the playback restriction that constrains what we can actually do.

---

## 1. The four paths in detail

### Path A — Stay on Mozart-only (the current spec)

**What it is.** The iOS app talks only to the Mozart REST API on the speaker. Deezer content reaches the user because the speaker's firmware has a Deezer integration; the user sets up Deezer once in the B&O app, assigns Deezer playlists or Deezer Flow as favourites, and from then on the speaker streams Deezer directly. Our app sees only the favourites list and the play/pause/volume API.

**What's notable about Deezer on Mozart vs. Tidal on Mozart.** Deezer integration on Mozart speakers is actually deeper than Tidal's in one respect: the Mozart `play_media` action accepts not just favourite IDs but also **Deezer-specific content types** — `deezer/flow` (the personalized infinite stream), and arbitrary `album:ALBUM_ID`, `playlist:PLAYLIST_ID`, `track:TRACK_ID` URIs. This is documented in the Bang & Olufsen Home Assistant integration. So if we know a Deezer ID, we can already play it on the speaker without it being a pre-assigned favourite. That is a meaningful capability the favourites-only flow doesn't yet exploit.

**What we get.** Full Deezer playback on the speaker, all current voice commands, plus the *latent* ability to play arbitrary Deezer content if we ever obtain Deezer IDs from somewhere.

**What we lose.** Same as Tidal: no search, no browse, no recommendations, no recently-played from within our app. The user must have done the curation work in the B&O app first.

**Policy exposure.** None. We do not use the Deezer for Developers platform, so the Deezer Developer Terms do not apply to us.

**Engineering effort.** Zero additional. Already in spec.

---

### Path B — Mozart for playback, Deezer Public API for metadata

**What it is.** Keep playback on Mozart. Use Deezer's public REST API at `https://api.deezer.com/` for catalog data (search, album, playlist, artist, recommendations, mixes/radio) and optionally user data (favourites, library) via OAuth 2.0. When the user asks "Beosound, play *Random Access Memories*", we resolve the title to a Deezer album ID via the Deezer search API, then call Mozart's `play_media` with `media_content_type: deezer` and `media_content_id: album:ALBUM_ID`.

This is the path that turns voice control into a discovery tool. And uniquely for Deezer, the Mozart API directly accepts the Deezer URIs we'd be resolving — so the architectural cost is lower than the equivalent Tidal path.

**The Deezer Public API surface.**

The API is a straightforward REST/JSON service, base URL `https://api.deezer.com/`. The salient endpoints:

| Endpoint | What it returns | User auth required? |
|---|---|---|
| `/search?q=...` | Search results for tracks | No |
| `/search/album?q=...` | Search results for albums | No |
| `/search/playlist?q=...` | Search results for playlists | No |
| `/search/artist?q=...` | Search results for artists | No |
| `/album/{id}` | Album details + tracks | No |
| `/playlist/{id}` | Playlist details + tracks | No |
| `/track/{id}` | Track details | No |
| `/artist/{id}` | Artist details | No |
| `/artist/{id}/top` | Artist's top tracks | No |
| `/radio` | Available "Mixes" / radio stations | No |
| `/genre` | All Deezer genres | No |
| `/user/me` | Current user profile | Yes |
| `/user/me/playlists` | User's playlists | Yes |
| `/user/me/tracks` | User's favourite tracks | Yes |
| `/user/me/albums` | User's favourite albums | Yes |
| `/user/{id}/recommendations/tracks` | Personalized track recommendations | Yes |

The breadth here is substantially better than Tidal's current Open API. Notably, **public catalog endpoints don't require authentication at all** — search, album lookup, playlist lookup all work with just an API key. This means a "voice search Deezer" feature could ship with no per-user OAuth flow at all, as long as it queries catalog rather than user data.

**OAuth 2.0 flow (when user data is needed).**

Deezer's OAuth is conventional but dated. Authorize URL format:

```
https://connect.deezer.com/oauth/auth.php?app_id=APP_ID&redirect_uri=URL&perms=basic_access,email,offline_access,manage_library
```

Permission scopes include: `basic_access`, `email`, `offline_access`, `manage_library`, `delete_library`, `listening_history`, `manage_community`. Token exchange returns an access token used as a query parameter on subsequent requests (older OAuth pattern — the token is appended as `?access_token=...` rather than sent in an Authorization header). This is unusual and worth flagging in any implementation; it creates accidental-token-leak risk if URLs ever land in logs.

There is one constraint on iOS that matters: Deezer's redirect URI scheme is locked to whatever was registered, with no support for multiple URIs per app. So a development-build redirect URI and a production-build redirect URI need separate Deezer app registrations.

**The 30-second preview restriction — and why it doesn't matter for our use case.**

Deezer's developer FAQ is unambiguous: third parties cannot stream the audio file directly from the API for legal reasons. The full track URLs returned by the API have a `preview` field which is a 30-second clip. Anything more requires either the JavaScript SDK (web-only) or a commercial agreement.

**This restriction does not affect Path B**, because we are not playing anything in our app. We are only using the Deezer API to *discover Deezer IDs*, then handing those IDs to the Mozart API for playback on the speaker. The speaker has its own Deezer integration with full streaming rights. The audio path is Deezer-server → speaker, never touching our app.

**Voice-policy question — where it actually falls.**

This is where Deezer compares favourably to Tidal and Spotify. The Deezer Terms of Use of Deezer for Developers contains:

- Restrictions on commercial use without partnership
- A 30-second preview limit on direct streaming
- Standard prohibitions on reverse engineering, content scraping, etc.
- A clause reserving Deezer's right to revoke access at any time without notice (standard, but worth noting)

It does **not** contain an explicit voice-control prohibition. This is the major textual difference from Spotify and Tidal. There is also a phrase that explicitly invites partnership conversations for hardware integrations, which suggests a more open posture toward novel use cases.

That said, the absence of an explicit prohibition is not the same as an explicit permission. Deezer reserves the right at any time for any reason and at its own discretion to modify, restrict or remove Developer access. So a voice-control app built on the Deezer API is on safer textual ground than the equivalent Tidal app, but still on revocable terms. This is a "less risky than Tidal, not zero risk" position.

**Engineering effort.** Lower than the Tidal equivalent. The OAuth flow is simpler (no PKCE complexity, though we should still use PKCE), the catalog endpoints don't require authentication at all, and the JSON responses are flat and easy to map to Swift models. Probably 1–2 weeks for a single engineer to ship a clean catalog-search-only implementation; add a few days more if user-library access is in scope.

**Recommendation.** This is the most promising path for v2 if voice-driven search becomes a priority. It carries less policy risk than the Tidal equivalent, is easier to build, and exploits a Mozart capability (accepting raw Deezer URIs) that's already available.

---

### Path C — Deezer JavaScript SDK in a hybrid web view

**What it is.** Deezer's only currently-supported playback SDK is the JavaScript SDK, intended for browsers. To use it in an iOS app you'd embed a `WKWebView`, run the Deezer JS SDK inside it, log the user in, and stream Deezer through the web view's audio output.

**Why it's a non-starter.**

- **It defeats the architecture.** The whole point is the speaker plays the music. A web view streaming through the iPhone's speaker, then somehow re-routed to the B&O speaker, is a bad answer to a problem we don't have.
- **iOS treats web-view audio as an in-app audio session,** not a stream we can hand off to a B&O speaker over the local network. The audio path would be Deezer → web view → iOS audio output → AirPlay (if available) → speaker. Most Mozart speakers don't even receive AirPlay.
- **The Deezer Native SDK has been deprecated** ("our Native SDK has been deprecated and Deezer no longer supports it"), so there is no iOS-native equivalent we can fall back to.

**Recommendation.** Ignore. Listed only so the option is explicitly ruled out.

---

### Path D — Direct partnership / commercial agreement

**What it is.** The Deezer FAQ explicitly invites partnership conversations: "If you would like to discuss a potential partnership with us to integrate Deezer in hardware devices, vehicles or other products, you can contact us with this form."

**What it would unlock.** Full streaming, removed quota limits, possibly co-marketing. Same as the Tidal equivalent.

**Why it's unrealistic for us as an indie app.** Same reasoning as the Tidal paper: this is a B&O-scale conversation, not a small-developer conversation. The natural path is via B&O if our app becomes part of an extended B&O voice ecosystem.

**Recommendation.** Park. Revisit only if there's a clear B&O endorsement story.

---

## 2. Comparison: Deezer vs. Tidal as a v2 metadata source

If we were to add one streaming-service catalog API to our app post-launch, Deezer is the better candidate, on five dimensions:

| Dimension | Tidal Open API | Deezer Public API |
|---|---|---|
| Voice-control policy | Explicit prohibition without written approval | No explicit prohibition |
| Catalog access without user OAuth | No (client credentials needed) | Yes (public endpoints) |
| API maturity | New, evolving, gaps in coverage | Older, stable, broader endpoint set |
| OAuth flow complexity | OAuth 2.1 + PKCE, fairly modern | OAuth 2.0, simpler but slightly dated |
| Mozart speaker acceptance of arbitrary IDs | Limited to what's documented for Tidal | Documented support for `album:`, `playlist:`, `track:`, plus Deezer Flow |

The Tidal advantage is audio quality (lossless / hi-res) and the partnership marketing alignment B&O has chosen to lean into. The Deezer advantage is API openness — both in policy and in technical surface.

A pragmatic v2 plan could be: **add Deezer first**, behind a feature flag, as the lower-risk way to validate whether voice search is something users actually want. If the feature lands well and B&O wants to extend it to Tidal users, revisit Path B of the Tidal paper as a follow-up under the umbrella of B&O's existing partnership.

---

## 3. Practical voice-flow pseudocode

For a future v2 voice-search feature on Deezer:

```swift
// User says: "Beosound, play Random Access Memories"
// 1. Strip speaker name → remainder = "play Random Access Memories"
// 2. CommandParser → .playNamed(query: "Random Access Memories")
// 3. Try local match against Mozart favourites first
//    → no match found
// 4. Fallback: Deezer search (no user auth needed for catalog)
let results = try await deezerAPI.search(
    query: "Random Access Memories",
    type: .album,
    limit: 5
)
// 5. Pick top result, present spoken confirmation
//    "Playing the album Random Access Memories by Daft Punk on Beosound"
// 6. User confirms
// 7. mozartAPI.playMedia(
//      speaker: beosound,
//      mediaContentType: .deezer,
//      mediaContentId: "album:\(results.first.id)"
//    )
```

The architectural hooks needed mirror the Tidal v2 sketch in the Tidal paper: a `DeezerCatalogService` parallel to `FavoritesService`, a routing decision in the use-case layer ("favourite first, then Deezer search"), and additional error states ("Deezer search returned no result", "Mozart rejected the Deezer ID").

The notable difference is that **no per-user OAuth flow is needed** for catalog search alone. The app can use a single registered Deezer app ID for all catalog calls, with no user login step. This is a meaningful UX simplification compared to the Tidal equivalent.

---

## 4. Risk register for any future Deezer integration

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Deezer revokes API access (per their broad discretionary clause) | Low–Medium | High | Wrap all Deezer calls in a service layer with a kill switch; favourites-only mode remains the default |
| Deezer adds a voice-control prohibition similar to Spotify/Tidal | Low–Medium | High | Monitor terms; build feature behind flag for fast disabling |
| Public catalog API rate-limited unexpectedly (no published quotas) | Medium | Medium | Cache search results aggressively; use exponential backoff |
| Deezer URIs not accepted by Mozart for some content type | Low | Medium | Validate with Mozart before confirming; fall back to user prompt |
| OAuth flow breaks (older OAuth pattern, token in query string) | Low | Low | Use HTTPS only, never log URLs with tokens, scrub in error reporting |
| Deezer deprecates the Public API entirely | Low | High | Deezer has signalled long-term commitment, but this is the catastrophic-tail risk |

---

## 5. Recommendation summary for the project

**For v1:** No change. Mozart-only. The functional spec is correct.

**For v2 (post-launch):** **Deezer is the preferred first streaming-service API to add**, ahead of Tidal, because:

- No explicit voice-control prohibition
- Catalog endpoints work without per-user OAuth
- Mozart speaker already accepts Deezer URIs natively
- Simpler engineering surface
- Lower policy exposure

Budget 1–2 engineering weeks for catalog-search-only, behind a feature flag, with playback always routed through Mozart.

**Tidal equivalent should follow Deezer if it follows at all**, ideally under B&O partnership cover.

**Spec changes recommended now:** Same as the Tidal paper — add a one-line clarifying clause to the functional spec stating that the app interacts only with the Mozart API and does not communicate with Deezer directly. This both protects against scope creep and gives a clean answer to App Store review.

---

## 6. Sources consulted

- Deezer for Developers — Terms of Use, Developer FAQs, JavaScript SDK reference (`developers.deezer.com`)
- Deezer Support Center — Developer FAQ updates 2025
- Public API references at RapidAPI, PublicAPI, and various integration guides
- Bang & Olufsen Mozart Open API and Home Assistant integration documentation (which documents the Deezer URI formats Mozart accepts: `album:ID`, `playlist:ID`, plus Deezer Flow)
- Deezer × Bang & Olufsen support pages on Mozart Platform integration
