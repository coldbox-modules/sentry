<cfscript>
service = new sentry.models.SentryService( { DSN : "http://public@127.0.0.1:60320/1", async : false, tracesSampleRate : 1, enableLogs : true, enableMetrics : true, enableMonitors : true } );
t = service.getObservability();
root = service.startTransaction( "GET /things/:id" );
t.setScope( { span : root } );
result = service.withSpan( "child", ( span ) => 42 );
root.finish();
writeOutput( serializeJSON( { result : result, headers : service.getTraceHeaders(), payload : root.toPayload(), diagnostics : t.getTransport().getDiagnostics() } ) );
service.shutdown();
</cfscript>
