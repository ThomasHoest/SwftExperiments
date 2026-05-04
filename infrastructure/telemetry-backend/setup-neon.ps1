# setup-neon.ps1 — create the Neon project and branches for Voxio Telemetry
#
# Usage:
#   $env:NEON_API_KEY = '<key>'
#   .\setup-neon.ps1
#
# What this does (all operations are idempotent):
#   1. Creates the Neon project 'voxio-telemetry' in aws-eu-central-1 (free tier).
#   2. Retrieves the main branch connection string  -> DATABASE_URL.
#   3. Creates a 'staging' branch from main         -> STAGING_DATABASE_URL.
#   4. Prints the values to set as GitHub secrets.
#
# Prerequisites:
#   neonctl  — npm install -g neonctl
#   NEON_API_KEY — generate at: neon.tech -> Account -> API Keys

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:NEON_API_KEY) { throw 'Set $env:NEON_API_KEY before running this script' }

$ProjectName = 'voxio-telemetry'
$Region      = 'aws-eu-central-1'

# ---------------------------------------------------------------------------
# Verify neonctl is available
# ---------------------------------------------------------------------------

if (-not (Get-Command neonctl -ErrorAction SilentlyContinue)) {
    throw 'neonctl not found. Install it with: npm install -g neonctl'
}

Write-Host "==> Setting up Neon database — project: $ProjectName"

# ---------------------------------------------------------------------------
# Find or create the project (idempotent)
# ---------------------------------------------------------------------------

$ProjectsJson = neonctl projects list --api-key $env:NEON_API_KEY --output json | ConvertFrom-Json
$Project      = $ProjectsJson.projects | Where-Object { $_.name -eq $ProjectName } | Select-Object -First 1

if ($Project) {
    $ProjectId = $Project.id
    Write-Host "==> Project '$ProjectName' already exists (id: $ProjectId)."
}
else {
    Write-Host "==> Creating project '$ProjectName' in $Region..."
    $Created   = neonctl projects create --name $ProjectName --region-id $Region --api-key $env:NEON_API_KEY --output json | ConvertFrom-Json
    $ProjectId = $Created.project.id
    Write-Host "==> Project created (id: $ProjectId)."
}

# ---------------------------------------------------------------------------
# Main branch connection string -> DATABASE_URL
# ---------------------------------------------------------------------------

$DatabaseUrl = neonctl connection-string `
    --project-id $ProjectId `
    --branch main `
    --api-key $env:NEON_API_KEY `
    --output json | ConvertFrom-Json

Write-Host '==> Main branch connection string retrieved.'

# ---------------------------------------------------------------------------
# Find or create the staging branch (idempotent)
# ---------------------------------------------------------------------------

$BranchesJson   = neonctl branches list --project-id $ProjectId --api-key $env:NEON_API_KEY --output json | ConvertFrom-Json
$StagingBranch  = $BranchesJson.branches | Where-Object { $_.name -eq 'staging' } | Select-Object -First 1

if ($StagingBranch) {
    Write-Host "==> Staging branch already exists (id: $($StagingBranch.id))."
}
else {
    Write-Host '==> Creating staging branch from main...'
    neonctl branches create `
        --project-id $ProjectId `
        --name staging `
        --parent main `
        --api-key $env:NEON_API_KEY `
        --output none | Out-Null
    Write-Host '==> Staging branch created.'
}

$StagingDatabaseUrl = neonctl connection-string `
    --project-id $ProjectId `
    --branch staging `
    --api-key $env:NEON_API_KEY `
    --output json | ConvertFrom-Json

Write-Host '==> Staging branch connection string retrieved.'

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '==> Neon setup complete.'
Write-Host ''
Write-Host "    Project id : $ProjectId"
Write-Host "    Console    : https://console.neon.tech/app/projects/$ProjectId"
Write-Host ''
Write-Host '    --- GitHub secrets to set ---'
Write-Host "    DATABASE_URL         = $DatabaseUrl"
Write-Host "    STAGING_DATABASE_URL = $StagingDatabaseUrl"
Write-Host ''
Write-Host '    --- Next steps ---'
Write-Host '    1. Set the GitHub secrets above in: Settings -> Secrets -> Actions'
Write-Host '    2. Run deploy.ps1 to provision the Azure SWA (it needs DATABASE_URL).'
Write-Host '    3. Run ''pnpm migrate:up'' with DATABASE_URL to create the schema on main.'
Write-Host '    4. Run ''pnpm migrate:up'' with STAGING_DATABASE_URL to create the schema on staging.'
Write-Host ''
Write-Host '    To create a personal dev branch:'
Write-Host "      neonctl branches create --project-id $ProjectId --name dev/<your-username> --parent main --api-key `$env:NEON_API_KEY"
