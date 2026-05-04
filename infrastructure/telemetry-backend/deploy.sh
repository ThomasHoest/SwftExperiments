#!/usr/bin/env bash
# deploy.sh — provision or update the Voxio Telemetry Backend SWA
#
# Usage:
#   DATABASE_URL=<...> TELEMETRY_API_KEY=<...> ./deploy.sh
#
# This creates one SWA resource. The staging named environment is created
# automatically by the CI/CD workflow when deploying from the develop branch.
#
# Prerequisites: Azure CLI logged in (az login) with Contributor on the subscription.

set -euo pipefail

: "${DATABASE_URL:?Set DATABASE_URL before deploying}"
: "${TELEMETRY_API_KEY:?Set TELEMETRY_API_KEY before deploying}"

RESOURCE_GROUP="rg-voxio-telemetry"
LOCATION="westeurope"
DEPLOYMENT_NAME="voxio-telemetry-$(date +%Y%m%d%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Deploying Voxio Telemetry Backend"
echo "    Resource group : ${RESOURCE_GROUP}"
echo "    Location       : ${LOCATION}"

# ---------------------------------------------------------------------------
# Idempotent resource group
# ---------------------------------------------------------------------------

az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none

echo "==> Resource group ready."

# ---------------------------------------------------------------------------
# Bicep deployment
# ---------------------------------------------------------------------------

DEPLOY_OUTPUT=$(az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "${SCRIPT_DIR}/main.bicep" \
  --parameters "${SCRIPT_DIR}/production.bicepparam" \
  --query "properties.outputs" \
  --output json)

HOSTNAME=$(echo "$DEPLOY_OUTPUT" | jq -r '.hostname.value')
DEPLOYMENT_TOKEN=$(echo "$DEPLOY_OUTPUT" | jq -r '.deploymentToken.value')

# ---------------------------------------------------------------------------
# Post-deploy instructions
# ---------------------------------------------------------------------------

echo ""
echo "==> Deployment complete."
echo ""
echo "    SWA hostname : https://${HOSTNAME}"
echo ""
echo "    --- GitHub secret to set ---"
echo "    AZURE_STATIC_WEB_APPS_API_TOKEN = ${DEPLOYMENT_TOKEN}"
echo "    DATABASE_URL                    = (already in your env)"
echo "    STAGING_DATABASE_URL            = (already in your env)"
echo ""
echo "    --- Next steps ---"
echo "    1. Set the GitHub secrets above in: Settings → Secrets → Actions"
echo "    2. Run 'pnpm migrate:up' with DATABASE_URL to initialise the production schema."
echo "    3. Run 'pnpm migrate:up' with STAGING_DATABASE_URL to initialise the staging schema."
echo "    4. Push to main to trigger the first CI deploy."
echo ""
echo "    --- Staging DATABASE_URL override ---"
echo "    The staging named environment inherits the production DATABASE_URL by default."
echo "    To point it at the Neon staging branch:"
echo "    Azure portal → swa-voxio-telemetry → Configuration → (select staging environment)"
echo "    → Application settings → add DATABASE_URL = <STAGING_DATABASE_URL>"
