component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "Operational review regressions", function(){
			it( "keeps one canonical phase when configured names differ only in case", function(){
				var timing = new sentry.models.telemetry.RequestTimings( {}, [ "render", "Render" ] );
				timing.measure( "render", function(){
					return 1;
				} );
				timing.measure( "Render", function(){
					return 2;
				} );
				expect( timing.snapshot().render.count ).toBe( 2 );
				expect( listLen( timing.toServerTiming(), "," ) ).toBe( 1 );
			} );
			it( "rejects trailing LF and CRLF in configured HTTP timing names", function(){
				var lf     = "render" & chr( 10 );
				var crlf   = "render" & chr( 13 ) & chr( 10 );
				var timing = new sentry.models.telemetry.RequestTimings( {}, [ lf, crlf ] );
				expect( timing.begin( lf ) ).toBeEmpty();
				expect( timing.begin( crlf ) ).toBeEmpty();
				expect( timing.toServerTiming() ).toBe( "" );
			} );
			it( "owns timing tokens privately and ignores mutable metadata and foreign handles", function(){
				var finishes = 0;
				var observer = {
					startSpan : function(){
						return {
							finish : function(){
								finishes++;
							}
						};
					}
				};
				var timing = new sentry.models.telemetry.RequestTimings( observer, [ "handler" ] );
				var other  = new sentry.models.telemetry.RequestTimings( observer, [ "handler" ] );
				var token  = timing.begin( "handler" );
				other.finish( token );
				expect( finishes ).toBe( 0 );
				token.name    = "PRIVATE";
				token.started = 0;
				token.span    = {};
				token.done    = "malformed";
				timing.finish( token );
				timing.finish( token );
				expect( finishes ).toBe( 1 );
				expect( timing.snapshot().handler.count ).toBe( 1 );
				expect( serializeJSON( timing.snapshot() ) ).notToInclude( "PRIVATE" );
				expect( other.snapshot() ).toBeEmpty();
				timing.finish( { "done" : "malformed" } );
			} );
			it( "attempts workflow span completion even if restoration or annotation fails", function(){
				for ( var mode in [ "restore", "attribute" ] ) {
					var finishes  = 0;
					var scopes    = 0;
					var telemetry = {
						getScope : function(){
							return {};
						},
						setScope : function(){
							scopes++;
							if ( mode == "restore" && scopes > 1 ) {
								throw( type = "ObserverFailure" );
							}
						},
						startSpan : function(){
							return {
								setAttribute : function(){
									if ( mode == "attribute" ) {
										throw( type = "ObserverFailure" );
									}
								},
								finish : function(){
									finishes++;
								}
							};
						},
						counter : function(){
						},
						distribution : function(){
						}
					};
					var operation = new sentry.models.telemetry.Operation( telemetry );
					expect(
						operation.run( "workflow", function(){
							return 42;
						} )
					).toBe( 42 );
					expect( finishes ).toBe( 1 );
					expect( function(){
						operation.run( "workflow", function(){
							throw( type = "OriginalFailure" );
						} );
					} ).toThrow( "OriginalFailure" );
					expect( finishes ).toBe( 2 );
				}
			} );
			it( "preserves distinct queue destinations differing only in case and reports both drained", function(){
				var samples = [];
				var rows    = [
					{ "queue" : "mail", "depth" : 2, "oldest" : 1 },
					{ "queue" : "MAIL", "depth" : 5, "oldest" : 1 }
				];
				var sampler = new sentry.models.telemetry.DatabaseQueueMetrics(
					{
						captureQueueMetrics : function( name, depth, age ){
							samples.append( { "name" : name, "depth" : depth } );
						}
					},
					{
						getWorkerPoolDefinitions : function(){
							return {
								"worker" : {
									getQueue : function(){
										return [ "mail", "MAIL" ];
									}
								}
							};
						}
					},
					function(){
						return new tests.resources.QueueMetricsQuery( rows );
					}
				);
				expect( sampler.capture() ).toBeTrue();
				expect( samples.len() ).toBe( 2 );
				for ( var sample in samples ) {
					expect( sample.depth ).toBe( compare( sample.name, "mail" ) == 0 ? 2 : 5 );
				}
				rows    = [];
				samples = [];
				expect( sampler.capture() ).toBeTrue();
				expect( samples.len() ).toBe( 2 );
				for ( var sample in samples ) {
					expect( sample.depth ).toBe( 0 );
				}
			} );
			it( "excludes transaction export time from queue processing duration", function(){
				var service = prepareMock(
					new sentry.models.SentryService( {
						DSN                : "http://public@127.0.0.1:60320/1",
						tracesSampleRate   : 1,
						enableQueueTracing : true
					} )
				);
				try {
					var clock     = 10;
					var telemetry = prepareMock( service.getObservability() );
					telemetry
						.$( "timestamp" )
						.$callback( function(){
							return clock;
						} );
					telemetry
						.$( "completeTransaction" )
						.$callback( function(){
							clock += 5;
						} );
					service.$( "counter" );
					service.$( "distribution" );
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
							return "mail";
						},
						getId : function(){
							return "id";
						},
						isBatchJob : function(){
							return false;
						}
					};
					var data = {
						"job"         : job,
						"attempt"     : 1,
						"executionId" : "duration-test",
						"status"      : "ok"
					};
					observer.onCBQJobAttemptScheduled( {}, data );
					observer.onCBQJobExecutionStarted( {}, data );
					clock = 11;
					observer.onCBQJobExecutionExited( {}, data );
					observer.onCBQJobAttemptFinished( {}, data );
					var calls = service.$callLog( "distribution" ).distribution;
					expect( calls.len() ).toBe( 2 );
					expect( calls[ 2 ][ 1 ] ).toBe( "queue.processing.duration" );
					expect( calls[ 2 ][ 2 ] ).toBe( 1000 );
				} finally {
					service.shutdown();
				}
			} );
		} );
	}

}
