# ADR-E44 — Admin Authentication and Route Protection

**Status:** Accepted
**Date:** 2026-05-04
**Parent ADRs:** ADR-E41, ADR-E43

---

## 1. Decision

Gate `/admin/*` and `/api/admin/*` to `allowedRoles: ["admin"]` via SWA's built-in route rules in `staticwebapp.config.json`, using SWA's pre-configured GitHub OAuth provider (no custom OAuth app, no `auth` block in the config). Add a `getClientPrincipal` helper at `src/lib/auth/clientPrincipal.ts` that accepts a `Headers` object — enabling use from both Server Components (via `import { headers } from 'next/headers'`) and Route Handlers. Admin UI pages (`layout.tsx`, `page.tsx`, `access-denied/page.tsx`) are placed under root `app/admin/` (not `src/app/admin/`). The `/admin/access-denied` rewrite is handled by a dedicated `app/admin/access-denied/page.tsx`.

---

## 2. Context

**From ADR-E41 (binding):**
- SWA Standard plan is mandatory; Standard is required for custom role assignment via the Azure portal Roles Management UI.
- `navigationFallback` must not appear in `staticwebapp.config.json`.
- Auth rules in `staticwebapp.config.json` are the sole enforcement mechanism — zero application auth code.

**From ADR-E43 (binding):**
- Split-root layout: `src/lib/` for shared code, root `app/api/` for Route Handlers.
- `next.config.ts` has no `experimental.srcDir`, no `dir` override. The root `app/` directory is the active App Router root.
- `@/*` resolves to `./src/*` (tsconfig and vitest both confirmed).
- `src/lib/auth.ts` exists; `src/lib/auth/clientPrincipal.ts` is a distinct path and does not conflict.

**Platform constraint confirmed from filesystem:**
- `backend/app/layout.tsx` and `backend/app/page.tsx` are committed. App Router root is `app/`.
- Next.js 15 cannot have two App Router roots — `src/app/` cannot be created alongside `app/`.

---

## 3. Options Considered

### 3A. GitHub OAuth mode

**Pre-configured SWA provider (chosen):** No `auth.identityProviders` block. SWA uses its managed GitHub OAuth app. Login URL is `/.auth/login/github`. Role assignment via Azure portal Role Management blade. No OAuth credential storage required.

**Custom OAuth app (rejected):** Requires a GitHub OAuth App, `clientId`/`clientSecret` SWA settings, and an `auth.identityProviders.gitHub.registration` block. Needed only for custom callback URLs or specific scopes — neither applies here. Adds secret rotation burden with no benefit.

**Platform constraint:** When using the pre-configured provider the `auth` block must be entirely absent. Including an `auth` block with an empty `gitHub` registration causes a SWA deploy validation error.

### 3B. `getClientPrincipal` signature

**Accept `Headers` (chosen):**
```ts
// Server Component:
import { headers } from 'next/headers'
const principal = getClientPrincipal(await headers())

// Route Handler:
const principal = getClientPrincipal(request.headers)
```
`Headers` is the lowest common denominator satisfying both callers. Server Components have no `Request` object — they access headers via `next/headers`. The spec T-4403 says `getClientPrincipal(request: Request)` but this is a platform error; `Headers` is the correct parameter type.

**Accept `Request` (rejected):** Forces Server Components to synthesise a fake Request object.

### 3C. Admin page placement

**Root `app/admin/` (chosen — hard platform constraint):** Next.js 15 supports only one App Router directory. `app/` is the committed root. Creating `src/app/` would require `next.config.ts` changes that break the existing `app/api/` route handlers from E-43.

**`src/app/admin/` (rejected):** Platform violation.

### 3D. `/admin/access-denied` route

**Dedicated `app/admin/access-denied/page.tsx` (chosen):** The SWA `responseOverrides[403]` rewrites to `/admin/access-denied`. A dedicated page at that exact path is cleaner and means `app/admin/page.tsx` does not need to infer its own render context from the URL. The `access-denied` page is static — it must not attempt to read the `ClientPrincipal` for gating (the user may not have a principal at all on a 403).

---

## 4. Rationale

Pre-configured GitHub provider eliminates all OAuth credential management while satisfying the single-admin use case. The `Headers`-parameter signature is the platform-idiomatic choice for Next.js 15 App Router — `import { headers } from 'next/headers'` is the documented Server Component pattern. Placing admin pages under root `app/admin/` is a hard platform constraint, not a preference. The dedicated access-denied page keeps routing declarative and the page logic simple.

---

## 5. Consequences

- Role assignment is entirely manual (Azure portal → SWA → Role Management). Document in runbook.
- `src/lib/auth.ts` and `src/lib/auth/clientPrincipal.ts` coexist. Never rename `auth.ts` to `auth/index.ts` — it would shadow the directory.
- Server Components (layout, pages) are not unit-testable with vitest. Only `getClientPrincipal` (pure function) is unit-tested. Pages are verified manually (T-4406).
- SWA `responseOverrides[401]` redirects ALL 401s to GitHub login, including future `/api/admin/*` Route Handlers. Machine-to-machine API callers will receive a 302 instead of a JSON 401. Acceptable for E-44 scope (human browser UI only).
- `vitest.config.ts` already has `resolve.alias` for `@/` — no change needed.

---

## 6. File-Level Plan

| File | Task | Description |
|---|---|---|
| `staticwebapp.config.json` | T-4401 | Add route rules for `/admin`, `/admin/*`, `/api/admin/*`; responseOverrides for 401 (→ `/.auth/login/github`) and 403 (→ `/admin/access-denied`); preserve existing globalHeaders; no `auth` block; no navigationFallback |
| `docs/decisions/auth.md` | T-4401 | Document pre-configured GitHub OAuth choice; warn against adding `auth` block; note C-3 (`auth.ts` rename hazard) |
| `docs/runbook-admin-roles.md` | T-4402 | Azure portal steps: SWA → Role Management → Invite → assign `admin` role; on/off-boarding procedure |
| `src/lib/auth/clientPrincipal.ts` | T-4403 | `getClientPrincipal(headers: Headers): ClientPrincipal \| null`; decodes `x-ms-client-principal` base64 JSON; null if header absent; throws if malformed |
| `app/admin/layout.tsx` | T-4404 | Server Component; top nav (Events, Stats, Export, Deletion); username from `getClientPrincipal(await headers())`; sign-out link; Tailwind; WCAG AA |
| `app/admin/page.tsx` | T-4405 | Server Component; null principal → sign-in prompt + GDPR notice; signed-in non-admin → access-denied message; admin → `redirect('/admin/events')` |
| `app/admin/access-denied/page.tsx` | T-4401/T-4405 | Static page for SWA 403 rewrite; access-denied message + sign-out link; no principal access |
| `tests/unit/clientPrincipal.test.ts` | T-4403 | Missing header → null; valid base64 JSON → typed object; malformed base64 → throws; missing required fields → throws |

---

## 7. Public Interface Contract

### `staticwebapp.config.json` (final merged shape)

```json
{
  "globalHeaders": {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "strict-origin-when-cross-origin"
  },
  "routes": [
    { "route": "/admin",      "allowedRoles": ["admin"] },
    { "route": "/admin/*",    "allowedRoles": ["admin"] },
    { "route": "/api/admin/*","allowedRoles": ["admin"] }
  ],
  "responseOverrides": {
    "401": { "redirect": "/.auth/login/github", "statusCode": 302 },
    "403": { "rewrite": "/admin/access-denied" }
  }
}
```

No `navigationFallback`. No `auth` block.

### `getClientPrincipal` contract

```ts
export interface ClientPrincipal {
  identityProvider: 'github'
  userId: string
  userDetails: string   // GitHub username
  userRoles: string[]   // includes 'admin' for invited admins
}

export function getClientPrincipal(headers: Headers): ClientPrincipal | null
// Returns null  → x-ms-client-principal header absent
// Throws Error  → header present but malformed or missing required fields
```

### SWA auth URLs (built-in, no Route Handler needed)

| Action | URL |
|---|---|
| Sign in with GitHub | `/.auth/login/github` |
| Sign out | `/.auth/logout?post_logout_redirect_uri=/` |
| Current user JSON | `/.auth/me` |

---

## 8. Conflicts Flagged

**C-1 (BLOCKING — spec correction):** T-4403 specifies `getClientPrincipal(request: Request)` but the caller in T-4404 is a Server Component with no `Request`. Changed to `getClientPrincipal(headers: Headers)`. Implementer must not follow the spec signature literally.

**C-2 (BLOCKING — platform constraint):** Spec T-4404/T-4405 reference `src/app/admin/`. Invalid — Next.js 15 cannot have two App Router roots. All admin pages go under `app/admin/`. Do not create `src/app/`.

**C-3 (non-blocking):** Never rename `src/lib/auth.ts` to `src/lib/auth/index.ts` — would shadow the `src/lib/auth/` directory. Document in `docs/decisions/auth.md`.

**C-4 (non-blocking):** `responseOverrides[401]` redirects all 401s to GitHub login, including future `/api/admin/*` Route Handlers. Machine-to-machine callers get 302 instead of JSON 401. Acceptable for E-44 scope; revisit if machine callers are added.

**C-5 (non-blocking):** Users who navigate directly to `/admin/access-denied` while logged in as admin will see the access-denied page. The page must not attempt role-gating — it is purely informational.

---

**VERDICT: PROCEED**
