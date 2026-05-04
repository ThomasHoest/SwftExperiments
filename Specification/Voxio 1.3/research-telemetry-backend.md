# Telemetry Backend Research — Voxio 1.3

## Summary

The recommended stack is: **Azure SWA built-in GitHub auth** (Standard plan, ~$9/month) for the admin site, **Next.js 15 hybrid mode on Azure SWA** for API routes (preview, workable with known caveats), **Neon serverless Postgres** (free tier, SQL) as the database, and a **static API key in a custom `X-Api-Key` header stored in iOS Keychain** for telemetry uploads. This keeps the entire backend inside the Azure SWA ecosystem already established by TheCheapPowerCompany, avoids new services, and costs near-zero at indie project volumes.

---

## Finding 1 — Admin Authentication

### Options evaluated

**Azure SWA built-in auth (GitHub or Microsoft Entra ID)**
- Zero application code. Sign-in routes are `/.auth/login/github` and `/.auth/login/aad`, handled entirely by the SWA runtime.
- GitHub and Microsoft Entra ID are pre-configured on all SWA plans including Free.
- After sign-in, users belong to built-in roles `anonymous` and `authenticated`. Route restrictions like `"allowedRoles": ["authenticated"]` work on Free.
- **Custom roles** (e.g. an `admin` role) require the **Standard plan** ($9/month) and the portal-based Invitations system. Each admin's GitHub username is invited to the `admin` role via the portal. Route rule `"allowedRoles": ["admin"]` in `staticwebapp.config.json` locks down all admin routes — zero application code.
- Gotcha: the pre-configured GitHub provider exposes only the GitHub username (not email). Custom email requires a custom GitHub OAuth app registration (Standard plan only).

**NextAuth.js v5 (Auth.js)**
- GitHub issues #1524 and #12547 confirm NextAuth.js v5 does NOT work reliably on Azure SWA — requests to `/api/auth/providers` return 500 errors in production. Closed without a confirmed fix.
- Verdict: avoid for this project.

**Azure AD B2C**
- Full enterprise identity platform. Requires tenant setup, custom policies, separate Azure resource costs.
- Complete overkill for 1–3 admins. Verdict: eliminate.

**Simple API key / basic auth**
- Appropriate for the iOS telemetry endpoint (see Finding 4). Not appropriate for the admin UI — no user identity, no role management.

### Recommendation

Use **Azure SWA built-in GitHub auth on the Standard plan**. Register each admin's GitHub username via the Role Management portal blade with the `admin` role. Add a single route rule in `staticwebapp.config.json` restricting all admin routes to `allowedRoles: ["admin"]`. Zero application code.

---

## Finding 2 — Backend API Hosting on Azure SWA

### How hybrid Next.js works on SWA

When a Next.js app is deployed in hybrid mode, static assets are served from SWA's global CDN; dynamic requests (Route Handlers, SSR) are proxied to a **managed App Service instance** Azure provisions automatically. Route Handlers at `app/api/*/route.ts` work as expected — confirmed in Microsoft's own tutorial. No separate Azure Functions project needed.

### Plan requirement

The managed App Service backend is available on all plans including Free. The **Standard plan** ($9/month) is needed for custom auth roles — but not for hybrid Next.js itself.

### Cold-start behaviour

GitHub issue #1545 (opened Sept 2024, unresolved) and community reports confirm:
- First request after the managed App Service goes idle: **5+ seconds**.
- Subsequent requests within the active window: 200–300 ms.
- No always-on configuration available on the managed backend.

For the telemetry upload endpoint this is acceptable — the iOS app can tolerate a slow first response. For the admin UI this is liveable for a 1–3 person internal tool.

**Mitigation**: a scheduled keep-alive `GET /api/health` ping (GitHub Actions cron, every 5 minutes) can prevent the idle timeout if cold starts are unacceptable in practice.

### Limitations

- Next.js hybrid on SWA is **preview** as of early 2026. Use `output: 'standalone'` mode.
- Max app size: 250 MB.
- `navigationFallback` in `staticwebapp.config.json` unsupported — configure rewrites in `next.config.js`.
- Linked custom backends (standalone Azure Functions) are not supported alongside hybrid Next.js.
- SWA CLI does not support hybrid Next.js locally — use `next dev`.

### Recommendation

A single Azure SWA hybrid Next.js deployment serves both the admin UI and the telemetry API Route Handlers. No separate backend needed.

---

## Finding 3 — Database

| Option | Cost at near-zero volume | Schema | Admin query |
|---|---|---|---|
| **Neon serverless Postgres** | **Free** (0.5 GB, 100 CU-h/month) | Relational SQL | Full SQL |
| Azure Cosmos DB serverless | ~$0.25/million RUs, no free tier | JSON documents | Limited SQL dialect |
| Azure Table Storage | ~$0.045/GB/month | Key-value only | No joins |
| Azure PostgreSQL Flexible Server | ~$25+/month minimum (always-on compute) | Relational SQL | Full SQL |

**Neon serverless Postgres**
- Free tier: 0.5 GB storage, 100 CU-hours/month, scale-to-zero when idle. Permanent, no credit card required.
- At ~100 bytes/event, 0.5 GB holds ~5 million events before archiving.
- SQL means admin labelling queries and CSV export (`COPY (SELECT …) TO STDOUT WITH CSV`) are trivial.
- `@neondatabase/serverless` driver works in Next.js Route Handlers (edge and serverless compatible).
- Acquired by Databricks May 2025; pricing cut post-acquisition. First paid tier is usage-based with no fixed monthly floor.
- Default region `aws-us-east-1`; if SWA is in a European region, create the Neon project in `aws-eu-central-1`.

### Recommendation

**Neon serverless Postgres** on the free tier. Only option with a genuine zero-cost free tier at indie volumes; SQL makes the admin labelling + export UI straightforward.

---

## Finding 4 — iOS App Authentication

The iOS app sends anonymised telemetry to `POST /telemetry/batch`. This is machine-to-machine — OAuth is not appropriate.

### Options evaluated

**Static API key in a custom `X-Api-Key` header** *(recommended)*
- A single secret stored in the iOS Keychain (hardware-encrypted on-device, Apple-recommended for secrets).
- Server validates the header against a SWA environment variable (`TELEMETRY_API_KEY`).
- Risk: key can theoretically be extracted from the binary. For anonymised, non-PII telemetry this is acceptable — worst case is spam writes, mitigated by rate limiting and key rotation.
- Simplest to implement: one env var on the server, one Keychain write on the client.

**HMAC-signed requests** — prevents replay attacks but same extraction risk as static key, with more complexity. Not worth it for non-PII telemetry.

**Anonymous device token (UUID-based)** — reinventing OAuth for a case that doesn't need it.

**Apple App Attest** — hardware-attested proof of genuine iOS app; correct for payment APIs, complete overkill here.

### Recommendation

**Static `X-Api-Key` header stored in iOS Keychain.** Generate with `openssl rand -hex 32`. Store as `TELEMETRY_API_KEY` in SWA environment variables. Add per-`deviceId` rate limiting in the Route Handler to mitigate key-compromise spam. Rotation path: update env var and re-release app.

---

## Recommended Stack

Deploy a single **Next.js 15 hybrid app on Azure Static Web Apps Standard plan** (~$9/month). The Standard plan covers custom GitHub OAuth roles for admin access and preview environments for PRs — consistent with the TheCheapPowerCompany CI/CD pattern. Authenticate admins via **SWA built-in GitHub auth** with the portal Role Management blade: zero application code. Store telemetry events in **Neon serverless Postgres** (free tier): SQL enables filtering, labelling, and CSV export without a query-language learning curve. The iOS app authenticates `POST /telemetry/batch` with a **static `X-Api-Key` header stored in the iOS Keychain**. The only live concern is the **Next.js hybrid cold-start** (~5 seconds after idle): acceptable for an internal tool, but worth noting in the spec. A scheduled keep-alive ping can eliminate it if needed.

---

## Open Questions / Caveats

1. **Cold-start for admin UI** — acceptable for internal tool; mitigation is a keep-alive ping via GitHub Actions cron or paying for a dedicated App Service (S1, ~$75/month).
2. **Next.js hybrid preview status** — feature is marked "preview" by Microsoft; verify Route Handler behaviour when it GA's. Fallback: `output: 'export'` + separate Azure Functions v4 app.
3. **Neon + Azure region latency** — default Neon region is `aws-us-east-1`. If SWA is in a European region, create Neon project in `aws-eu-central-1`.
4. **GDPR cascade delete** — `DELETE /telemetry/{deviceId}` should also delete any labels associated with that device's events. Confirm cascade behaviour in the schema.
5. **SWA Standard plan cost** — $9/month required for custom `admin` role. Confirm acceptable before locking hosting cost.

---

## Sources

| Resource | URL |
|---|---|
| Next.js support on Azure SWA | https://learn.microsoft.com/en-us/azure/static-web-apps/nextjs |
| Deploy hybrid Next.js on Azure SWA | https://learn.microsoft.com/en-us/azure/static-web-apps/deploy-nextjs-hybrid |
| SWA Authentication and authorization | https://learn.microsoft.com/en-us/azure/static-web-apps/authentication-authorization |
| SWA Custom authentication (Standard plan / roles) | https://learn.microsoft.com/en-us/azure/static-web-apps/authentication-custom |
| Cold start issue #1545 (SWA GitHub) | https://github.com/Azure/static-web-apps/issues/1545 |
| NextAuth on SWA issue #1524 | https://github.com/Azure/static-web-apps/issues/1524 |
| NextAuth + Next.js 15 on SWA issue #12547 | https://github.com/nextauthjs/next-auth/issues/12547 |
| Neon plans | https://neon.com/docs/introduction/plans |
| Neon pricing | https://neon.com/pricing |
| Azure Cosmos DB serverless pricing | https://azure.microsoft.com/en-us/pricing/details/cosmos-db/serverless/ |
| Azure Cosmos DB free tier limitations | https://learn.microsoft.com/en-us/azure/cosmos-db/free-tier |
| Azure Table Storage pricing | https://azure.microsoft.com/en-us/pricing/details/storage/tables/ |
| Apple Keychain services | https://developer.apple.com/documentation/security/keychain-services |
| Apple App Attest vs static secrets | https://levelup.gitconnected.com/implementing-apple-app-attest-for-ios-api-security-no-more-static-secrets-952014ed5058 |
