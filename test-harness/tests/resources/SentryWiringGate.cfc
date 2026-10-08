/** Pause real WireBox autowiring so concurrent lookup is deterministic. */
component {

	function init( required any started, required any release ){
		variables.started = arguments.started;
		variables.release = arguments.release;
		return this;
	}

	function beforeInstanceAutowire( required struct data ){
		if ( arguments.data.mapping.getName() == "sentryRegression" ) {
			variables.started.countDown();
			if (
				!variables.release.await(
					javacast( "long", 5 ),
					createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
				)
			) {
				throw( type = "Test.WiringTimeout", message = "Sentry wiring gate was not released." );
			}
		}
	}

}
