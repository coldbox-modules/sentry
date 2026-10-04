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
					},
					isBatchJob : function(){
						return false;
					}
				};
				var observation = { job : job, executionId : "attempt-1", attempt : 1 };
				var prior       = variables.service.startTransaction( "request" );
				variables.telemetry.setScope( { span : prior } );
				interceptor.onCBQJobAttemptScheduled( {}, observation );
				var scheduledAt = variables.telemetry.timestamp();
				sleep( 40 );
				interceptor.onCBQJobExecutionStarted( {}, observation );
				expect( variables.telemetry.getScope().span.toPayload().start_timestamp - scheduledAt ).toBeGTE(
					0.025
				);
				expect(
					variables.telemetry.getScope().span.toPayload().data[ "messaging.message.receive.latency" ]
				).toBeGTE( 25 );
				var context           = variables.service.getTraceContext();
				var attemptSpan       = variables.telemetry.getScope().span;
				var observerReference = createObject( "java", "java.util.concurrent.atomic.AtomicReference" ).init(
					interceptor
				);
				var callbackThread= "sentry-test-" & replace( createUUID(), "-", "", "all" );
				thread name       =callbackThread action="run" observer=observerReference data=observation {
					attributes.data.status = "deadline_exceeded";
					attributes.observer.get().onCBQJobAttemptFinished( {}, attributes.data );
				}
				thread action="join" name=callbackThread timeout=5000;
				expect( cfthread[ callbackThread ].status ).toBe( "COMPLETED" );
				expect( attemptSpan.toPayload().status ).toBe( "deadline_exceeded" );
				observation.status = "ok";
				interceptor.onCBQJobAttemptFinished( {}, observation );
				expect( attemptSpan.toPayload().status ).toBe( "deadline_exceeded" );
				interceptor.onCBQJobExecutionExited( {}, observation );
				expect( variables.service.getTraceContext().span_id ).toBe( prior.getContext().span_id );
				expect( interceptor.getPendingAttemptCount() ).toBe( 0 );
				observation.executionId = "attempt-2";
				observation.attempt     = 2;
				interceptor.onCBQJobAttemptScheduled( {}, observation );
				interceptor.onCBQJobExecutionStarted( {}, observation );
				var retrySpan = variables.telemetry.getScope().span;
				expect( retrySpan.toPayload().data[ "messaging.message.retry.count" ] ).toBe( 1 );
				interceptor.onCBQJobExecutionExited( {}, observation );
				observation.status = "cancelled";
				interceptor.onCBQJobAttemptFinished( {}, observation );
				expect( retrySpan.toPayload().status ).toBe( "cancelled" );
				expect( interceptor.getPendingAttemptCount() ).toBe( 0 );
				expect( variables.service.getTraceContext().span_id ).toBe( prior.getContext().span_id );
				prior.finish();
				expect( interceptor.getObservationFailureCount() ).toBe( 0 );
			} );
			it( "persists trace context for chained publication after callback scope cleanup", function(){
				var observer = createMock( "sentry.interceptors.QueueObservability" ).$property(
					"sentry",
					"variables",
					variables.service
				);
				var props = {};
				var chain = [ { properties : {} } ];
				var job   = {
					getId         : () => "synthetic-first",
					getProperties : () => props,
					getQueue      : () => "synthetic",
					getChained    : () => chain
				};
				var root = variables.service.startTransaction( "chain request" );
				variables.telemetry.setScope( { span : root } );
				observer.onCBQJobAdded( {}, { job : job } );
				var initial = props[ "__sentry" ].headers[ "sentry-trace" ];
				expect( chain[ 1 ].properties[ "__sentry" ].headers[ "sentry-trace" ] ).toBe( initial );
				observer.onCBQJobPublished( {}, { job : job } );
				expect( root.getChildren().len() ).toBe( 1 );
				expect( root.getChildren()[ 1 ].toPayload().data[ "messaging.message.id" ] ).toBe( "synthetic-first" );
				variables.telemetry.clearScope();
				var continuation = chain[ 1 ].properties;
				var nextJob      = {
					getId         : () => "synthetic-next",
					getProperties : () => continuation,
					getQueue      : () => "synthetic",
					getChained    : () => []
				};
				observer.onCBQJobAdded( {}, { job : nextJob } );
				expect( continuation[ "__sentry" ].headers[ "sentry-trace" ] ).notToBe( initial );
				expect( continuation[ "__sentry" ].headers[ "sentry-trace" ].left( 32 ) ).toBe(
					root.getContext().trace_id
				);
				observer.onCBQJobPublished( {}, { job : nextJob } );
				expect( variables.telemetry.getScope().isEmpty() ).toBeTrue();
				root.finish();
				expect( observer.getObservationFailureCount() ).toBe( 0 );
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
					expect( child.toPayload().data[ "cache.key" ] ).toBeArray();
					expect( child.toPayload().data[ "cache.key" ][ 1 ] ).toInclude( "sha256:" );
					expect( child.toPayload().data ).notToHaveKey( "cache.item_size" );
				}
				root.finish();
			} );
			it( "preserves failures unless an existing Lucee error listener handles them", function(){
				var listener = variables.service.createLuceeQueryListener();
				var root     = variables.service.startTransaction( "listener error" );
				variables.telemetry.setScope( { span : root } );
				listener.before( {}, { sql : "SELECT 'PRIVATE' AS id" } );
				var failure = {};
				try {
					throw( type = "SentryTest.QueryFailure", message = "original failure" );
				} catch ( SentryTest.QueryFailure original ) {
					failure = original;
				}
				try {
					listener.error( {}, {}, {}, failure );
					fail( "Failure must reach the caller" );
				} catch ( SentryTest.QueryFailure caught ) {
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
