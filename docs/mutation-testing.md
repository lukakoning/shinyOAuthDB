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

## Second local pass: authorization, Trino and ODBC

The next pass added identity/protocol validation through both direct and
reactively selected authorizations, including recovery of a real SQLite
connection after a malformed selection. It also tests foreign-session
rejection at helper creation and accepts module scopes of the owning
session.

Core operation-scope tests now check independent consumers, cached errors,
equivalent scope sets, unrelated permission changes and recovery after a
required permission is restored. These run in the minimum-dependency lane
and the lifecycle mutation profile, without needing a platform SDK.
Lifecycle tests also preserve a confirmed denial during refresh uncertainty,
recover to both active and limited status, and recheck permissions after
token validation with an unknown expiry.

New campaigns used the unchanged R source, seed `20261104`, two workers and
a 240-second timeout. These processes completed successfully.

| Campaign before the new regressions | Generated | Tested | KILLED | HANG | SURVIVED |
| --- | ---: | ---: | ---: | ---: | ---: |
| Trino and shared native-option validation | 332 | 30 | 20 | 0 | 10 |
| ODBC adapters, Databricks and shared native-option validation | 981 | 30 | 15 | 0 | 15 |
| Lifecycle and authorization | 548 | 40 | 22 | 0 | 18 |

Trino additions cover malformed CA path arguments, protected credential
aliases, unnamed native options, explicit CA forwarding, verified TLS and
the native driver's HTTP-authentication policy. The HTTPS-origin callback
already rejects HTTP; the driver flag is an additional policy check, not
evidence that the sampled edit alone leaked a token.

ODBC additions cover alternate spellings of owned connection settings,
port shape and boundary validation, and forwarding of StarRocks result
timezones while retaining JWT authentication. Databricks discovery tests
also check nonce/user-info defaults and reject invalid override lists
before discovery.

The first ODBC profile omitted the existing provider, Redshift and StarRocks
test files. The original lifecycle profile also omitted the Fabric API tests.
The expanded profiles include these suites. Sampling and test-profile changes
must be taken into account when comparing reports.

Selected survivors were replayed in disposable copies after a strict passing
control. Each original R file's MD5 had to match the current source before
its generated mutant was applied. The focused replay results were:

| Focused regression tests | Edits detected | Assertion failures only | Assertions and errors | Errors only |
| --- | ---: | ---: | ---: | ---: |
| Authorization, ownership, lifecycle and operation scopes | 8 | 4 | 2 | 2 |
| Trino contracts | 6 | 6 | 0 | 0 |
| ODBC contracts and provider configuration | 13 | 9 | 0 | 4 |

The 27 replays had no skipped tests or warnings. Eight of these edits also
fail pre-existing tests outside the original profiles: four Redshift guards,
one StarRocks port guard, Snowflake provider overrides and the two Fabric
scope-subscription changes. Replays against those suites confirm this
existing coverage. The counts describe focused detection, including profile
selection improvements; they do not measure newly discovered package bugs.
The larger samples were not all rerun after the additions.

Raw reports are under `.validation/mutator-round2-before/`,
`.validation/mutator-round2-existing-coverage/` and
`.validation/mutator-lifecycle/lifecycle/round2-replay-verified.json`.

Trino and ODBC now have independent CI matrix jobs, alongside transport,
lifecycle and BigQuery. Campaigns remain diagnostic; individual survivors
need review, and the original four named security regressions remain gates.

## Remaining priorities

1. Re-run the larger transport and BigQuery campaigns with the 240-second
   timeout. Triage surviving edits and inspect mutant test logs before
   interpreting any aggregate score.
2. Investigate sampled changes to DBI validity-check exception handling
   (`session.R_363.R`) and malformed authorization-container field access
   (`authorization.R_002.R`). Check the full existing suite before adding
   regressions, and distinguish redundant guards from observable changes.
3. Extend generated campaigns to PostgreSQL and Fabric target routing. Keep
   the Linux native PostgreSQL hook in its existing instrumented Docker lane:
   mutator edits R source, not C.

Two replayed BigQuery type-validation edits still survived because later
validation rejected the same invalid input. Other survivors change error
wording, redundant defaults or unused return values. Do not add tests that
assert implementation details just to kill an equivalent edit. Not every
remaining survivor has been classified.

See [development checks](development.md) for commands and settings. The
committed workflow runs transport, lifecycle, BigQuery, Trino and ODBC campaigns
as five independent jobs, retaining baseline counts, source hashes, configuration,
summaries, individual outcomes, original sources and sampled mutant files.
Local audit data and verified replay reports are under ignored
`.validation/mutator*/` directories; Actions uploads its campaign artifacts.
