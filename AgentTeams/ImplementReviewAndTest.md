Create an agent team to implement one epic from the B&O Voice Controller
project. The epic ID and name will be supplied at the end of this prompt.

Spawn the following four teammates: Architect, Implementer, Test Writer,
and Reviewer. The Architect runs first and gates the others. Implementer
and Test Writer then run in parallel. Reviewer runs last.

All teammates have access to the four specification documents in
docs/specs/ and must read the relevant sections before starting.

Shared task list: use the Agent Teams built-in shared task list for all
status updates. Each teammate posts an entry on start and on completion.
File ownership is partitioned (see below) — there are no same-file edits
across teammates.

================================================================
ARCHITECT  —  Sonnet 4.6  —  read-only + write access to docs/adr/**
================================================================

Runs first. Implementer and Test Writer both block on the Architect's
PROCEED signal.

Read first:
- The relevant epic section in epics-and-tasks-bo-voice-control.md
- The functional spec sections for the user stories the epic covers
- The design spec sections for any UI work
- spec-command-parser-bo-voice-control.md if the epic touches E-03
- The architecture pattern decision recorded under T-0103 (e.g. MVVM +
  Coordinator or TCA) and any prior epic ADRs in docs/adr/
- The existing project structure under Sources/** to understand what
  patterns are already in place

Produce a short Architecture Decision Record at
docs/adr/E-XX-<epic-slug>.md covering:
- Decision: the architectural approach for this epic in 2–4 sentences
- Context: what constraints and prior decisions shape this epic
- Options considered: at least two, with one-line trade-offs each
- Rationale: why the chosen option wins given the constraints
- Consequences: what follow-on work or limitations this creates
- File-level plan: which new files/types this epic introduces, where
  they live in the folder structure, and which existing files they
  modify (this is the contract the Implementer follows)
- Public interface contract: the type signatures, protocols, or
  function shapes the Implementer must expose so the Test Writer can
  write tests against them in parallel
- Conflicts flagged: anything in the epic spec that contradicts an
  earlier ADR, the architecture pattern, or the design spec — call
  these out explicitly

Keep ADRs under one page. The point is to lock the interface contract
before parallel work starts, not to re-derive the spec.

Verdict (post to shared task list as the final line):
- `PROCEED` — Implementer and Test Writer may begin
- `REVISE SPEC` — surface to me; team halts until the spec is updated

File ownership: you own docs/adr/**. You may read everything but write
only there.

Post to the shared task list when done:
- The ADR file path
- The public interface contract section verbatim (so the Test Writer
  doesn't have to re-derive it)
- One-line verdict: PROCEED or REVISE SPEC

================================================================
IMPLEMENTER  —  Opus 4.6  —  write access to Sources/** and Tests/Unit/**
================================================================

Wait for the Architect's PROCEED signal.

Read first:
- The Architect's ADR for this epic (docs/adr/E-XX-<epic-slug>.md) —
  this is the authoritative file-level plan and interface contract
- The relevant epic section in epics-and-tasks-bo-voice-control.md
- The functional spec sections referenced by the epic's user stories
- The design spec sections for any UI work
- spec-command-parser-bo-voice-control.md if the epic touches E-03

Implement every task in the epic in dependency order, following the
ADR's file-level plan and matching the public interface contract
exactly. If you discover a real reason the contract must change, halt
and surface to the lead — do not silently deviate (the Test Writer is
already writing tests against that contract in parallel). Write production
code and unit tests together — unit tests live in Tests/Unit/** alongside
the code they cover. Run the unit test suite before posting completion.

After each task is complete, mark `[x]` next to its T-XXXX ID in
epics-and-tasks-bo-voice-control.md. Do not modify any other section of
that document.

File ownership: you own Sources/** and Tests/Unit/**. You must not touch
Tests/Integration/**, Tests/Acceptance/**, or any file under docs/specs/**
other than the checkbox updates above.

Post to the shared task list when done:
- The list of changed files
- Unit test results (pass/fail count)
- Any open questions or assumptions you had to make
- The single epic commit you created (one commit per epic, titled
  `E-XX: <epic name>`, with the T-XXXX task IDs in the body)

Do NOT commit until the Reviewer has approved.

================================================================
TEST WRITER  —  Sonnet 4.6  —  write access to Tests/Integration/** and Tests/Acceptance/**
================================================================

Start in parallel with the Implementer, after the Architect posts
PROCEED. Do not wait for code.

Read first:
- The Architect's ADR for this epic, especially the public interface
  contract section — write your tests against that contract so they
  don't depend on implementation details
- The relevant epic section in epics-and-tasks-bo-voice-control.md
- The functional spec acceptance criteria for every user story the epic covers
- The error states table in the functional spec
- The design spec for any UI behaviour assertions

While the Implementer codes, write integration and acceptance tests
against the public interfaces defined in the spec — not against the
implementation. Cover:
- Every acceptance criterion from the spec (one test minimum per criterion)
- Every error state in the error table that the epic touches
- Boundary values (volume 0, 1, 99, 100; empty favourite lists; speaker
  unreachable mid-command; etc.)

Once the Implementer posts changed files, run the full test suite
(unit + integration + acceptance). If a test fails because the
implementation is wrong, log it for the Reviewer — do not patch the
implementation yourself. If a test fails because the test is wrong,
fix the test.

File ownership: you own Tests/Integration/** and Tests/Acceptance/**.
You must not touch Sources/**, Tests/Unit/**, or docs/specs/**.

Post to the shared task list when done:
- The list of test files created
- Full suite pass/fail counts and any failing test names
- Coverage delta if available
- Any spec gaps you discovered (an acceptance criterion that's untestable
  as written, an error state with no defined trigger, etc.)

================================================================
REVIEWER  —  Haiku 4.5  —  read-only
================================================================

Wait until both the Implementer and the Test Writer have posted completion.

Use the project's existing reviewer.md agent definition as your operating
spec — same dimensions reviewed (correctness, security, performance,
readability, best practices), same severity levels, same output structure
(Summary / Issues / Positives / Verdict).

Review scope for this epic:
- Every file in the Implementer's changed-files list
- Every test file the Test Writer created
- Cross-check the implementation against the Architect's ADR — flag
  any deviation from the file-level plan or interface contract that
  was not surfaced and approved
- The epic checkbox updates in epics-and-tasks-bo-voice-control.md (verify
  every task in the epic is actually checked off)
- Cross-check: every acceptance criterion in the relevant user stories has
  at least one passing test that exercises it

Issue format (matches reviewer.md exactly):

  [SEVERITY] file:line — Title
  > Problem description and suggested fix.

Severity: CRITICAL | HIGH | MEDIUM | LOW | SUGGESTION

Verdict: ✅ Approve | ⚠️ Approve with minor changes | 🔁 Request changes | ❌ Reject

Post the structured review to the shared task list. If requesting changes,
list exactly which teammate must fix what before merge.

================================================================
COORDINATION RULES FOR THE LEAD
================================================================

Per-epic flow:
1. Architect runs first. Implementer and Test Writer are blocked.
2. When the Architect posts PROCEED, Implementer and Test Writer run
   in parallel. If the Architect posts REVISE SPEC, halt and surface
   to me — do not start the implementation.
3. Reviewer runs after both Implementer and Test Writer post completion.
4. Surface the Reviewer's verdict, the changed-files list, the ADR
   path, and the test results to me. Do not start the next epic until
   I reply with PROCEED.

Change-request loop:
- If the Reviewer returns 🔁 Request changes:
  - Route only the affected teammate(s) for rework — do not respawn the
    whole team.
  - Issues tagged to Sources/** or Tests/Unit/** go to the Implementer.
  - Issues tagged to Tests/Integration/** or Tests/Acceptance/** go to
    the Test Writer.
  - Issues spanning both go to both, sequentially: Implementer first,
    then Test Writer re-runs the suite.
  - After rework, the Reviewer re-reviews only the changed files (not
    the full epic).

Hard stop conditions — halt and surface to me, do not auto-rework:
- Architect verdict is REVISE SPEC.
- Any CRITICAL severity issue from the Reviewer.
- Test suite fails to run at all (compilation error, missing dependency).
- Implementer or Test Writer reports they cannot complete a task without
  a spec change, or that the ADR's interface contract needs to change
  mid-flight.
- Verdict is ❌ Reject.

Commit policy:
- One git commit per epic, created by the Implementer only after Reviewer
  approval.
- Commit title: `E-XX: <epic name>` (e.g. `E-02: Mozart API Integration`).
- Commit body: bullet list of all T-XXXX task IDs included.
- Do not commit work-in-progress, do not squash across epics.

Surface to me at end of epic:
- Reviewer verdict
- ADR path for this epic
- Final changed files list
- Test suite results (pass/fail counts, coverage if available)
- Open questions, spec gaps, or assumptions logged by any teammate
- Confirmation that the epic checkboxes are marked in
  epics-and-tasks-bo-voice-control.md

================================================================
EPIC TO IMPLEMENT
================================================================

Defined in : epics-and-tasks-telemetry-backend.md