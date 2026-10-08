<cfscript>
service = new sentry.models.SentryService( { DSN : "http://public@127.0.0.1:60320/1", tracesSampleRate : 1 } );
t = service.getObservability();
listener = t.registerBoxLangQueries( getApplicationMetadata().name );
root = service.startTransaction( "native query proof" ); t.setScope( { span : root } );
rows = queryNew( "id", "integer", [ { id : 1 } ] );
result = queryExecute( "select id from rows", [], { dbtype : "query" } );
writeOutput( serializeJSON( { "spans" : root.getChildren().len(), "payloads" : root.getChildren().map( ( span ) => span.toPayload() ) } ) );
root.finish(); service.shutdown();
</cfscript>
