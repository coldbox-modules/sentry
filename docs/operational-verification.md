# Local operational-observability verification — October 25, 2026

## Provider-owned query and queue adapters

qb now owns the optional `QueryTelemetryAdapter@qb` execution listeners. Sentry resolves that explicit mapping through the generic query-setup contract, passes telemetry/application name/database system, and owns no qb interceptor or built-in `qb` mode. Manual query spans and native engine listeners remain available. Shutdown rejects new observations while active query completions drain and restore their scopes before qb unregisters its own listeners. Independent review found the original immediate-unregister race; the corrected implementation and regressions were re-reviewed. Adobe also required avoiding a listener method named `release`, which collides with engine lifecycle behavior.

cbq's queue adapter now selects exactly one `options.workerPool` or `options.connection`. Worker pools supply combined worker/backlog data; connections supply backlog without requiring or registering workers. Queue overrides/defaults follow the selected source. Ambiguous sources and the former `options.pool` spelling are rejected. The earlier reported MySQL CI failure was superseded by the existing quoted-alias fix; it was already green before this selector follow-up.

Final local proof on each prepared Lucee 5.4.8.2, Adobe 2023 update 25 and BoxLang 1.18.0+66 runtime:

- **141/141 Sentry specs**, including thirteen real PostgreSQL/cbq cases. New cases prove connection-only snapshots without a worker pool and actual ColdBox/WireBox qb adapter resolution, real query success/error spans, SQL scrubbing, manual de-duplication, scope restoration, independent listener ownership and in-flight completion during shutdown.
- **14/14 cbq adapter specs**, including both selector paths, absent capabilities and failure/validation behavior.
- **16/16 focused qb adapter/failure-hook specs**, run independently by the qb implementation subagent. The complete qb suite and hosted checks are recorded separately on its draft PR.

All local results above have zero failures/errors/skips. Evidence is `/tmp/sentry-provider-adapters-final-{lucee5,adobe2023,boxlang}.json`, `/tmp/cbq-provider-selectors-final-{lucee5,adobe2023,boxlang}.json` and `/tmp/qb-telemetry-final-{lucee5,adobe2023,boxlang}.json`. The dedicated PostgreSQL 18.1 database is `sentry_queue_health_adapters_20261025`; the final runs leave zero tables. The owned harness uses the new qb/cbq worktrees through temporary local links/settings; installed application modules remain unchanged. Formatting and whitespace checks pass. Adapter mappings require provider versions containing these additions; no release or consumer upgrade is implied by a draft PR. Prepared-runtime, provider/backend, heartbeat, timeout and delivery limitations below still apply.

## Unified queue adapter follow-up

The current configuration is one `automaticCollectors.queues` list, with explicit provider adapters returning whichever queue/worker fields they support. The former automatic worker/database groups are removed. Generic snapshots emit fixed `queue.name` labels with shared freshness/failure diagnostics; backlog-only providers need no worker fields. No automatic Sentry path selects cbq, constructs a SQL builder or chooses a jobs table/datasource. The cbq `QueueHealthAdapter` reads the pool/provider selection; its database provider owns the aggregate query and configured query options. Older manual APIs remain as compatibility entrypoints.

Final local results: **137/137 Sentry specs plus 9/9 cbq adapter specs on each of Lucee 5.4.8.2, BoxLang 1.18.0+66 and Adobe 2023 update 25**, with zero failures/errors/skips. Evidence: `/tmp/sentry-unified-final-lucee5.json`, `/tmp/sentry-unified-final-boxlang.json`, `/tmp/sentry-unified-final-adobe2023.json` and the corresponding `/tmp/cbq-unified-final-*.json` files. The Sentry suite includes eleven actual PostgreSQL/cbq integration cases. One automatic definition now measures both real worker execution and database depth/age/lease state. New real queries verify provider-owned table/datasource options, multiple queues, wildcard selection and bound quote-bearing names. Native activity, unsupported fields, combined/backlog-only providers and preserved manual APIs are covered. The separate cbq hosted suite additionally tests its database snapshot against MySQL.

Review found an optional facade test that now also needs cbq; its fixture guard is corrected. Adobe exposed a constructor/inline-callback compiler error; the provider now declares the factory and snapshot separately. After that failure, only the dedicated test database's leftover fixture tables were removed before the final reruns; final runs left zero tables. The disposable `sentry_queue_health_unified_20261024` database was removed after owned processes stopped, and local server settings/dependency links were restored. Installed application modules and the pre-existing PostgreSQL server were not changed. Formatting and whitespace checks passed. Current hosted results are recorded on the draft PRs; the earlier configurations/results below are historical.

## Earlier provider-owned worker adapter follow-up

Automatic `queueWorkers` now requires an explicit `adapter`, with provider configuration in `options`. Sentry no longer chooses cbq from a `pool` key. The optional cbq implementation lives in cbq as `WorkerHealthAdapter@cbq`, follows the `sample(context)` contract without a Sentry dependency, and requires `options.pool`. The existing manual cbq API delegates to that mapping; generic manual snapshot APIs remain available without cbq.

The complete Sentry harness passed **134/134**, and cbq's new adapter bundle passed **6/6**, on each prepared Lucee 5.4.8.2, BoxLang 1.18.0+66 and Adobe 2023 update 25 runtime. All results have zero failures, errors or skips. The ten live PostgreSQL/cbq cases use cbq `next` base `fad884a` plus the new adapter, installed qb 14.1.0, and actual registered worker pools. The automatic case resolves cbq's adapter through WireBox, passes its explicit pool option, and observes an actual blocked worker with reserved work, pending depth and oldest age. Native executor activity is also checked in the adapter bundle. No installed application dependency was edited.

Evidence: `/tmp/sentry-worker-adapter-final-lucee5.json`, `/tmp/sentry-worker-adapter-final-boxlang.json`, `/tmp/sentry-worker-adapter-final-adobe2023.json`, and the corresponding `/tmp/cbq-worker-adapter-final-*.json` files. Sentry formatting checked 63 files; cbq formatting checked its two new CFCs. Both whitespace checks passed. Independent bug/CFML/BoxLang compatibility review found a stale configuration example, now fixed, and re-review found no remaining actionable issue. The separate complete cbq suite was not run locally; its hosted workflow and the Sentry hosted matrix are reported on their draft PRs.

The disposable database `sentry_queue_health_adapter_20261024` had no fixture tables after tests and was removed after owned processes stopped. The pre-existing PostgreSQL server remains running. Local server configuration and dependency links were restored. Using the cbq mapping requires a cbq release containing the adapter; existing releases do not acquire it automatically. Earlier evidence and limitations below retain their original scope.

## Ad hoc timing follow-up

Manual `measure(name,callback)` and `begin(name)` now register valid phase names on first use without `requestTimingNames` configuration. The setting remains an optional initial name/header order list. Case variants record under the first spelling. Existing 32-name/64-sample limits, token ownership, name validation and original callback outcomes are preserved.

The updated 43-spec focused bundle reproduced the previous restriction (39 passed, two failures, two errors in `/tmp/sentry-adhoc-before.json`). After the fix, the complete ordinary harness passed **123/123 on Lucee 5.4.8.2, BoxLang 1.18.0+66 and Adobe 2023 update 25**, zero failures, errors or skips. Evidence: `/tmp/sentry-adhoc-final-lucee5.json`, `/tmp/sentry-adhoc-final-boxlang.json`, `/tmp/sentry-adhoc-final-adobe2023.json`. New coverage checks ad hoc manual and shared automatic instances, once-only tokens, case canonicalization, emitted phase metrics, limits, invalid names and preserved callback returns/exceptions. Independent source review found no remaining actionable bug or CFML/BoxLang/older-Adobe compatibility issue. Formatting checked 63 files and whitespace checks passed.

These follow-up runs use the prepared local runtimes with optional qb compilation contracts enabled. The ten opt-in live PostgreSQL/cbq cases were not rerun for this timing-only change; their earlier 130/130 evidence below remains historical. Browser assets are unchanged. Hosted CI evidence is recorded separately on draft PR #56.

## Earlier automatic-collector verification

The configuration-driven automatic collectors and dependency adapters passed the complete local suite: **130/130 on each engine, zero failures, errors or skips**. Manual APIs remain covered. Each run includes 25 automatic-configuration specs and 10 live PostgreSQL/cbq cases.

| Engine | JVM / servlet runtime | Current raw evidence |
| --- | --- | --- |
| Lucee 5.4.8.2 | Temurin 21.0.10+7, Runwar 5.2.7 | `/tmp/sentry-auto-final-lucee5.json` |
| BoxLang 1.18.0+66 | Temurin 21.0.10+7, Runwar 6.1.8 | `/tmp/sentry-auto-final-boxlang.json` |
| Adobe ColdFusion 2023 update 25 | Temurin 21.0.10+7, Runwar 5.2.7 | `/tmp/sentry-auto-final-adobe.json` |

The new coverage verifies default-off behavior, partial settings, bounded names, callback/object/WireBox-interface contracts, real WireBox method interception, original returns/errors/null/void behavior, manual/automatic deduplication, failing observation/classifier setup, once-only query setup/cleanup, actual scheduled collection, scope isolation, no overlapping cycles, shutdown during a cycle, local receipt failures, automatic handler/render phases, early exits, invalid phase names and gated Server-Timing publication. The tenth live case runs the background sampler against a real blocked cbq job and a WireBox query factory, asserting actual execution activity, reservation, depth and oldest-age metrics.

Review findings are fixed and re-reviewed: open timing tokens on early exits, partial nested settings at module load, dispatch after shutdown, scope lookup breaking fail-open execution, receipt-poll failures omitted from cycle diagnostics, an accidentally empty disabled test, and complex phase names reaching deduplication before validation. Full testing also found and fixed a BoxLang built-in `attempt()` name collision and missing application context on raw scheduled runnables. Automatic work now uses ColdBox's context-aware Runnable proxy when available, including Adobe JDBC thread-state cleanup. The reviewer found no remaining actionable bug or CFML/BoxLang compatibility issue.

The existing prepared runtimes and read-only ColdBox/TestBox/qb/cbq dependencies described below were reused. Adobe's PostgreSQL package was registered, but its servlet context could not load the JDBC class after restart. The owned ignored runtime was repaired by reinstalling its CFPM PostgreSQL package and adding its existing JDBC 42.7.3 JAR to `WEB-INF/lib`, followed by restart. Both package registration and classpath availability were required; no product workaround or installed application dependency change was made. This qualifies these prepared local runtimes, not a fresh installation.

CFFormat checked **63 files**; `git diff --check` passed. No browser code changed; the earlier **28/28** browser result below is historical and was not rerun for this backend-only change. Engine suites share a mutable loopback receiver and must run sequentially: a concurrent run interfered with one delivery-diagnostics case; the final sequential rerun passed. Raw evidence is local temporary output, not a durable CI artifact.

The dedicated database was `sentry_queue_health_auto_20261024`, on the pre-existing local PostgreSQL 18.1 server. Fixture tables were removed, owned test processes stopped, and the disposable database dropped after verification. Remaining limits: no fresh-install or full hosted-engine matrix, Lucee 6, real MySQL/SQL Server polling, Redis/SQS adapters, worker-process crash recovery, real heartbeat producer, production profiling, real provider delivery/indexing or consumer adoption. Consumer adapters must set their own query/network timeouts; shutdown cannot force an uncooperative callback to return. WireBox interception applies to configured methods on subsequently WireBox-created instances; it cannot intercept arbitrary HTTP clients or objects created with `new`. Manual APIs cover those paths.

## Earlier local verification — October 22, 2026

The following sections retain the evidence and scope of the earlier commits. Their totals and local-only statements describe those runs, before the later authorized push and draft PR update.

After subagent review, the timestamp clock correction and the request/dependency/worker-health additions and real database/worker integration coverage, the final module harness passed **104/104** on each local engine, with zero failures, errors or skips:

| Engine | JVM / servlet runtime | Evidence |
| --- | --- | --- |
| Lucee 5.4.8.2 | Temurin 21.0.10+7, Runwar 5.2.7 | `/tmp/sentry-queue-health-final-lucee5.json` |
| BoxLang 1.18.0+66, reported by servlet startup | Temurin 21.0.10+7, Runwar 6.1.8 | `/tmp/sentry-queue-health-final-boxlang.json` |
| Adobe ColdFusion 2023 update 25 (`2023,0,25,330977`) | Temurin 21.0.10+7, Runwar 5.2.7 | `/tmp/sentry-queue-health-final-adobe.json` |

The BoxLang engine package is labeled `1.18.6+62`; its startup reports the runtime version above. Do not infer the running engine version from the package label or the legacy TestBox reporter. The local CommandBox initial-install hook failed before boot with missing `CFENGINE` metadata; the owned engine then used the existing compatible `bx-compat-cfml`/`bx-esapi` runtime modules and explicit Jakarta Runwar 6.1.8. These are local harness setup details, not qualified fresh-install behavior or release changes.

The Adobe check uses an isolated copy of the previously prepared engine, including its existing Commons IO 2.4 runtime repair; it does not qualify a pristine engine installation. Native thread sampling now uses the exported JMX interface, and missing null argument slots are guarded before access. A fresh local Adobe probe returned heap, threads, process CPU, and GC count/time (`/tmp/sentry-review-jvm-adobe.json`).

The harness uses existing ColdBox `7.5.2+27` and TestBox `3.2.0+356` dependencies through read-only links. The reused BoxLang runtime modules report `bx-compat-cfml` `1.40.0+56` and `bx-esapi` `1.10.0+14`. `SENTRY_QB_SOURCE` points to CommuniArts' installed qb `14.1.0`, read without modification. Queue tests exercise configured idle queues, dynamic queues returning to zero, failed polls, bounded lifetime labels and qb's actual PostgreSQL/MySQL/SQL Server SQL compilation. The earlier depth-sampler contracts stub database execution at qb's `get()` boundary. The new health-adapter integration below additionally executes real PostgreSQL queries and actual cbq workers. The existing cross-thread timeout/late completion/retry/scope regressions also pass. cbq's separate upstream hook suite was not rerun.

New coverage includes opt-in receipt collection, async acceptance observed once, rejection/rate-limit drops/network failures, bounded diagnostics; fixed request labels and budgets, once-only timing tokens, original callback return/error preservation; workflow outcome privacy, classifier validation, callback-once behavior, original exception preservation; optional pool adapters; unstarted attempt cancellation, opt-in terminal counters, destination label restrictions; native JMX interface calls and unsupported CPU/GC omission; and lowercase error-event trace correlation. Existing error APIs, timestamps, request URLs and initialization concurrency remain covered.

A local native probe additionally returned heap used/max, thread count, process CPU load and cumulative GC count/time on both engines. Raw numeric samples are in `/tmp/sentry-reusable-jvm-lucee5.json` and `/tmp/sentry-reusable-jvm-boxlang.json`. The probe template was removed. This demonstrates local MXBean support, not production profiling or provider arrival.

Commands used the loopback envelope receiver and the module's existing runners:

```sh
node test-harness/support/receiver.mjs
curl --fail 'http://127.0.0.1:60361/tests/runner.cfm?reporter=json'
curl --fail 'http://127.0.0.1:60362/tests/runner.cfm?reporter=json'
curl --fail 'http://127.0.0.1:60363/tests/runner.cfm?reporter=json'
box run-script format
box run-script format:check
npm --prefix browser ci --ignore-scripts
npm --prefix browser test
git diff --check
```

CFFormat checked 48 files successfully. The earlier unchanged browser Vitest run passed **28/28** in eight files; no browser source or assets changed. The unchanged browser development dependency tree has npm audit advisories for Vite (high), Vitest (moderate) and `@vitest/mocker` (moderate); no unrelated dependency upgrades were made. This does not assess production exploitability.

Lucee 6, the complete hosted matrix, browser UI matrices, crash/recovery loops, real MySQL/SQL Server polling, supported vendor pool adapters, production profiling, real provider delivery/indexing and consumer adoption remain unverified here. Publication, deployment, hosted workflow dispatch, alert/uptime configuration, external messaging and automation changes were not performed. Consumer and original module checkouts remain unchanged. Owned test servers and the receiver are stopped after verification.

The [audit and adoption sequence](observability-upstream-audit.md) records ownership and release prerequisites; [operational setup](operational-observability.md) documents configurable APIs and consumer recipes. No package/lock versions or installed application module source were changed.

## Subagent review follow-up

The independent review found six bugs, each reproduced by a failing regression against the initial commit: case-alias phase merging, exact queue names overwriting one another, workflow completion skipped after an earlier cleanup failure, mutable/foreign timing tokens bypassing bounds, trailing newlines accepted by the phase-name regex, and exporter work included in queue processing duration. All six are fixed. The reviewer rechecked the implementation and the BoxLang exact-name / Adobe null-array follow-ups and found no remaining actionable issue. `OperationalReviewSpec` is included in the normal and telemetry runners. Adobe also required a nonempty HTTP reset body in the receipt test fixture.

## Timestamp clock correction

The earlier discrepancy is now diagnosed and fixed. The local Lucee 5.4.8.2 configuration reports a time-server offset of **+72 ms**. Its `now()` implementation constructs a `DateTimeImpl` with that offset applied (confirmed from the installed runtime bytecode). Sentry's default error timestamp used `now()`, while its transport, traces and test bounds used the JVM clock. At JVM epoch millisecond `1792707331943`, adding 72 ms crosses into Unix second `1792707332` while the JVM remains in second `1792707331`.

Default error timestamps now use the unadjusted JVM millisecond clock, consistent with the other telemetry. Explicit date arguments preserve their supplied instant. ISO and Unix values still derive from one truncated epoch second. A new deterministic boundary regression and the frozen-clock capture/post-metadata regression both failed before the implementation fix and pass afterward; the existing strict current-time bounds remain intact.

The same local probe observed **12 future timestamps in 150 samples before** and **zero in 150 after**, with the +72 ms engine offset still present. Evidence: `/tmp/sentry-timestamp-clock-before.json`, `/tmp/sentry-timestamp-offset-before.json`, `/tmp/sentry-timestamp-clock-after.json`, and `/tmp/sentry-timestamp-regressions-before.json`. No engine time-server settings or system clocks were changed. Probe templates were removed. The timestamp correction passed its four timestamp specs and the then-complete 78-spec suite on all three local engines. The expanded final suite above includes those regressions.


## Request saturation, dependency outcomes and queue worker health

The expanded suite adds **17 focused specs**, for **95/95 on each engine**, with zero failures, errors or skips. New coverage exercises bounded active-request tracking, monotonic ages, explicit once-only timeout completion, cross-thread completion, trace-disabled request lifecycle, the terminal exception path with no postProcess, retained error trace correlation, disabled collection, fixed dependency classifications and retry/status/breaker fields, original return/exception preservation, callback-only duration, observation-failure cleanup, worker heartbeat/backlog snapshots, failed/unsupported-versus-zero sampling, and fixed executor labels.

The optional database-health query compiles against the installed qb public API with PostgreSQL, MySQL and SQL Server grammars. Its predicates distinguish runnable/delayed unclaimed jobs, claimed/reserved jobs and expired leases. Those initial contracts stub query execution at get(). The subsequent PostgreSQL integration below executes the health adapter and lease recovery against real database rows and workers; other database engines remain compilation-only. The cbq pool contract reads configured quantity and the executor's supported activity statistics. A real local ColdBox Executor wrapping a JVM fixed pool verifies idle activity as zero; unsupported executor capability leaves activity absent. This does not prove live worker heartbeats or production workload behavior.

Independent subagent review found three bugs in the first implementation: annotation errors could skip dependency span completion; a ColdBox exception skipped postProcess and leaked an active request observation; and cbq execution capacity was mislabeled as active work. All three are fixed and covered by regressions. The capacity/activity and unsupported-executor regressions failed before the adapter fix (15 passed, 2 failed in /tmp/sentry-worker-capacity-regression-before.json). The reviewer rechecked the revised implementation and documentation and found no further actionable bug or CFML/BoxLang/Adobe compatibility issue. Dependency duration also excludes classifier/setup/export work.

All collectors remain opt-in with bounded fixed labels. No scheduler or worker heartbeat is fabricated. Request executor details, real worker heartbeats and provider retry/exhaustion totals require supported consumer snapshots. No application adoption, dependency/package changes, browser changes, hosted checks, external provider changes, push, publication or deployment were performed. The original module and consumer worktrees remain unchanged; owned local test processes were stopped after verification.


## Real PostgreSQL and actual cbq worker verification

The opt-in DatabaseQueueHealthIntegrationSpec now contributes **9 live integration specs**. Final normal-runner totals are **104/104 on Lucee 5, BoxLang and Adobe 2023**, with zero failures, errors or skips, using the exact engine/JVM versions listed above. This is real PostgreSQL 18.1 (Postgres.app) on 127.0.0.1:5432 in a newly created disposable database, sentry_queue_health_20261022. Each case creates/drops a uniquely named table; the final database has zero fixture tables. Owned test servers/receiver are stopped and the disposable database is removed after verification. The pre-existing PostgreSQL server remains running.

The fixture uses installed qb 14.1.0 and cbq 7.0.2 package metadata with the existing local cbq hook/bulk modifications; this is not qualification of a pristine stock package installation. Read-only source fingerprints (SHA-256): DBProvider.cfc: 352a9a7703760e093c472726b94f00601125d344b41ffbe30d3a898869293d96; WorkerPool.cfc: 5bd1dc014c26f278336f307b1c0753257f1ece63bc17383997c6ca3de7da9ed8. Lucee uses its existing PostgreSQL JDBC 42.6.0 bundle; the isolated BoxLang servlet uses the same driver JAR in WEB-INF/lib. Adobe required its registered PostgreSQL CFPM package 2023.0.11.330706 and dependent JDBC 42.7.3. These are local ignored runtime setup changes, with no application dependency or package/lock changes.

Actual cbq connections, DBProvider, scheduler polling, job persistence/serialization/deserialization, WorkerPool executors and job.handle() run without database/provider/worker mocks. The worker metric is intercepted only at the telemetry gauge boundary to assert actual public executor activity. The tests prove:

- Empty measured zeros and mixed runnable/delayed/reserved/stale counts; completed/failed and other queues are excluded. A quote-bearing queue name verifies bound query parameters.
- Idle executor activity0, real blocked job activity1 with reserved1, followed by completion/drained zeros.
- Real delayed execution, retry/backoff returning to delayed backlog and eventual success, plus terminal exhausted failure excluded from pending counts.
- A deliberately expired execution lease and a staged reservedBy-only claim are both reported stale, then reclaimed and completed by actual cbq workers with the expected attempt counts.
- A deliberately injected drain error still cleans the real fixture table, task/pool/connection/executor registrations, shared job state and telemetry resources.

The adapter required no product-code change: the original predicates matched observed provider behavior. New fixture issues were fixed: avoid the CFML built-in query() name; preserve exact PostgreSQL identifier spelling in qb fixture data; require positive numeric timestamps rather than null-only checks when CFML null support is disabled; retain job state through shutdown; continue independent cleanup after failures; and use a shared struct error accumulator because Adobe copies array arguments. The latter regression failed on Adobe (8 passed, 1 failed in /tmp/sentry-queue-health-final-focused-adobe.json) before the struct correction. The independent subagent reviewed the adapter and new fixture, reported the cleanup issue, and re-reviewed the cleanup and Adobe compatibility corrections with no further actionable findings.

See operational-observability.md for the explicit local opt-in setup. The normal and telemetry runners include the integration bundle; without SENTRY_QUEUE_HEALTH_DB it registers no integration tests and requires no database. The mode forces module telemetry to loopback and disables automatic error/appender capture. Verification does not establish worker-process crash recovery, real worker heartbeats, Redis/SQS behavior, MySQL/SQL Server execution, production profiling or real provider indexing/delivery. No push, hosted workflow, publication, deployment, consumer adoption or provider setting change was performed.
