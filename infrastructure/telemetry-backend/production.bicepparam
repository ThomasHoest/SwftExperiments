using './main.bicep'

// Secrets are read from environment variables at deploy time — never hardcode here.
param databaseUrl = readEnvironmentVariable('DATABASE_URL')
param telemetryApiKey = readEnvironmentVariable('TELEMETRY_API_KEY')

// Optional — set only during key rotation; leave blank otherwise.
// param telemetryApiKeyPrevious = readEnvironmentVariable('TELEMETRY_API_KEY_PREVIOUS')
