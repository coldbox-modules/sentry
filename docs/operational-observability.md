# Operational observability

All collectors are called explicitly by the consumer. This module does not create uptime monitors, alert rules, scheduler tasks, polling threads, or notification destinations. Existing `enableMetrics`, `enableQueueTracing`, `enableMonitors`, trace sampling, and privacy filters still apply. Configure fixed labels; never derive names from URLs, tenant IDs, email addresses, filenames, job IDs, or exception messages.

## Delivery freshness

Set `enableDeliveryDiagnostics: true` to collect receipt diagnostics (default false). `sentry.deliveryDiagnostics()` reports whether collection is `enabled` and returns process-local envelope outcomes: `accepted`, `rejected`, `failed`, `dropped`, `filtered`, `disabled`, and `invalid` counters, plus `pending`, `oldestPendingSeconds`, `lastAttemptAt`, `lastAcceptedAt`, and `untracked`. Timestamps are Unix seconds; zero means no observation. Acceptance is HTTP acceptance by ingestion, not indexed/searchable data. The timestamp records when acceptance was observed, potentially during a later poll. Calling this API polls pending receipts without waiting for network completion. Retention is bounded by `maxPendingEnvelopes` (diagnostic cap 4096); `untracked` explicitly reports incomplete coverage. Counters reset on service restart. No payloads, event IDs, DSNs, response bodies, or exceptions are returned.

Poll it from an existing low-frequency scheduler or protected operator endpoint. Compare counter deltas and the last accepted timestamp across polls. Keep operator health independently accessible: sending an alarm exclusively through the broken ingestion path cannot reliably report that path's failure. Do not automatically include these diagnostics in public readiness responses. `getTransport().getDiagnostics()` remains available for transport capacity/rate-limit diagnostics. Legacy `/store` error posting is outside envelope receipt diagnostics; use `sentryEventEndpoint: "envelope"` when that coverage is required. Captures rejected before the transport boundary require application capture/lifecycle diagnostics.

Local freshness does not prove provider retention. Independently query the latest indexed sample for each expected metric, environment, and release. A missing queue series is unknown, not zero backlog. A fresh successful sampler poll with zero pending jobs is a measured zero. Do not replace missing series with zero in dashboards or alerts.

## Request phases and Server-Timing

```cfml
// moduleSettings.sentry; empty by default
requestTimingNames: [ "handler", "shared_props", "render" ]

// Create once per eligible request and keep it in PRC, never on a singleton.
prc.timings = sentry.newRequestTimings();
result = prc.timings.measure( "shared_props", function(){ return buildSharedProps(); } );
// Or begin(name) / finish(token, status="ok") around lifecycle hooks.

// Before response output, under the application's authorization/eligibility policy:
event.setHTTPHeader( name="Server-Timing", value=prc.timings.toServerTiming() );
```

This extracts the portable mechanism from CommuniArts' request timing service. Labels are restricted to 32 configured HTTP-safe names, 48 characters each; there are at most 64 samples per instance. Durations use a monotonic clock. Completion is atomic per token and telemetry failure preserves callback results/exceptions. `snapshot()` returns per-label duration in milliseconds and count. Child `app.phase` spans follow the current trace's sampling. Overlapping phases must not be summed. Instances are request-local; do not share an instance across parallel tasks. App-specific GET/route/authentication/Inertia eligibility, header publication, named phases, and root timing attributes stay in the app. No module interceptor emits a header automatically.

## Workflows and providers

```cfml
// Empty allowlists by default; also enable metrics/tracing as desired.
operationNames: [ "invitation_send", "pdf_process" ],
providerNames: [ "mail", "storage" ]

response = sentry.withOperation(
    name="invitation_send",
    provider="mail",
    callback=function(){ return mailClient.send( message ); },
    classify=function( response ){ return response.wasAccepted() ? "accepted" : "failed"; }
);
```

The callback runs once, even when telemetry setup/completion fails. Registered names produce an `app.workflow` child span plus `workflow.operations` and `workflow.duration` metrics (milliseconds), labeled with the fixed workflow/provider/outcome. Unregistered names/providers run without observation. Allowed outcomes are `success`, `accepted`, `delivered`, `retry`, `timeout`, `cancelled`, `failed`, and `unknown`. Missing classifier means callback `success`; an invalid or failing classifier means `unknown`. A thrown callback remains the original exception with outcome `failed`. Results and exception text never enter telemetry. `accepted` does not establish `delivered`; record actual delivery only from authenticated provider delivery evidence. Use existing `withSpan`, `withHttpSpan`, and `withTraceContext` for custom spans, outbound requests and background roots; do not wrap an already instrumented provider call twice just to obtain another HTTP span.

Audition submission, publishing, invitations, upload/PDF work and notification delivery are application workflows. Their names, business success/retry rules, compensation and provider-specific response/webhook interpretation are application policy. A workflow may include existing HTTP/storage/search spans without duplicating them.

## Queue metrics

Existing cbq integration uses immutable per-attempt handles, worker entry/exit scope restoration, atomic completion, receive latency, retry count, attempt outcome and processing duration. Completion callbacks may run on another thread; never replace handles with callback-thread scope lookups. A timeout wins over late success. Attempts that never started no longer emit a fictional zero processing duration. The root is completed before best-effort metric emission.

`queueMetricDestinations: [ "mail", "pdf" ]` opts into destination labels for attempt/wait metrics. Other destinations are aggregated without a destination attribute. Optional `enableQueueJobMetrics: true` adds `queue.jobs` counters from cbq's terminal `onCBQJobComplete`/`onCBQJobFailed` callbacks, with `completed`/`failed` outcomes. Attempt `internal_error`, `released` and timeout are not proof of exhausted retries; job failure is measured at the terminal hook. Terminal counters count hook notifications and do not provide durable job-ID deduplication. No job payload, result or exception enters these metrics. Consumers already counting terminal hooks should choose one producer.

For the cbq **database provider**, construct one sampler for each database/table being observed:

```cfml
sampler = new sentry.models.telemetry.DatabaseQueueMetrics(
    telemetry = sentry.getObservability(),
    config = wirebox.getInstance( "Config@cbq" ),
    queryFactory = function(){ return wirebox.getInstance( "QueryBuilder@qb" ); },
    table = "cbq_jobs",
    maxQueues = 64
);
// Existing consumer scheduler, for example once per minute:
ok = sampler.capture();
diagnostics = sampler.getDiagnostics();
```

The query factory must return a fresh qb builder configured with the correct datasource/grammar. Use a separate sampler for each connection; supply only worker definitions belonging to that connection. Redis, SQS and sync providers require their own supported queue-statistics adapters, not this table query. There is no mandatory qb/cbq dependency or automatic WireBox mapping.

Configured idle queues emit zero immediately after a successful poll. Dynamically observed queues are remembered so they return to zero when drained. Label retention and emissions are bounded (64 by default; maximum 256 per sampler lifetime). Additional queues are omitted and counted in `omittedQueues`; fixed worker names are strongly preferred. Poll failures emit no fabricated zero samples and update `failures`/`lastFailureAt` while retaining `lastSuccessAt`. Diagnostics contain no SQL or error text. Pending depth excludes reserved/completed/failed jobs and includes delayed jobs. Oldest age is since creation, not since runnable time. The query uses qb, including grammar-aware identifier quoting; never silently change a consumer's direct-SQL policy.

## JVM and database connections

Schedule existing `sentry.captureRuntimeGauges()` explicitly with `enableMetrics: true`. It now returns the samples it observed: heap used/max bytes, thread count, optional process CPU load (`jvm.cpu.process`, ratio 0–1), and cumulative GC collections/time (`jvm.gc.collections.total`, `jvm.gc.duration.total`, milliseconds). Negative/unsupported CPU or GC values are omitted. GC gauges are totals since JVM startup: calculate deltas over elapsed time and handle resets; do not sum cumulative samples or interpret them as pause percentiles. CPU uses an optional JVM MXBean attribute, not a BoxLang profiler. Heap/threads remain independent of CPU/GC availability. No sampling occurs when metrics are disabled.

Connection acquisition and pool visibility depend on the engine/provider. Query execution spans do not isolate connection waits. BoxLang currently falls back to qb when the native runtime lacks a caught-query failure event; direct native SQL is then absent from normal query tracing. Native Lucee query listeners remain supported as documented in [observability.md](observability.md). No CPU stack profiler, allocation profiler, JDBC driver patch or engine-internal datasource pool inspection is added here.

Use a supported provider/JMX adapter with `databasePoolNames: [ "primary" ]` and `sentry.captureDatabasePool( "primary", function(){ return poolAdapter.snapshot(); } )`. The callback returns any available nonnegative numeric `active`, `idle`, `max`, `waiters`, and cumulative `timeouts`; all other fields are discarded. `db.pool.utilization` is derived only from valid active/max values. Unsupported fields remain absent; callback failure returns false. Never return connection strings, credentials, datasource/tenant IDs, SQL, or exception text. Pool counters are gauges; compare deltas and account for JVM/pool resets. This is an optional adapter boundary, not a claim that these measurements are available on every CFML/BoxLang runtime.

If your provider exposes acquisition directly, use existing `withSpan( "primary connection", acquireCallback, "db.connection" )` strictly around its connection acquisition call, then execute queries under their normal query instrumentation. Do not label the entire query or transaction as connection wait. Do not acquire extra connections just to measure the pool.

## Alerts, availability and scheduled work

Use the consumer's Sentry environment/release consistently. In Sentry's [Monitors](https://docs.sentry.io/product/monitors-and-alerts/monitors/) UI, create metric monitors from the relevant Explorer query and attach the organization's chosen alert destination. Choose thresholds, minimum volume, sustained evaluation window, recovery window and notification routing based on the service's baseline and SLO. Verify the final query, filters, units, sampling, data availability and plan support before enabling it. Useful recipes:

| Concern | Input and evaluation |
| --- | --- |
| Error regression | Errors/request ratio plus minimum request count; sustained increase relative to the prior healthy window, grouped by environment/release. An exception event count is not automatically a request error rate. |
| Latency regression | p95 `http.server.duration` or request spans for fixed route templates, plus minimum samples and a sustained window. Keep absolute SLO and relative-change thresholds separate. |
| Queue health | Fresh `queue.depth`/`queue.oldest_age`, wait/processing duration, attempt outcomes and terminal failures. Treat sample absence as telemetry failure/unknown, not an empty queue. |
| JVM/pool pressure | Sustained CPU/heap ratio, GC time deltas, pool utilization/waiters/acquisition timeouts. Unsupported fields are gaps to investigate, not zero pressure. |
| Telemetry outage | Independent polling of local receipt/sampler diagnostics plus indexed latest timestamps and provider outcome/drop counters. Fresh HTTP acceptance alone does not establish indexed samples. |

For [external uptime monitoring](https://docs.sentry.io/product/monitors-and-alerts/monitors/uptime-monitoring/), create explicit monitors for the public liveness URL and application readiness URL. Use a cheap GET/HEAD, expected 2xx, bounded timeout and consecutive-failure/recovery thresholds. Liveness measures process reachability; readiness should return 503 when essential dependencies cannot serve traffic, without disclosing dependency details. Keep probes read-only and free of user data, credentials and session creation. Test each endpoint's actual response before saving a monitor. An external probe must run outside the application so it can detect a stopped app. The module cannot infer which dependencies define readiness.

Existing `withMonitor`/`captureCheckIn` already support scheduled jobs. Configure `enableMonitors`, a fixed `monitorSlugs` allowlist, and per-job schedule/timezone, `checkin_margin` and `max_runtime` through `monitorConfig` (see [Cron monitors](https://docs.sentry.io/product/monitors-and-alerts/monitors/crons/)). Wrap the actual job once: `withMonitor( "nightly-summary", runSummary, monitorConfig )`. An `in_progress`/`ok` pair with the same ID measures completion; error reports execution failure; provider-side missing-check-in/runtime rules detect missed or overrun jobs even when no callback returns. Schedule syntax, thresholds, destinations and monitor limits belong to the consumer. Do not create a monitor for every fast idle poll.

## Browser and release correlation

The companion and official browser SDK already provide browser tracing/Web Vitals and release/environment configuration. Keep that existing integration for LCP/INP/CLS. Do not initialize a second browser SDK. Compare vitals by fixed page/component name, release, browser and sufficient sample count. Retain existing navigation/resource span privacy filters. Network failures, CSP and dynamic-import failures are distinct observations; a later successful probe cannot prove the original request succeeded.

CommuniArts already has Vue/Inertia navigation tracing, Postmark/storage/Typesense spans, a bounded preload/resource diagnostic collector, and replay upload triggered by feedback. Those capture policies, screenshot/tunnel authorization and resource classification stay in the app. This change does not broaden replay/error capture or add redundant browser listeners. Ensure frontend and backend release IDs identify the actual deployed assets/source; package installation and accepted envelopes do not establish deployment or provider indexing.
