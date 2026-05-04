# Runbook: Admin Role Management

**System:** Voxio Telemetry — Azure Static Web Apps
**ADR:** E-44

---

## Overview

Admin access to the Voxio Telemetry dashboard is granted via Azure Static Web Apps Role Management. Access is restricted to GitHub accounts explicitly invited by name. No self-service sign-up is possible.

Cost policy: maximum ~5 admin accounts at any time (SWA Standard plan; additional roles have no direct cost but are operationally bounded).

---

## Adding an Admin

1. Open the [Azure portal](https://portal.azure.com).
2. Navigate to the SWA resource: **Resource Groups → voxio-telemetry → Static Web App**.
3. In the left sidebar, click **Role Management**.
4. Click **Invite**.
5. Fill in the form:
   - **Identity provider:** GitHub
   - **GitHub username:** enter the exact GitHub username of the person (case-insensitive, but use their display casing for clarity)
   - **Role:** `admin`
6. Click **Generate** to create the invite link.
7. Send the invite link to the person out-of-band (email, Slack, etc.). The link expires after a short window.
8. The person must open the link and accept. After acceptance, their GitHub account is granted the `admin` role and they can access `/admin`.

### Verifying access

Ask the new admin to open `https://<swa-hostname>/admin`. On first visit they will be prompted to sign in with GitHub. After authenticating they should be redirected to `/admin/events`.

---

## Removing an Admin

1. Open the Azure portal and navigate to the SWA resource.
2. Click **Role Management** in the left sidebar.
3. Find the user in the list (filter by GitHub identity).
4. Click the **delete** (trash) icon next to their entry.
5. Confirm the removal.

The removal takes effect immediately. The user's next request to `/admin/*` will receive a 403 and be shown the access-denied page.

### Off-boarding checklist

- [ ] Remove the user from Role Management (step above).
- [ ] Confirm the user no longer appears in the Role Management list.
- [ ] Notify the user that their access has been revoked.
- [ ] If the user had any in-flight exports or deletion requests, verify those completed (or cancel them) before removal.

---

## Audit

SWA does not provide a built-in audit log for role assignment. As a compensating control:
- Record all role additions and removals in the team access log (e.g., a shared Notion page or ticket in the project tracker).
- Include: date, GitHub username, action (added/removed), performed by.

---

## Troubleshooting

| Symptom | Likely cause | Resolution |
|---|---|---|
| User sees "Access Denied" after accepting invite | Role not yet propagated | Wait 60 seconds, then retry |
| Invite link expired | Link was not used promptly | Generate a new invite link |
| User cannot find the invite link | Link was lost | Generate a new invite link and resend |
| User sees GitHub 404 on login | Incorrect GitHub username | Re-invite with correct username |
| Role Management blade not visible | Insufficient Azure permissions | Request Owner or Contributor access to the SWA resource |
