# Voxio Specification — v1.4
**Version:** 1.4.0
**Status:** Placeholder
**Date:** 2026-05-04
**Platform:** iOS 26 (iPhone, portrait)
**References:** VoxioSpecification-1.3.md, spotify-integration-research.md, research-deezer-integration-options.md, research-tidal-integration-options.md, CLAUDE.md
**Languages:** English (`en-US`) and Danish (`da-DK`)

**Amendment history**

| Version | Date | Summary |
|---|---|---|
| 1.4.0 | 2026-05-04 | Placeholder. Streaming service integration workstream deferred from v1.3. |

---

## Planned Workstreams

### Feature 1 — Streaming Service Integrations

Spotify, Deezer, and Tidal integration research has been completed and is in this folder. Feature scope and implementation detail to be defined.

Key research findings:

- **Spotify** (`spotify-integration-research.md`) — native Spotify Connect on B&O Mozart speakers; Web API path (PKCE auth, Connect transfer) is the best expansion path; voice-SDA policy prohibition is a hard constraint; 5-user dev cap permanent for indie projects.
- **Deezer** (`research-deezer-integration-options.md`) — see research doc.
- **Tidal** (`research-tidal-integration-options.md`) — see research doc.

Full feature spec, user stories, and task breakdown to be written as this workstream is planned.

---

## Open Questions

1. Which streaming service should be implemented first, and in what order?
2. How does the Spotify voice-SDA policy prohibition affect the voice-command integration path?
3. What is the right OAuth/auth model for each service on iOS?
4. Should streaming service credentials be stored per-user or per-device?
