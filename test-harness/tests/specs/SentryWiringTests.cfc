component extends="coldbox.system.testing.BaseTestCase" appMapping="/root" {

	function run(){
		describe( "Sentry singleton publication", function(){
			beforeEach( function(){
				setup();
			} );
			it( "waits for Sentry settings before concurrent exception capture", function(){
				var root     = getWireBox();
				var isolated = new coldbox.system.ioc.Injector( binder = "tests.resources.SentryWiringBinder" );
				isolated.setColdBox( getController() );
				isolated.setParent( root );

				var binder = isolated.getBinder();
				binder.map( "sentryRegression" ).to( "sentry.models.SentryService" );
				var started = createObject( "java", "java.util.concurrent.CountDownLatch" ).init( 1 );
				var release = createObject( "java", "java.util.concurrent.CountDownLatch" ).init( 1 );
				var entered = createObject( "java", "java.util.concurrent.CountDownLatch" ).init( 1 );
				var seconds = createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS;
				var millis  = createObject( "java", "java.util.concurrent.TimeUnit" ).MILLISECONDS;
				isolated
					.getEventManager()
					.register( new tests.resources.SentryWiringGate( started, release ), "sentryGate" );
				var executorName = "sentry-wiring-" & createUUID();
				var async        = getController().getAsyncManager();
				var executor     = async.newExecutor( executorName, "fixed", 2 );
				try {
					var producer = executor.submit( function(){
						return isolated.getInstance( "sentryRegression" );
					} );
					expect( started.await( javacast( "long", 3 ), seconds ) ).toBeTrue();
					var consumer = executor.submit( function(){
						entered.countDown();
						return isolated.getInstance( "sentryRegression" );
					} );
					expect( entered.await( javacast( "long", 3 ), seconds ) ).toBeTrue();
					var waitingForWiring = false;
					try {
						consumer
							.getNative()
							.get( javacast( "long", 200 ), millis )
							.captureException(
								exception = {
									"message"    : "Synthetic original error",
									"detail"     : "",
									"stackTrace" : ""
								}
							);
					} catch ( java.util.concurrent.TimeoutException expected ) {
						waitingForWiring = true;
					}
					expect( waitingForWiring ).toBeTrue();
					release.countDown();
					producer.getNative().get( javacast( "long", 3 ), seconds );
					var ready = consumer.getNative().get( javacast( "long", 3 ), seconds );
					expect( ready.getSettings().showJavaStackTrace ).toBeFalse();
					expect( ready ).toBe( producer.getNative().get() );
					// Replace only transport: exercise the real initialized capture pipeline.
					prepareMock( ready ).$( "post" );
					ready.setEnabled( true );
					ready.captureException(
						exception = {
							"message"    : "Original application error",
							"detail"     : "",
							"stackTrace" : "Synthetic stack"
						},
						cgiVars   = {},
						useThread = false
					);
					var payload = deserializeJSON( ready.$callLog( "post" ).post[ 1 ][ 4 ] );
					expect( payload.message ).toInclude( "Original application error" );
				} finally {
					release.countDown();
					executor.shutdown();
					executor.getNative().awaitTermination( javacast( "long", 5 ), seconds );
					async.deleteExecutor( executorName );
					isolated.setColdBox( "" );
					isolated.shutdown();
				}
			} );
		} );
	}

}
