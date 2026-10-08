/** qb fallback; one adapter produces each execution's span. */
component {

	property name="sentry" inject="SentryService@sentry";
	function preQBExecute( event, interceptData ){
		try {
			if ( arguments.interceptData.pretend ?: false ) {
				return;
			}
			var telemetry = variables.sentry.getObservability();
			if ( variables.sentry.getSettings().queryAdapter != "qb" ) {
				return;
			}
			var current = telemetry.getScope();
			if ( current.keyExists( "manualQuerySpan" ) ) {
				return;
			}
			var span = telemetry.startSpan(
				telemetry.scrubSQL( arguments.interceptData.sql ),
				"db.query",
				{ "db.system" : variables.sentry.getSettings().databaseSystem ?: "other" }
			);
			arguments.interceptData[ "_sentryExecution" ] = { span : span, previous : current };
			var next                                      = structCopy( current );
			next.span                                     = span;
			telemetry.setScope( next );
		} catch ( any ignored ) {
		}
	}
	function postQBExecute( event, interceptData ){
		complete( arguments.interceptData );
	}
	function onQBExecuteException( event, interceptData ){
		complete( arguments.interceptData, "internal_error" );
	}
	private function complete( required struct data, string status = "ok" ){
		try {
			var execution = arguments.data[ "_sentryExecution" ] ?: {};
			if ( execution.keyExists( "span" ) ) {
				execution.span.finish( arguments.status );
				variables.sentry.getObservability().setScope( execution.previous );
			}
		} catch ( any ignored ) {
		}
	}

}
