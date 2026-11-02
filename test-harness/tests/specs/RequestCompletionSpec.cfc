component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "request completion ownership", function(){
			beforeEach( function(){
				variables.service = new sentry.models.SentryService( {
					DSN                           : "http://public@127.0.0.1:1/1",
					tracesSampleRate              : 1,
					enableRequestTracing          : true,
					enableAutomaticRequestTimings : true,
					beforeSendSignal              : function(){
						return javacast( "null", "" );
					}
				} );
				variables.telemetry = variables.service.getObservability();
				variables.observer  = createMock( "sentry.interceptors.Observability" ).$property(
					"sentry",
					"variables",
					variables.service
				);
			} );
			afterEach( function(){
				variables.service.shutdown();
			} );
			it( "drains binary render and manual handles exactly once at abort completion", function(){
				var event = context();
				variables.observer.onRequestCapture( event, {} );
				var state  = event.getPrivateValue( "_sentryRequest", {} );
				var manual = state.timings.begin( "manual" );
				variables.observer.preEvent( event, {} );
				variables.observer.postEvent( event, {} );
				variables.observer.preRender( event, {} );
				variables.service.endRequest();
				var payload = state.span.toPayload();
				expect( state.span.getChildren().len() ).toBe( 3 );
				expect( state.timings.snapshot().render.count ).toBe( 1 );
				expect( state.timings.snapshot().manual.count ).toBe( 1 );
				expect( state.timings.begin( "after_response" ) ).toBeEmpty();
				state.timings.finish( manual );
				variables.observer.postRender( event, {} );
				variables.observer.postProcess( event, {} );
				variables.service.endRequest();
				expect( state.span.toPayload().timestamp ).toBe( payload.timestamp );
				expect( state.span.getChildren().len() ).toBe( 3 );
				expect( variables.telemetry.getScope() ).toBeEmpty();
			} );
			it( "does not close a new request from an old event callback on a reused worker", function(){
				var first = context();
				variables.observer.onRequestCapture( first, {} );
				var firstState = first.getPrivateValue( "_sentryRequest", {} );
				variables.service.endRequest();
				var second = context();
				variables.observer.onRequestCapture( second, {} );
				var secondState = second.getPrivateValue( "_sentryRequest", {} );
				variables.observer.postProcess( first, {} );
				expect( secondState.span.isFinished() ).toBeFalse();
				expect( variables.telemetry.getScope().requestState.id ).toBe( secondState.id );
				variables.service.endRequest();
				expect( secondState.span.isFinished() ).toBeTrue();
				expect( variables.telemetry.getScope() ).toBeEmpty();
			} );
			it( "isolates successive request contexts even if a worker missed all cleanup", function(){
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "executionOwner", "request-one" );
				telemetry.setScope( { marker : "old request" } );
				telemetry.$( "executionOwner", "request-two" );
				expect( telemetry.getScope() ).toBeEmpty();
				expect( telemetry.getScopeResetCount() ).toBe( 1 );
				telemetry.setScope( { marker : "new request" } );
				expect( telemetry.getScope().marker ).toBe( "new request" );
			} );
			it( "restores a same-request scope after completion", function(){
				variables.telemetry.setScope( { marker : "outer" } );
				var event = context();
				variables.observer.onRequestCapture( event, {} );
				variables.service.endRequest( statusCode = 303 );
				expect( variables.telemetry.getScope().marker ).toBe( "outer" );
				expect(
					event.getPrivateValue( "_sentryRequest", {} ).span.toPayload().data[ "http.response.status_code" ]
				).toBe( 303 );
			} );
			it( "uses elapsed monotonic time despite a wall-clock jump and preserves epoch seconds", function(){
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "timestamp", 1700000000 );
				telemetry.$( "monotonicTime", 1000000000 );
				var span = telemetry.startTransaction( "clock" );
				telemetry.$( "timestamp", 1700027000 );
				telemetry.$( "monotonicTime", 2500000000 );
				span.finish();
				expect( span.toPayload().start_timestamp ).toBe( 1700000000 );
				expect( span.toPayload().timestamp ).toBe( 1700000001.5 );
				expect( span.getDurationMilliseconds() ).toBe( 1500 );
				expect( span.finish() ).toBeFalse();
				telemetry.$( "monotonicTime", 10000000000 );
				var backwards = telemetry.startTransaction( "backwards clock" );
				telemetry.$( "timestamp", 1700000000 );
				telemetry.$( "monotonicTime", 12000000000 );
				backwards.finish();
				expect( backwards.toPayload().timestamp ).toBe( 1700027002 );
			} );
			it( "resets the monotonic origin when queued work actually starts", function(){
				var telemetry = prepareMock( variables.telemetry );
				telemetry.$( "monotonicTime", 1000000000 );
				var span = telemetry.startTransaction( "queued" );
				telemetry.$( "monotonicTime", 9000000000 );
				span.markStarted( 1700000008 );
				telemetry.$( "monotonicTime", 9250000000 );
				span.finish();
				expect( span.toPayload().timestamp ).toBe( 1700000008.25 );
			} );
			it( "preserves callback results and original exceptions with unavailable telemetry", function(){
				var timings = new sentry.models.telemetry.RequestTimings(
					{
						startSpan : function(){
							throw( type = "SentryFixture.Unavailable" );
						},
						distribution : function(){
							throw( type = "SentryFixture.Unavailable" );
						}
					},
					[],
					64,
					true
				);
				expect(
					timings.measure( "result", function(){
						return false;
					} )
				).toBeFalse();
				try {
					timings.measure( "failure", function(){
						throw( type = "SentryFixture.Original", message = "preserve me" );
					} );
					fail( "must throw" );
				} catch ( SentryFixture.Original original ) {
					expect( original.message ).toBe( "preserve me" );
				}
				expect( timings.snapshot().failure.count ).toBe( 1 );
			} );
			it( "keeps concurrent request spans and restored scopes independent", function(){
				var reference = createObject( "java", "java.util.concurrent.atomic.AtomicReference" ).init(
					variables.service
				);
				var results = createObject( "java", "java.util.concurrent.ConcurrentHashMap" ).init();
				var gate    = createObject( "java", "java.util.concurrent.CyclicBarrier" ).init( 2 );
				var names   = [];
				for ( var i = 1; i <= 2; i++ ) {
					var name = "request-isolation-" & replace( createUUID(), "-", "", "all" );
					names.append( name );
					thread name=name action="run" service=reference results=results gate=gate marker=i {
						var telemetry = attributes.service.get().getObservability();
						for ( var iteration = 1; iteration <= 2; iteration++ ) {
							telemetry.setScope( { marker : attributes.marker } );
							var root  = telemetry.startTransaction( "concurrent request" );
							var state = {
								span     : root,
								previous : { marker : attributes.marker },
								done     : createObject( "java", "java.util.concurrent.atomic.AtomicBoolean" ).init(
									false
								)
							};
							telemetry.setScope( { span : root, requestState : state } );
							attributes.gate.await(
								javacast( "long", 5 ),
								createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
							);
							var child = telemetry.startSpan( "owned" );
							child.finish();
							attributes.service.get().endRequest();
							attributes.results.put(
								attributes.marker & "-" & iteration,
								{
									marker     : telemetry.getScope().marker,
									trace      : root.getContext().trace_id,
									childTrace : child.getContext().trace_id,
									finished   : root.isFinished(),
									count      : root.getChildren().len()
								}
							);
							telemetry.clearScope();
						}
					}
				}
				thread action="join" name=arrayToList( names ) timeout=15000;
				for ( var name in names ) expect( cfthread[ name ].status ).toBe( "COMPLETED" );
				expect( results.size() ).toBe( 4 );
				var traces = {};
				for ( var key in results.keySet() ) {
					var result = results.get( key );
					expect( result.marker ).toBe( val( key ) );
					expect( result.finished ).toBeTrue();
					expect( result.count ).toBe( 1 );
					expect( result.childTrace ).toBe( result.trace );
					traces[ result.trace ] = true;
				}
				expect( traces.count() ).toBe( 4 );
				expect( variables.telemetry.getScope() ).toBeEmpty();
			} );
		} );
	}
	private function context(){
		var state = {};
		return {
			getPrivateValue : function( name, fallback ){
				return state[ arguments.name ] ?: arguments.fallback;
			},
			setPrivateValue : function( name, value ){
				state[ arguments.name ] = arguments.value;
			},
			getCurrentRoute : function(){
				return "binary/:id";
			},
			getCurrentEvent : function(){
				return "Responses.binary";
			},
			getHTTPMethod : function(){
				return "GET";
			}
		};
	}

}
