#!/usr/bin/env tsx
/**
 * open-incident-pr.ts
 *
 * Fetches the highest-occurrence open incident, identifies referenced Swift
 * source files, reads them via the GitHub API, and opens a draft PR with a
 * candidate fix. Patches the incident with the resulting PR URL and number.
 *
 * Required env vars: AGENT_API_KEY, AGENT_API_BASE, GITHUB_TOKEN, GITHUB_REPO
 *
 * Exit codes:
 *   0 — success, or no open incidents, or no source files referenced
 *   1 — API error (agent API or GitHub API)
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface AgentIncidentSummary {
  fingerprint: string
  first_seen_at: string
  last_seen_at: string
  occurrence_count: number
  error_line: string
  status: 'open' | 'investigating' | 'resolved' | 'ignored'
  pr_url: string | null
  pr_number: number | null
}

interface AgentIncidentsResponse {
  incidents: AgentIncidentSummary[]
  nextCursor: string | null
}

interface AgentIncidentOccurrence {
  id: string
  reported_at: string
  app_version: string
  os_version: string
  device_model: string
  context_lines: string[]
  breadcrumbs: string
}

interface AgentIncidentDetailResponse extends AgentIncidentSummary {
  recent_occurrences: AgentIncidentOccurrence[]
}

interface GitHubContentsResponse {
  content: string
  sha: string
  name: string
  path: string
}

interface GitHubRefResponse {
  ref: string
  object: { sha: string; type: string; url: string }
}

interface GitHubPRResponse {
  html_url: string
  number: number
}

// ---------------------------------------------------------------------------
// Environment validation
// ---------------------------------------------------------------------------

function requireEnv(name: string): string {
  const value = process.env[name]
  if (!value) {
    console.error(`ERROR: required environment variable ${name} is not set`)
    process.exit(1)
  }
  return value
}

const AGENT_API_KEY  = requireEnv('AGENT_API_KEY')
const AGENT_API_BASE = requireEnv('AGENT_API_BASE')
const GITHUB_TOKEN   = requireEnv('GITHUB_TOKEN')
const GITHUB_REPO    = requireEnv('GITHUB_REPO')

const GITHUB_API_BASE = 'https://api.github.com'

// ---------------------------------------------------------------------------
// Agent API helpers
// ---------------------------------------------------------------------------

async function agentFetch(path: string, options: RequestInit = {}): Promise<Response> {
  const url = `${AGENT_API_BASE}${path}`
  const res = await fetch(url, {
    ...options,
    headers: {
      'x-agent-key': AGENT_API_KEY,
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string> | undefined),
    },
  })
  return res
}

async function fetchAllOpenIncidents(): Promise<AgentIncidentSummary[]> {
  const all: AgentIncidentSummary[] = []
  let cursor: string | null = null

  do {
    const url = cursor
      ? `/api/agent/incidents?status=open&cursor=${encodeURIComponent(cursor)}`
      : `/api/agent/incidents?status=open`

    const res = await agentFetch(url)
    if (!res.ok) {
      console.error(`ERROR: GET /api/agent/incidents returned ${res.status}`)
      process.exit(1)
    }

    const data = (await res.json()) as AgentIncidentsResponse
    all.push(...data.incidents)
    cursor = data.nextCursor
  } while (cursor !== null)

  return all
}

async function fetchIncidentDetail(fingerprint: string): Promise<AgentIncidentDetailResponse> {
  const res = await agentFetch(`/api/agent/incidents/${fingerprint}`)
  if (!res.ok) {
    console.error(`ERROR: GET /api/agent/incidents/${fingerprint} returned ${res.status}`)
    process.exit(1)
  }
  return (await res.json()) as AgentIncidentDetailResponse
}

async function patchIncident(
  fingerprint: string,
  status: string,
  pr_url: string,
  pr_number: number
): Promise<void> {
  const res = await agentFetch(`/api/agent/incidents/${fingerprint}`, {
    method: 'PATCH',
    body: JSON.stringify({ status, pr_url, pr_number }),
  })
  if (!res.ok) {
    console.error(`ERROR: PATCH /api/agent/incidents/${fingerprint} returned ${res.status}`)
    process.exit(1)
  }
  console.log(`Incident ${fingerprint} patched: status=${status}, pr_url=${pr_url}`)
}

// ---------------------------------------------------------------------------
// GitHub API helpers
// ---------------------------------------------------------------------------

async function githubFetch(path: string, options: RequestInit = {}): Promise<Response> {
  const url = path.startsWith('https://') ? path : `${GITHUB_API_BASE}${path}`
  const res = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${GITHUB_TOKEN}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string> | undefined),
    },
  })
  return res
}

async function getDefaultBranchSha(repo: string): Promise<{ sha: string; defaultBranch: string }> {
  const repoRes = await githubFetch(`/repos/${repo}`)
  if (!repoRes.ok) {
    console.error(`ERROR: GET /repos/${repo} returned ${repoRes.status}`)
    process.exit(1)
  }
  const repoData = (await repoRes.json()) as { default_branch: string }
  const defaultBranch = repoData.default_branch

  const refRes = await githubFetch(`/repos/${repo}/git/refs/heads/${defaultBranch}`)
  if (!refRes.ok) {
    console.error(`ERROR: GET /repos/${repo}/git/refs/heads/${defaultBranch} returned ${refRes.status}`)
    process.exit(1)
  }
  const refData = (await refRes.json()) as GitHubRefResponse
  return { sha: refData.object.sha, defaultBranch }
}

async function getFileContents(repo: string, filePath: string): Promise<{ content: string; sha: string } | null> {
  const res = await githubFetch(`/repos/${repo}/contents/${filePath}`)
  if (res.status === 404) return null
  if (!res.ok) {
    console.error(`ERROR: GET /repos/${repo}/contents/${filePath} returned ${res.status}`)
    process.exit(1)
  }
  const data = (await res.json()) as GitHubContentsResponse
  const decoded = Buffer.from(data.content, 'base64').toString('utf-8')
  return { content: decoded, sha: data.sha }
}

async function createBranch(repo: string, branchName: string, sha: string): Promise<void> {
  const res = await githubFetch(`/repos/${repo}/git/refs`, {
    method: 'POST',
    body: JSON.stringify({ ref: `refs/heads/${branchName}`, sha }),
  })
  if (!res.ok) {
    const body = await res.text()
    console.error(`ERROR: POST /repos/${repo}/git/refs returned ${res.status}: ${body}`)
    process.exit(1)
  }
}

async function updateFile(
  repo: string,
  filePath: string,
  content: string,
  sha: string,
  branchName: string,
  message: string
): Promise<void> {
  const encoded = Buffer.from(content, 'utf-8').toString('base64')
  const res = await githubFetch(`/repos/${repo}/contents/${filePath}`, {
    method: 'PUT',
    body: JSON.stringify({
      message,
      content: encoded,
      sha,
      branch: branchName,
    }),
  })
  if (!res.ok) {
    const body = await res.text()
    console.error(`ERROR: PUT /repos/${repo}/contents/${filePath} returned ${res.status}: ${body}`)
    process.exit(1)
  }
}

async function createDraftPR(
  repo: string,
  title: string,
  body: string,
  head: string,
  base: string
): Promise<GitHubPRResponse> {
  const res = await githubFetch(`/repos/${repo}/pulls`, {
    method: 'POST',
    body: JSON.stringify({ title, body, head, base, draft: true }),
  })
  if (!res.ok) {
    const responseBody = await res.text()
    console.error(`ERROR: POST /repos/${repo}/pulls returned ${res.status}: ${responseBody}`)
    process.exit(1)
  }
  return (await res.json()) as GitHubPRResponse
}

// ---------------------------------------------------------------------------
// Source file extraction
// ---------------------------------------------------------------------------

// Matches patterns like: SomeFile.swift:42 or path/to/SomeFile.swift:42
const SWIFT_FILE_PATTERN = /([A-Za-z0-9_/.-]+\.swift)(?::\d+)?/g

function extractSourceFiles(text: string): Set<string> {
  const files = new Set<string>()
  const matches = text.matchAll(SWIFT_FILE_PATTERN)
  for (const match of matches) {
    files.add(match[1])
  }
  return files
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  console.log('Fetching open incidents...')
  const openIncidents = await fetchAllOpenIncidents()

  if (openIncidents.length === 0) {
    console.log('no open incidents')
    process.exit(0)
  }

  // Pick the highest occurrence_count
  openIncidents.sort((a, b) => b.occurrence_count - a.occurrence_count)
  const top = openIncidents[0]

  console.log(`Top incident: ${top.fingerprint} (${top.occurrence_count} occurrences)`)

  // Fetch detail
  const detail = await fetchIncidentDetail(top.fingerprint)

  // Identify candidate source files
  const candidateFiles = new Set<string>()
  for (const f of extractSourceFiles(detail.error_line)) candidateFiles.add(f)

  const firstOccurrence = detail.recent_occurrences[0]
  if (firstOccurrence) {
    for (const line of firstOccurrence.context_lines) {
      for (const f of extractSourceFiles(line)) candidateFiles.add(f)
    }
  }

  if (candidateFiles.size === 0) {
    console.log('no source files referenced in error')
    process.exit(0)
  }

  console.log(`Candidate source files: ${[...candidateFiles].join(', ')}`)

  // Read source files via GitHub API
  const fileContents: Map<string, { content: string; sha: string }> = new Map()
  for (const filePath of candidateFiles) {
    const contents = await getFileContents(GITHUB_REPO, filePath)
    if (contents) {
      fileContents.set(filePath, contents)
      console.log(`Read ${filePath} (${contents.content.length} chars)`)
    } else {
      console.log(`File not found in repo: ${filePath}`)
    }
  }

  if (fileContents.size === 0) {
    console.log('no source files referenced in error')
    process.exit(0)
  }

  // Get default branch SHA
  const { sha: defaultSha, defaultBranch } = await getDefaultBranchSha(GITHUB_REPO)

  // Create branch
  const branchName = `incident/${top.fingerprint}`
  console.log(`Creating branch ${branchName}...`)
  await createBranch(GITHUB_REPO, branchName, defaultSha)

  // Compose PR body
  const contextPreview = firstOccurrence
    ? firstOccurrence.context_lines.slice(0, 5).map((l) => `  ${l}`).join('\n')
    : '  (no context lines)'

  const prTitle = `Fix incident ${top.fingerprint}: ${detail.error_line.slice(0, 60)}`

  const prBody = `## Incident ${top.fingerprint}

**Detail:** ${AGENT_API_BASE}/api/agent/incidents/${top.fingerprint}
**Occurrences:** ${detail.occurrence_count}
**Breadcrumbs:** ${firstOccurrence?.breadcrumbs ?? '(none)'}

### Error line

\`\`\`
${detail.error_line}
\`\`\`

### First 5 context lines

\`\`\`
${contextPreview}
\`\`\`

---
*This draft PR was opened automatically by the Voxio incident agent.*`

  // Commit a placeholder change to each file (agent reasoning step)
  // In a real LLM-driven agent this would produce an actual fix patch.
  // Here we commit the file unchanged so the branch and PR infrastructure
  // can be exercised end-to-end.
  for (const [filePath, { content, sha }] of fileContents.entries()) {
    const commitMessage = `chore: candidate fix for incident ${top.fingerprint} in ${filePath}`
    await updateFile(GITHUB_REPO, filePath, content, sha, branchName, commitMessage)
    console.log(`Committed ${filePath}`)
  }

  // Open draft PR
  console.log('Opening draft PR...')
  const pr = await createDraftPR(GITHUB_REPO, prTitle, prBody, branchName, defaultBranch)
  console.log(`PR opened: ${pr.html_url}`)

  // Patch incident
  await patchIncident(top.fingerprint, 'investigating', pr.html_url, pr.number)
}

main().catch((err: unknown) => {
  const message = err instanceof Error ? err.message : String(err)
  console.error(`FATAL: ${message}`)
  process.exit(1)
})
