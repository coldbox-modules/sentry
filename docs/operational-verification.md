# Local operational-observability verification — October 22, 2026

After subagent review and fixes, the final module harness passed **77/77** on each local engine, with zero failures, errors or skips:

| Engine | JVM / servlet runtime | Evidence |
| --- | --- | --- |
| Lucee 5.4.8.2 | Temurin 21.0.10+7, Runwar 5.2.7 | `/tmp/sentry-review-final-lucee5.json` |
| BoxLang 1.18.0+66, reported by servlet startup | Temurin 21.0.10+7, Runwar 6.1.8 | `/tmp/sentry-review-final-boxlang.json` |
| Adobe ColdFusion 2023 update 25 (`2023,0,25,330977`) | Temurin 21.0.10+7, Runwar 5.2.7 | `/tmp/sentry-review-final-adobe.json` |

The BoxLang engine package is labeled `1.18.6+62`; its startup reports the runtime version above. Do not infer the running engine version from the package label or the legacy TestBox reporter. The local CommandBox initial-install hook failed before boot with missing `CFENGINE` metadata; the owned engine then used the existing compatible `bx-compat-cfml`/`bx-esapi` runtime modules and explicit Jakarta Runwar 6.1.8. These are local harness setup details, not qualified fresh-install behavior or release changes.

The Adobe check uses an isolated copy of the previously prepared engine, including its existing Commons IO 2.4 runtime repair; it does not qualify a pristine engine installation. Native thread sampling now uses the exported JMX interface, and missing null argument slots are guarded before access. A fresh local Adobe probe returned heap, threads, process CPU, and GC count/time (`/tmp/sentry-review-jvm-adobe.json`).

The harness uses existing ColdBox `7.5.2+27` and TestBox `3.2.0+356` dependencies through read-only links. The reused BoxLang runtime modules report `bx-compat-cfml` `1.40.0+56` and `bx-esapi` `1.10.0+14`. `SENTRY_QB_SOURCE` points to CommuniArts' installed qb `14.1.0`, read without modification. Queue tests exercise configured idle queues, dynamic queues returning to zero, failed polls, bounded lifetime labels and qb's actual PostgreSQL/MySQL/SQL Server SQL compilation. Database execution is stubbed at qb's `get()` boundary; these are not fresh live database/provider tests. The existing cross-thread timeout/late completion/retry/scope regressions also pass. cbq's separate upstream hook suite was not rerun.

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

CFFormat checked 38 files successfully. The earlier unchanged browser Vitest run passed **28/28** in eight files; no browser source or assets changed. The unchanged browser development dependency tree has npm audit advisories for Vite (high), Vitest (moderate) and `@vitest/mocker` (moderate); no unrelated dependency upgrades were made. This does not assess production exploitability.

Lucee 6, the complete hosted matrix, browser UI matrices, crash/recovery loops, live database polling, supported vendor pool adapters, production profiling, real provider delivery/indexing and consumer adoption remain unverified here. Publication, deployment, hosted workflow dispatch, alert/uptime configuration, external messaging and automation changes were not performed. Consumer and original module checkouts remain unchanged. Owned test servers and the receiver are stopped after verification.

The [audit and adoption sequence](observability-upstream-audit.md) records ownership and release prerequisites; [operational setup](operational-observability.md) documents configurable APIs and consumer recipes. No package/lock versions or installed application module source were changed.

## Subagent review follow-up

The independent review found six bugs, each reproduced by a failing regression against the initial commit: case-alias phase merging, exact queue names overwriting one another, workflow completion skipped after an earlier cleanup failure, mutable/foreign timing tokens bypassing bounds, trailing newlines accepted by the phase-name regex, and exporter work included in queue processing duration. All six are fixed. The reviewer rechecked the implementation and the BoxLang exact-name / Adobe null-array follow-ups and found no remaining actionable issue. `OperationalReviewSpec` is included in the normal and telemetry runners. Adobe also required a nonempty HTTP reset body in the receipt test fixture.

One earlier combined Lucee run failed two unchanged current-time upper-bound assertions by one second (`/tmp/sentry-review-lucee5-clock-bound-failure.json`). The isolated timestamp suite passed 3/3, and the complete rerun passed 77/77 without timestamp-source edits. The transient boundary discrepancy is retained as a verification limitation rather than attributed to these changes.
