# Performance dashboard recipes

These offline recipes describe queries for Sentry's widget builder. They never
create dashboards, deploy code, change sampling, send telemetry or create alerts.
They are **not** an API import payload. Dataset and query serialization can differ
between Sentry releases: Explore calls application metrics `metrics`, while saved
dashboard widgets currently use `tracemetrics`.

Copy `consumer.example.json` outside the module. Replace project slugs and the
readiness description, and verify the phase field against live data before use:

```sh
node dashboards/build-recipes.mjs /path/to/consumer-config.json > /path/to/recipes.json
node --test dashboards/build-recipes.test.mjs
```

Organization, dashboard/project IDs, tokens and consumer routes do not belong in
module defaults. Consumers own readiness and authorization policy. The generator
uses Node built-ins without network requests. Its tests check scope isolation,
readiness exclusion, phase separation and metric sample coverage. These files
change no CFML runtime behavior.

## Updating an existing dashboard

1. Inspect the consumer's immutable module pin and serving release separately from
   the local checkout. These recipes require observability telemetry; an older
   2.1.x checkout does not establish its availability.
2. Save the complete existing dashboard definition before editing. Preserve widget
   IDs, relevant views, filters, production environment and seven-day default.
   Keep consumer snapshots and raw query evidence outside the reusable module.
   A connector Markdown definition is a reviewable saved-query snapshot, not a
   lossless API restoration payload.
3. Prefer the Sentry connector for inspection and validation. If dashboard writes
   are unavailable, apply recipes through the browser widget builder. Recipe
   `fields` describe table columns; use aggregates as chart series and `groupBy`
   as chart breakdowns. Preview changed queries against live data before saving.
4. Save and read the dashboard back through the connector. Compare datasets,
   conditions, fields, groupings, defaults and IDs. Capture screenshots of the
   saved dashboard and the affected labels.

## Query contracts

| Signal          | Query                                                                              | Interpretation                                                                                                                                                                                                |
| --------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| HTTP            | Backend `http.server`; exact readiness description split                           | Pair application percentiles with identical-filter counts. Retain readiness count/p95/status/release views. Non-readiness still includes security probes, failures and assets.                                |
| Routes/releases | Description and release with count/p95                                             | Use parameterized routes. Sparse rows limit tail estimates. Label suspect asset lifecycle timing explicitly; do not silently exclude slow spans.                                                              |
| DB              | `db.query`; p95/count/cumulative duration; scrubbed shape and parent `transaction` | Parent grouping separates probe queries. Cumulative span time is workload, not request latency. Coverage may be incomplete. Never include SQL bindings or remove security/readiness checks to improve charts. |
| Browser         | Frontend `pageload`/`navigation`                                                   | Preserve project distinctions and sample counts. Pageload duration is not FCP or proof of first-paint experience.                                                                                             |
| JVM             | `jvm.heap.used` gauge/byte; `jvm.threads` gauge/none                               | Unsupported/absent metrics remain absent.                                                                                                                                                                     |
| Queue pools     | `has:queue.name`, group `queue.name`; depth gauge/none and oldest-age gauge/second | Labels describe worker pools; a mail pool can cover several destinations. Never merge legacy `messaging.destination.name` history or sum overlapping collectors.                                              |
| Queue coverage  | Counts of each gauge with matching pool filter                                     | Positive samples plus zero gauge means measured zero. Missing/no samples means unknown. Inspect recent hourly buckets and Explore samples for freshness; a seven-day average is not current queue state.      |
| Phases          | Both `app.phase`/`app.navigation`, group by operation and verified phase field     | Inclusive phases overlap: never sum them. Automatic and focused instrumentation have different populations. Sort by count to keep automatic phases visible.                                                   |

Sentry may display empty buckets at a baseline or connect neighboring samples.
A chart line alone cannot distinguish missing data from zero. Keep per-signal
sample coverage visible and explain this in widget descriptions. Never add
zero-filling formulas, use sums to disguise gaps, or infer uptime from absent
probes. Counts describe recorded telemetry, not necessarily all generated events.
Do not change sampling to improve appearance.

Sample cadence depends on collector configuration and the number of running
instances. Higher counts can reflect concurrent instances or lifecycle overlap;
they are not an uptime percentage. Prefer per-pool averages over sums for gauges.

## Verifying the phase field

Raw spans can contain `description: handler` while their displayed/indexed `name`
is `app.phase`. Query both `span.name` and `span.description` with count, then
filter a known phase and verify a raw trace example. Confirm the saved widget
preview resolves the same labels. One current Sentry dataset groups handler/render
under `span.description` while `span.name` stays `app.phase`; recheck for each
consumer. `phaseField` is explicit configuration, not an inferred SDK attribute.

If no deployed field works, retain operation-level coverage, mark the breakdown
pending deployment, and implement a bounded SDK attribute in the official module
with focused tests. A local SDK change is not evidence of live ingestion.

## Adoption boundaries

Dashboard edits, local checks, hosted CI, publication, consumer dependency adoption,
deployment and live ingestion are separate claims. Dashboard-only changes can use
already indexed data without deployment. These recipe checks do not require the
full CFML/browser matrix. Alerts, schedules, notification destinations, sampling,
credentials and unrelated production settings need separate task authorization.
