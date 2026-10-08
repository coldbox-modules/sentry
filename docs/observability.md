# Observability and feedback for CFML and BoxLang

All new integrations are opt-in. Existing error APIs, LogBox appender settings, standalone construction, and thread-safe WireBox initialization remain available. Version 2.2.0 adds these features without requiring existing applications to enable them. Optional qb/cbq integrations require the hooks described below.

## Server setup

```cfml
moduleSettings.sentry = {
    DSN: getSystemSetting( "SENTRY_DSN", "" ),
    environment: "production",
    release: "my-release",
    tracesSampleRate: 1,
    enableRequestTracing: true,
    queryAdapter: "auto",
    databaseSystem: "postgresql",
    enableQueueTracing: true,
    enableLogs: true,
    enableStructuredLogBoxAppender: true,
    logMessageMode: "category",
    enableMetrics: true,
    enableMonitors: true,
    monitorSlugs: [ "hourly-work" ],
    tracePropagationTargets: [ "https://app.example.test" ],
    trustIncomingTrace: false
};
```

The same struct works in BoxLang. Standalone usage: `new sentry.models.SentryService( settings )`. Pass the same service across operations; call `shutdown()` at application shutdown. Add `sentry.endRequest()` in Application.cfc/Application.bx `onRequestEnd` to cover early redirects and aborted requests. ColdBox postProcess finishes ordinary requests after rendering. Route-template transaction names fall back to handler/action. Response status is read from the servlet response; explicit `endRequest(statusCode=303)` is also supported.

Use a trustIncomingTrace callback at your ingress boundary. Reject public forged trace headers unless the request is from an approved browser/proxy boundary. Parent sampling decisions are honored; malformed/all-zero IDs are ignored. Propagation targets compare exact scheme/host/port and reject URL userinfo. Baggage carries only allowlisted technical sampling context. Use requestFilter, attributeFilter, beforeSendSignal, and beforeSendFeedback to filter signals. Application bodies, SQL bindings/results, job payloads, cached values, and credentials are never needed by instrumentation.

```cfml
sentry.withTraceContext( headers, function( root ) {
    return sentry.withSpan( "load inventory", function( span ) {
        span.setAttribute( "organization.id", opaqueOrganizationId );
        return loadInventory();
    } );
}, "inventory work", "task" );
```

`startTransaction(name,op,headers,trusted)` creates a root handle; activate it with `getObservability().setScope({span:root})` for explicit/manual lifecycles and restore the previous scope in finally. `startSpan`, `withSpan`, `getTraceHeaders`, and `withTraceContext` support nesting. Handles have `setAttribute`, `setStatus`, `getContext`, and atomic `finish`. Disabled/unsampled spans are harmless. Always pass trace headers explicitly across worker boundaries; ThreadLocal context is not implicitly inherited. Telemetry delivery uses an independent two-thread Java HTTP executor, bounded pending envelopes (64), bounded signal buffers (100 per type), 2,000ms timeout, five-second flushing, category rate limits, and shutdown flushing. `getObservability().getTransport().getDiagnostics()` distinguishes accepted, rejected, pending, and dropped envelopes. HTTP acceptance is not a guarantee of indexing.

## Queries

On Lucee 6+, compose your existing application listener:

```cfml
this.query.listener = sentry.createLuceeQueryListener(
    listener = existingListener,
    databaseSystem = "postgresql"
);
// Set queryAdapter="lucee" so qb does not produce a second span.
```

Native global listeners are officially scoped to Lucee 6+ ([Lucee documentation](https://docs.lucee.org/recipes/query-listener.html)); older engines are not automatically enabled. Existing before/after/error returns and transformations are preserved. Each thread has a nesting stack; use the manual wrapper for asynchronous query modes whose callbacks do not execute on that thread.

BoxLang auto selects application-scoped preQueryExecute/postQueryExecute/onQueryExecuteError only when the runtime exposes ON_QUERY_EXECUTE_ERROR. Earlier runtimes fall back to qb. The upstream hook includes PendingQuery identity, context, elapsed milliseconds, and the unchanged exception. Cached execution events include cached/dbtype and correlate with the same pending identity. The currently tested server runtime lacks that error event: successful native direct queries were exercised separately, but automatic configuration deliberately uses qb there. Connection acquisition/build failures occurring before native PRE remain a manual-wrapper boundary.

qb's new onQBExecuteException closes the original preQBExecute span and preserves the database exception even if an observer fails. Pretend queries are skipped. Adobe CF and runtimes without complete native coverage use these hooks plus:

```cfml
result = sentry.withQuerySpan( sql, function( span ) {
    return queryExecute( sql, parameters, options );
}, "postgresql" );
```

An explicit query wrapper suppresses native/qb span creation for its execution. SQL literals/comments/numbers are scrubbed; unsupported quoting fails closed. Cached queries and query-of-queries have distinct attributes/operations and are not reported as database round trips. Generic SQL scrubbing is conservative; use signal filters if your schema/identifiers themselves contain sensitive information.

## Queues, caches, external calls and scheduled work

cbq reserves job properties.__sentry for enqueue timestamp, trace headers, and publish ID. New Scheduled/Started/Exited/Finished hooks carry an immutable executionId and attempt. Started/Exited bracket the actual worker body; Finished may run on a different thread. Handles are keyed by executionId, completion is atomic, and a late success cannot overwrite a timed-out attempt. Request/worker scopes are restored in finally; retention is bounded. Success, manual release, cancellation and failure statuses are recorded. Existing chain/batch paths dispatch through these boundaries. Their comprehensive provider/retry matrices remain deferred.

`getInstrumentedCache(name)` delegates CacheBox operations without serializing values; false/zero/empty-string values are hits. `inject="sentryCache:featureFlags"` is available to ColdBox consumers. The decorator forwards other methods but does not implement the ICacheProvider interface; use its underlying provider for consumers requiring that nominal type.

`withHttpSpan(url,callback,method)` calls callback(span,headers), records safe origin/method, and propagates only to configured targets. Set `http.response.status_code` from the response; exceptions record internal_error and rethrow. Never pass body or signed URL attributes. `captureLog(message,level,attributes)` emits structured INFO+ logs. The bridge accepts configurable application category prefixes, excludes framework/query debug chatter and extraInfo, and does not capture another error event. category mode emits a fixed diagnostic message with its technical category; use sanitized message mode only for an approved logging policy.

`counter`, `gauge`, and `distribution` emit typed trace_metric items with optional units/attributes. Request counts/durations, job outcomes/durations, and cache reads are seeded by integrations. `captureQueueMetrics(destination,depth,oldestAgeSeconds)` and `captureRuntimeGauges()` sample queue depth/age and inexpensive heap/thread values; schedule readers at a minute interval, not every idle poll.

```cfml
sentry.withMonitor( "hourly-work", function(){ return performWork(); }, {
    schedule: { type: "interval", value: 1, unit: "hour" },
    checkin_margin: 2, max_runtime: 10
} );
```

`captureCheckIn` and `withMonitor` use matching check-in IDs. Choose monitorSlugs according to your entitlement. Productive outbox work can use withTraceContext without a check-in for every two-second poll.

## Browser installation

Releases contain browser/dist/sentry-box.js and lazy ES-module chunks; plain layouts require no Node build. Alias only that directory (for example `/sentry-assets` to the installed module's browser/dist). Never expose the module root, settings, or application source. Browser sources/package metadata are also included for Vue bundler consumers.

CFML layout:

```cfml
<cfset browserConfig = sentry.getBrowserConfig()>
<script src="/sentry-assets/sentry-box.js"></script>
<script>
(async () => {
  const api = await SentryBox.ready();
  api.initializeBrowser(<cfoutput>#serializeJSON(browserConfig)#</cfoutput>);
  api.mountFeedbackWidget({ eligible: () => true });
})();
</script>
```

BoxLang layout uses `<bx:output>#JSONSerialize(sentry.getBrowserConfig())#</bx:output>` in the same initializer. Or import `/sentry-assets/esm/index.js` directly. Configure settings.browser with dsn, enabled, and optional localVerification/tracesSampleRate. getBrowserConfig exposes only public DSN/environment/release/sampling/targets. Encode JSON safely for your layout/CSP and never include arbitrary untrusted strings in an inline script.

Official SDK document tracing supplies supported LCP/CLS/INP/FCP/TTFB and resource/request timings. initializeBrowser reuses a supplied/existing client and otherwise creates one. For Inertia set inertia=true, start navigation explicitly using startInertiaNavigation(component), and finish on the navigation lifecycle. Subsequent navigation spans do not reuse document Web Vitals. Stable identities, URLs, interactions, and attributes are sanitized. Localhost/development verification must be enabled explicitly. Browser entry points rely on modern ES modules, crypto.subtle, AbortController and HTMLDialogElement; older browser compatibility is deferred.

## Feedback policy

Native `captureFeedback(message,page,associatedEventId,replayId,attachments,wait)` returns a receipt/event ID: queued is distinct from accepted, rejected, failed, disabled, filtered or dropped. Attachments are binary, bounded to 2MB, with safe filenames. Waiting is appropriate when confirming delivery. Browser confirmation waits for the matching event's ingestion 2xx; a generic SDK flush never proves acceptance.

The default widget offers pointer/touch/keyboard activation, drag-to-corner persistence, safe areas, focus restoration, reduced motion, configurable labels/className, review/removal, retry and object-URL cleanup. The custom controller is framework independent. Labels/disclosure should be translated by the host application. Screenshots include sanitized visible form state and use a configurable same-origin stylesheet policy. Limits are 1.5 million pixels, 2MB PNG, and eight seconds; capture failure preserves text feedback.

Capture defaults to conservative masking. Approved readable policy is explicit: configureCapturePolicy({readable:true,...}) or widget.policy. Shared exclusions cover dynamic/show-password controls, credentials, login codes, tokens, card/bank fields, hidden controls, explicit mask/block markers, unsafe attributes, signed media, hidden application state, network bodies, console/custom replay events. Protected-page/media and stylesheet rules are configurable. Replay is prohibited on query/fragment URLs. Eligible users lazy-load replay/screenshot code; setEnabled(false) stops recording and discards the buffer. percentageEligible uses a stable SHA256 rollout bucket matching the server. Feature-flag persistence and tenant authorization belong to the application.

Opening feedback immediately uploads the recent replay buffer. Message/PNG upload only on submission. The UI discloses this. Buffer freeze/restart/navigation operations guard overlapping flushes and stale captures. Automatic session and error replay sampling remain zero. Readable capture can contain personal information; Sentry project access is separate from tenant permissions. Review that access before enabling a readable policy.

## Dashboards and profiling

Use environment/release filters and stable route identities. Useful saved queries: `span.op:http.server` with p95(span.duration) grouped by transaction; `span.op:db*` grouped by span.description; `span.op:queue.process` with messaging.message.receive.latency/retry count; `span.op:cache.get` with cache.hit; `span.op:http.client span.status:internal_error`; metric.name:queue.depth/queue.oldest_age; metric.name:http.server.duration; and check-in monitor health. Availability of specialized feature screens is distinct from span ingestion and depends on the provider's conventions/entitlements.

Browser profiling needs a separate browser support/Document-Policy and overhead evaluation. This module does not enable profiling. JVM profiling would require an evaluated Java SDK/JFR integration; heap/thread gauges are not profiles. No profiling compatibility or overhead result is claimed.

See verification.md for commands, exact versions, provider proof and deferred checks.

Lucee 6 global listener cache classification requires the query result metadata to include cached (for queryExecute, an existing result option). Missing cache metadata is marked db.cache_status=unknown. Query-of-queries bypassed global listeners in 6.2.8.20; instrument those explicitly with withQuerySpan. Existing error handlers retain their handling behavior; absent one, the adapter throws the original query exception. See the [Lucee listener contract](https://docs.lucee.org/recipes/query-listener.html).
