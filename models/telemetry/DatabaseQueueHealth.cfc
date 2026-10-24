/** Optional cbq database-provider health snapshot using the provider's epoch-second availability/lease fields. */
component {

	function init( required function queryFactory, string table = "cbq_jobs" ){
		variables.queryFactory = arguments.queryFactory;
		variables.table        = arguments.table;
		return this;
	}
	function snapshot( required string queue ){
		var builder   = variables.queryFactory();
		var grammar   = builder.getGrammar();
		var available = grammar.wrapValue( "availableDate" );
		var reserved  = grammar.wrapValue( "reservedDate" );
		var owner     = grammar.wrapValue( "reservedBy" );
		var created   = grammar.wrapValue( "createdDate" );
		var unclaimed = reserved & " IS NULL AND " & owner & " IS NULL";
		var claimed   = "(" & reserved & " IS NOT NULL OR " & owner & " IS NOT NULL)";
		var now       = int( createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000 );
		var rows      = builder
			.from( variables.table )
			.where( "queue", arguments.queue )
			.whereNull( "completedDate" )
			.whereNull( "failedDate" )
			.selectRaw(
				"COALESCE(SUM(CASE WHEN " & unclaimed & " AND " & available & " <= ? THEN 1 ELSE 0 END),0) AS runnable",
				[ now ]
			)
			.selectRaw(
				"COALESCE(SUM(CASE WHEN " & unclaimed & " AND " & available & " > ? THEN 1 ELSE 0 END),0) AS delayed",
				[ now ]
			)
			.selectRaw( "COALESCE(SUM(CASE WHEN " & claimed & " THEN 1 ELSE 0 END),0) AS reserved" )
			.selectRaw(
				"COALESCE(SUM(CASE WHEN " & claimed & " AND " & available & " <= ? THEN 1 ELSE 0 END),0) AS staleReservations",
				[ now ]
			)
			.selectRaw( "MIN(CASE WHEN " & unclaimed & " THEN " & created & " ELSE NULL END) AS oldestCreatedAt" )
			.get();
		if ( !isArray( rows ) || rows.len() != 1 ) throw( type = "Sentry.InvalidQueueHealthResult" );
		var snapshot                   = rows[ 1 ];
		snapshot[ "depth" ]            = snapshot.runnable + snapshot.delayed;
		snapshot[ "oldestAgeSeconds" ] = snapshot.depth > 0 && snapshot.keyExists( "oldestCreatedAt" ) && !isNull(
			snapshot.oldestCreatedAt
		) && isNumeric( snapshot.oldestCreatedAt ) ? max( 0, now - snapshot.oldestCreatedAt ) : 0;
		snapshot.delete( "oldestCreatedAt" );
		return snapshot;
	}

}
