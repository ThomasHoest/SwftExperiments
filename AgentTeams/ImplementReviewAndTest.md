Create an agent team to work on a new feature

TEST WRITER
Wait for the implementer to post changed files. Write integration and
edge-case tests that complement the implementer's unit tests. Cover: all
acceptance criteria from the spec, all error states from the error table,
and boundary values. Run the full test suite. Post pass/fail results and
coverage delta to the shared task list when done.

REVIEWER
Wait for both the implementer and test writer to finish. Review all
changed files for: correctness against acceptance criteria, security
issues, performance concerns, readability, and test coverage. Use this
format for each issue:
  [SEVERITY] file:line — Title
  > Problem description and suggested fix.
Severity: CRITICAL | HIGH | MEDIUM | LOW | SUGGESTION
Post a structured review with a verdict (APPROVE / REQUEST CHANGES) to
the shared task list. If requesting changes, list exactly what must be
fixed before merge.

IMPLEMENTER
Wait for the architect's PROCEED signal. Read the spec and ADR. Implement
the feature following the ADR constraints exactly. Write production code
and unit tests together — tests live alongside the code they cover. Run
the test suite before finishing. Do not modify files owned by the Test
Writer. Post the list of changed files to the shared task list when done.

COORDINATION RULES FOR THE LEAD:
- Issues from the reviewer that are high or critical must break for solution review and approval.
- If several epics are being implemented. Wait for approval between epics,  each epics must have its own commits. 