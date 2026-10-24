# Operational observability

Collectors can run through the manual APIs or the opt-in configuration-driven background sampler below. The sampler owns one scheduled executor per service and stops with that service. This module does not create uptime monitors, alert rules, or notification destinations. Existing `enableMetrics`, `enableQueueTracing`, `enableMonitors`, trace sampling, and privacy filters still apply. Configure fixed labels; never derive names from URLs, tenant IDs, email addresses, filenames, job IDs, or exception messages.

## Delivery freshness

Set `enableDeliveryDiagnostics: true` to collect receipt diagnostics (default false). `sentry.deliveryDiagnostics()` reports whether collection is `enabled` and returns process-local envelope outcomes: `accepted`, `rejected`, `failed`, `dropped`, `filtered`, `disabled`, and `invalid` counters, plus `pending`, `oldestPendingSeconds`, `lastAttemptAt`, `lastAcceptedAt`, and `untracked`. Timestamps are Unix seconds; zero means no observation. Acceptance is HTTP acceptance by ingestion, not indexed/searchable data. The timestamp records when acceptance was observed, potentially during a later poll. Calling this API polls pending receipts without waiting for network completion. Retention is bounded by `maxPendingEnvelopes` (diagnostic cap 4096); `untracked` explicitly reports incomplete coverage. Counters reset on service restart. No payloads, event IDs, DSNs, response bodies, or exceptions are returned.

Poll it from an existing low-frequency scheduler or protected operator endpoint. Compare counter deltas and the last accepted timestamp across polls. Keep operator health independently accessible: sending an alarm exclusively through the broken ingestion path cannot reliably report that path's failure. Do not automatically include these diagnostics in public readiness responses. `getTransport().getDiagnostics()` remains available for transport capacity/rate-limit diagnostics. Legacy `/store` error posting is outside envelope receipt diagnostics; use `sentryEventEndpoint: "envelope"` when that coverage is required. Captures rejected before the transport boundary require application capture/lifecycle diagnostics.

Local freshness does not prove provider retention. Independently query the latest indexed sample for each expected metric, environment, and release. A missing queue series is unknown, not zero backlog. A fresh successful sampler poll with zero pending jobs is a measured zero. Do not replace missing series with zero in dashboards or alerts.

## Request phases and Server-Timing

```cfml
// Create once per eligible request and keep it in PRC, never on a singleton.
// Names are registered when used; no requestTimingNames setting is required.
prc.timings = sentry.newRequestTimings();
result = prc.timings.measure( "shared_props", function(){ return buildSharedProps(); } );
// Or begin(name) / finish(token, status="ok") around lifecycle hooks.

// Before response output, under the application's authorization/eligibility policy:
event.setHTTPHeader( name="Server-Timing", value=prc.timings.toServerTiming() );
```

`measure(name,callback)` and `begin(name)` register a phase on first use. No upfront allowlist is required. The optional `requestTimingNames` setting seeds names and their Server-Timing header order; it does not restrict later names. Names are deduplicated without regard to case and use the first spelling in spans, metrics, snapshots and headers. For example, `render` and `Render` both record under the first spelling.

Each instance retains at most 32 distinct names and 64 samples. Existing name validation still applies: 1–48 ASCII letters/digits/underscores, beginning with a letter; control characters are rejected. Invalid names or exhausted limits skip observation while the callback still runs once with its original return value/exception. Choose stable names for code blocks instead of generating names from user data. Durations use a monotonic clock. Tokens are opaque and belong to their creating instance; timing names, starts and span handles remain private. Foreign tokens and mutable extra token fields are ignored. Completion is atomic per token and telemetry failure preserves callback results/exceptions. `snapshot()` returns per-label duration in milliseconds and count. Child `app.phase` spans follow the current trace's sampling. Overlapping phases must not be summed. Instances are request-local; do not share an instance across parallel tasks. App-specific GET/route/authentication/Inertia eligibility and root timing attributes stay in the app. Manual instances leave header publication to the caller; the automatic instance publishes only when `publishServerTiming` is enabled.

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

Existing cbq integration uses immutable per-attempt handles, worker entry/exit scope restoration, atomic completion, receive latency, retry count, attempt outcome and processing duration. Completion callbacks may run on another thread; never replace handles with callback-thread scope lookups. A timeout wins over late success. Attempts that never started no longer emit a fictional zero processing duration. The completion timestamp is captured before exporter work, so serialization/delivery diagnostics cannot inflate processing duration. The root is completed before best-effort metric emission.

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

Configured idle queues emit zero immediately after a successful poll. Dynamically observed queues are remembered so they return to zero when drained. Exact destination identity is preserved, including queues that differ only in letter case. Label retention and emissions are bounded (64 by default; maximum 256 per sampler lifetime). Additional queues are omitted and counted in `omittedQueues`; fixed worker names are strongly preferred. Poll failures emit no fabricated zero samples and update `failures`/`lastFailureAt` while retaining `lastSuccessAt`. Diagnostics contain no SQL or error text. Pending depth excludes reserved/completed/failed jobs and includes delayed jobs. Oldest age is since creation, not since runnable time. The query uses qb, including grammar-aware identifier quoting; never silently change a consumer's direct-SQL policy.

## JVM and database connections

Schedule existing `sentry.captureRuntimeGauges()` explicitly with `enableMetrics: true`. It now returns the samples it observed: heap used/max bytes, thread count, optional process CPU load (`jvm.cpu.process`, ratio 0–1), and cumulative GC collections/time (`jvm.gc.collections.total`, `jvm.gc.duration.total`, milliseconds). Negative/unsupported CPU or GC values are omitted. GC gauges are totals since JVM startup: calculate deltas over elapsed time and handle resets; do not sum cumulative samples or interpret them as pause percentiles. CPU uses an optional JVM MXBean attribute, not a BoxLang profiler. Heap/threads remain independent of CPU/GC availability. No sampling occurs when metrics are disabled.

Connection acquisition and pool visibility depend on the engine/provider. Query execution spans do not isolate connection waits. BoxLang automatic query tracing stays off when the native runtime lacks a caught-query failure event; no query library is inferred. qb hooks require explicit selection. Native Lucee query listeners and custom/manual integrations remain supported as documented in [observability.md](observability.md). No CPU stack profiler, allocation profiler, JDBC driver patch or engine-internal datasource pool inspection is added here.

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

## Request saturation

Enable `enableMetrics: true` and `enableRequestSaturation: true` to count eligible ColdBox requests independently of trace sampling or `enableRequestTracing`. The existing `requestFilter` applies. Request capture starts one observation; `postProcess` and explicit `endRequest()` finish it once. The exception hook finishes its saturation observation even when ColdBox skips `postProcess`, while retaining an existing trace for error correlation. Always call `sentry.endRequest()` in Application.cfc/Application.bx `onRequestEnd` for early redirects/aborts and final trace/scope cleanup after exceptions. A hard engine termination that bypasses all cleanup cannot be detected reliably by the module.

Poll `sentry.captureRequestSaturation()` from an existing scheduler. It emits `http.server.active_requests`, `http.server.oldest_active` (seconds), `http.server.long_running`, and cumulative `http.server.untracked_starts.total`. `sentry.requestSaturation()` returns the same local snapshot without emitting. Ages use a monotonic JVM clock; `requestLongRunningSeconds` defaults to 30. Long-running requests are not automatically declared timed out. An authenticated engine/application timeout callback can call `endRequest(timedOut=true)` or `finishRequestObservation(token,timedOut=true)` to record `http.server.timeouts` once.

Standalone consumers can pair `token = sentry.beginRequestObservation()` with `sentry.finishRequestObservation(token)` in `finally`. Tokens have private start state and belong to their service. Retention is capped by `maxObservedRequests` (default/maximum 4096). When full, new starts are untracked and counted; observed active count is then a lower bound. Abandoned observations remain visible rather than silently expiring into a fabricated recovery. All counts reset on service restart; collection is local to that service/process.

Engine executor information is explicit because servlet/runtime pool APIs differ:

```cfml
// moduleSettings.sentry
requestExecutorNames: [ "http" ]

sentry.captureRequestExecutor( "http", function(){
    return executorAdapter.snapshot(); // active, max, queued, rejected (cumulative)
} );
health = sentry.requestExecutorDiagnostics( "http" );
```

Only finite nonnegative numeric fields are emitted as `http.server.executor.active`, `.max`, `.queued`, and `.rejected.total` gauges. The module does not inspect private engine pools. Unsupported fields stay absent. A failed or empty snapshot returns false, emits no fabricated zero, and updates bounded per-name `lastSuccessAt`, `lastFailureAt`, and `failures` diagnostics. Executor and worker samplers permit up to 32 configured technical names of 1–48 ASCII letters/digits/underscore/dot/hyphen; case aliases are deduplicated and callers must use the first configured spelling. Disabled metrics skip callbacks entirely.

## Dependency outcomes

```cfml
// moduleSettings.sentry
 dependencyNames: [ "mail", "storage", "search" ]

result = sentry.withDependency( "mail", function(){
    return mailClient.send( message );
}, function( result, failure ){
    if ( !isNull( arguments.failure ) ) {
        return { outcome: "error" }; // Map known exception types here; do not return exception text.
    }
    return {
        outcome: result.wasAccepted() ? "success" : "rejected",
        statusCode: result.statusCode,
        retryCount: result.retryCount,
        circuitState: result.circuitState
    };
} );
```

One callback invocation represents one logical dependency call, including any retries the callback owns. The wrapper never retries or changes circuit-breaker policy. It preserves the callback result, null/void return and original exception. The classifier receives `(result, failure)` with the unused argument null and may return only an allowlisted outcome (`success`, `error`, `timeout`, `connection_error`, `cancelled`, `rejected`, `unknown`), optional HTTP `statusCode` (100–599), nonnegative integer `retryCount`, and `circuitState` (`open`, `closed`, `half_open`). An exception cannot become `success`. Without a classifier, normal return means `success` and a thrown callback means `error`; invalid/failing classifiers produce `unknown`. The consumer must interpret provider responses—HTTP success is not necessarily business success or delivery.

The wrapper emits `dependency.calls`, `dependency.duration` (milliseconds) and optional `dependency.retries` distributions, with fixed dependency name/outcome and optional HTTP status class/circuit state. Duration covers the callback, excluding telemetry setup, classification and export. Circuit state describes the observed call; it is not a continuously sampled breaker gauge. An `app.dependency` span follows existing sampling. Existing `withHttpSpan` remains the transport span/propagation mechanism; wrap it inside this logical dependency observation where appropriate, without adding a second HTTP span. Results, bodies, exception messages and URLs never become dependency metric labels. Unconfigured names or disabled metrics run the callback directly without classification or observation.

## Queue health

```cfml
// moduleSettings.sentry
queueNames: [ "mail" ]

// Choose a provider adapter explicitly. This example uses the adapter shipped by cbq.
queueAdapter = wirebox.getInstance( "QueueHealthAdapter@cbq" );
sentry.captureQueueHealth( "mail", function(){
    return queueAdapter.sample( { options: { pool: "outbound" } } );
} );

// Or call another queue provider's supported snapshot API:
sentry.captureQueueHealth( "mail", function(){
    return otherQueueProvider.workerSnapshot();
} );
health = sentry.queueHealthDiagnostics( "mail" );
```

The cbq queue adapter combines provider queue measurements with configured worker concurrency and active executions from executor statistics when the executor advertises task-method support. Its current executor capacity is not an activity count. An unavailable/uninitialized executor leaves active executions absent; these measurements do not prove that workers are alive. A provider snapshot may additionally supply actual `activeWorkers`, `lastHeartbeatAt` (JVM-compatible Unix seconds), `runnable`, `delayed`, `reserved`, `staleReservations`, and cumulative `retries`/`exhausted`. Fields map to `queue.workers.configured`, `queue.workers.active`, `queue.executions.active`, `queue.worker.heartbeat_age` (seconds), `queue.backlog.runnable`, `.delayed`, `.reserved`, `queue.reservations.stale`, `queue.retries.total`, and `queue.exhausted.total`, labeled by the configured `queue.name`. A heartbeat must come from real worker activity; zero/absent/future heartbeat timestamps are omitted. A successful poll does not manufacture a worker heartbeat.

Only available finite nonnegative numeric fields are emitted. Cumulative retry/exhaustion gauges reset with their provider; compute deltas and handle resets. They differ from existing per-attempt and terminal-hook counters. Choose one producer for each series. Failed/empty snapshots emit no fabricated zeros and leave the last successful timestamp unchanged; read diagnostics to detect stale polling. Manual capture creates no polling threads. The optional automatic sampler is described below; neither mode mutates queues or captures job IDs/payloads.

The cbq adapter asks its configured provider for queue health. Its database provider owns the table, datasource and aggregate query; these are not Sentry settings. Older manual integrations can still use the optional compatibility facade:

```cfml
queueHealth = new sentry.models.telemetry.DatabaseQueueHealth(
    queryFactory = function(){ return wirebox.getInstance( "QueryBuilder@qb" ); },
    table = "cbq_jobs"
);
sentry.captureQueueHealth( "mail", function(){
    return queueHealth.snapshot( "mail" );
} );
```

Use a fresh correctly configured qb builder per call. `snapshot(queue)` performs one parameterized aggregate query excluding completed/failed jobs. Unclaimed jobs are runnable when `availableDate <= now`, delayed otherwise. Reserved/claimed jobs form a separate total; a lease is stale when its `availableDate <= now`, matching the inspected cbq database-provider lease convention. These are database observations, not proof of a running worker or permission to release a lease. Configured worker definitions/connection selection and scheduler cadence belong to the consumer. Other providers need their own supported snapshot adapter. No mandatory qb/cbq dependency is added.

### Local database and worker integration tests

`DatabaseQueueHealthIntegrationSpec` is opt-in. Without `SENTRY_QUEUE_HEALTH_DB`, it registers no tests and the ordinary harness needs no database or cbq installation. To enable it:

1. Create an empty disposable PostgreSQL database on **127.0.0.1:5432**, accessible as local test role `postgres` without a password. Its name must begin with `sentry_queue_health_` and contain only lowercase ASCII letters, digits and underscores. Never point this fixture at an application database.
2. Place read-only local dependency links at `test-harness/modules/qb`, `test-harness/modules/cbq` and `test-harness/modules/str` (the latter can point to cbq's nested str module). These paths are ignored. Set `SENTRY_QB_SOURCE` and `SENTRY_CBQ_SOURCE` to the matching local sources, and `SENTRY_QUEUE_HEALTH_DB` to the dedicated database name in the owned server environment.
3. Supply the engine's PostgreSQL JDBC driver. The verified Lucee runtime uses its existing `org.postgresql.jdbc` 42.6.0 bundle. The BoxLang runtime uses that driver JAR in its isolated servlet classpath. Adobe requires its `postgresql` CFPM package; copying a driver JAR alone does not satisfy its package registration. Do not change an application/server shared with other work.
4. Start the loopback envelope receiver, then run `/tests/runner.cfm?directory=&reporter=json&bundles=tests.specs.DatabaseQueueHealthIntegrationSpec` on the local harness server. The full normal runner and telemetry runner include the opt-in bundle as well. Run engine suites sequentially against the shared receiver.

The integration fixture loads the real cbq module and registers its own database connections/pools. Jobs are serialized, persisted, fetched by cbq's real scheduled poller, deserialized and executed on actual cbq worker executors. Java latches hold a job while sampling reservation and executor activity. Tests cover empty/mixed queues, bound queue-name parameters, idle/busy/drained workers, delayed execution, retries, terminal exhaustion, expired execution leases and staged claims. Lease recovery uses deliberately expired fixture rows; it does not kill a worker process or qualify crash recovery.

Each case creates a uniquely named table in the dedicated database and drops it afterward. Teardown stops polling, releases blocked jobs, drains/shuts down workers, removes executor/config registrations, clears shared state and closes telemetry. A forced-drain-failure regression verifies cleanup continues after an error. Synthetic failures cannot inherit an external `SENTRY_DSN`: this mode forces the module's receiver URL to loopback and disables automatic error/appender capture. No application dependency source or provider settings are modified.


## Configuration-driven automatic collection

Manual APIs remain available. Enable metrics, configure a valid DSN, and enable one periodic sampler. Queue collection has **one** provider-neutral setting: `automaticCollectors.queues`. Each queue adapter supplies the fields its provider supports; worker measurements, backlog, age and lease health do not require separate collectors.

```cfml
moduleSettings.sentry = {
    DSN: getSystemSetting( "SENTRY_DSN", "" ),
    enableMetrics: true,
    enableRequestSaturation: true,
    enableAutomaticRequestTimings: true,
    publishServerTiming: false,
    automaticCollectors: {
        enabled: true,
        intervalSeconds: 60,
        runtime: true,
        requestSaturation: true,
        queues: [ {
            // One fixed logical queue label, independent of provider identifiers.
            name: "mail",
            // Explicit provider-owned implementation; there is no default provider.
            adapter: "QueueHealthAdapter@cbq",
            // Adapter-specific selection. cbq derives its provider and queues from this pool.
            options: { pool: "outbound" }
        } ],
        requestExecutors: [ { name: "http", adapter: "HttpExecutorSnapshot" } ],
        databasePools: [ { name: "primary", adapter: "PrimaryPoolSnapshot" } ]
    }
};
```

A different queue provider supplies a different adapter or callback, with its own options. A backlog-only adapter can return `{depth:0}`; no worker fields are required. A combined snapshot can return `{depth:7,oldestAgeSeconds:15,configuredWorkers:4,activeExecutions:2,runnable:5,delayed:2,reserved:1}`. Only measured finite nonnegative fields are emitted. Supported fields include `depth`, `oldestAgeSeconds`, `configuredWorkers`, `activeWorkers`, `activeExecutions`, `lastHeartbeatAt`, `runnable`, `delayed`, `reserved`, `staleReservations`, `retries` and `exhausted`. All automatic queue series use the fixed `queue.name` label. Missing capabilities remain absent; a failed snapshot records a failed poll instead of fake zeros.

The former automatic `queueWorkers` and `databaseQueues` settings are replaced by `queues`; they are not aliases or additional collector types. There is no SQL builder, table name, datasource, default queue provider or cbq schema in Sentry's automatic collection path. Those choices belong to the selected adapter/provider. Configured queue names extend the bounded `queueNames` allowlist. Worker and backlog data are sampled once per definition, with a shared `queueHealthDiagnostics(name)` freshness/failure record. `captureQueueHealth(name,callback)` uses the same snapshot contract for explicit manual collection. Legacy manual worker APIs and their `worker.name` labels remain available for existing integrations.

The fixed delay starts after the first interval and follows the end of each cycle. It defaults to 60 seconds, permitting integer intervals from 1 through 3600. Cycles cannot overlap; slow adapters delay later cycles. Keep callbacks bounded and configure query/network timeouts in the provider. Shutdown prevents dispatching later adapters; an already-running callback may take time to return. ColdBox's context-aware Runnable establishes the engine application context for named datasources and releases Adobe JDBC thread state. The sampler isolates/restores trace scope, continues after adapter failures, and retains bounded process-local diagnostics through `automaticCollectorDiagnostics()`. It does not send its own failure details recursively through telemetry.

Each group processes at most 32 definitions. Partial overrides inherit defaults. `requestSaturation` also requires `enableRequestSaturation`. `deliveryDiagnostics:true` polls local receipts. Avoid multiple producers for the same series. `collectAutomaticMetrics()` shares the non-overlap guard; `startAutomaticCollectors()` is idempotent. Restart the service after changing configuration.

### Callback and WireBox adapter contracts

Adapters can be callbacks, WireBox mapping IDs, compatible objects, or `{mapping,method}` descriptors. Mappings are resolved lazily. Snapshot context contains the fixed `name`, collector `kind` and a copy of the definition's `options` struct. Options never become metric attributes.

| Adapter | Callback / interface method | Result |
| --- | --- | --- |
| Queue, executor or pool snapshot | callback(context) / ISnapshotAdapter.sample(context) | Supported numeric fields |
| Dependency classifier | callback(result,failure) / IDependencyClassifier.classify(result,failure) | Bounded outcome/status/retry/circuit fields |
| Query tracing setup | callback(context) / IQueryAdapter.configure(context) | Built-in mode or `{mode:"custom",shutdown:callback}` |

Interfaces live under `sentry.models.telemetry.adapters`. Compatible provider adapters need not import Sentry's interface or depend on Sentry. Standalone services can use callbacks/objects; mapping IDs require an injector (ColdBox supplies it). Query tracing configuration receives `context.telemetry` and `context.applicationName`; built-in `queryAdapter` values `none`, `qb`, `lucee`, `auto` and `boxlang` retain their behavior. Custom setup can install query hooks and return a shutdown callback. This controls query tracing, independently of queue snapshots; there is no queue-specific query factory setting.

### cbq adapter ownership

The optional cbq integration lives in cbq as `QueueHealthAdapter@cbq` and requires explicit `options.pool`. It resolves the actual pool each time, reads its provider and queue selection, and combines worker activity with any supported `getQueueHealth(queue)` provider snapshot. An optional `options.queue` overrides the selected queue(s). Otherwise the pool's queue name/array/wildcard selection is used. cbq's database provider applies its own configured table and query options/datasource. Other cbq providers without queue-snapshot support still report supported worker measurements, without invented backlog or heartbeat values.

Worker measurements describe the entire pool, including when `options.queue` narrows the backlog selection. Prefer one collector per pool for combined measurements; separate per-queue backlog-only adapters should avoid duplicating shared pool activity.

The installed cbq version must contain the adapter; existing releases do not gain it automatically. `WorkerHealthAdapter@cbq` remains a compatibility alias. Sentry's legacy `captureCBQWorkerHealth(name,pool)` and `DatabaseQueueHealth(queryFactory,table)` entrypoints delegate to cbq's optional implementations. New integrations should use the unified adapter contract. Neither module requires the other as an installed dependency.

### Automatic dependency and request instrumentation

A dependencyAdapters entry binds WireBox AOP to the exact mapping and named public methods. Up to 32 entries and 16 methods per entry are retained. It observes normal calls to WireBox-created instances without a manual wrapper. Objects created with new, already-created singletons and internal calls bypassing the WireBox proxy require the manual API. Bindings are registered at module load; dependencyAdapterGenerationPath selects a writable mapping for generated AOP code when the module installs the Mixer listener. Existing Mixer configuration is reused.

Classification follows the manual withDependency contract. A failing classifier yields unknown and cannot replace the original result/exception. The same dependency name is observed once when a manual wrapper and automatic method advice overlap or nest; the outer observation supplies its classifier. Different configured dependency names remain separate logical observations. Method arguments, results and raw exceptions never become telemetry attributes.

With enableAutomaticRequestTimings, ColdBox preEvent/postEvent measure handler work and preRender/postRender measure rendering, using a shared request-local timing instance. These are framework boundaries, not individually classified business operations. Automatic finishes also emit http.server.phase.duration in milliseconds. Open phases are drained on exceptions and explicit endRequest, including early redirects; keep the Application onRequestEnd fallback. Nested events can overlap, so do not sum their durations as wall time. The optional Server-Timing header is only published when publishServerTiming is true and an optional serverTimingFilter(event) permits it; responses that already committed headers cannot receive it.

Manual newRequestTimings()/measure() and withDependency()/withOperation() remain available. sentry.getRequestTimings() returns the active automatic instance, or null outside an automatically timed request. Additional manual phases work without requestTimingNames configuration. Use distinct names instead of timing the same automatic handler/render interval again.
