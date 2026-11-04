# Mutation testing: 4 November 2026

This audit used [mutator](https://prl-prg.github.io/mutator/) 0.3.0 to generate
AST edits, then used surviving edits to choose additional behavioral tests.
Everything ran locally. BigQuery responses were mocked; no cloud workspace
or API was used. External/LLM equivalence detection was disabled.

## Initial samples

These are diagnostic samples of different source/test snapshots, before the
corresponding regression tests were added. They are not a package-wide score.
Sampling used seed `20261104` and coverage-guided test selection.

| Source scope | Generated | Tested | KILLED | HANG | SURVIVED |
| --- | ---: | ---: | ---: | ---: | ---: |
| HTTP, API, authorization and conditions | 658 | 100 | 64 | 18 | 18 |
| BigQuery | 809 | 100 | 63 | 1 | 36 |
| Session lifecycle and authorization | 548 | 30 | 16 | 0 | 14 |

Mutator counts both test failures and execution errors as `KILLED`. The first
transport timeout was 90 seconds, shorter than its measured 96.94-second
baseline. Its 18 hangs are inconclusive, not detected regressions. The
BigQuery sample also used 90 seconds; the lifecycle sample and committed
runner use 240 seconds. Reassess timeouts on a slower machine.

The transport and lifecycle research processes wrote complete result objects
but subsequently exited with a script parse error after their scripts were
edited during execution. Their raw outcomes informed test selection; they
are not clean runner-validation runs. The unchanged committed runner passed
a separate smoke run, including its strict baseline and artifact checks.

## Verified improvements

Each row below describes generated edits that previously survived. Replays
used a passing unmutated control and the current regression tests. Source
identity was checked before applying an edit. For BigQuery, only the changed,
unchanged-since-sampling function was replaced, preserving newer metadata
validation in other functions.

| Previously surviving behavior change | Added regression | Replayed edits now detected |
| --- | --- | ---: |
| Permit zero operation timeout | Reject it before credentials or HTTP, while accepting a small positive timeout | 1 |
| Remove query-list or reserved httr2 argument checks | Reject malformed filters and request-control arguments before HTTP | 2 |
| Renew credentials during the post-response validity check | Return a completed response without unnecessary renewal | 1 |
| Disable minimum SDK version checks | Reject older SDKs; accept each exact supported version boundary | 1 |
| Accept invalid BigQuery job identities | Reject missing/malformed/wrong-project identities before polling | 4 |
| Follow BigQuery redirects or accept HTTP 300 | Require redirect disabling and enforce the 200–299 range | 3 |
| Miscompute BigQuery's 15-minute submission retry window | Check reuse of the original request ID at a nonzero monotonic clock and reject a retry at 900 seconds | 1 |
| Lose BigQuery UTC or STRUCT handling | Check the UTC attribute under another local timezone and preserve named STRUCT fields | 2 |
| Accept ambiguous parameter type maps | Reject unnamed/empty-name maps before token acquisition or HTTP | 2 |
| Remove explicit DATETIME/TIME aliases | Check submitted parameter types and returned strings | 2 |
| Return NA when a native connection validator throws | Close the old SQLite handle, reconnect with the rotated token, reuse the replacement and close it at session end | 1 |

That is 20 previously surviving edits detected by the expanded tests. Some
replays fail assertions; others raise errors in the named behavioral test.
The UTC edit also raises timezone warnings. These outcomes are recorded
separately rather than presented as assertion-only kills.

A repeated two-mutant transport campaign changed from one killed/one
surviving to two killed/zero surviving after the timeout regression. Its
100% result applies only to those two sampled edits. The broader samples
were not all rerun after the additions.

The new authorization protocol tests also reject malformed scope evidence
and preserve provider errors. BigQuery tests cover malformed completion
flags and repeated metadata page tokens. These additions check public
behavior even where no sampled mutant demonstrated the gap.

## Remaining priorities

1. Re-run the larger campaigns with the 240-second timeout. Triage surviving
   edits and inspect mutant test logs before interpreting any aggregate score.
2. Add authorization identity-shape and operation-scope observer regressions.
   Lifecycle sampling still found surviving changes in those guards and
   subscriptions; their behavioral effect needs focused investigation.
3. Expand generated campaigns to the Trino and ODBC adapters. Keep the Linux
   native PostgreSQL hook in its existing instrumented Docker lane: mutator
   edits R source, not C.

Two replayed BigQuery type-validation edits still survived because later
validation rejected the same invalid input. Other survivors change error
wording, redundant defaults or unused return values. Do not add tests that
assert implementation details just to kill an equivalent edit. Not every
remaining survivor has been classified.

See [development checks](development.md) for commands and settings. The
committed workflow runs transport, lifecycle and BigQuery campaigns as three
independent jobs, retaining baseline counts, source hashes, configuration,
summaries, individual outcomes, original sources and sampled mutant files.
Local audit data and verified replay reports are under ignored
`.validation/mutator*/` directories; Actions uploads its campaign artifacts.
