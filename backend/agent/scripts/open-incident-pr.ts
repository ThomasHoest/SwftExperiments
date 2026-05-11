/**
 * Fetches the highest-occurrence open incident, asks Claude to propose a fix,
 * opens a GitHub draft PR, and links the PR back to the incident record.
 *
 * Usage: tsx agent/scripts/open-incident-pr.ts
 *
 * Required env vars:
 *   AGENT_API_KEY      — x-agent-key for /api/agent/* routes
 *   AGENT_API_BASE     — SWA hostname, e.g. https://voxio-prod.azurestaticapps.net
 *   GITHUB_TOKEN       — PAT with contents:write + pull_requests:write
 *   GITHUB_REPO        — owner/repo, e.g. T-Creative/SwftExperiments
 *   ANTHROPIC_API_KEY  — Anthropic API key (read by the SDK)
 */

import Anthropic from '@anthropic-ai/sdk'

// ---------------------------------------------------------------------------
// Env
// ---------------------------------------------------------------------------

function requireEnv(name: string): string {
  const val = process.env[name]
  if (!val) {
    console.error(`[open-incident-pr] missing required env var: ${name}`)
    process.exit(1)
  }
  return val
}

const AGENT_API_KEY = requireEnv('AGENT_API_KEY')
const AGENT_API_BASE = requireEnv('AGENT_API_BASE').replace(/\/$/, '')
const GITHUB_TOKEN = requireEnv('GITHUB_TOKEN')
const GITHUB_REPO = requireEnv('GITHUB_REPO')
// ANTHROPIC_API_KEY is picked up automatically by the SDK

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface IncidentSummary {
  fingerprint: string
  first_seen_at: string
  last_seen_at: string
  occurrence_count: number
  error_line: string
  status: string
  pr_url: string | null
  pr_number: number | null
}

interface OccurrenceDetail {
  id: string
  reported_at: string
  app_version: string
  os_version: string
  device_model: string
  context_lines: string[]
  breadcrumbs: string
}

interface IncidentDetail extends IncidentSummary {
  recent_occurrences: OccurrenceDetail[]
}

interface GitHubFileContent {
  path: string
  sha: string
  content: string
  encoding: string
}

interface GitHubBranch {
  commit: {
    sha: string
    commit: { tree: { sha: string } }
  }
  default_branch?: string
}

interface GitHubTreeItem {
  path: string
  type: string
}

interface GitHubTree {
  tree: GitHubTreeItem[]
  truncated: boolean
}

interface GitHubPR {
  html_url: string
  number: number
}

interface FileSource {
  path: string
  sha: string
  content: string
}

interface ProposedChange {
  path: string
  content: string
}

interface FixProposal {
  changes: ProposedChange[]
  commitMessage: string
  prBody: string
}

// ---------------------------------------------------------------------------
// Backend API helpers
// ---------------------------------------------------------------------------

async function agentGet(path: string): Promise<unknown> {
  const res = await fetch(`${AGENT_API_BASE}${path}`, {
    headers: { 'x-agent-key': AGENT_API_KEY },
  })
  if (!res.ok) {
    throw new Error(`Backend GET ${path} → ${res.status}: ${await res.text()}`)
  }
  return res.json()
}

async function agentPatch(path: string, body: unknown): Promise<void> {
  const res = await fetch(`${AGENT_API_BASE}${path}`, {
    method: 'PATCH',
    headers: {
      'x-agent-key': AGENT_API_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    throw new Error(`Backend PATCH ${path} → ${res.status}: ${await res.text()}`)
  }
}

// ---------------------------------------------------------------------------
// GitHub API helpers
// ---------------------------------------------------------------------------

const GH_BASE = `https://api.github.com/repos/${GITHUB_REPO}`
const GH_HEADERS = {
  Authorization: `Bearer ${GITHUB_TOKEN}`,
  Accept: 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
}

async function ghGet<T>(path: string): Promise<T> {
  const res = await fetch(`${GH_BASE}${path}`, { headers: GH_HEADERS })
  if (!res.ok) {
    throw new Error(`GitHub GET ${path} → ${res.status}: ${await res.text()}`)
  }
  return res.json() as Promise<T>
}

async function ghPost<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${GH_BASE}${path}`, {
    method: 'POST',
    headers: { ...GH_HEADERS, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    throw new Error(`GitHub POST ${path} → ${res.status}: ${await res.text()}`)
  }
  return res.json() as Promise<T>
}

async function ghPut<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${GH_BASE}${path}`, {
    method: 'PUT',
    headers: { ...GH_HEADERS, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    throw new Error(`GitHub PUT ${path} → ${res.status}: ${await res.text()}`)
  }
  return res.json() as Promise<T>
}

// ---------------------------------------------------------------------------
// Fetch all open incidents (paginated)
// ---------------------------------------------------------------------------

async function fetchAllOpenIncidents(): Promise<IncidentSummary[]> {
  const all: IncidentSummary[] = []
  let cursor: string | null = null
  do {
    const qs = cursor ? `?status=open&cursor=${encodeURIComponent(cursor)}` : '?status=open'
    const page = (await agentGet(`/api/agent/incidents${qs}`)) as {
      incidents: IncidentSummary[]
      nextCursor: string | null
    }
    all.push(...page.incidents)
    cursor = page.nextCursor
  } while (cursor !== null)
  return all
}

// ---------------------------------------------------------------------------
// Extract candidate Swift filenames from log text.
//
// Two strategies, applied in order and merged:
//   1. Explicit file references: AVService.swift:181
//   2. Module tags:              [mDNS], [WS:...], [HomeView] → try Tag.swift
//
// Tags are pulled from the error_line first, then from ERROR-level context
// lines, then from all context lines. Results are capped at MAX_SOURCE_FILES
// to keep the Claude prompt manageable.
// ---------------------------------------------------------------------------

const MAX_SOURCE_FILES = 4

const SWIFT_REF_RE = /\b([A-Za-z0-9_]+\.swift):\d+\b/g
// Matches [Tag] or [Tag:anything] — stops before : or ]
// Requires at least 3 chars and PascalCase or known acronym (starts uppercase or is all-caps acronym)
const MODULE_TAG_RE = /\[([A-Za-z][A-Za-z0-9_-]{2,})(?::[^\]]+)?\]/g
const SKIP_TAGS = new Set([
  'INFO', 'ERROR', 'WARN', 'VERBOSE', 'DEBUG', 'IP',
  'TRANSCRIPTION', 'UUID', 'JID',           // anonymiser placeholders
])

function extractModuleTags(text: string): string[] {
  const seen = new Set<string>()
  for (const m of text.matchAll(SWIFT_REF_RE)) seen.add(m[1])
  for (const m of text.matchAll(MODULE_TAG_RE)) {
    const tag = m[1]
    // Skip log-level noise, anonymiser placeholders, and all-lowercase sub-labels
    if (SKIP_TAGS.has(tag.toUpperCase())) continue
    if (tag === tag.toLowerCase()) continue   // e.g. "pers", "clear", "kw"
    seen.add(tag)
  }
  return [...seen]
}

function candidatesFromIncident(errorLine: string, contextLines: string[]): string[] {
  const ordered: string[] = []
  const seen = new Set<string>()

  const add = (tags: string[]) => {
    for (const t of tags) {
      if (!seen.has(t)) { seen.add(t); ordered.push(t) }
    }
  }

  // Primary: error_line tags
  add(extractModuleTags(errorLine))
  // Secondary: other ERROR lines in context
  add(extractModuleTags(contextLines.filter(l => l.includes('[ERROR]')).join('\n')))
  // Tertiary: all context lines
  add(extractModuleTags(contextLines.join('\n')))

  return ordered
}

// ---------------------------------------------------------------------------
// Resolve module tags / filenames to full repo paths via the git tree.
// For each tag T, tries (in order):
//   1. Exact:  T.swift
//   2. Fuzzy:  any .swift whose base name (without .swift) contains T
//              case-insensitively, or whose T contains the base name.
// ---------------------------------------------------------------------------

async function resolveFilePaths(
  candidates: string[],
  defaultBranch: string,
): Promise<Map<string, string>> {
  const branch = await ghGet<GitHubBranch>(`/branches/${defaultBranch}`)
  const treeSha = branch.commit.commit.tree.sha
  const tree = await ghGet<GitHubTree>(`/git/trees/${treeSha}?recursive=1`)

  if (tree.truncated) {
    console.warn('[open-incident-pr] git tree was truncated — some files may not be found')
  }

  const swiftFiles = tree.tree.filter(
    (item) => item.type === 'blob' && item.path.endsWith('.swift'),
  )

  // tag → full repo path
  const pathMap = new Map<string, string>()

  for (const candidate of candidates) {
    if (pathMap.size >= MAX_SOURCE_FILES) break

    // Strip .swift suffix if already present (from explicit file refs)
    const baseName = candidate.endsWith('.swift')
      ? candidate.slice(0, -6)
      : candidate
    const candidateLower = baseName.toLowerCase()

    // 1. Exact filename match (case-sensitive)
    const exact = swiftFiles.find(
      (f) => f.path.split('/').pop() === `${baseName}.swift`,
    )
    if (exact && !pathMap.has(exact.path)) {
      pathMap.set(candidate, exact.path)
      continue
    }

    // 2. Case-insensitive contains match
    const fuzzy = swiftFiles.find((f) => {
      const fileLower = f.path.split('/').pop()!.slice(0, -6).toLowerCase()
      return (
        !pathMap.has(f.path) &&
        (fileLower.includes(candidateLower) || candidateLower.includes(fileLower))
      )
    })
    if (fuzzy) pathMap.set(candidate, fuzzy.path)
  }

  return pathMap
}

// ---------------------------------------------------------------------------
// Read source files (returns content + blob SHA for updating)
// ---------------------------------------------------------------------------

async function readSourceFiles(paths: string[]): Promise<FileSource[]> {
  const sources: FileSource[] = []
  for (const path of paths) {
    const data = await ghGet<GitHubFileContent>(`/contents/${path}`)
    const content = Buffer.from(data.content.replace(/\n/g, ''), 'base64').toString('utf-8')
    sources.push({ path, sha: data.sha, content })
  }
  return sources
}

// ---------------------------------------------------------------------------
// Ask Claude to propose a fix
// ---------------------------------------------------------------------------

async function composeFix(
  incident: IncidentSummary,
  detail: IncidentDetail,
  sources: FileSource[],
): Promise<FixProposal> {
  const client = new Anthropic()
  const first = detail.recent_occurrences[0]
  const contextLines = first?.context_lines.join('\n') ?? '(none)'
  const breadcrumbs = first?.breadcrumbs ?? '(none)'

  const sourceBlocks = sources
    .map((s) => `### ${s.path}\n\`\`\`swift\n${s.content}\n\`\`\``)
    .join('\n\n')

  const prompt = `You are a senior iOS Swift engineer reviewing a production error incident in the Voxio app.

## Incident
- Fingerprint: ${incident.fingerprint}
- Occurrences: ${incident.occurrence_count}
- Error: ${incident.error_line}
- Breadcrumbs (navigation path): ${breadcrumbs}

## Context lines (device log near the error, oldest first)
${contextLines}

## Source files referenced by the error
${sourceBlocks}

Propose a minimal, safe fix. Return ONLY valid JSON — no markdown fences, no extra text — matching this exact shape:
{
  "changes": [
    {
      "path": "full/repo/path/to/File.swift",
      "content": "complete new file content"
    }
  ],
  "commitMessage": "Fix: one-line description under 72 chars",
  "prBody": "## What\\n\\nDescribe the fix.\\n\\n## Why\\n\\nExplain the root cause."
}

Rules:
- Only change what is needed to address this specific error.
- Return the COMPLETE new file content for every changed file (the GitHub API replaces the whole file).
- Do NOT include markdown fences inside the JSON string values.
- If you cannot determine a safe, targeted fix, return {"changes":[],"commitMessage":"","prBody":""}.`

  const response = await client.messages.create({
    model: 'claude-opus-4-7',
    max_tokens: 16000,
    messages: [{ role: 'user', content: prompt }],
  })

  const text = response.content[0]?.type === 'text' ? response.content[0].text : ''

  const jsonMatch = text.match(/\{[\s\S]*\}/)
  if (!jsonMatch) {
    console.warn('[open-incident-pr] Claude response contained no JSON')
    return { changes: [], commitMessage: '', prBody: '' }
  }

  try {
    return JSON.parse(jsonMatch[0]) as FixProposal
  } catch {
    console.warn('[open-incident-pr] failed to parse Claude JSON response')
    return { changes: [], commitMessage: '', prBody: '' }
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  // Step 1 — fetch all open incidents and pick the highest-occurrence one
  console.log('[open-incident-pr] fetching open incidents...')
  const incidents = await fetchAllOpenIncidents()

  if (incidents.length === 0) {
    console.log('[open-incident-pr] no open incidents')
    process.exit(0)
  }

  incidents.sort((a, b) => b.occurrence_count - a.occurrence_count)
  const incident = incidents[0]
  console.log(
    `[open-incident-pr] top incident: ${incident.fingerprint} (${incident.occurrence_count} occurrences)`,
  )

  // Step 2 — fetch full detail
  const detail = (await agentGet(`/api/agent/incidents/${incident.fingerprint}`)) as IncidentDetail

  // Step 3 — extract module tags / file references from the error and context
  const firstOcc = detail.recent_occurrences[0]
  const contextLines = firstOcc?.context_lines ?? []
  const candidates = candidatesFromIncident(incident.error_line, contextLines)

  if (candidates.length === 0) {
    console.log('[open-incident-pr] no source files referenced in error')
    process.exit(0)
  }

  console.log(`[open-incident-pr] candidates: ${candidates.join(', ')}`)

  // Step 4 — read source files from GitHub
  const repoInfo = await ghGet<{ default_branch: string }>('')
  const defaultBranch = repoInfo.default_branch

  const pathMap = await resolveFilePaths(candidates, defaultBranch)

  if (pathMap.size === 0) {
    console.log('[open-incident-pr] no source files referenced in error')
    process.exit(0)
  }

  const sources = await readSourceFiles([...pathMap.values()])
  console.log(`[open-incident-pr] read ${sources.length} source file(s)`)

  // Step 5 — ask Claude for a fix
  console.log('[open-incident-pr] composing fix with Claude...')
  const fix = await composeFix(incident, detail, sources)

  if (fix.changes.length === 0) {
    console.log('[open-incident-pr] no fix generated — leaving incident open')
    process.exit(0)
  }

  // Only commit changes for files we actually read (guards against hallucinated paths)
  const shaMap = new Map(sources.map((s) => [s.path, s.sha]))
  const validChanges = fix.changes.filter((c) => {
    if (!shaMap.has(c.path)) {
      console.warn(`[open-incident-pr] skipping unknown path in fix: ${c.path}`)
      return false
    }
    return true
  })

  if (validChanges.length === 0) {
    console.log('[open-incident-pr] no valid file changes after path validation')
    process.exit(0)
  }

  // Step 6a — create branch incident/<fingerprint>
  const branchName = `incident/${incident.fingerprint}`
  console.log(`[open-incident-pr] creating branch ${branchName}...`)

  const headBranch = await ghGet<GitHubBranch>(`/branches/${defaultBranch}`)
  const headSha = headBranch.commit.sha

  await ghPost('/git/refs', {
    ref: `refs/heads/${branchName}`,
    sha: headSha,
  })

  // Step 6b — commit each changed file
  for (const change of validChanges) {
    console.log(`[open-incident-pr] committing ${change.path}...`)
    await ghPut(`/contents/${change.path}`, {
      message: fix.commitMessage,
      content: Buffer.from(change.content, 'utf-8').toString('base64'),
      sha: shaMap.get(change.path),
      branch: branchName,
    })
  }

  // Step 6c — open draft PR
  const prTitle = `Fix incident ${incident.fingerprint}: ${incident.error_line.slice(0, 60)}`
  const contextPreview = firstOcc?.context_lines.slice(0, 5).join('\n') ?? '(none)'

  const prBody = `${fix.prBody}

---

**Incident fingerprint:** \`${incident.fingerprint}\`
**Occurrences:** ${incident.occurrence_count}
**Breadcrumbs:** ${firstOcc?.breadcrumbs ?? 'unknown'}

**Context (first 5 log lines):**
\`\`\`
${contextPreview}
\`\`\`

*Auto-generated — [view incident](${AGENT_API_BASE}/api/agent/incidents/${incident.fingerprint})*`

  const pr = await ghPost<GitHubPR>('/pulls', {
    title: prTitle,
    body: prBody,
    head: branchName,
    base: defaultBranch,
    draft: true,
  })

  console.log(`[open-incident-pr] PR opened: ${pr.html_url}`)

  // Step 7 — link PR back to the incident
  await agentPatch(`/api/agent/incidents/${incident.fingerprint}`, {
    status: 'investigating',
    pr_url: pr.html_url,
    pr_number: pr.number,
  })

  console.log(`[open-incident-pr] incident ${incident.fingerprint} → investigating`)
}

main().catch((err: unknown) => {
  const msg = err instanceof Error ? err.message : String(err)
  console.error(`[open-incident-pr] fatal: ${msg}`)
  process.exit(1)
})
