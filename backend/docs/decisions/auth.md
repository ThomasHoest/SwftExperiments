# Authentication Decision — Voxio Telemetry Admin

**Date:** 2026-05-04
**ADR:** E-44

---

## Decision: SWA Pre-Configured GitHub OAuth

We use Azure Static Web Apps' built-in (pre-configured) GitHub OAuth provider. No custom GitHub OAuth App is registered; SWA manages the OAuth credentials internally.

Login URL: `/.auth/login/github`
Logout URL: `/.auth/logout?post_logout_redirect_uri=/`
Current user: `/.auth/me`

Role assignment is performed manually via the Azure portal: SWA resource → Role Management → Invite.

---

## Why there is no `auth` block in `staticwebapp.config.json`

When using the SWA pre-configured GitHub provider, the `auth` block **must be entirely absent** from `staticwebapp.config.json`. Including an `auth` block — even an empty one — triggers a SWA deployment validation error because SWA interprets its presence as an attempt to register a custom provider, which requires a `clientId` and `clientSecret` registration entry.

Do not add any of the following:

```jsonc
// WRONG — causes deployment failure with pre-configured provider
{
  "auth": {
    "identityProviders": {
      "gitHub": { ... }
    }
  }
}
```

---

## C-3 Warning: Never rename `src/lib/auth.ts` to `src/lib/auth/index.ts`

`src/lib/auth.ts` is the API key helper (used by Route Handlers).
`src/lib/auth/clientPrincipal.ts` is the SWA principal decoder (used by Server Components).

These two paths coexist safely:
- `@/lib/auth` resolves to `src/lib/auth.ts`
- `@/lib/auth/clientPrincipal` resolves to `src/lib/auth/clientPrincipal.ts`

If `auth.ts` were renamed to `auth/index.ts`, Node module resolution would make `@/lib/auth` resolve to the directory index, shadowing the intent of the original `auth.ts` and potentially breaking all Route Handlers that import `requireApiKey`. **Never perform this rename.**

---

## Route Protection Summary

All route enforcement is in `staticwebapp.config.json`, not in application code:

| Route pattern | Required role |
|---|---|
| `/admin` | `admin` |
| `/admin/*` | `admin` |
| `/api/admin/*` | `admin` |

Unauthenticated requests (401) are redirected to `/.auth/login/github`.
Authenticated but unauthorised requests (403) are rewritten to `/admin/access-denied`.
