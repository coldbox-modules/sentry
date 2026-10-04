component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "bounded envelope transport", function(){
			function receiver( struct mode = {} ){
				cfhttp( url = "http://127.0.0.1:60320/reset", method = "post" ) {
					cfhttpparam( type = "body", value = serializeJSON( arguments.mode ) );
				}
			}
			afterEach( function(){
				receiver();
			} );
			it( "distinguishes rejected delivery and honors category rate limits", function(){
				receiver( {
					"status"  : 429,
					"delay"   : 0,
					"headers" : { "X-Sentry-Rate-Limits" : "60:user_report::,60:log_item::" }
				} );
				var service = new sentry.models.SentryService( { DSN : "http://public@127.0.0.1:60320/1", async : false } );
				try {
					expect( service.captureFeedback( message = "Synthetic", wait = true ).getStatus() ).toBe( "rejected" );
					expect( service.captureFeedback( message = "Retry", wait = true ).getStatus() ).toBe( "dropped" );
					expect(
						service
							.getObservability()
							.sendSignal(
								"transaction",
								{ event_id : repeatString( "a", 32 ) },
								"transaction",
								[],
								true
							)
							.getStatus()
					).toBe( "rejected" );
				} finally {
					service.shutdown();
				}
			} );
			it( "limits attachments independently and observes each response once", function(){
				receiver( {
					status    : 200,
					"headers" : { "X-Sentry-Rate-Limits" : "60:attachment::,60:metric::" }
				} );
				var service = new sentry.models.SentryService( { DSN : "http://public@127.0.0.1:60320/1" } );
				try {
					var receipt = service.captureFeedback( message = "First", wait = true );
					receipt.awaitDelivery();
					receipt.awaitDelivery();
					expect(
						service
							.getObservability()
							.getTransport()
							.getDiagnostics()
							.accepted
					).toBe( 1 );
					expect(
						service
							.captureFeedback(
								message     = "No attachment",
								attachments = [
									{
										filename : "verification.bin",
										data     : charsetDecode( "synthetic", "UTF-8" )
									}
								],
								wait = true
							)
							.isAccepted()
					).toBeTrue();
					cfhttp( url = "http://127.0.0.1:60320/state" );
					var received = deserializeJSON( cfhttp.fileContent );
					expect( received[ 2 ].items.len() ).toBe( 1 );
					expect(
						service
							.getObservability()
							.sendSignal(
								"trace_metric",
								{ items : [] },
								"trace_metric",
								[],
								true
							)
							.getStatus()
					).toBe( "dropped" );
				} finally {
					service.shutdown();
				}
			} );
			it( "bounds pending requests and handles unavailable ingestion", function(){
				receiver( { "status" : 200, "delay" : 300, "headers" : {} } );
				var service = new sentry.models.SentryService( {
					DSN                 : "http://public@127.0.0.1:60320/1",
					maxPendingEnvelopes : 1
				} );
				try {
					var first = service.captureFeedback( message = "First" );
					expect( first.getStatus() ).toBe( "queued" );
					expect( service.captureFeedback( message = "Second" ).getStatus() ).toBe( "dropped" );
					expect( first.awaitDelivery( 1000 ).getStatus() ).toBe( "accepted" );
				} finally {
					service.shutdown();
				}
				var unavailable = new sentry.models.SentryService( {
					DSN              : "http://public@127.0.0.1:60329/1",
					transportTimeout : 100
				} );
				try {
					expect( unavailable.captureFeedback( message = "Offline", wait = true ).isAccepted() ).toBeFalse();
				} finally {
					unavailable.shutdown();
				}
			} );
		} );
	}

}
