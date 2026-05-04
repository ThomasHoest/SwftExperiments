# Tidal — integration options and possibilities

**Date:** 4 May 2026
**Project:** B&O Voice Control (iOS, Mozart API)
**Question:** What are the realistic ways our app could integrate with Tidal, and what would each cost us in terms of policy exposure, engineering, and user experience?

---

## TL;DR

There are five distinct ways an iOS app can interact with Tidal. Only two of them are open to a third-party developer without a partnership agreement. Of those two, only one is genuinely usable for our voice-control use case — and it's the one we already have via the Mozart API. The other (Tidal's public Open API) cannot stream full tracks; the SDK explicitly limits third-party playback to 30-second previews.

The order of preference for our app is:

1. **Stay on Mozart-only** (current architecture). Zero Tidal policy exposure, full playback, full B&O integration. Already implemented in spec.
2. **Mozart + Tidal Open API as a metadata enricher.** Use the Open API only for catalog search/browse to support a future "play any Tidal track by voice" feature; still hand off actual playback to Mozart. Modest engineering cost, manageable policy exposure if voice scope is documented carefully.
3. **Tidal Connect as a target (the inverse of what we want).** The phone is the controller, the speaker is the target — useful only if we want to *initiate* Tidal playback we otherwise can't via Mozart. Requires the Tidal app on the user's phone, so this is really a routing trick, not an integration.
4. **Tidal SDK with Player module — preview-only.** Not viable for our use case; 30-second clips don't make a music app.
5. **Direct partnership / written approval for voice control.** Only Bang & Olufsen (the company) can credibly pursue this, not us as third-party app developers.

The body of this paper expands each option, what it costs, what it unlocks, and where the policy lines actually fall.

---

## 1. The five paths in detail

### Path A — Stay on Mozart-only (the current spec)

**What it is.** The iOS app talks only to the Mozart REST API on the speaker. Tidal content reaches the user because the speaker's firmware has a Tidal integration; the user sets up Tidal once in the B&O app, assigns Tidal playlists as favourites, and from then on the speaker streams Tidal directly from Tidal's servers. Our app sees only the favourites list and a play/pause/volume API.

**What we get.** Full lossless Tidal playback on the speaker, all current voice commands (play favourite, list favourites, stop, pause, resume, volume, mute), no Tidal credentials in our app, no OAuth flow, no Tidal API quotas.

**What we lose.** We cannot do anything with Tidal content that isn't already a favourite. "Beosound, play *Kind of Blue* by Miles Davis" is impossible — that album isn't in the favourites list. Search, browse, recommendations, recently played — none of that is reachable via Mozart.

**Policy exposure.** None. We do not use the Tidal Developer Platform, so the Tidal Developer Guidelines (including the voice-control prohibition) do not apply to us. Tidal's relationship with our app is entirely indirect — through B&O's certified hardware partnership.

**Engineering effort.** Zero additional. This is what the spec already describes.

---

### Path B — Mozart for playback, Tidal Open API for metadata

**What it is.** Keep playback on Mozart, but call Tidal's public Open API (`https://openapi.tidal.com/`) for catalog data: search, album lookup, artist lookup, possibly user playlists in the future. Our app would authenticate the user with Tidal via OAuth 2.1 (PKCE), use the resulting access token to enrich the voice flow with catalog knowledge, and then translate user intent back to a Mozart playback action.

**Concrete example of what this would unlock.** A v2 voice command like *"Beosound, search Tidal for Kind of Blue"* could:

1. Resolve "Kind of Blue" against the Tidal Open API's `/searchresults` endpoint.
2. Get back a Tidal playlist or album ID.
3. Call the Mozart API to play that ID — the Mozart `play_media` action accepts album, playlist, or track IDs for Tidal content via the `media_content_type: tidal` channel that the Home Assistant integration already documents.

This is the path that turns voice control into a *discovery* tool rather than a *favourites recall* tool.

**The hard limits of the Open API in 2026.**

- **Authorization.** Tidal uses OAuth 2.1 with PKCE. Three flows are supported: client credentials (catalog only), authorization code (user data), and refresh token. The token endpoint is `https://auth.tidal.com/v1/oauth2/token`. Catalog access uses scopes that are claimed by the app at registration; user data requires PKCE.
- **What's actually exposed.** As of the most recent Tidal developer discussion threads, the v2 API exposes: catalog (albums, artists, tracks, search), user info, playlists (read access rolled out, write access following), and user collection R/W for albums, artists and playlists. "My Collection" tracks/albums was still being rolled out as of late 2025 with a target of early 2026 for full coverage. The picture is much more limited than Spotify's Web API at its peak.
- **What's not exposed.** Recommendations endpoints are not yet open to third parties. The legacy `api.tidal.com` (with `r_usr` scope) is closed; only endpoints documented at `developer.tidal.com/reference/web-api` are usable.
- **Quotas.** Every newly created app starts in "Development mode" with strict quotas. To get production-grade access requires an Application Review which Tidal manually evaluates and "usually takes a couple of weeks." The bar is not as explicit as Spotify's 250k-MAU rule but the gating mechanism is the same shape.

**The voice-policy question — where it actually falls.**

This is the subtle part. Tidal's Developer Guidelines prohibit "creation of functionality allowing users to control or operate the TIDAL Service using voice control or recognition technology" without express written approval. The question is whether using the Open API only for metadata lookup (and routing playback back through Mozart) counts as "controlling or operating the TIDAL Service" with voice.

A reasonable, conservative reading: if the voice command resolves a song name to a Tidal ID and then plays it on Tidal infrastructure, we are using the Tidal platform's catalog tooling to enable a voice experience that ends in Tidal playback. That is plausibly within the policy's scope, even if the audio path goes through Mozart. We would be relying on a benign-intent argument that wouldn't survive a strict review.

Mitigation strategies, in increasing order of caution:

1. **Treat the Tidal Open API as a search aid the user invokes manually**, not a voice target. The user types a search box that queries Tidal; the voice layer only operates over results the user has already pinned. This is awkward for a voice app.
2. **Get B&O to obtain written approval on our behalf** under their existing Tidal partnership. Realistic only if our app is endorsed/co-marketed by B&O.
3. **Apply for written approval ourselves** as a small developer building voice control on top of B&O speakers. Possible but not certain; Tidal grants this case-by-case.

**Engineering effort.** Moderate. OAuth 2.1 PKCE flow on iOS (well-supported by `ASWebAuthenticationSession`), token storage in Keychain, refresh-token handling, mapping Tidal IDs into Mozart `play_media` calls, error handling for the additional failure mode (Tidal API up but speaker offline, or vice versa). Probably 2–3 weeks of work for a single engineer to ship a clean implementation, plus ongoing maintenance as Tidal continues to evolve its v2 endpoints.

**Recommendation.** Defer to v2. Worth doing eventually because it's the natural evolution from "favourites recall" to "voice search and play." Not worth doing for v1 because the policy exposure is real and the favourites flow already covers 80% of the value at zero policy cost.

---

### Path C — Tidal Connect as a routing target

**What it is.** Tidal Connect is Tidal's equivalent of Spotify Connect. The Tidal app on the user's phone discovers Tidal-Connect-capable speakers (Mozart products are on the supported list) and hands off playback so the speaker streams directly from Tidal's servers, with the phone reduced to a remote.

**Why this is interesting for us — and why it isn't.**

In theory, our voice app could trigger Tidal Connect by asking the Tidal app on the phone (via deep links or shortcuts) to start playback on a specific speaker. In practice:

- There is **no public Tidal Connect SDK for third-party iOS apps.** Tidal Connect is a closed, partner-only protocol implemented in certified hardware (B&O is one). The "controller" side is the official Tidal app, not something we can drive programmatically.
- **iOS deep linking into the Tidal app is limited.** We can open the Tidal app to a specific track/album/playlist via `tidal://` URLs, but we cannot programmatically tell it which Connect target to use, nor reliably initiate playback without user interaction.
- **The whole point of our architecture is to keep playback on Mozart.** Tidal Connect would mean the user has the Tidal app open, which defeats the voice-first ambition.

**Where Tidal Connect *does* come up.** It comes up as a thing the user might already be doing when our app receives a stop/pause/resume voice command. If the user started a Tidal Connect stream from their phone, our app can still call `POST /speakers/{id}/pause` and the speaker will pause that stream — because we are pausing the speaker, not Tidal. Same logic applies to volume. So Tidal-Connect-initiated playback is already covered by our existing transport commands without us having to think about it.

**Recommendation.** No engineering work needed. Document in the spec that transport commands (stop/pause/resume/volume) work uniformly on whatever the speaker is playing, including Tidal Connect streams the user started from the Tidal app.

---

### Path D — The Tidal SDK Player module (preview-only)

**What it is.** Tidal publishes an official SDK with a Player module which the developer documentation describes as "the only allowed way for third-party applications to incorporate playback of TIDAL content." The crucial caveat: third-party applications can include playback of TIDAL previews, i.e. 30-second clips.

**Why it's unusable for us.** Voice control over a music speaker cannot end in 30-second clips. The whole UX assumption is full track playback. The Player module is intended for apps that want to add a Tidal-flavoured listen-before-you-buy experience, not apps that drive a hi-fi speaker.

**What about full-track playback?** Full-track playback through the SDK is reserved for partner integrations (the same agreements that put Tidal natively on B&O speakers). It is not a self-service capability.

**Recommendation.** Disregard. Listed here only for completeness so the option is explicitly ruled out.

---

### Path E — Direct partnership / written approval

**What it is.** Tidal's policy says voice control is prohibited without "express written approval." That approval channel exists. It is the channel B&O presumably uses for the deep Tidal integration in the B&O app today.

**What it would unlock.** Anything Tidal agrees to. In principle, a voice-control app with full Tidal access (search, play, library) could be sanctioned under such an agreement, including using Tidal's full-track Player module.

**Why it's unrealistic for us as an indie app.**

- The partnership process is slow, opaque, and oriented toward hardware vendors and large software platforms (Apple Music, Sonos, Bluesound, etc.).
- The natural path here is *via B&O*: if we can get B&O to position our app as a sanctioned voice-control extension of the B&O app, we sit under B&O's existing Tidal partnership rather than negotiating our own. That is a business conversation, not an engineering one.
- Without B&O endorsement, the chance of Tidal granting a small developer voice-control approval is low. Their developer-platform stance has trended toward more gating, not less, over the last 18 months.

**Recommendation.** Park this. Revisit only if (a) the app gets traction and B&O wants to deepen the integration, or (b) Tidal opens a self-service voice-approval programme.

---

## 2. The Tidal Open API in more detail

For the path that's most realistic to revisit (Path B), here's the technical surface as it stands.

### Authentication

| Flow | What it gives | When to use |
|---|---|---|
| Client credentials | Catalog access (search, lookup) only | Server-side prefetch of catalog, no user data |
| Authorization code (PKCE) | User-data scopes | Client app reading user playlists or collection |
| Refresh token | New access tokens | Standard token rotation |

iOS implementation pattern: `ASWebAuthenticationSession` for the auth code step, Keychain for token storage, automatic refresh in a `TidalAPIClient` layer parallel to our existing `MozartAPIClient`.

### Endpoint coverage (current state)

Available:

- Catalog v2: albums, artists, tracks, search results, MIME-type `application/vnd.tidal.v1+json` on JSON:API-shaped responses
- User info: basic profile
- Playlists: read access (write access in flight)
- User collections: R/W for albums, artists, playlists

Not yet available:

- "My Collection" tracks (rolling out, target early 2026)
- Recommendations
- Anything resembling Spotify's audio-features / audio-analysis endpoints

### Practical voice-flow pseudocode (for a future v2 of our app)

Given a transcribed command "Beosound, play Kind of Blue":

```swift
// 1. Strip speaker name → remainder = "play Kind of Blue"
// 2. CommandParser → .playNamed(query: "Kind of Blue")
// 3. Try local match against Mozart favourites first (existing behaviour)
//    → no match found
// 4. Fallback: Tidal search
let results = try await tidalAPI.search(
    query: "Kind of Blue",
    types: [.album, .playlist],
    limit: 5
)
// 5. Pick top result, present spoken confirmation
//    "Playing the album Kind of Blue by Miles Davis on Beosound"
// 6. User confirms
// 7. mozartAPI.playMedia(
//      speaker: beosound,
//      mediaContentType: .tidal,
//      mediaContentId: "album:\(results.first.id)"
//    )
```

The notable architectural change: there are now *two* sources of truth for what's playable (favourites + Tidal catalog), and the parser/use-case layer must decide between them. The existing `FavoritesService` would be joined by a `TidalCatalogService` and a routing layer that decides which to consult and in what order.

---

## 3. Risk register for any future Tidal integration

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Tidal interprets our voice flow as a policy violation | Medium | High (API access revoked) | Keep voice scope narrow; document architecture; pursue B&O umbrella approval |
| Tidal v2 endpoints we depend on are deprecated or change | Medium | Medium | Wrap all Tidal calls in a service layer; pin to specific endpoint versions; monitor the developer forum |
| Tidal tightens developer access further (Spotify-style quota gates) | Medium | High | Treat Tidal integration as a feature flag we can disable; ensure favourites-only mode remains the default |
| Mozart and Tidal IDs drift / Mozart can't accept a given Tidal ID | Low | Medium | Validate the ID with Mozart before confirming voice command; fall back to user prompt |
| OAuth flow breaks on iOS update | Low | Low | Use `ASWebAuthenticationSession` and stay on Apple's recommended path |

---

## 4. Recommendation summary for the project

**For v1:** No change. Mozart-only. The functional spec already correctly describes this architecture and it incurs no Tidal policy exposure.

**For v2 (post-launch, if voice search becomes a priority feature):** Add the Tidal Open API for catalog metadata only, behind a feature flag, with playback always routed through Mozart. Do this only after either (a) explicit user research showing favourites-only is insufficient, or (b) a conversation with B&O about extending their Tidal partnership umbrella to cover our app. Budget 2–3 engineering weeks plus ongoing maintenance.

**Never:** Direct Tidal SDK Player playback (preview-only, useless), or attempting to drive Tidal Connect from our app (no public API, defeats the architecture).

**Spec changes recommended now:** Add a one-line clarifying clause to the functional spec stating that the app interacts only with the Mozart API and does not communicate with Tidal directly. This protects against scope creep and gives a clean, defensible answer to any future review or App Store query.

---

## 5. Sources consulted

- TIDAL Developer Portal — Overview, Quick Start, Authorization, Developer Guidelines (`developer.tidal.com`)
- TIDAL Web API Reference (`tidal-music.github.io/tidal-api-reference/`)
- TIDAL developer forum discussions on playlist endpoints, my-collection, v2 authorization
- Bang & Olufsen Mozart Open API (`bang-olufsen.github.io/mozart-open-api`) and Home Assistant integration docs
- Tidal × Bang & Olufsen partnership pages and B&O firmware release notes
- Industry coverage of Tidal Connect protocol and certified-device list
