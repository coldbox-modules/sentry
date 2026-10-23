component extends="cbq.models.Jobs.AbstractJob" {

	function handle(){
		var state = getInstance( "QueueHealthState" ).get( getProperties().runId );
		state.handled.incrementAndGet();
		state.started.countDown();
		if ( getProperties().mode == "block" ) {
			if (
				!state.release.await(
					javacast( "long", 20 ),
					createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
				)
			)
				throw( type = "QueueHealthFixtureTimeout" );
		}
		if ( getProperties().mode == "fail" || ( getProperties().mode == "retry" && getCurrentAttempt() == 1 ) )
			throw( type = "QueueHealthSyntheticFailure" );
		return true;
	}

}
