<cfscript>
setting showDebugOutput=false;
t = request.sentry.getObservability(); root = request.sentry.startTransaction( "Lucee native query listener verification" ); t.setScope( { "span" : root } );
result = queryExecute( "SELECT 1 AS id" );
caught = false;
try { queryExecute( "SELECT missing_column_for_sentry_verification" ); } catch( any expected ) { caught = true; }
queryExecute( "SELECT 2 AS id", [], { cachedWithin : createTimeSpan( 0, 0, 0, 30 ), result : "verificationMetadata" } );
queryExecute( "SELECT 2 AS id", [], { cachedWithin : createTimeSpan( 0, 0, 0, 30 ), result : "verificationMetadata" } );
request.listener = request.sentry.createLuceeQueryListener( listener = { before : function( caller, args ) { args.sql = "SELECT 3 AS id"; return arguments; } }, databaseSystem = "postgresql" );
transformed = queryExecute( "SELECT 99 AS id" );
request.sentry.withQuerySpan( "SELECT 4 AS id", function( span ){ return queryExecute( "SELECT 4 AS id" ); }, "postgresql" );
payloads = []; for( span in root.getChildren() ) { payloads.append( span.toPayload() ); }
if ( !caught || transformed.id[1] != 3 || payloads.len() != 6 || !( payloads[4].data["db.cached"] ?: false ) || payloads[2].status != "internal_error" ) { throw( message = "Native query listener regression" ); }
root.finish();
writeOutput( serializeJSON( { "version" : server.lucee.version, "caught" : caught, "transformedId" : transformed.id[1], "spans" : payloads } ) );
</cfscript>