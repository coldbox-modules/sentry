# Response completion and timing

Call the same, application-owned Sentry service from both application callbacks:

```cfml
function onRequestEnd( targetPage ) {
    finishTelemetryRequest();
}
function onAbort( targetPage ) {
    finishTelemetryRequest();
}
private function finishTelemetryRequest() {
    try {
        if ( !isNull( application.cbController ) ) {
            application.cbController.getWireBox().getInstance( "SentryService@sentry" ).endRequest();
        }
    } catch ( any telemetryUnavailable ) {
        // Preserve the original response, including successful binary output.
    }
}
```

The same callbacks work in Application.bx. Merge these calls into existing callbacks; retain their application behavior. `onAbort` does not mean the request failed: an engine can terminate successfully after writing binary content. Status still comes from the response, or an explicit `statusCode` argument. Confirmed timeout callbacks may use `endRequest(timedOut=true)`. Long requests are never automatically classified as timeouts.

ColdBox `postProcess` completes ordinary requests. Binary output through `cfcontent` may bypass `postRender`, `postProcess`, and Application `onRequestEnd`, reaching `onAbort` instead. Finishing at `preRender` would exclude actual response output; this module does not do that. A synchronous output loop is covered until its handler/request exits. Detached asynchronous servlet work must finish its own explicit span when its actual operation completes; these application hooks are not a servlet async-completion listener.

Request scopes are bound to an opaque request identity as well as the current thread. When a servlet worker is assigned a new request, it cannot inherit the prior request's scope. Event-driven completion also checks the originating request handle, so a late old event cannot close the worker's newer transaction. Normal completion restores a prior scope belonging to the same request. Each request and timing handle claims completion once. Timing handles are bounded (64 samples, 32 phase names), drained before the root finishes, and reject starts after closure. No new telemetry fields contain request identities or response bytes.

Span start timestamps remain Unix epoch seconds. Span end timestamps use that start plus elapsed JVM `nanoTime`; wall-clock adjustments during a span do not become latency. Request duration metrics use the same completed span duration. Queue execution resets both start timestamp and monotonic origin when execution starts. These changes neither cap durations nor suppress slow spans.

No hook can recover an accurate end timestamp after every lifecycle callback was bypassed, a process died, or an engine terminated a thread forcibly. The ownership guard prevents stale context reuse in that situation; it cannot reconstruct an unobserved completion. The local `getObservability().getScopeResetCount()` diagnostic counts these ownership mismatches without exporting request identities. Keep the application callbacks even with the guard. It does not send an abandoned span later with an invented duration.

## Reproduction and local verification

On November 2, 2026, the pinned baseline `d3062ae` was exercised in a fresh loopback CommandBox runtime with ColdBox 8 and binary `renderData`. The six bytes `0001027f80ff` reached the client in 131 ms. Hook capture recorded `onAbort`, not `onRequestEnd`; no binary transaction had completed. After an intentional 1.8-second idle interval and subsequent requests on reused workers, its root measured 1,837 ms and render measured 1,827 ms. This demonstrates instrumentation lifetime extending beyond response delivery. It does not establish the exact history of any individual production request.

With the application abort hook and module changes, the HTTP probe checks completion **before another ColdBox request is issued**, verifies the exact bytes and security/content headers, waits through an idle interval, and verifies the timestamp never changes. It also covers normal output, a deliberately slow handler, noRender, synchronous output, explicit abort, redirect, exception, and concurrent binary/text requests. The real slow handler must retain its elapsed duration.

Prepare the normal test-harness dependencies and a private loopback runtime using the normal server configuration as a starting point. The `request-lifecycle` fixture uses the harness's `/coldbox`, `/testbox`, and module dependencies. Its signal filter retains synthetic transaction payloads in memory and returns null, so it never ingests them into Sentry. Its report/reset endpoint is a test fixture only; do not deploy the test harness.

```sh
node test-harness/request-lifecycle/verify.mjs \
  http://127.0.0.1:60339/request-lifecycle/ /tmp/sentry-lifecycle-after.json
```

Run `tests.specs.RequestCompletionSpec` through the normal TestBox runner for lifecycle ownership, repeated and late completion, two concurrent workers each executing successive requests, wall-clock jumps, queue start resets, and telemetry failures. `test-harness/tests/telemetry-runner.cfm` includes this bundle. The existing loopback envelope receiver (`node test-harness/support/receiver.mjs`) is required for transport tests in broader telemetry suites.

The owned runtime used the `boxlang@1.18.6+62` servlet artifact (manifest `1.18.6+62`, SHA-256 `4338d7c40393c82f0c544f6e586ece9f7d1dee187ec016f421837426a6ae419b`). Its bundled core reports `1.18.0+66`, so the runtime report alone is not the servlet package version. Other engine versions, Adobe/Lucee abort semantics, remote storage behavior, servlet asynchronous output/disconnects, production ingestion, and hosted CI are separate verification boundaries. No full engine/browser matrix, hosted workflow, publication, push, or deployment is part of this check.

Final local results: 92 passing module specs, no failures/errors, and one skipped optional qb grammar/provider fixture; all 20 HTTP responses passed. The binary response completed at the client in 17 ms and its transaction measured 5.80 ms. The intentional 250 ms handler measured 264.91 ms. Eight new lifecycle contracts are included in the 92 module passes. `cfformat check`, Node syntax validation, and `git diff --check` passed for the changed module sources.

## Consumer adoption

The abort-hook change can be adopted with existing `endRequest()` support. Adopt the reviewed module commit through the consumer's normal pinned dependency and lock/manifest process after its upstream work is integrated or released. Do not vendor or edit installed `lib/modules/sentry`. Keep domain authorization, storage reads, response bytes and headers in the consumer. After a separately authorized deployment, compare real affected responses with newly ingested spans; local checks do not prove production ingestion.
