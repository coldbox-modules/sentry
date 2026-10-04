# Verification record

Work is isolated in sentry-observability, qb-sentry-hooks, cbq-sentry-hooks, boxlang-sentry-hooks, and CommuniArts worktree 084b. No production deployment or hosted workflow dispatch was performed.

## Reproducible local checks

Start CommandBox on an isolated port with the module test-harness webroot and /moduleroot/sentry alias. Install ColdBox/TestBox and module dependencies with CommandBox. Start `node test-harness/support/receiver.mjs` (loopback 60320). Set SENTRY_CBQ_SOURCE to the owning cbq checkout to include its focused hook specs. Run tests/telemetry-runner.cfm and tests/runner.cfm?directory=&bundles=tests.specs.SentryTests,tests.specs.SentryWiringTests&reporter=json. Receiver /state contains decoded JSON items and base64 binary items, while /reset can simulate delay/status/category limits. The browser feedback.html fixture uses synthetic data only. Run `npm --prefix browser test` and `npm --prefix browser run build`. Native query smoke is separate from capability-selected automatic instrumentation.

The harness and CommuniArts server run BoxLang 1.18.0+66 (build 2026-10-02), despite CommandBox's engine target metadata saying 1.18.6+62. Java is Temurin 21.0.10+7 arm64, Runwar 6.1.8. Lucee targeted listener verification uses 6.2.8.20, Java 21.0.10 and Runwar 5.2.7. The BoxLang upstream JUnit source build includes the new event; the application runtime has not consumed that runtime build.

Transport checks exercise Unicode/real binary lengths, matching receipts, 429 category limits, unavailable ingestion, pending bounds and shutdown. Span checks cover malformed/all-zero headers, trusted parent sampling/baggage, nesting, failures, isolation, exact-origin propagation, completion once, redirect cleanup, manual/native de-duplication, zero/false/empty cached values, and Lucee listener composition. Queue tests include completion on another thread, timeout followed by late exit, synchronous observer exceptions, bulk enqueue failures, and an actual asynchronous cbq timeout. Hook JUnit tests preserve exception identity/correlation and cached event identity without introducing new DDL.

Browser tests cover screenshot privacy, unsaved values, protected pages, capture deadlines, replay races, navigation cancellation, stale object URLs, eligibility and rejected-delivery retry. A Chromium generic widget capture produced a 1426x1051 PNG (61,900 bytes): visible edited note retained, synthetic displayed password and explicit masked content absent. Decoded real SDK replay payloads also excluded those secrets. Sentry played the uploaded replay and seeking reached 00:10 in the 14-second recording. CommuniArts sign-in to password recovery navigation rendered on communiarts.localhost:60321, with initial sentry-trace metadata and no anonymous feedback eligibility.

## Provider recognition

The CommuniArts Developer plan showed 5M spans, 5GB logs, 5GB application metrics, 1GB attachments, and one Cron monitor. No trial/billing changes were made. Synthetic traffic used sentry-verification and no application/customer records.

Backend trace e8b904f3221b4924a4817a69472cebe3 was indexed with http.server, db.query, http.client, cache.get and queue.process spans. A structured log and sentry.verification.requests counter were indexed with that trace. All three envelopes received HTTP acceptance. Browser trace 55ad848cf4ce4b7e94bba8888bafe4d3 included document LCP 68ms, FCP 68ms, and TTFB 13.3ms. Replay 787f30f633f44fd9b75a0f7269542f4f was indexed under sentry-verification, played, and sought. Synthetic browser feedback received matching ingestion acceptance and is visible as COMMUNIARTS-FRONTEND-C in Spam. Its provider PNG preserves the unsaved synthetic note and masks the displayed password; the feedback links to the replay above. Cross-project trace 0167f55b73064debb5e26914c5f74c67 connects frontend http.client 8c13e6b93b3d8fc1 to backend http.server 5ce5ba73ca5b49eb.

## Boundaries

Focused success does not establish deployment readiness. Full hosted CI, browser matrices, Adobe CF/older Lucee compatibility, comprehensive queue retry/release/chain/batch/provider matrices, specialized Sentry dashboards, profiling and production traffic remain deferred. Native BoxLang caught direct-query errors require the proposed runtime release; qb hooks and withQuerySpan cover the current application. Browser SDK support determines which vitals are emitted: INP needs qualifying interactions and CLS needs layout shifts; absence of those in a static synthetic page is not failure.

The full CommuniArts Vitest sweep also exposed existing pageMetadata registry and kiosk CheckIn sharing-payload mismatches in untouched files. Focused observability/feedback specs are the acceptance proof for this change; do not present them as a complete JavaScript-suite pass.

Native Lucee 6.2.8.20 PostgreSQL verification passed success, caught failure, composed SQL transformation, cached result metadata, and manual/native de-duplication (six spans). Without a caller-supplied result option, Lucee supplies only executionTime, so cache status is unknown rather than incorrectly reported as a database round trip. This Lucee runtime bypassed global listeners for query-of-queries; use the manual wrapper for that coverage.

Final focused results: module telemetry and cbq hook specs 20/20; existing module API/wiring 27/27; browser companion 27/27; CommuniArts backend integration and unit specs 25/25; CommuniArts focused feedback/tracing Vitest 69/69. The complete CommuniArts Vitest run passed 803 and failed the two pre-existing contracts noted above. The application build passed its initial JavaScript gzip budget at 518.2 KiB.

Queue regression checks also verify worker-start timestamps, wait time excluding processing, retry counts, cancellation after worker exit, and persisted chain propagation after callback scope cleanup. The package build produced a source ZIP including browser source/package metadata and bundled assets, excluding node_modules and installed modules. Cleanup was verified against an external symlink sentinel.

Native BoxLang/CFML captureFeedback with the captured 61,900-byte PNG received HTTP 200 for event 14625ba2371241fbb0f651fcfe3e80e2. Sentry indexed attachment 24792376268 as sentry-verification.png, image/png, 61,900 bytes; this confirms binary attachment recognition independently of the HTTP receipt. Browser feedback visibility and replay playback were verified in the frontend project; the native feedback entry itself was not inspected in the backend feedback UI.

Standalone browser spans also use beforeSendSpan sanitization, including clients supplied by consumers. This removes interaction selectors and unapproved attributes even when the SDK sends a span outside a transaction envelope.
