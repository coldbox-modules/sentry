/** Install on Lucee 6+ as this.query.listener. Wraps an existing listener without changing its return contract. */
component {

	function init(
		required any telemetry,
		any listener,
		string databaseSystem = "other"
	){
		variables.telemetry      = arguments.telemetry;
		variables.listener       = arguments.listener ?: {};
		variables.databaseSystem = arguments.databaseSystem;
		variables.executions     = createObject( "java", "java.lang.ThreadLocal" ).init();
		return this;
	}
	function before( caller, args ){
		var result = delegate( "before", arguments ) ?: {};
		try {
			// Lucee applies the returned args after this callback; observe that transformed SQL.
			var sql   = result.args.sql ?: result.sql ?: arguments.args.sql ?: "";
			var stack = variables.executions.get() ?: [];
			if ( variables.telemetry.getScope().keyExists( "manualQuerySpan" ) ) {
				stack.append( { "manual" : true } );
				variables.executions.set( stack );
				return result;
			}
			var span = variables.telemetry.startSpan(
				variables.telemetry.scrubSQL( sql ),
				"db.query",
				{
					"db.system"    : variables.databaseSystem,
					"db.operation" : uCase( listFirst( trim( sql ), " " ) )
				}
			);
			stack.append( span );
			variables.executions.set( stack );
		} catch ( any ignored ) {
		}
		return result;
	}
	function after( caller, args, result, meta ){
		complete(
			"ok",
			arguments.meta ?: {},
			arguments.args ?: {},
			arguments.result ?: javacast( "null", "" )
		);
		return delegate( "after", arguments );
	}
	function error( args, caller, meta, exception ){
		complete( "internal_error" );
		if ( structKeyExists( variables.listener, "error" ) ) {
			return delegate( "error", arguments );
		}
		// Lucee treats an installed error callback as handling the failure.
		throw( object = arguments.exception );
	}
	private function complete(
		required string status,
		struct meta = {},
		struct args = {},
		any queryResult
	){
		try {
			var stack = variables.executions.get() ?: [];
			if ( stack.len() ) {
				var span = stack[ stack.len() ];
				stack.deleteAt( stack.len() );
				if ( structKeyExists( span, "manual" ) ) {
					if ( !stack.len() ) {
						variables.executions.remove();
					}
					return;
				}
				var cached = arguments.meta.cached ?: "unknown";
				if ( !arguments.meta.keyExists( "cached" ) && !isNull( arguments.queryResult ) ) {
					try {
						cached = arguments.queryResult.isCached();
					} catch ( any unavailable ) {
					}
				}
				if ( isBoolean( cached ) ) {
					span.setAttribute( "db.cached", cached );
				} else {
					span.setAttribute( "db.cache_status", "unknown" );
				}
				span.setAttribute( "db.query_of_queries", ( arguments.args.dbtype ?: "" ) == "query" );
				if ( isNumeric( arguments.meta.executionTime ?: "" ) ) {
					span.setAttribute( "db.execution.duration", arguments.meta.executionTime );
				}
				span.finish( arguments.status );
			}
			if ( !stack.len() ) {
				variables.executions.remove();
			}
		} catch ( any ignored ) {
		}
	}
	private function delegate( required string method, required struct args ){
		if ( structKeyExists( variables.listener, arguments.method ) ) {
			return invoke(
				variables.listener,
				arguments.method,
				arguments.args
			);
		}
		return javacast( "null", "" );
	}

}
