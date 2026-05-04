@description('Azure region')
param location string = resourceGroup().location

@description('Production database connection string')
@secure()
param databaseUrl string

@description('Telemetry API key (current)')
@secure()
param telemetryApiKey string

@description('Telemetry API key (previous — for zero-downtime rotation)')
@secure()
param telemetryApiKeyPrevious string = ''

// ---------------------------------------------------------------------------
// Azure Static Web App
// ---------------------------------------------------------------------------

resource swa 'Microsoft.Web/staticSites@2023-01-01' = {
  name: 'swa-voxio-telemetry'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    // Workflow is managed in .github/workflows/backend-ci-cd.yml
    buildProperties: {
      appLocation: 'backend'
      outputLocation: ''
      apiLocation: ''
      skipGithubActionWorkflowGeneration: true
    }
  }
}

// ---------------------------------------------------------------------------
// Application settings (production — visible to all environments by default)
// Staging DATABASE_URL override: Azure portal → SWA → Configuration →
// select the staging environment → add DATABASE_URL pointing at the Neon staging branch.
// ---------------------------------------------------------------------------

resource swaAppSettings 'Microsoft.Web/staticSites/config@2023-01-01' = {
  parent: swa
  name: 'appsettings'
  properties: {
    DATABASE_URL: databaseUrl
    TELEMETRY_API_KEY: telemetryApiKey
    TELEMETRY_API_KEY_PREVIOUS: telemetryApiKeyPrevious
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('SWA hostname (no scheme) — e.g. polite-wave-12345.azurestaticapps.net')
output hostname string = swa.properties.defaultHostname

@description('Deployment token — set as AZURE_STATIC_WEB_APPS_API_TOKEN GitHub secret')
output deploymentToken string = swa.listSecrets().properties.apiKey
