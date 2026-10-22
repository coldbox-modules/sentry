component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "Reusable observations", function(){
			beforeEach( function(){
				variables.service = new sentry.models.SentryService( {
					DSN                : "http://public@127.0.0.1:60320/1",
					tracesSampleRate   : 1,
					enableMetrics      : true,
					enableQueueTracing : true,
					requestTimingNames : [ "handler", "render", "bad,header" ],
					operationNames     : [ "invitation" ],
					providerNames      : [ "mail" ],
					databasePoolNames  : [ "primary" ]
				} );
				variables.telemetry = variables.service.getObservability();
			} );
			afterEach( function(){
				variables.telemetry.clearScope();
				variables.service.shutdown();
			} );
			it( "bounds request phases, preserves callbacks and completes tokens once", function(){
				var root = variables.service.startTransaction( "request" );
				variables.telemetry.setScope( { "span" : root } );
				var timing = variables.service.newRequestTimings();
				expect( timing.begin( "unregistered" ) ).toBeEmpty();
				expect( timing.begin( "bad,header" ) ).toBeEmpty();
				var token = timing.begin( "handler" );
				timing.finish( token );
				timing.finish( token, "internal_error" );
				expect( timing.snapshot().handler.count ).toBe( 1 );
				expect(
					timing.measure( "render", function(){
						return 42;
					} )
				).toBe( 42 );
				expect( function(){
					timing.measure( "render", function(){
						throw( type = "OriginalFailure" );
					} );
				} ).toThrow( "OriginalFailure" );
				expect( root.getChildren().len() ).toBe( 3 );
				expect( root.getChildren()[ 3 ].toPayload().status ).toBe( "internal_error" );
				expect( timing.toServerTiming() ).toInclude( "handler;dur=" );
				expect( timing.toServerTiming() ).notToInclude( "bad" );
				expect( variables.service.newRequestTimings().snapshot() ).toBeEmpty();
				for ( var i = 1; i <= 64; i++ ) {
					timing.finish( timing.begin( "handler" ) );
				}
				expect( timing.snapshot().handler.count ).toBe( 62 );
				expect( timing.begin( "handler" ) ).toBeEmpty();
				root.finish();
			} );
			it( "retains timings and original exceptions when tracing is unavailable", function(){
				var timing = new sentry.models.telemetry.RequestTimings(
					{
						startSpan : function(){
							throw( type = "TelemetryUnavailable" );
						}
					},
					[ "handler" ]
				);
				expect(
					timing.measure( "handler", function(){
						return false;
					} )
				).toBeFalse();
				expect( function(){
					timing.measure( "handler", function(){
						throw( type = "OriginalFailure" );
					} );
				} ).toThrow( "OriginalFailure" );
				expect( timing.snapshot().handler.count ).toBe( 2 );
			} );
			it( "records registered workflow outcomes without collecting results or expanding capture", function(){
				var root = variables.service.startTransaction( "request" );
				variables.telemetry.setScope( { "span" : root } );
				var calls  = 0;
				var result = variables.service.withOperation(
					"invitation",
					function(){
						calls++;
						return { "private" : "PRIVATE" };
					},
					"mail",
					function(){
						return "accepted";
					}
				);
				expect( calls ).toBe( 1 );
				expect( result.private ).toBe( "PRIVATE" );
				expect( root.getChildren()[ 1 ].toPayload().data[ "workflow.outcome" ] ).toBe( "accepted" );
				expect( serializeJSON( root.getChildren()[ 1 ].toPayload() ) ).notToInclude( "PRIVATE" );
				expect( variables.telemetry.getScope().span.getContext().span_id ).toBe(
					root.getContext().span_id
				);
				variables.service.withOperation( "unregistered", function(){
					calls++;
				} );
				variables.service.withOperation(
					"invitation",
					function(){
						calls++;
					},
					"unregistered"
				);
				expect( calls ).toBe( 3 );
				expect( root.getChildren().len() ).toBe( 1 );
				variables.service.withOperation(
					"invitation",
					function(){
						return 1;
					},
					"mail",
					function(){
						return "PRIVATE";
					}
				);
				expect( root.getChildren()[ 2 ].toPayload().data[ "workflow.outcome" ] ).toBe( "unknown" );
				expect( function(){
					variables.service.withOperation( "invitation", function(){
						throw( type = "OriginalFailure" );
					} );
				} ).toThrow( "OriginalFailure" );
				expect( root.getChildren()[ 3 ].toPayload().status ).toBe( "internal_error" );
				root.finish();
			} );
			it( "never retries application callbacks when observation fails", function(){
				var observer = new sentry.models.telemetry.Operation( {
					getScope : function(){
						throw( type = "TelemetryUnavailable" );
					},
					counter : function(){
						throw( type = "TelemetryUnavailable" );
					}
				} );
				var calls = 0;
				expect(
					observer.run( "test", function(){
						calls++;
						return 0;
					} )
				).toBe( 0 );
				expect( calls ).toBe( 1 );
				observer.run( "test", function(){
					calls++;
				} );
				expect( calls ).toBe( 2 );
				expect( function(){
					observer.run( "test", function(){
						throw( type = "OriginalFailure" );
					} );
				} ).toThrow( "OriginalFailure" );
			} );
			it( "keeps terminal queue outcomes separate and avoids fictional processing samples", function(){
				var service = prepareMock( variables.service );
				service.$( "counter" );
				service.$( "distribution" );
				service.getSettings().enableQueueJobMetrics = true;
				service.getSettings().queueMetricDestinations = [ "mail" ];
				var observer = createMock( "sentry.interceptors.QueueObservability" ).$property(
					"sentry",
					"variables",
					service
				);
				var queue = "mail";
				var job   = {
					getProperties : function(){
						return {};
					},
					getMapping : function(){
						return "TestJob";
					},
					getQueue : function(){
						return queue;
					},
					getId : function(){
						return "PRIVATE";
					},
					isBatchJob : function(){
						return false;
					}
				};
				var data = {
					"job"         : job,
					"attempt"     : 2,
					"executionId" : "unstarted",
					"status"      : "cancelled"
				};
				observer.onCBQJobAttemptScheduled( {}, data );
				observer.onCBQJobAttemptFinished( {}, data );
				observer.onCBQJobAttemptFinished( {}, data );
				expect( service.$callLog( "counter" ).counter.len() ).toBe( 1 );
				expect( service.$callLog( "distribution" ).distribution.len() ).toBe( 0 );
				observer.onCBQJobFailed( {}, data );
				queue = "PRIVATE";
				observer.onCBQJobComplete( {}, data );
				var calls = service.$callLog( "counter" ).counter;
				expect( calls[ 2 ][ 1 ] ).toBe( "queue.jobs" );
				expect( calls[ 2 ][ 3 ].outcome ).toBe( "failed" );
				expect( calls[ 2 ][ 3 ][ "messaging.destination.name" ] ).toBe( "mail" );
				expect( calls[ 3 ][ 3 ].outcome ).toBe( "completed" );
				expect( serializeJSON( calls ) ).notToInclude( "PRIVATE" );
				service.getSettings().enableQueueJobMetrics = false;
				observer.onCBQJobFailed( {}, data );
				expect( service.$callLog( "counter" ).counter.len() ).toBe( 3 );
			} );
			it( "samples JVM gauges and omits unsupported CPU/GC instead of substituting zero", function(){
				var samples = variables.service.captureRuntimeGauges();
				expect( samples[ "jvm.heap.used" ].value ).toBeGT( 0 );
				expect( samples[ "jvm.threads" ].value ).toBeGT( 0 );
				var sampler = prepareMock( new sentry.models.telemetry.RuntimeMetrics( variables.telemetry ) );
				expect( sampler.readAttribute( "java.lang:type=OperatingSystem", "AvailableProcessors" ) ).toBeGT(
					0
				);
				sampler
					.$( "readAttribute" )
					.$callback( function( bean, attribute ){
						return attribute == "ProcessCpuLoad" ? 0.25 : 2;
					} );
				var supported = sampler.capture();
				expect( supported[ "jvm.cpu.process" ].value ).toBe( 0.25 );
				if (
					createObject( "java", "java.lang.management.ManagementFactory" )
						.getGarbageCollectorMXBeans()
						.size() > 0
				) {
					expect( supported[ "jvm.gc.collections.total" ].value ).toBeGT( 0 );
					expect( supported[ "jvm.gc.duration.total" ].value ).toBeGT( 0 );
				}
				sampler.$( "readAttribute", -1 );
				var unsupported = sampler.capture();
				expect( unsupported ).notToHaveKey( "jvm.cpu.process" );
				expect( unsupported ).notToHaveKey( "jvm.gc.duration.total" );
				expect( unsupported ).toHaveKey( "jvm.heap.used" );
			} );
			it( "closes queue roots even if attempt metrics fail", function(){
				var service  = prepareMock( variables.service );
				var observer = createMock( "sentry.interceptors.QueueObservability" ).$property(
					"sentry",
					"variables",
					service
				);
				var job = {
					getProperties : function(){
						return {};
					},
					getMapping : function(){
						return "TestJob";
					},
					getQueue : function(){
						return "test";
					},
					getId : function(){
						return "test-id";
					},
					isBatchJob : function(){
						return false;
					}
				};
				var data = {
					"job"         : job,
					"attempt"     : 1,
					"executionId" : "test-attempt",
					"status"      : "ok"
				};
				observer.onCBQJobAttemptScheduled( {}, data );
				observer.onCBQJobExecutionStarted( {}, data );
				var span = variables.telemetry.getScope().span;
				service.$( "counter" ).$throws( "TelemetryUnavailable" );
				observer.onCBQJobAttemptFinished( {}, data );
				expect( span.isFinished() ).toBeTrue();
				expect( span.getRoot().isFinished() ).toBeTrue();
				observer.onCBQJobExecutionExited( {}, data );
				expect( observer.getPendingAttemptCount() ).toBe( 0 );
			} );
			it( "requires a named supported pool adapter and sends only numeric pool fields", function(){
				var calls = 0;
				expect(
					variables.service.captureDatabasePool( "unregistered", function(){
						calls++;
						return {};
					} )
				).toBeFalse();
				expect( calls ).toBe( 0 );
				expect(
					variables.service.captureDatabasePool( "primary", function(){
						throw( type = "UnsupportedPool" );
					} )
				).toBeFalse();
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "gauge" );
				expect(
					variables.service.captureDatabasePool( "primary", function(){
						return {
							"active"   : 2,
							"max"      : 4,
							"waiters"  : -1,
							"password" : "PRIVATE"
						};
					} )
				).toBeTrue();
				var calls = telemetry.$callLog( "gauge" ).gauge;
				expect( calls.len() ).toBe( 3 );
				expect( serializeJSON( calls ) ).notToInclude( "PRIVATE" );
				expect( calls[ 3 ][ 1 ] ).toBe( "db.pool.utilization" );
				expect( calls[ 3 ][ 2 ] ).toBe( 0.5 );
			} );
			it( "serializes the standard lowercase trace context for error events", function(){
				var root = variables.service.startTransaction( "request" );
				variables.telemetry.setScope( { "span" : root } );
				var service = prepareMock( variables.service ).$( "post" );
				service.captureMessage(
					message   = "test",
					cgiVars   = {},
					useThread = false
				);
				var json = service.$callLog( "post" ).post[ 1 ][ 4 ];
				expect( find( """trace"":", json ) ).toBeGT( 0 );
				expect( find( """TRACE"":", json ) ).toBe( 0 );
				expect( find( """contexts"":", json ) ).toBeGT( 0 );
				root.finish();
			} );
		} );
	}

}
