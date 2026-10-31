/** Compatibility facade. The cbq package owns its database schema and snapshot implementation. */
component {

	function init( required function queryFactory, string table = "cbq_jobs" ){
		variables.adapter = createObject( "component", "cbq.models.Telemetry.DatabaseQueueSnapshot" ).init(
			queryFactory = arguments.queryFactory,
			table        = arguments.table
		);
		return this;
	}
	function snapshot( required any queue ){
		return variables.adapter.snapshot( arguments.queue );
	}

}
