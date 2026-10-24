component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "Request saturation, dependencies and workers", function(){
			beforeEach( function(){
				variables.service = new sentry.models.SentryService( {
					DSN                     : "http://public@127.0.0.1:60320/1",
					enableMetrics           : true,
					enableRequestSaturation : true,
					maxObservedRequests     : 2,
					dependencyNames         : [ "mail", "MAIL", "bad,label" ],
					requestExecutorNames    : [ "http" ],
					queueWorkerNames        : [ "mail" ]
				} );
				variables.telemetry = variables.service.getObservability();
			} );
			afterEach( function(){
				variables.telemetry.clearScope();
				variables.service.shutdown();
			} );
			it( "cleans exception-path request observations when postProcess does not run", function(){
				var observer = createMock( "sentry.interceptors.Observability" ).$property(
					"sentry",
					"variables",
					variables.service
				);
				var values = {};
				var event  = {
					getPrivateValue : function( name, defaultValue ){
						return values[ name ] ?: defaultValue;
					},
					setPrivateValue : function( name, value ){
						values[ name ] = value;
					},
					getCurrentRoute : function(){
						return "test";
					},
					getHTTPMethod : function(){
						return "GET";
					}
				};
				observer.onRequestCapture( event, {} );
				observer.onException( event, {} );
				expect( variables.service.requestSaturation().active ).toBe( 0 );
				expect( variables.telemetry.getScope() ).toBeEmpty();
				variables.service.getSettings().enableRequestTracing = true;
				values = {};
				observer.onRequestCapture( event, {} );
				var context = variables.service.getTraceContext();
				observer.onException( event, {} );
				expect( variables.service.requestSaturation().active ).toBe( 0 );
				expect( variables.service.getTraceContext().span_id ).toBe( context.span_id );
				variables.service.endRequest( statusCode = 500 );
				expect( variables.telemetry.getScope() ).toBeEmpty();
			} );
			it( "excludes classifier and exporter work from dependency duration", function(){
				var nanos    = 0;
				var measured = 0;
				var observer = prepareMock(
					new sentry.models.telemetry.Dependency( {
						getScope : function(){
							nanos += 1000000000;
							return {};
						},
						startSpan : function(){
							throw( type = "NoSpan" );
						},
						setScope : function(){
						},
						counter : function(){
							nanos += 1000000000;
						},
						distribution : function( name, value ){
							if ( name == "dependency.duration" ) measured = value;
						}
					} )
				);
				observer.$property(
					"clock",
					"variables",
					{
						nanoTime : function(){
							return nanos;
						}
					}
				);
				observer.run(
					"mail",
					function(){
						nanos += 10000000;
						return true;
					},
					function(){
						nanos += 1000000000;
						return { outcome : "success" };
					}
				);
				expect( measured ).toBe( 10 );
			} );

			it(
				title = "compiles database runnable, delayed and expired lease snapshots with qb grammars",
				body  = function(){
					for ( var dialect in [ "Postgres", "MySQL", "SqlServer" ] ) {
						var grammar = createObject( "component", "qb.models.Grammars." & dialect & "Grammar" ).init();
						var builder = prepareMock(
							new qb.models.Query.QueryBuilder( grammar = grammar, paginationCollector = {} )
						);
						builder.$(
							"get",
							[
								{
									runnable          : 2,
									delayed           : 3,
									reserved          : 1,
									staleReservations : 1
								}
							]
						);
						var adapter = new sentry.models.telemetry.DatabaseQueueHealth( function(){
							return builder;
						} );
						var result = adapter.snapshot( "PRIVATE-queue" );
						expect( result.runnable ).toBe( 2 );
						var sql = builder.toSQL();
						expect( sql ).toInclude( grammar.wrapValue( "reservedBy" ) );
						expect( sql ).toInclude( grammar.wrapValue( "availableDate" ) );
						expect( sql ).toInclude( "staleReservations" );
						expect( sql ).notToInclude( "PRIVATE-queue" );
						expect( builder.getBindings().len() ).toBe( 4 );
					}
				},
				skip = function(){
					var source = createObject( "java", "java.lang.System" ).getenv( "SENTRY_QB_SOURCE" );
					return isNull( source ) || !len( source );
				}
			);

			it( "counts active requests, bounds retention and accepts completion once", function(){
				var first  = variables.service.beginRequestObservation();
				var second = variables.service.beginRequestObservation();
				expect( variables.service.beginRequestObservation() ).toBeEmpty();
				var snapshot = variables.service.captureRequestSaturation();
				expect( snapshot.active ).toBe( 2 );
				expect( snapshot.untrackedStarts ).toBe( 1 );
				expect( variables.service.finishRequestObservation( { id : "foreign" }, true ) ).toBeFalse();
				expect( variables.service.finishRequestObservation( first, true ) ).toBeTrue();
				expect( variables.service.finishRequestObservation( first, true ) ).toBeFalse();
				expect( variables.service.requestSaturation().timeouts ).toBe( 1 );
				expect( variables.service.finishRequestObservation( second ) ).toBeTrue();
				snapshot = variables.service.captureRequestSaturation();
				expect( snapshot.active ).toBe( 0 );
				expect( snapshot.oldestSeconds ).toBe( 0 );
			} );
			it( "uses monotonic ages without converting long running requests into timeouts", function(){
				var nanos    = 1000000000;
				var observer = prepareMock(
					new sentry.models.telemetry.RequestSaturation( variables.telemetry, 2, 30 )
				);
				observer.$property(
					"clock",
					"variables",
					{
						nanoTime : function(){
							return nanos;
						}
					}
				);
				var token = observer.begin();
				nanos += 31000000000;
				var snapshot = observer.snapshot();
				expect( snapshot.oldestSeconds ).toBe( 31 );
				expect( snapshot.longRunning ).toBe( 1 );
				expect( snapshot.timeouts ).toBe( 0 );
				observer.finish( token );
				expect( observer.snapshot().longRunning ).toBe( 0 );
			} );
			it( "tracks the ColdBox lifecycle with tracing disabled and cleans early endRequest once", function(){
				var observer = createMock( "sentry.interceptors.Observability" ).$property(
					"sentry",
					"variables",
					variables.service
				);
				var values = {};
				var event  = {
					getPrivateValue : function( name, defaultValue ){
						return values[ name ] ?: defaultValue;
					},
					setPrivateValue : function( name, value ){
						values[ name ] = value;
					}
				};
				observer.onRequestCapture( event, {} );
				observer.onRequestCapture( event, {} );
				expect( variables.service.requestSaturation().active ).toBe( 1 );
				expect( variables.telemetry.getScope().requestState ).notToHaveKey( "span" );
				variables.service.endRequest( timedOut = true );
				observer.postProcess( event, {} );
				expect( variables.service.requestSaturation().active ).toBe( 0 );
				expect( variables.service.requestSaturation().timeouts ).toBe( 1 );
				expect( variables.telemetry.getScope() ).toBeEmpty();
			} );
			it( "completes a request token safely from another thread", function(){
				var token     = variables.service.beginRequestObservation();
				var reference = createObject( "java", "java.util.concurrent.atomic.AtomicReference" ).init(
					variables.service
				);
				var name   = "sentry-health-" & replace( createUUID(), "-", "", "all" );
				thread name=name action="run" service=reference token=token {
					attributes.service.get().finishRequestObservation( attributes.token, true );
				}
				thread action="join" name=name timeout=5000;
				expect( cfthread[ name ].status ).toBe( "COMPLETED" );
				expect( variables.service.requestSaturation().active ).toBe( 0 );
				expect( variables.service.finishRequestObservation( token, true ) ).toBeFalse();
				expect( variables.service.requestSaturation().timeouts ).toBe( 1 );
			} );
			it( "does no collection or provider sampling when metrics are disabled", function(){
				variables.service.getSettings().enableMetrics = false;
				var calls  = 0;
				var sample = function(){
					calls++;
					return { active : 1 };
				};
				expect( variables.service.beginRequestObservation() ).toBeEmpty();
				expect( variables.service.captureRequestSaturation() ).toBeEmpty();
				expect( variables.service.captureRequestExecutor( "http", sample ) ).toBeFalse();
				expect( variables.service.captureQueueWorkerHealth( "mail", sample ) ).toBeFalse();
				expect(
					variables.service.withDependency(
						"mail",
						function(){
							return 0;
						},
						sample
					)
				).toBe( 0 );
				expect( calls ).toBe( 0 );
			} );
			it( "records bounded dependency outcomes and preserves private callback results", function(){
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "counter" );
				telemetry.$( "distribution" );
				var calls  = 0;
				var result = variables.service.withDependency(
					"mail",
					function(){
						calls++;
						return { body : "PRIVATE" };
					},
					function( result, failure ){
						expect( result.body ).toBe( "PRIVATE" );
						expect( isNull( arguments.failure ) ).toBeTrue();
						return {
							outcome      : "rejected",
							statusCode   : 429,
							retryCount   : 2,
							circuitState : "half_open",
							body         : result.body
						};
					}
				);
				expect( result.body ).toBe( "PRIVATE" );
				expect( calls ).toBe( 1 );
				var count = telemetry.$callLog( "counter" ).counter[ 1 ];
				expect( count[ 1 ] ).toBe( "dependency.calls" );
				expect( count[ 3 ].outcome ).toBe( "rejected" );
				expect( count[ 3 ][ "http.status_class" ] ).toBe( "4xx" );
				expect( count[ 3 ][ "circuit.state" ] ).toBe( "half_open" );
				var durations = telemetry.$callLog( "distribution" ).distribution;
				expect( durations.len() ).toBe( 2 );
				expect( durations[ 2 ][ 1 ] ).toBe( "dependency.retries" );
				expect( durations[ 2 ][ 2 ] ).toBe( 2 );
				expect( serializeJSON( count ) ).notToInclude( "PRIVATE" );
				expect( serializeJSON( durations ) ).notToInclude( "PRIVATE" );
			} );
			it( "classifies thrown dependency failures and rethrows the original exception", function(){
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "counter" );
				telemetry.$( "distribution" );
				expect( function(){
					variables.service.withDependency(
						"mail",
						function(){
							throw( type = "OriginalTimeout", message = "PRIVATE" );
						},
						function( result, failure ){
							expect( isNull( arguments.result ) ).toBeTrue();
							expect( failure.type ).toBe( "OriginalTimeout" );
							return {
								outcome      : "timeout",
								retryCount   : 1,
								circuitState : "open"
							};
						}
					);
				} ).toThrow( "OriginalTimeout" );
				expect( telemetry.$callLog( "counter" ).counter[ 1 ][ 3 ].outcome ).toBe( "timeout" );
				expect( serializeJSON( telemetry.$callLog( "counter" ) ) ).notToInclude( "PRIVATE" );
			} );
			it( "omits invalid classifier fields and never observes unconfigured case variants", function(){
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "counter" );
				telemetry.$( "distribution" );
				var classified = 0;
				var callback   = function(){
					return false;
				};
				var classifier = function(){
					classified++;
					return {
						outcome      : "PRIVATE",
						statusCode   : 999,
						retryCount   : -1,
						circuitState : "PRIVATE"
					};
				};
				expect( variables.service.withDependency( "MAIL", callback, classifier ) ).toBeFalse();
				expect( variables.service.withDependency( "bad,label", callback, classifier ) ).toBeFalse();
				expect( classified ).toBe( 0 );
				expect( variables.service.withDependency( "mail", callback, classifier ) ).toBeFalse();
				var labels = telemetry.$callLog( "counter" ).counter[ 1 ][ 3 ];
				expect( labels.outcome ).toBe( "unknown" );
				expect( labels ).notToHaveKey( "http.status_class" );
				expect( labels ).notToHaveKey( "circuit.state" );
				expect( telemetry.$callLog( "distribution" ).distribution.len() ).toBe( 1 );
			} );
			it( "preserves callbacks and cleanup even if dependency telemetry fails", function(){
				var finishes = 0;
				var calls    = 0;
				var observer = new sentry.models.telemetry.Dependency( {
					getScope : function(){
						return {};
					},
					startSpan : function(){
						return {
							setAttribute : function(){
								throw( type = "ObserverFailure" );
							},
							finish : function(){
								finishes++;
							}
						};
					},
					setScope : function(){
						throw( type = "ObserverFailure" );
					},
					counter : function(){
						throw( type = "ObserverFailure" );
					},
					distribution : function(){
						throw( type = "ObserverFailure" );
					}
				} );
				expect(
					observer.run( "mail", function(){
						calls++;
						return 42;
					} )
				).toBe( 42 );
				expect( calls ).toBe( 1 );
				expect( function(){
					observer.run( "mail", function(){
						throw( type = "OriginalFailure" );
					} );
				} ).toThrow( "OriginalFailure" );
				expect( finishes ).toBe( 2 );
			} );
			it( "samples worker counts, backlog and heartbeat without exporting provider contents", function(){
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "gauge" );
				var now = createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000;
				expect(
					variables.service.captureQueueWorkerHealth( "mail", function(){
						return {
							configuredWorkers : 4,
							activeWorkers     : 3,
							activeExecutions  : 2,
							lastHeartbeatAt   : now - 20,
							runnable          : 5,
							delayed           : 6,
							reserved          : 2,
							staleReservations : 1,
							retries           : 10,
							exhausted         : 2,
							password          : "PRIVATE"
						};
					} )
				).toBeTrue();
				var calls = telemetry.$callLog( "gauge" ).gauge;
				expect( calls.len() ).toBe( 10 );
				expect( serializeJSON( calls ) ).notToInclude( "PRIVATE" );
				var heartbeat = 0;
				for ( var call in calls ) {
					if ( call[ 1 ] == "queue.worker.heartbeat_age" ) heartbeat = call[ 2 ];
					expect( call[ 3 ][ "worker.name" ] ).toBe( "mail" );
				}
				expect( heartbeat ).toBeGTE( 20 );
				expect( variables.service.queueWorkerDiagnostics( "mail" ).lastSuccessAt ).toBeGT( 0 );
			} );
			it( "keeps failed and unsupported worker snapshots distinct from measured zero", function(){
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "gauge" );
				expect(
					variables.service.captureQueueWorkerHealth( "mail", function(){
						return { activeWorkers : 0, lastHeartbeatAt : 0, delayed : -1 };
					} )
				).toBeTrue();
				expect( telemetry.$callLog( "gauge" ).gauge.len() ).toBe( 1 );
				var success = variables.service.queueWorkerDiagnostics( "mail" ).lastSuccessAt;
				expect(
					variables.service.captureQueueWorkerHealth( "mail", function(){
						throw( type = "ProviderUnavailable", message = "PRIVATE" );
					} )
				).toBeFalse();
				expect(
					variables.service.captureQueueWorkerHealth( "mail", function(){
						return { password : "PRIVATE" };
					} )
				).toBeFalse();
				expect( variables.service.queueWorkerDiagnostics( "mail" ).failures ).toBe( 2 );
				expect( variables.service.queueWorkerDiagnostics( "mail" ).lastSuccessAt ).toBe( success );
				expect( telemetry.$callLog( "gauge" ).gauge.len() ).toBe( 1 );
				expect( serializeJSON( variables.service.queueWorkerDiagnostics( "mail" ) ) ).notToInclude( "PRIVATE" );
			} );

			it( "delegates the cbq compatibility API to its optional external adapter", function(){
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "gauge" );
				var calls = 0;
				telemetry.$property(
					"adapterResolver",
					"variables",
					{
						resolve : function( mapping ){
							expect( mapping ).toBe( "WorkerHealthAdapter@cbq" );
							return {
								samplePool : function( pool ){
									expect( pool.marker ).toBe( "PRIVATE" );
									calls++;
									return { configuredWorkers : 4, activeExecutions : 1 };
								}
							};
						}
					}
				);
				expect( variables.service.captureCBQWorkerHealth( "mail", { marker : "PRIVATE" } ) ).toBeTrue();
				expect( calls ).toBe( 1 );
				expect( telemetry.$callLog( "gauge" ).gauge.len() ).toBe( 2 );
				expect( serializeJSON( telemetry.$callLog( "gauge" ) ) ).notToInclude( "PRIVATE" );
			} );
			it( "keeps generic manual sampling available when the optional cbq adapter is absent", function(){
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "gauge" );
				telemetry.$property(
					"adapterResolver",
					"variables",
					{
						resolve : function(){
							throw( type = "MissingOptionalAdapter" );
						}
					}
				);
				expect( variables.service.captureCBQWorkerHealth( "mail", {} ) ).toBeFalse();
				expect( telemetry.$callLog( "gauge" ).gauge.len() ).toBe( 0 );
				expect(
					variables.service.captureQueueWorkerHealth( "mail", function(){
						return { activeWorkers : 0 };
					} )
				).toBeTrue();
				expect( telemetry.$callLog( "gauge" ).gauge.len() ).toBe( 1 );
			} );

			it( "restricts executor names and omits unsupported or nonnumeric fields", function(){
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "gauge" );
				var count  = 0;
				var sample = function(){
					count++;
					return {
						active   : 2,
						max      : 4,
						queued   : 0,
						rejected : 3,
						password : "PRIVATE",
						other    : 123
					};
				};
				expect( variables.service.captureRequestExecutor( "PRIVATE", sample ) ).toBeFalse();
				expect( count ).toBe( 0 );
				expect( variables.service.captureRequestExecutor( "http", sample ) ).toBeTrue();
				expect( count ).toBe( 1 );
				expect( telemetry.$callLog( "gauge" ).gauge.len() ).toBe( 4 );
				expect( serializeJSON( telemetry.$callLog( "gauge" ) ) ).notToInclude( "PRIVATE" );
				expect(
					variables.service.captureRequestExecutor( "http", function(){
						return { active : -1, max : "PRIVATE" };
					} )
				).toBeFalse();
				expect( variables.service.requestExecutorDiagnostics( "http" ).failures ).toBe( 1 );
			} );
		} );
	}

}
