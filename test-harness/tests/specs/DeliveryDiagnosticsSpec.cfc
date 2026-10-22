component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "Envelope delivery freshness", function(){
			afterEach( function(){
				cfhttp( url = "http://127.0.0.1:60320/reset", method = "post" ) {
					cfhttpparam( type = "body", value = "{}" );
				}
			} );
			it( "keeps receipt collection opt-in", function(){
				var service = new sentry.models.SentryService( { DSN : "http://public@127.0.0.1:60320/1" } );
				try {
					service.captureFeedback( message = "test", wait = true );
					expect( service.deliveryDiagnostics().enabled ).toBeFalse();
					expect( service.deliveryDiagnostics().outcomes ).toBeEmpty();
				} finally {
					service.shutdown();
				}
			} );
			it( "polls asynchronous acceptance once and exposes content-free freshness", function(){
				var service = new sentry.models.SentryService( {
					DSN                       : "http://public@127.0.0.1:60320/1",
					enableDeliveryDiagnostics : true
				} );
				try {
					expect( service.deliveryDiagnostics().lastAcceptedAt ).toBe( 0 );
					var receipt = service.captureFeedback( message = "PRIVATE" );
					receipt.awaitDelivery();
					var diagnostics = service.deliveryDiagnostics();
					expect( diagnostics.outcomes.accepted ).toBe( 1 );
					expect( diagnostics.pending ).toBe( 0 );
					expect( diagnostics.lastAcceptedAt ).toBeGT( 0 );
					expect( service.deliveryDiagnostics().outcomes.accepted ).toBe( 1 );
					expect( serializeJSON( diagnostics ) ).notToInclude( "PRIVATE" );
					expect( serializeJSON( diagnostics ) ).notToInclude( receipt.getEventId() );
				} finally {
					service.shutdown();
				}
			} );
			it( "records rejected, failed, disabled and filtered results separately", function(){
				cfhttp( url = "http://127.0.0.1:60320/reset", method = "post" ) {
					cfhttpparam( type = "body", value = "{""status"":429}" );
				}
				var service = new sentry.models.SentryService( {
					DSN                       : "http://public@127.0.0.1:60320/1",
					enableDeliveryDiagnostics : true
				} );
				try {
					service.captureFeedback( message = "test", wait = true );
					service.captureFeedback( message = "test", wait = true );
					var d = service.deliveryDiagnostics();
					expect( d.outcomes.rejected ).toBe( 1 );
					expect( d.outcomes.dropped ).toBe( 1 );
					expect( d.lastAcceptedAt ).toBe( 0 );
				} finally {
					service.shutdown();
				}
				var offline = new sentry.models.SentryService( {
					DSN                       : "http://public@127.0.0.1:60360/1",
					enableDeliveryDiagnostics : true,
					transportTimeout          : 100
				} );
				try {
					offline.captureFeedback( message = "test", wait = true );
					offline.flush();
					expect( offline.deliveryDiagnostics().outcomes.failed ).toBe( 1 );
				} finally {
					offline.shutdown();
				}
				var diagnostics = new sentry.models.telemetry.DeliveryDiagnostics( 1 );
				diagnostics.record( new sentry.models.telemetry.Receipt( "test", "disabled" ) );
				diagnostics.record( new sentry.models.telemetry.Receipt( "test", "filtered" ) );
				expect( diagnostics.snapshot().outcomes.disabled ).toBe( 1 );
				expect( diagnostics.snapshot().outcomes.filtered ).toBe( 1 );
			} );
			it( "bounds receipt retention and makes incomplete diagnostic coverage explicit", function(){
				var diagnostics = new sentry.models.telemetry.DeliveryDiagnostics( 1 );
				var pending     = {
					getStatus : function(){
						return "queued";
					}
				};
				diagnostics.record( pending );
				diagnostics.record( pending );
				expect( diagnostics.snapshot().pending ).toBe( 1 );
				expect( diagnostics.snapshot().untracked ).toBe( 1 );
				expect( diagnostics.snapshot().lastAcceptedAt ).toBe( 0 );
			} );
		} );
	}

}
