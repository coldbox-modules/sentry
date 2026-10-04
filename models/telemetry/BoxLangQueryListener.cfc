/** Runtime events are global; this listener accepts only its owning application's context. */
component {

	function init(
		required any telemetry,
		required string applicationName,
		string databaseSystem = "other"
	){
		variables.telemetry       = arguments.telemetry;
		variables.applicationName = arguments.applicationName;
		variables.databaseSystem  = arguments.databaseSystem;
		variables.pending         = createObject( "java", "java.util.concurrent.ConcurrentHashMap" ).init();
		return this;
	}
	private function owns( required struct data ){
		try {
			var applicationContext = arguments.data.context.getParentOfType(
				createObject( "java", "java.lang.Class" ).forName( "ortus.boxlang.runtime.context.ApplicationBoxContext" )
			);
			return !isNull( applicationContext ) && applicationContext
				.getApplication()
				.getName()
				.toString() == variables.applicationName;
		} catch ( any ignored ) {
			return false;
		}
	}
	function preQueryExecute( required struct data ){
		try {
			if ( !owns( arguments.data ) || variables.telemetry.getScope().keyExists( "manualQuerySpan" ) ) {
				return;
			}
			var span = variables.telemetry.startSpan(
				variables.telemetry.scrubSQL( arguments.data.sql ),
				( arguments.data.cached ?: false ) ? "db.query.cache" : (
					( arguments.data.dbtype ?: "" ) == "query" ? "db.query.qoq" : "db.query"
				),
				{
					"db.system"    : variables.databaseSystem,
					"db.operation" : uCase( listFirst( trim( arguments.data.sql ), " " ) ),
					"db.cached"    : arguments.data.cached ?: false
				}
			);
			variables.pending.put( arguments.data.pendingQuery, span );
		} catch ( any ignored ) {
		}
	}
	function postQueryExecute( required struct data ){
		complete( arguments.data, "ok" );
	}
	function onQueryExecuteError( required struct data ){
		complete( arguments.data, "internal_error" );
	}
	private function complete( required struct data, required string status ){
		try {
			var span = variables.pending.remove( arguments.data.pendingQuery );
			if ( !isNull( span ) ) {
				span.setAttribute( "db.cached", arguments.data.result.cached ?: false );
				if ( isNumeric( arguments.data.executionTime ?: "" ) ) {
					span.setAttribute( "db.execution.duration", arguments.data.executionTime );
				}
				span.finish( arguments.status );
			}
		} catch ( any ignored ) {
		}
	}

}
