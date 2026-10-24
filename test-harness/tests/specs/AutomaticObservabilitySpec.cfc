component extends="testbox.system.BaseSpec" {

	function beforeAll(){
		// Generated AOP code lives in an ignored directory, absent in a fresh checkout.
		// Lucee expandPath falls back to the web root while a mapped target does not exist.
		var generationDirectory = getApplicationMetadata().mappings[ "/sentryAOP" ];
		var parentDirectory     = getDirectoryFromPath( generationDirectory );
		if ( !directoryExists( parentDirectory ) ) directoryCreate( parentDirectory );
		if ( !directoryExists( generationDirectory ) ) directoryCreate( generationDirectory );
	}

	function run(){
		describe( "Automatic collectors and adapter configuration", function(){
			beforeEach( function(){
				variables.services = [];
				variables.injector = javacast( "null", "" );
			} );
			afterEach( function(){
				if ( !isNull( variables.injector ) ) variables.injector.shutdown();
				for ( var service in variables.services ) service.shutdown();
			} );
			it( "invokes the callback adapter contract directly", function(){
				var resolver = new sentry.models.telemetry.AdapterResolver();
				var result   = resolver.call(
					function( context ){
						return { activeWorkers : context.value };
					},
					"sample",
					{ "context" : { "value" : 2 } }
				);
				expect( result.activeWorkers ).toBe( 2 );
			} );

			it( "records an ad hoc manual phase on the automatic request timing instance", function(){
				var service   = makeService( { enableAutomaticRequestTimings : true } );
				var telemetry = prepareMock( service.getObservability() );
				telemetry.$( "distribution" );
				var context  = eventContext();
				var observer = createMock( "sentry.interceptors.Observability" ).$property(
					"sentry",
					"variables",
					service
				);
				observer.onRequestCapture( context, {} );
				var timing = service.getRequestTimings();
				expect(
					timing.measure( "loadDashboard", function(){
						return 42;
					} )
				).toBe( 42 );
				expect( timing.snapshot().loadDashboard.count ).toBe( 1 );
				var calls = telemetry.$callLog( "distribution" ).distribution;
				expect( calls.len() ).toBe( 1 );
				expect( calls[ 1 ][ 1 ] ).toBe( "http.server.phase.duration" );
				expect( calls[ 1 ][ 3 ].phase ).toBe( "loadDashboard" );
				observer.postProcess( context, {} );
				expect( telemetry.getScope() ).toBeEmpty();
			} );
			it( "ignores invalid manual phase names in both timing APIs", function(){
				var service = makeService( {
					requestTimingNames : [
						{},
						[],
						"valid",
						"valid",
						"bad-name",
						javacast( "null", "" )
					]
				} );
				var manual = service.newRequestTimings();
				manual.finish( manual.begin( "valid" ) );
				expect( manual.snapshot().valid.count ).toBe( 1 );
				var automatic = service.newRequestTimings( true );
				automatic.finish( automatic.begin( "handler" ) );
				automatic.finish( automatic.begin( "valid" ) );
				expect( automatic.snapshot().handler.count ).toBe( 1 );
				expect( automatic.snapshot().valid.count ).toBe( 1 );
			} );
			it( "finishes open automatic phase tokens on early request termination", function(){
				var service = makeService( {
					enableAutomaticRequestTimings : true,
					enableRequestTracing          : true,
					tracesSampleRate              : 1
				} );
				var telemetry = prepareMock( service.getObservability() );
				telemetry.$( "distribution" );
				var context             = eventContext();
				context.getCurrentRoute = function(){
					return "early";
				};
				context.getHTTPMethod = function(){
					return "GET";
				};
				var observer = createMock( "sentry.interceptors.Observability" ).$property(
					"sentry",
					"variables",
					service
				);
				observer.onRequestCapture( context, {} );
				observer.preEvent( context, {} );
				var timings = service.getRequestTimings();
				var root    = telemetry.getScope().span;
				service.endRequest( 303 );
				expect( timings.snapshot().handler.count ).toBe( 1 );
				expect( root.isFinished() ).toBeTrue();
				expect( root.getChildren()[ 1 ].isFinished() ).toBeTrue();
				expect( telemetry.getScope() ).toBeEmpty();
			} );
			it( "accepts valid partial automatic collector settings at actual module startup", function(){
				var service                  = makeService();
				var injector                 = makeInjector( service );
				var settings                 = duplicate( service.getSettings() );
				settings.automaticCollectors = { intervalSeconds : 30 };
				var config                   = createMock( "sentry.ModuleConfig" )
					.$property( "wirebox", "variables", injector )
					.$property( "binder", "variables", injector.getBinder() )
					.$property( "settings", "variables", settings )
					.$property( "moduleMapping", "variables", "sentry" );
				config.onLoad();
				expect( service.automaticCollectorDiagnostics().started ).toBeFalse();
			} );
			it( "runs application code once even when dependency scope lookup fails", function(){
				var service   = makeService( { dependencyNames : [ "mail" ] } );
				var telemetry = prepareMock( service.getObservability() );
				telemetry.$( "getScope" ).$throws( "ScopeUnavailable" );
				var calls = 0;
				expect(
					service.withDependency( "mail", function(){
						calls++;
						return 42;
					} )
				).toBe( 42 );
				expect( calls ).toBe( 1 );
				expect( function(){
					service.withDependency( "mail", function(){
						throw( type = "OriginalFailure" );
					} );
				} ).toThrow( "OriginalFailure" );
			} );
			it( "deduplicates nested dependency observations even when span creation fails", function(){
				var service   = makeService( { dependencyNames : [ "mail" ] } );
				var telemetry = prepareMock( service.getObservability() );
				telemetry.$( "startSpan" ).$throws( "NoTracing" );
				telemetry.$( "counter" );
				expect(
					service.withDependency( "mail", function(){
						return service.withDependency( "mail", function(){
							return 1;
						} );
					} )
				).toBe( 1 );
				expect( telemetry.$callLog( "counter" ).counter.len() ).toBe( 1 );
			} );
			it( "configures query instrumentation using a WireBox interface mapping", function(){
				var service  = makeService( { queryAdapter : { mapping : "QueryAdapter", method : "configure" } } );
				var injector = makeInjector( service );
				service.getObservability().setAdapterInjector( injector );
				expect( service.getObservability().configureQueryInstrumentation( "fixture" ) ).toBe( "qb" );
			} );
			it( "prevents overlapping ticks and starting more adapters after shutdown", function(){
				var started = createObject( "java", "java.util.concurrent.CountDownLatch" ).init( 1 );
				var release = createObject( "java", "java.util.concurrent.CountDownLatch" ).init( 1 );
				var calls   = createObject( "java", "java.util.concurrent.atomic.AtomicInteger" ).init( 0 );
				var service = makeService( {
					automaticCollectors : {
						enabled           : true,
						intervalSeconds   : 3600,
						runtime           : false,
						requestSaturation : false,
						queueWorkers      : [
							{
								name    : "blocked",
								adapter : function( context ){
									started.countDown();
									release.await();
									return { activeWorkers : 0 };
								}
							},
							{
								name    : "later",
								adapter : function( context ){
									calls.incrementAndGet();
									return { activeWorkers : 0 };
								}
							}
						]
					}
				} );
				var ref    = createObject( "java", "java.util.concurrent.atomic.AtomicReference" ).init( service );
				var name   = "auto-test-" & replace( createUUID(), "-", "", "all" );
				thread name=name action="run" reference=ref {
					attributes.reference.get().collectAutomaticMetrics();
				}
				try {
					expect(
						started.await(
							javacast( "long", 5 ),
							createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
						)
					).toBeTrue();
					service.collectAutomaticMetrics();
					expect( service.automaticCollectorDiagnostics().skipped ).toBe( 1 );
					service.shutdown();
				} finally {
					release.countDown();
					thread action="join" name=name timeout=5000;
				}
				expect( calls.get() ).toBe( 0 );
				expect( cfthread[ name ].status ).toBe( "COMPLETED" );
			} );
			it( "isolates collector work from the caller's active trace and restores it", function(){
				var observed = true;
				var service  = makeService( {
					automaticCollectors : {
						enabled           : true,
						intervalSeconds   : 3600,
						runtime           : false,
						requestSaturation : false,
						queueWorkers      : [
							{
								name    : "mail",
								adapter : function( context ){
									observed = service.getTraceContext().keyExists( "span_id" );
									return { activeWorkers : 0 };
								}
							}
						]
					}
				} );
				var root = service.startTransaction( "caller" );
				service.getObservability().setScope( { span : root } );
				service.collectAutomaticMetrics();
				expect( observed ).toBeFalse();
				expect( service.getTraceContext().span_id ).toBe( root.getContext().span_id );
				root.finish();
			} );


			it( "does not collect or resolve adapters when automatic collection is disabled", function(){
				var calls   = 0;
				var service = makeService( {
					automaticCollectors : {
						enabled      : false,
						runtime      : false,
						queueWorkers : [
							{
								name    : "mail",
								adapter : function( context ){
									calls++;
									return { activeWorkers : 0 };
								}
							}
						]
					}
				} );
				service.collectAutomaticMetrics();
				expect( calls ).toBe( 0 );
				expect( service.automaticCollectorDiagnostics().started ).toBeFalse();
			} );
			it( "records local receipt snapshot failures without emitting diagnostic metrics", function(){
				var service = makeService( {
					automaticCollectors : {
						enabled             : true,
						intervalSeconds     : 3600,
						runtime             : false,
						requestSaturation   : false,
						deliveryDiagnostics : true
					}
				} );
				var telemetry = prepareMock( service.getObservability() );
				telemetry.$( "deliveryDiagnostics" ).$throws( "SnapshotUnavailable" );
				telemetry.$( "gauge" );
				service.collectAutomaticMetrics();
				expect( service.automaticCollectorDiagnostics().failures ).toBe( 1 );
				expect( telemetry.$callLog( "gauge" ).gauge.len() ).toBe( 0 );
			} );

			it( "requires an explicit worker adapter rather than assuming cbq from a pool setting", function(){
				var service = makeService( {
					automaticCollectors : {
						enabled           : true,
						intervalSeconds   : 3600,
						runtime           : false,
						requestSaturation : false,
						queueWorkers      : [ { name : "mail", pool : "not-a-default-provider" } ]
					}
				} );
				var telemetry = prepareMock( service.getObservability() );
				var injector  = prepareMock( makeInjector( service ) );
				injector.$( "getInstance" ).$throws( "UnexpectedProviderLookup" );
				telemetry.setAdapterInjector( injector );
				telemetry.$( "gauge" );
				service.collectAutomaticMetrics();
				expect( service.automaticCollectorDiagnostics().failures ).toBe( 1 );
				expect( injector.$callLog( "getInstance" ).getInstance.len() ).toBe( 0 );
				expect( telemetry.$callLog( "gauge" ).gauge.len() ).toBe( 0 );
			} );
			it( "automatically samples configured callbacks and permits manual sampling too", function(){
				var calls   = 0;
				var service = makeService( {
					enableRequestSaturation : true,
					automaticCollectors     : {
						enabled         : true,
						intervalSeconds : 3600,
						runtime         : false,
						queueWorkers    : [
							{
								name    : "mail",
								pool    : "ignored-legacy-shortcut",
								options : { pool : "outbound", token : "PRIVATE" },
								adapter : function( context ){
									expect( context.kind ).toBe( "queueWorkers" );
									expect( context.options.pool ).toBe( "outbound" );
									calls++;
									return { activeWorkers : 0 };
								}
							}
						]
					}
				} );
				var telemetry = prepareMock( service.getObservability() );
				telemetry.$( "gauge" );
				var token = service.beginRequestObservation();
				service.collectAutomaticMetrics();
				expect( calls ).toBe( 1 );
				expect( service.automaticCollectorDiagnostics().runs ).toBe( 1 );
				expect( service.automaticCollectorDiagnostics().failures ).toBe( 0 );
				var payload = serializeJSON( telemetry.$callLog( "gauge" ) );
				expect( payload ).toInclude( "http.server.active_requests" );
				expect( payload ).toInclude( "queue.workers.active" );
				expect( payload ).notToInclude( "PRIVATE" );
				expect(
					service.captureQueueWorkerHealth( "mail", function(){
						return { activeWorkers : 2 };
					} )
				).toBeTrue();
				service.finishRequestObservation( token );
			} );
			it( "continues other collectors after an adapter fails and records only bounded diagnostics", function(){
				var good    = 0;
				var service = makeService( {
					automaticCollectors : {
						enabled           : true,
						intervalSeconds   : 3600,
						runtime           : false,
						requestSaturation : false,
						queueWorkers      : [
							{
								name    : "bad",
								adapter : function( context ){
									throw( type = "AdapterFailed", message = "PRIVATE" );
								}
							},
							{
								name    : "good",
								adapter : function( context ){
									good++;
									return { activeWorkers : 0 };
								}
							}
						]
					}
				} );
				service.collectAutomaticMetrics();
				expect( good ).toBe( 1 );
				expect( service.automaticCollectorDiagnostics().failures ).toBe( 1 );
				expect( serializeJSON( service.automaticCollectorDiagnostics() ) ).notToInclude( "PRIVATE" );
			} );
			it( "starts one scheduler, actually samples, and stops on shutdown", function(){
				var calls   = createObject( "java", "java.util.concurrent.atomic.AtomicInteger" ).init( 0 );
				var service = makeService( {
					automaticCollectors : {
						enabled           : true,
						intervalSeconds   : 1,
						runtime           : false,
						requestSaturation : false,
						queueWorkers      : [
							{
								name    : "mail",
								adapter : function( context ){
									calls.incrementAndGet();
									return { activeWorkers : 0 };
								}
							}
						]
					}
				} );
				expect( service.startAutomaticCollectors() ).toBeFalse();
				awaitCondition( function(){
					return calls.get() > 0;
				} );
				service.shutdown();
				var observed = calls.get();
				sleep( 1150 );
				expect( calls.get() ).toBe( observed );
			} );
			it( "rejects invalid intervals without starting an executor", function(){
				var service = makeService( { automaticCollectors : { enabled : true, intervalSeconds : 0, runtime : false } } );
				expect( service.automaticCollectorDiagnostics().started ).toBeFalse();
				expect( service.automaticCollectorDiagnostics().failures ).toBe( 1 );
			} );
			it( "does not invoke collectors when metrics or the DSN is disabled", function(){
				var calls    = 0;
				var settings = {
					enableMetrics       : false,
					automaticCollectors : {
						enabled         : true,
						intervalSeconds : 1,
						runtime         : false,
						queueWorkers    : [
							{
								name    : "mail",
								adapter : function( context ){
									calls++;
									return { activeWorkers : 0 };
								}
							}
						]
					}
				};
				var service = makeService( settings );
				service.collectAutomaticMetrics();
				expect( calls ).toBe( 0 );
				expect( service.automaticCollectorDiagnostics().started ).toBeFalse();
			} );
			it( "resolves snapshot mappings and explicit interface methods through actual WireBox", function(){
				var service = makeService( {
					automaticCollectors : {
						enabled           : true,
						intervalSeconds   : 3600,
						runtime           : false,
						requestSaturation : false,
						requestExecutors  : [ { name : "http", adapter : "SnapshotAdapter" } ],
						databasePools     : [
							{
								name    : "db",
								adapter : { mapping : "SnapshotAdapter", method : "sample" }
							}
						]
					}
				} );
				var injector = makeInjector( service );
				service.getObservability().setAdapterInjector( injector );
				var telemetry = prepareMock( service.getObservability() );
				telemetry.$( "gauge" );
				service.collectAutomaticMetrics();
				expect( service.automaticCollectorDiagnostics().failures ).toBe( 0 );
				var calls = serializeJSON( telemetry.$callLog( "gauge" ) );
				expect( calls ).toInclude( "http.server.executor.active" );
				expect( calls ).toInclude( "db.pool.utilization" );
				expect( calls ).notToInclude( "PRIVATE" );
			} );
			it( "configures query tracing with a callback once and cleans custom resources", function(){
				var calls   = 0;
				var stopped = 0;
				var service = makeService( {
					queryAdapter : function( context ){
						calls++;
						expect( context.applicationName ).toBe( "test-app" );
						return {
							mode     : "custom",
							shutdown : function(){
								stopped++;
							}
						};
					}
				} );
				var telemetry = service.getObservability();
				expect( telemetry.configureQueryInstrumentation( "test-app" ) ).toBe( "custom" );
				expect( telemetry.configureQueryInstrumentation( "test-app" ) ).toBe( "custom" );
				expect( calls ).toBe( 1 );
				service.shutdown();
				expect( stopped ).toBe( 1 );
			} );
			it( "fails closed for an invalid query adapter while preserving built-in modes", function(){
				var service = makeService( {
					queryAdapter : function( context ){
						throw( type = "PRIVATE" );
					}
				} );
				expect( service.getObservability().configureQueryInstrumentation( "test" ) ).toBe( "none" );
				var qb = makeService( { queryAdapter : "qb" } );
				expect( qb.getObservability().configureQueryInstrumentation( "test" ) ).toBe( "qb" );
			} );
			it( "supports classifier mappings in the unchanged manual dependency API", function(){
				var service  = makeService( { dependencyNames : [ "mail" ] } );
				var injector = makeInjector( service );
				service.getObservability().setAdapterInjector( injector );
				var telemetry = prepareMock( service.getObservability() );
				telemetry.$( "counter" );
				expect(
					service.withDependency(
						"mail",
						function(){
							return false;
						},
						"Classifier"
					)
				).toBeFalse();
				expect( telemetry.$callLog( "counter" ).counter[ 1 ][ 3 ].outcome ).toBe( "rejected" );
			} );
			it( "automatically observes actual WireBox methods, preserves results and original exceptions", function(){
				var service = makeService( {
					dependencyAdapters : [
						{
							name     : "mail",
							mapping  : "MailClient",
							methods  : [ "send", "fail", "nothing", "manual" ],
							classify : "Classifier"
						}
					]
				} );
				var injector = makeInjector( service );
				installModule( service, injector );
				var telemetry = prepareMock( service.getObservability() );
				telemetry.$( "counter" );
				telemetry.$( "distribution" );
				var gateway = injector.getInstance( "MailClient" );
				expect( gateway.send( "PRIVATE" ).message ).toBe( "PRIVATE" );
				expect( function(){
					gateway.fail();
				} ).toThrow( "OriginalDependencyFailure" );
				gateway.nothing();
				expect( gateway.manual( "PRIVATE" ) ).toBe( "PRIVATE" );
				var calls = telemetry.$callLog( "counter" ).counter;
				expect( calls.len() ).toBe( 4 );
				expect( calls[ 1 ][ 3 ].outcome ).toBe( "rejected" );
				expect( calls[ 2 ][ 3 ].outcome ).toBe( "timeout" );
				expect( serializeJSON( calls ) ).notToInclude( "PRIVATE" );
				expect( telemetry.getScope() ).toBeEmpty();
			} );
			it( "keeps an outer manual dependency wrapper from double-counting an automatic method", function(){
				var service = makeService( {
					dependencyAdapters : [
						{
							name    : "mail",
							mapping : "MailClient",
							methods : [ "send" ]
						}
					]
				} );
				var injector = makeInjector( service );
				installModule( service, injector );
				var telemetry = prepareMock( service.getObservability() );
				telemetry.$( "counter" );
				var gateway = injector.getInstance( "MailClient" );
				var result  = service.withDependency( "mail", function(){
					return gateway.send( "PRIVATE" );
				} );
				expect( result.message ).toBe( "PRIVATE" );
				expect( telemetry.$callLog( "counter" ).counter.len() ).toBe( 1 );
			} );
			it( "bounds configured adapter names and never observes invalid names", function(){
				var entries = [];
				for ( var i = 1; i <= 40; i++ )
					entries.append( {
						name    : "worker_" & i,
						adapter : function( context ){
							return { activeWorkers : 0 };
						}
					} );
				var service = makeService( {
					automaticCollectors : {
						enabled           : true,
						intervalSeconds   : 3600,
						runtime           : false,
						requestSaturation : false,
						queueWorkers      : entries
					}
				} );
				var telemetry = prepareMock( service.getObservability() );
				telemetry.$( "gauge" );
				service.collectAutomaticMetrics();
				expect( telemetry.$callLog( "gauge" ).gauge.len() ).toBe( 32 );
			} );
			it( "times framework phases automatically and leaves header publication opt-in", function(){
				var service = makeService( { enableAutomaticRequestTimings : true } );
				for ( var i = 1; i <= 32; i++ ) service.getSettings().requestTimingNames.append( "manual_" & i );
				var telemetry = prepareMock( service.getObservability() );
				telemetry.$( "distribution" );
				var context  = eventContext();
				var observer = createMock( "sentry.interceptors.Observability" ).$property(
					"sentry",
					"variables",
					service
				);
				observer.onRequestCapture( context, {} );
				observer.preEvent( context, {} );
				observer.postEvent( context, {} );
				observer.preRender( context, {} );
				observer.postRender( context, {} );
				expect( service.getRequestTimings().snapshot().handler.count ).toBe( 1 );
				expect( service.getRequestTimings().snapshot().render.count ).toBe( 1 );
				observer.postProcess( context, {} );
				expect( context.headers ).toBeEmpty();
				expect( telemetry.$callLog( "distribution" ).distribution.len() ).toBe( 2 );
				expect( telemetry.getScope() ).toBeEmpty();
			} );
			it( "publishes Server-Timing only under configured eligibility and closes exceptional phases once", function(){
				var service = makeService( {
					enableAutomaticRequestTimings : true,
					publishServerTiming           : true,
					serverTimingFilter            : function( event ){
						return event.allowed;
					}
				} );
				var context     = eventContext();
				context.allowed = true;
				var observer    = createMock( "sentry.interceptors.Observability" ).$property(
					"sentry",
					"variables",
					service
				);
				observer.onRequestCapture( context, {} );
				observer.preEvent( context, {} );
				observer.onException( context, {} );
				observer.postProcess( context, {} );
				expect( context.headers[ "Server-Timing" ] ).toInclude( "handler;dur=" );
				var blocked     = eventContext();
				blocked.allowed = false;
				observer.onRequestCapture( blocked, {} );
				observer.preEvent( blocked, {} );
				observer.postEvent( blocked, {} );
				observer.postProcess( blocked, {} );
				expect( blocked.headers ).toBeEmpty();
				service.getSettings().serverTimingFilter = "invalid";
				var invalid = eventContext();
				observer.onRequestCapture( invalid, {} );
				observer.preEvent( invalid, {} );
				observer.postEvent( invalid, {} );
				observer.postProcess( invalid, {} );
				expect( invalid.headers ).toBeEmpty();
			} );
		} );
	}
	private function makeService( struct settings = {} ){
		var config = {
			DSN                             : "http://public@127.0.0.1:60320/1",
			enableMetrics                   : true,
			enableLogBoxAppender            : false,
			dependencyAdapterGenerationPath : "/sentryAOP"
		};
		config.append( arguments.settings, true );
		var service = new sentry.models.SentryService( config );
		variables.services.append( service );
		return service;
	}
	private function makeInjector( required any service ){
		variables.injector = new coldbox.system.ioc.Injector(
			binder    : "tests.resources.AutomaticBinder",
			properties: { service : arguments.service }
		);
		return variables.injector;
	}
	private function installModule( required any service, required any injector ){
		var config = createMock( "sentry.ModuleConfig" )
			.$property( "wirebox", "variables", arguments.injector )
			.$property(
				"binder",
				"variables",
				arguments.injector.getBinder()
			)
			.$property(
				"settings",
				"variables",
				arguments.service.getSettings()
			)
			.$property( "moduleMapping", "variables", "sentry" );
		config.onLoad();
	}
	private function eventContext(){
		var values  = {};
		var headers = {};
		var event   = {
			headers         : headers,
			getPrivateValue : function( name, defaultValue ){
				return values[ name ] ?: defaultValue;
			},
			setPrivateValue : function( name, value ){
				values[ name ] = value;
			},
			setHTTPHeader : function( name, value ){
				headers[ name ] = value;
			}
		};
		return event;
	}
	private function awaitCondition( required function callback ){
		var deadline = getTickCount() + 5000;
		while ( getTickCount() < deadline ) {
			if ( arguments.callback() ) return;
			sleep( 25 );
		}
		throw( type = "AutomaticTelemetryTestTimeout" );
	}

}
