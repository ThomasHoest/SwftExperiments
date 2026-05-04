#!/usr/bin/env bash
# setup-neon.sh — create the Neon project and branches for Voxio Telemetry
#
# Usage:
#   NEON_API_KEY=<key> ./setup-neon.sh
#
# What this does (all operations are idempotent):
#   1. Creates the Neon project 'voxio-telemetry' in aws-eu-central-1 (free tier).
#   2. Retrieves the main branch connection string  → DATABASE_URL.
#   3. Creates a 'staging' branch from main         → STAGING_DATABASE_URL.
#   4. Prints the values to set as GitHub secrets.
#
# Prerequisites:
#   curl, jq
#   NEON_API_KEY — generate at: neon.tech → Account → API Keys

set -euo pipefail

: "${NEON_API_KEY:?Set NEON_API_KEY before running this script}"
: "${NEON_ORG_ID:?Set NEON_ORG_ID before running this script (find it at: neon.tech → Settings → General)}"

NEON_API="https://console.neon.tech/api/v2"
PROJECT_NAME="voxio-telemetry"
REGION="aws-eu-central-1"
AUTH_HEADER="Authorization: Bearer ${NEON_API_KEY}"

neon_get()  { curl -sf -H "$AUTH_HEADER" "${NEON_API}${1}"; }
neon_post() { curl -sf -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" -d "${2}" "${NEON_API}${1}"; }

echo "==> Setting up Neon database — project: ${PROJECT_NAME}"

# ---------------------------------------------------------------------------
# Find or create the project (idempotent)
# ---------------------------------------------------------------------------

PROJECT_ID=$(neon_get "/projects?org_id=${NEON_ORG_ID}" \
  | jq -r --arg name "$PROJECT_NAME" '.projects[] | select(.name == $name) | .id' \
  | head -1)

if [[ -n "$PROJECT_ID" ]]; then
  echo "==> Project '${PROJECT_NAME}' already exists (id: ${PROJECT_ID})."
  MAIN_BRANCH_ID=$(neon_get "/projects/${PROJECT_ID}/branches" \
    | jq -r '.branches[] | select(.name == "main") | .id')
else
  echo "==> Creating project '${PROJECT_NAME}' in ${REGION}..."
  CREATE_RESPONSE=$(neon_post "/projects" \
    "{\"project\":{\"name\":\"${PROJECT_NAME}\",\"region_id\":\"${REGION}\",\"org_id\":\"${NEON_ORG_ID}\"}}")
  PROJECT_ID=$(echo "$CREATE_RESPONSE"    | jq -r '.project.id')
  MAIN_BRANCH_ID=$(echo "$CREATE_RESPONSE" | jq -r '.branch.id')
  echo "==> Project created (id: ${PROJECT_ID})."
fi

# ---------------------------------------------------------------------------
# Main branch connection string → DATABASE_URL
# ---------------------------------------------------------------------------

DATABASE_URL=$(neon_get "/projects/${PROJECT_ID}/connection_uri?branch_id=${MAIN_BRANCH_ID}&role_name=neondb_owner&database_name=neondb" \
  | jq -r '.uri')

echo "==> Main branch connection string retrieved."

# ---------------------------------------------------------------------------
# Find or create the staging branch (idempotent)
# ---------------------------------------------------------------------------

STAGING_BRANCH_ID=$(neon_get "/projects/${PROJECT_ID}/branches" \
  | jq -r '.branches[] | select(.name == "staging") | .id')

if [[ -n "$STAGING_BRANCH_ID" ]]; then
  echo "==> Staging branch already exists (id: ${STAGING_BRANCH_ID})."
else
  echo "==> Creating staging branch from main..."
  STAGING_RESPONSE=$(neon_post "/projects/${PROJECT_ID}/branches" \
    "{\"branch\":{\"name\":\"staging\",\"parent_id\":\"${MAIN_BRANCH_ID}\"},\"endpoints\":[{\"type\":\"read_write\"}]}")
  STAGING_BRANCH_ID=$(echo "$STAGING_RESPONSE" | jq -r '.branch.id')
  echo "==> Staging branch created (id: ${STAGING_BRANCH_ID})."
fi

STAGING_DATABASE_URL=$(neon_get "/projects/${PROJECT_ID}/connection_uri?branch_id=${STAGING_BRANCH_ID}&role_name=neondb_owner&database_name=neondb" \
  | jq -r '.uri')

echo "==> Staging branch connection string retrieved."

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

echo ""
echo "==> Neon setup complete."
echo ""
echo "    Project id : ${PROJECT_ID}"
echo "    Console    : https://console.neon.tech/app/projects/${PROJECT_ID}"
echo ""
echo "    --- GitHub secrets to set ---"
echo "    DATABASE_URL         = ${DATABASE_URL}"
echo "    STAGING_DATABASE_URL = ${STAGING_DATABASE_URL}"
echo ""
echo "    --- Next steps ---"
echo "    1. Set the GitHub secrets above in: Settings → Secrets → Actions"
echo "    2. Run deploy.sh to provision the Azure SWA (it needs DATABASE_URL)."
echo "    3. Run 'pnpm migrate:up' with DATABASE_URL to create the schema on main."
echo "    4. Run 'pnpm migrate:up' with STAGING_DATABASE_URL to create the schema on staging."
echo ""
echo "    To create a personal dev branch:"
echo "      BRANCH_NAME=dev/<your-username>"
echo "      curl -sf -X POST -H \"Authorization: Bearer \$NEON_API_KEY\" -H \"Content-Type: application/json\" \\"
echo "        -d \"{\\\"branch\\\":{\\\"name\\\":\\\"\$BRANCH_NAME\\\",\\\"parent_id\\\":\\\"${MAIN_BRANCH_ID}\\\"},\\\"endpoints\\\":[{\\\"type\\\":\\\"read_write\\\"}]}\" \\"
echo "        ${NEON_API}/projects/${PROJECT_ID}/branches | jq -r '.connection_uris[0].connection_uri'"
