Create an agent team to work on a new feature

RESEARCHER
Investigate any unfamiliar technology, API, library, or constraint that
the feature touches before the spec is written. Search the web and read
local docs. Produce a structured findings summary with sources and a
recommended approach. Post findings to the shared task list when done so
the Spec Writer can read them before drafting.

ARCHITECT
Read the spec and the existing codebase architecture (/Specifications/*, CLAUDE.md). Validate the design against platform constraints. Produce an
Architecture Decision Record covering: decision, context, options
considered, rationale, and consequences. Flag any conflicts with existing
patterns. Post the ADR path and a one-line verdict (PROCEED / REVISE
SPEC first) to the shared task list when done.

SPEC WRITER
Read the researcher's findings, the existing specs in Specifications/, and
CLAUDE.md. Write a complete functional specification: overview, technical
context table, goals, out-of-scope items, user stories with acceptance
criteria, error states table, and open questions. Save to
Specifications/Voxio V.1.0/ as an md file. Post a summary and the list of open
questions to the shared task list when done. After the architect is done with the review, proceed to break down the feature into epics and tasks. 
