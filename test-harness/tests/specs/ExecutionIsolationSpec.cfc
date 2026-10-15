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
			it( "reads the publication sweep clock once per callback while preserving expiry and every new trace", function(){
				var clock     = variables.telemetry.timestamp();
				var reads     = createObject( "java", "java.util.concurrent.atomic.AtomicLong" ).init( 0 );
				var telemetry = prepareMock( variables.telemetry );
				telemetry
					.$( "timestamp" )
					.$callback( function(){
						reads.incrementAndGet();
						return clock;
					} );
				var pending  = createObject( "java", "java.util.concurrent.ConcurrentHashMap" ).init();
				var observer = createMock( "sentry.interceptors.QueueObservability" )
					.$property( "sentry", "variables", variables.service )
					.$property( "publishes", "variables", pending );
				var finished = [];
				function abandonedSpan( required string label, required array completions ){
					var label     = arguments.label;
					var eventSink = arguments.completions;
					return {
						finish : function( status ){
							eventSink.append( label & ":" & status );
						}
					};
				}
				function publicationJob( required numeric index ){
					var properties = {
						"deliveryId" : "native-" & arguments.index,
						"private"    : "PRIVATE"
					};
					var id = "job-" & arguments.index;
					return {
						getId         : () => id,
						getProperties : () => properties,
						getQueue      : () => "notifications",
						getChained    : () => []
					};
				}
				var root = variables.service.startTransaction( "bulk publication" );
				telemetry.setScope( { span : root } );
				var baseline = publicationJob( 0 );
				reads.set( 0 );
				observer.onCBQJobAdded( {}, { job : baseline } );
				var callbackReads = reads.get();
				expect( callbackReads ).toBeGTE( 3 );
				observer.onCBQJobPublished( {}, { job : baseline } );
				expect( pending.size() ).toBe( 0 );
				for (
					var entry in [
						{ id : "expired-owned", age : 3601, ownsRoot : true },
						{ id : "expired-borrowed", age : 3601, ownsRoot : false },
						{ id : "exact-boundary", age : 3600, ownsRoot : true },
						{ id : "live", age : 10, ownsRoot : true }
					]
				) {
					pending.put(
						entry.id,
						{
							created  : clock - entry.age,
							ownsRoot : entry.ownsRoot,
							span     : abandonedSpan( entry.id & "-span", finished ),
							root     : abandonedSpan( entry.id & "-root", finished )
						}
					);
				}
				var jobs = [];
				reads.set( 0 );
				for ( var index = 1; index <= 20; index++ ) {
					var job = publicationJob( index );
					jobs.append( job );
					observer.onCBQJobAdded( {}, { job : job } );
					var metadata = job.getProperties()[ "__sentry" ];
					expect( metadata.enqueuedAt ).toBe( clock );
					expect( reFind( "^[a-f0-9]{32}$", metadata.publishId ) ).toBe( 1 );
					expect( metadata.headers[ "sentry-trace" ].left( 32 ) ).toBe( root.getContext().trace_id );
					expect( metadata.headers[ "sentry-trace" ].right( 2 ) ).toBe( "-1" );
					expect( JSONSerialize( metadata ) ).notToInclude( "PRIVATE" );
					expect( telemetry.getScope().span.getContext().span_id ).toBe( root.getContext().span_id );
				}
				expect( reads.get() ).toBe( callbackReads * 20 );
				expect( pending.size() ).toBe( 22 );
				expect( pending.containsKey( "exact-boundary" ) ).toBeTrue();
				expect( pending.containsKey( "live" ) ).toBeTrue();
				expect( finished.sort( "text" ) ).toBe( [
					"expired-borrowed-span:deadline_exceeded",
					"expired-owned-root:deadline_exceeded",
					"expired-owned-span:deadline_exceeded"
				] );
				for ( var job in jobs ) {
					observer.onCBQJobPublished( {}, { job : job } );
				}
				expect( pending.size() ).toBe( 2 );
				expect( root.getChildren().len() ).toBe( 21 );
				expect( root.getChildren().every( ( span ) => span.isFinished() ) ).toBeTrue();
				expect( observer.getObservationFailureCount() ).toBe( 0 );
				root.finish();
			} );
			it( "skips healthy publication scans and expires backwards-clock entries without holding the registry lock during callbacks", function(){
				var clock     = variables.telemetry.timestamp();
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "timestamp" ).$callback( () => clock );
				var pending  = createObject( "java", "java.util.concurrent.ConcurrentHashMap" ).init();
				var scans    = createObject( "java", "java.util.concurrent.atomic.AtomicLong" ).init( 0 );
				var registry = {
					isEmpty : () => pending.isEmpty(),
					size    : () => pending.size(),
					put     : ( id, value ) => pending.put( id, value ),
					get     : ( id ) => pending.get( id ),
					remove  : ( id ) => pending.remove( id ),
					keySet  : function(){
						scans.incrementAndGet();
						return pending.keySet();
					}
				};
				var registryLock = createObject( "java", "java.util.concurrent.locks.ReentrantLock" ).init();
				var observer     = createMock( "sentry.interceptors.QueueObservability" )
					.$property( "sentry", "variables", variables.service )
					.$property( "publishes", "variables", registry )
					.$property( "publishLock", "variables", registryLock );
				function nextJob(){
					var properties = {};
					return {
						getId         : () => createUUID(),
						getProperties : () => properties,
						getQueue      : () => "notifications",
						getChained    : () => []
					};
				}
				var root = variables.service.startTransaction( "healthy bulk sweep" );
				telemetry.setScope( { span : root } );
				var jobs = [];
				for ( var index = 1; index <= 100; index++ ) {
					var job = nextJob();
					jobs.append( job );
					observer.onCBQJobAdded( {}, { job : job } );
				}
				expect( scans.get() ).toBe( 0 );
				expect( pending.size() ).toBe( 100 );
				var normalClock = clock;
				clock -= 4000;
				var backwards = nextJob();
				observer.onCBQJobAdded( {}, { job : backwards } );
				var backwardsId = backwards.getProperties()[ "__sentry" ].publishId;
				clock += 3600;
				observer.onCBQJobAdded( {}, { job : nextJob() } );
				expect( pending.containsKey( backwardsId ) ).toBeTrue();
				expect( scans.get() ).toBe( 0 );
				var failedRootFinished = false;
				var replacement        = pending.get( backwardsId );
				// A custom span may throw. Cleanup must release the lock, finish its owned root, and retain the next trace.
				replacement.span       = {
					finish : function( status ){
						expect( registryLock.isHeldByCurrentThread() ).toBeFalse();
						throw( type = "Test.PublishFailure", message = "custom span failure" );
					}
				};
				replacement.ownsRoot = true;
				replacement.root     = {
					finish : function( status ){
						expect( registryLock.isHeldByCurrentThread() ).toBeFalse();
						failedRootFinished = true;
					}
				};
				var secondRootFinished = false;
				pending.put(
					"second-expired",
					{
						created  : replacement.created,
						ownsRoot : true,
						span     : {
							finish : function( status ){
								expect( registryLock.isHeldByCurrentThread() ).toBeFalse();
								throw( type = "Test.PublishFailure", message = "second custom span failure" );
							}
						},
						root : {
							finish : function( status ){
								expect( registryLock.isHeldByCurrentThread() ).toBeFalse();
								secondRootFinished = true;
							}
						}
					}
				);
				clock += 0.001;
				var recovered = nextJob();
				observer.onCBQJobAdded( {}, { job : recovered } );
				expect( pending.containsKey( backwardsId ) ).toBeFalse();
				expect( scans.get() ).toBe( 1 );
				expect( failedRootFinished ).toBeTrue();
				expect( secondRootFinished ).toBeTrue();
				expect( pending.containsKey( "second-expired" ) ).toBeFalse();
				expect( observer.getObservationFailureCount() ).toBe( 2 );
				expect( recovered.getProperties().keyExists( "__sentry" ) ).toBeTrue();
				clock = normalClock;
				for ( var job in jobs ) {
					observer.onCBQJobPublished( {}, { job : job } );
				}
				observer.onCBQJobPublishException( {}, { job : recovered } );
				root.finish();
			} );
			it( "bounds concurrent publication admission and releases every callback without holding the registry lock", function(){
				var pending = createObject( "java", "java.util.concurrent.ConcurrentHashMap" ).init();
				var clock   = variables.telemetry.timestamp();
				for ( var index = 1; index <= 1023; index++ ) {
					pending.put( "retained-" & index, { created : clock } );
				}
				var observer = createMock( "sentry.interceptors.QueueObservability" )
					.$property( "sentry", "variables", variables.service )
					.$property( "publishes", "variables", pending )
					.$property( "oldestPublishCreated", "variables", clock );
				var start      = createObject( "java", "java.util.concurrent.CountDownLatch" ).init( 1 );
				var added      = createObject( "java", "java.util.concurrent.CountDownLatch" ).init( 8 );
				var violations = createObject( "java", "java.util.concurrent.atomic.AtomicLong" ).init( 0 );
				var names      = [];
				for ( var index = 1; index <= 8; index++ ) {
					var name = "publish-" & createUUID();
					names.append( name );
					thread
						name          =name
						action        ="run"
						observer      =observer
						pending       =pending
						start         =start
						added         =added
						violations    =violations {
						var properties= {};
						var job       = {
							getId         : () => "concurrent",
							getProperties : () => properties,
							getQueue      : () => "notifications",
							getChained    : () => []
						};
						attributes.start.await();
						try {
							attributes.observer.onCBQJobAdded( {}, { job : job } );
						} finally {
							attributes.added.countDown();
						}
						attributes.added.await(
							5,
							createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
						);
						if ( attributes.pending.size() > 1024 || !properties.keyExists( "__sentry" ) ) {
							attributes.violations.incrementAndGet();
						}
						attributes.observer.onCBQJobPublished( {}, { job : job } );
					}
				}
				start.countDown();
				thread action="join" name=names.toList() timeout=10000;
				for ( var name in names ) {
					expect( cfthread[ name ].status ).toBe( "COMPLETED" );
				}
				expect( violations.get() ).toBe( 0 );
				expect( pending.size() ).toBe( 1023 );
				expect( observer.getObservationFailureCount() ).toBe( 0 );
			} );
			it( "retains zero-time entries at the exact TTL boundary and expires them after earlier entries are removed", function(){
				var clock     = 3600;
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "timestamp" ).$callback( () => clock );
				// Ordered entries reproduce zero followed by a positive survivor during minimum recomputation.
				var pending  = createObject( "java", "java.util.LinkedHashMap" ).init();
				var finished = [];
				for (
					var entry in [
						{ id : "negative", created : -1 },
						{ id : "zero", created : 0 },
						{ id : "positive", created : 1 }
					]
				) {
					var label = entry.id;
					var span  = (
						function( id ){
							return {
								finish : function( status ){
									finished.append( id );
								}
							};
						}
					)( label );
					pending.put( entry.id, { created : entry.created, span : span, ownsRoot : false } );
				}
				var observer = createMock( "sentry.interceptors.QueueObservability" )
					.$property( "sentry", "variables", variables.service )
					.$property( "publishes", "variables", pending )
					.$property( "oldestPublishCreated", "variables", -1 );
				function zeroTimeJob(){
					var properties = {};
					return {
						getId         : () => "zero-time",
						getProperties : () => properties,
						getQueue      : () => "notifications",
						getChained    : () => []
					};
				}
				var first = zeroTimeJob();
				observer.onCBQJobAdded( {}, { job : first } );
				expect( pending.containsKey( "negative" ) ).toBeFalse();
				expect( pending.containsKey( "zero" ) ).toBeTrue();
				clock += 0.001;
				var second = zeroTimeJob();
				observer.onCBQJobAdded( {}, { job : second } );
				expect( pending.containsKey( "zero" ) ).toBeFalse();
				expect( pending.containsKey( "positive" ) ).toBeTrue();
				expect( finished ).toBe( [ "negative", "zero" ] );
				observer.onCBQJobPublished( {}, { job : first } );
				observer.onCBQJobPublished( {}, { job : second } );
				expect( observer.getObservationFailureCount() ).toBe( 0 );
			} );
			it( "reports a concrete matching backend SDK version for portable Git installations", function(){
				var descriptor = deserializeJSON( fileRead( expandPath( "/sentry/box.json" ) ) );
				var module     = new sentry.ModuleConfig();
				expect( descriptor.version ).toBe( "2.2.1+bulk.clock.2" );
				expect( module.version ).toBe( descriptor.version );
				var root = variables.service.startTransaction( "SDK version" );
				root.finish();
				expect( variables.service.flush( 5000 ) ).toBeTrue();
				cfhttp( url = "http://127.0.0.1:60320/state" );
				var received    = deserializeJSON( cfhttp.fileContent );
				var ownEnvelope = received.filter( ( envelope ) => envelope.items.some( ( item ) => item.header.type == "transaction" && item.payload.transaction == "SDK version" ) );
				expect( ownEnvelope.len() ).toBe( 1 );
				expect( ownEnvelope[ 1 ].sdkClient ).toBe( "sentry.cfml/" & descriptor.version );
				expect( ownEnvelope[ 1 ].sdkClient ).notToInclude( "@build." );
				var browser = deserializeJSON( fileRead( expandPath( "/sentry/browser/package.json" ) ) );
				expect( browser.version ).toBe( "2.2.1" );
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
				expect( root.getChildren()[ 1 ].toPayload().data[ "messaging.message.id" ] ).toBe(
					"synthetic-first"
				);
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
