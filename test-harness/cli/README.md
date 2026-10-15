# Real CLI regression

Run from the module root with BoxLang 1.17.2 (or newer), the Runwar servlet API,
ColdBox installed at `test-harness/coldbox`, and `funclinenums` installed at
`test-harness/modules/funclinenums`. Link this module to
`test-harness/modules/sentry` so ColdBox can discover it.

Set `BOXLANG_JAR`, `RUNWAR_JAR`, and `BOXLANG_HOME` to that installed runtime, then run:

```sh
node test-harness/cli/verify.mjs
```

The check starts an ephemeral loopback envelope receiver, launches the real
BoxRunner with no CGI scope, and exercises standalone message/exception capture
and a real ColdBox module bootstrap. It verifies all three delivered events,
actual host names, and the absence of invented HTTP requests or client IPs.
The receiver closes after either a pass or a failure. No external provider is used.

Keep the existing HTTP TestBox request URL, timestamp, and observability privacy
specs as the web contract checks:

```sh
box testbox run bundles=tests.specs.SentryRequestURLTests,tests.specs.SentryTimestampTests,tests.specs.ObservabilitySpec
```
