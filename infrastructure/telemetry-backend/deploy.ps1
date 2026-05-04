# deploy.ps1 — provision or update the Voxio Telemetry Backend SWA
#
# Usage:
#   $env:DATABASE_URL = '<...>'; $env:TELEMETRY_API_KEY = '<...>'
#   .\deploy.ps1
#
# This creates one SWA resource. The staging named environment is created
# automatically by the CI/CD workflow when deploying from the develop branch.
#
# Prerequisites: Azure CLI logged in (az login) with Contributor on the subscription.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:DATABASE_URL)      { throw 'Set $env:DATABASE_URL before deploying' }
if (-not $env:TELEMETRY_API_KEY) { throw 'Set $env:TELEMETRY_API_KEY before deploying' }

$ResourceGroup  = 'rg-voxio-telemetry'
$Location       = 'westeurope'
$Timestamp      = Get-Date -Format 'yyyyMMddHHmmss'
$DeploymentName = "voxio-telemetry-$Timestamp"
$ScriptDir      = $PSScriptRoot

Write-Host '==> Deploying Voxio Telemetry Backend'
Write-Host "    Resource group : $ResourceGroup"
Write-Host "    Location       : $Location"

# ---------------------------------------------------------------------------
# Idempotent resource group
# ---------------------------------------------------------------------------

az group create `
    --name $ResourceGroup `
    --location $Location `
    --output none

Write-Host '==> Resource group ready.'

# ---------------------------------------------------------------------------
# Bicep deployment
# ---------------------------------------------------------------------------

$DeployOutputRaw = az deployment group create `
    --resource-group $ResourceGroup `
    --name $DeploymentName `
    --template-file "$ScriptDir\main.bicep" `
    --parameters "$ScriptDir\production.bicepparam" `
    --query 'properties.outputs' `
    --output json

$DeployOutput    = $DeployOutputRaw | ConvertFrom-Json
$Hostname        = $DeployOutput.hostname.value
$DeploymentToken = $DeployOutput.deploymentToken.value

# ---------------------------------------------------------------------------
# Post-deploy instructions
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '==> Deployment complete.'
Write-Host ''
Write-Host "    SWA hostname : https://$Hostname"
Write-Host ''
Write-Host '    --- GitHub secrets to set ---'
Write-Host "    AZURE_STATIC_WEB_APPS_API_TOKEN = $DeploymentToken"
Write-Host '    DATABASE_URL                    = (already in your env)'
Write-Host '    STAGING_DATABASE_URL            = (already in your env)'
Write-Host ''
Write-Host '    --- Next steps ---'
Write-Host '    1. Set the GitHub secrets above in: Settings -> Secrets -> Actions'
Write-Host '    2. Run ''pnpm migrate:up'' with DATABASE_URL to initialise the production schema.'
Write-Host '    3. Run ''pnpm migrate:up'' with STAGING_DATABASE_URL to initialise the staging schema.'
Write-Host '    4. Push to main to trigger the first CI deploy.'
Write-Host ''
Write-Host '    --- Staging DATABASE_URL override ---'
Write-Host '    The staging named environment inherits the production DATABASE_URL by default.'
Write-Host '    To point it at the Neon staging branch:'
Write-Host '    Azure portal -> swa-voxio-telemetry -> Configuration -> (select staging environment)'
Write-Host '    -> Application settings -> add DATABASE_URL = <STAGING_DATABASE_URL>'
