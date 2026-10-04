component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "Native observability", function(){
			beforeEach( function(){
				variables.service = new sentry.models.SentryService( {
					DSN                     : "http://public@127.0.0.1:60320/1",
					async                   : false,
					tracesSampleRate        : 1,
					enableLogs              : true,
					enableMetrics           : true,
					enableMonitors          : true,
					tracePropagationTargets : [ "https://api.example.test" ]
				} );
				variables.telemetry = variables.service.getObservability();
			} );
			afterEach( function(){
				variables.service.shutdown();
			} );
			it( "honors parent sampling and rejects malformed headers", function(){
				var off = variables.service.startTransaction(
					"off",
					"task",
					{ "sentry-trace" : repeatString( "a", 32 ) & "-" & repeatString( "b", 16 ) & "-0" },
					true
				);
				expect( off.isSampled() ).toBeFalse();
				expect( variables.telemetry.parseHeaders( { "sentry-trace" : "invalid" } ) ).toBeEmpty();
				expect(
					variables.telemetry.parseHeaders( { "sentry-trace" : repeatString( "0", 32 ) & "-" & repeatString( "b", 16 ) } )
				).toBeEmpty();
			} );
			it( "restores nesting and exception scopes, completes once", function(){
				var root = variables.service.startTransaction( "GET /things/:id" );
				variables.telemetry.setScope( { span : root } );
				expect(
					variables.service.withSpan( "child", function( span ){
						expect( variables.service.getTraceContext().span_id ).toBe( span.getContext().span_id );
						return 42;
					} )
				).toBe( 42 );
				expect( function(){
					variables.service.withSpan( "failed", function( span ){
						throw( type = "TestFailure", message = "expected" );
					} );
				} ).toThrow( "TestFailure" );
				expect( variables.service.getTraceContext().span_id ).toBe( root.getContext().span_id );
				expect( root.getChildren().len() ).toBe( 2 );
				expect( root.finish() ).toBeTrue();
				expect( root.finish( "internal_error" ) ).toBeFalse();
				expect( root.toPayload().status ).toBe( "ok" );
			} );
			it( "propagates to exact trusted origins only", function(){
				variables.telemetry.setScope( { span : variables.service.startTransaction( "task" ) } );
				expect( variables.service.getTraceHeaders( "https://api.example.test/path?token=secret" ) ).notToBeEmpty();
				expect( variables.service.getTraceHeaders( "https://api.example.test.evil/path" ) ).toBeEmpty();
				expect( variables.service.getTraceHeaders( "https://password@api.example.test/path" ) ).toBeEmpty();
			} );
			it( "sends feedback with Unicode and real binary attachments", function(){
				var receipt = variables.service.captureFeedback(
					message     = "Synthetic café 🎭",
					page        = "https://app.example.test/path?token=secret",
					attachments = [
						{
							filename    : "capture.png",
							contentType : "image/png",
							data        : binaryDecode( "89504e470d0a1a0a000102ff", "hex" )
						}
					],
					wait = true
				);
				expect( receipt.getStatus() ).toBe( "accepted" );
				expect( receipt.getEventId().len() ).toBe( 32 );
				expect( variables.service.captureFeedback( message = " " ).getStatus() ).toBe( "invalid" );
			} );
			it( "scrubs literals and unsafe attributes", function(){
				expect(
					variables.telemetry.scrubSQL( "select * from people where secret = 'dont-export' and id = 42" )
				).notToInclude( "dont-export" );
				expect( variables.telemetry.scrubSQL( "select $$private$$" ) ).notToInclude( "private" );
				expect(
					variables.telemetry.sanitizeAttributes( {
						password      : "secret",
						"db.bindings" : "data",
						outcome       : "ok"
					} )
				).toHaveLength( 1 );
			} );
			it( "buffers structured logs and trace metrics and matches check-ins", function(){
				var safe = variables.telemetry.sanitizeAttributes( {
					"cache.key"   : [ "sha256:synthetic", { "password" : "secret" } ],
					"other.array" : [ "secret" ],
					"db.bindings" : [ "secret" ]
				} );
				expect( safe ).toHaveLength( 1 );
				expect( safe[ "cache.key" ] ).toBe( [ "sha256:synthetic" ] );
				variables.service.captureLog(
					"Synthetic operation",
					"info",
					{ outcome : "ok", "cache.key" : [ "sha256:synthetic" ] }
				);
				variables.service.counter( "request.count" );
				variables.service.gauge( "queue.depth", 3 );
				variables.service.distribution( "request.duration", 7, {}, "millisecond" );
				expect(
					variables.service.withMonitor( "synthetic-monitor", function(){
						return 42;
					} )
				).toBe( 42 );
				expect( variables.service.flush() ).toBeTrue();
			} );
		} );
	}

}
