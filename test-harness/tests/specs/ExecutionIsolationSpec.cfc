component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "isolated execution and cache observation", function(){
			beforeEach( function(){
				variables.service = new sentry.models.SentryService( {
					DSN                : "http://public@127.0.0.1:60320/1",
					tracesSampleRate   : 1,
					enableQueueTracing : true
				} );
				variables.telemetry = variables.service.getObservability();
			} );
			afterEach( function(){
				variables.service.shutdown();
			} );
			it( "preserves trusted sampling baggage without credential labels", function(){
				var root = variables.service.startTransaction(
					"task",
					"task",
					{
						"sentry-trace" : repeatString( "a", 32 ) & "-" & repeatString( "b", 16 ) & "-1",
						"baggage"      : "sentry-release=release-1,sentry-user_id=PRIVATE,other=PRIVATE"
					},
					true
				);
				variables.telemetry.setScope( { span : root } );
				var headers = variables.service.getTraceHeaders();
				expect( headers.baggage ).toInclude( "release-1" );
				expect( headers.baggage ).notToInclude( "PRIVATE" );
				root.finish();
			} );
			it( "closes a timed out attempt on another thread and cleans the worker scope after late exit", function(){
				var interceptor = createMock( "sentry.interceptors.QueueObservability" ).$property(
					"sentry",
					"variables",
					variables.service
				);
				var properties = {};
				var job        = {
					getProperties : function(){
						return properties;
					},
					getId : function(){
						return "synthetic-id";
					},
					getQueue : function(){
						return "synthetic";
					},
					getMapping : function(){
						return "SyntheticJob";
					}
				};
				var observation = { job : job, executionId : "attempt-1", attempt : 1 };
				var prior       = variables.service.startTransaction( "request" );
				variables.telemetry.setScope( { span : prior } );
				interceptor.onCBQJobAttemptScheduled( {}, observation );
				interceptor.onCBQJobExecutionStarted( {}, observation );
				var context       = variables.service.getTraceContext();
				var attemptSpan   = variables.telemetry.getScope().span;
				var callbackThread= "sentry-test-" & replace( createUUID(), "-", "", "all" );
				thread name       =callbackThread action="run" observer=interceptor data=observation {
					attributes.data.status = "deadline_exceeded";
					attributes.observer.onCBQJobAttemptFinished( {}, attributes.data );
				}
				thread action="join" name=callbackThread timeout=5000;
				expect( attemptSpan.toPayload().status ).toBe( "deadline_exceeded" );
				observation.status = "ok";
				interceptor.onCBQJobAttemptFinished( {}, observation );
				expect( attemptSpan.toPayload().status ).toBe( "deadline_exceeded" );
				interceptor.onCBQJobExecutionExited( {}, observation );
				expect( variables.service.getTraceContext().span_id ).toBe( prior.getContext().span_id );
				expect( interceptor.getPendingAttemptCount() ).toBe( 0 );
				prior.finish();
			} );
			it( "finishes a redirected request once and restores the previous scope", function(){
				var previous = { "test" : true };
				var span     = variables.service.startTransaction( "GET /redirect" );
				variables.telemetry.setScope( {
					"span"         : span,
					"requestState" : { "span" : span, "previous" : previous }
				} );
				variables.service.endRequest( statusCode = 303 );
				expect( span.toPayload().data[ "http.response.status_code" ] ).toBe( 303 );
				expect( variables.telemetry.getScope() ).toBe( previous );
				expect( span.finish() ).toBeFalse();
			} );
			it( "does not duplicate a manual query span when a runtime listener observes it", function(){
				var root = variables.service.startTransaction( "query wrapper" );
				variables.telemetry.setScope( { "span" : root } );
				var listener = variables.service.createLuceeQueryListener();
				variables.service.withQuerySpan( "SELECT 'PRIVATE'", function( span ){
					listener.before( {}, { sql : "SELECT 'PRIVATE'" } );
					listener.after( {}, {}, {}, {} );
					return 42;
				} );
				expect( root.getChildren().len() ).toBe( 1 );
				root.finish();
			} );
			it( "keeps false, zero, and empty cached values as hits while delegating the provider", function(){
				var values   = { "false" : false, "zero" : 0, "empty" : "" };
				var provider = {
					getName : function(){
						return "synthetic";
					},
					get : function( objectKey ){
						return values[ objectKey ];
					},
					getCacheID : function(){
						return "original";
					}
				};
				var cache = new sentry.models.telemetry.InstrumentedCache( provider, variables.telemetry );
				var root  = variables.service.startTransaction( "cache test" );
				variables.telemetry.setScope( { span : root } );
				expect( cache.get( "false" ) ).toBeFalse();
				expect( cache.get( "zero" ) ).toBe( 0 );
				expect( cache.get( "empty" ) ).toBe( "" );
				expect( cache.getCacheID() ).toBe( "original" );
				for ( var child in root.getChildren() ) {
					expect( child.toPayload().data[ "cache.hit" ] ).toBeTrue();
				}
				root.finish();
			} );
			it( "preserves failures unless an existing Lucee error listener handles them", function(){
				var listener = variables.service.createLuceeQueryListener();
				var root     = variables.service.startTransaction( "listener error" );
				variables.telemetry.setScope( { span : root } );
				listener.before( {}, { sql : "SELECT 'PRIVATE' AS id" } );
				var failure = { type : "database", message : "original failure" };
				try {
					listener.error( {}, {}, {}, failure );
					fail( "Failure must reach the caller" );
				} catch ( database caught ) {
					expect( caught.message ).toBe( failure.message );
				}
				expect( root.getChildren()[ 1 ].toPayload().status ).toBe( "internal_error" );
				expect( root.getChildren()[ 1 ].toPayload().description ).toBe( "SELECT ? AS id" );
				var composed = variables.service.createLuceeQueryListener(
					listener = {
						error : function(){
							return { result : "handled" };
						}
					}
				);
				composed.before( {}, { sql : "SELECT missing" } );
				expect( composed.error( {}, {}, {}, failure ).result ).toBe( "handled" );
				root.finish();
			} );
			it( "composes Lucee transformations without exporting callback values", function(){
				var existing = {
					before : function( caller, args ){
						args.sql = "SELECT 'PRIVATE'";
						return { args : args };
					},
					after : function(){
						return { result : "unchanged" };
					}
				};
				var listener = new sentry.models.telemetry.LuceeQueryListener( variables.telemetry, existing );
				var root     = variables.service.startTransaction( "listener" );
				variables.telemetry.setScope( { span : root } );
				expect( listener.before( {}, { sql : "SELECT original" } ).args.sql ).toBe( "SELECT 'PRIVATE'" );
				expect( listener.after( {}, {}, {}, {} ).result ).toBe( "unchanged" );
				expect( root.getChildren()[ 1 ].toPayload().description ).notToInclude( "PRIVATE" );
				root.finish();
			} );
		} );
	}

}
