/** One logical dependency call; retries and breaker policy remain in the callback. */
component {

	function init( required any telemetry ){
		variables.telemetry = arguments.telemetry;
		variables.clock     = createObject( "java", "java.lang.System" );
		return this;
	}
	function run(
		required string name,
		required function callback,
		any classify = ""
	){
		var started = 0;
		var ended   = 0;
		var state   = {};
		var details = { "outcome" : "success" };
		try {
			state.previous = variables.telemetry.getScope();
			state.span     = variables.telemetry.startSpan(
				arguments.name,
				"app.dependency",
				{ "dependency.name" : arguments.name }
			);
			var next       = structCopy( state.previous );
			next[ "span" ] = state.span;
			variables.telemetry.setScope( next );
		} catch ( any unavailable ) {
		}
		started = variables.clock.nanoTime();
		try {
			var result = arguments.callback();
			ended      = variables.clock.nanoTime();
			details    = classifyResult(
				arguments.classify,
				isNull( local.result ) ? javacast( "null", "" ) : result,
				javacast( "null", "" ),
				false
			);
			return isNull( local.result ) ? javacast( "null", "" ) : result;
		} catch ( any failure ) {
			ended   = variables.clock.nanoTime();
			details = classifyResult(
				arguments.classify,
				javacast( "null", "" ),
				failure,
				true
			);
			rethrow;
		} finally {
			var duration = max( 0, ( ended - started ) / 1000000 );
			complete( arguments.name, details, duration, state );
		}
	}
	private function classifyResult(
		required any classifier,
		any result,
		any failure,
		boolean failed = false
	){
		var details = { "outcome" : arguments.failed ? "error" : "success" };
		if ( !isCustomFunction( arguments.classifier ) ) return details;
		details.outcome = "unknown";
		try {
			var raw = arguments.classifier(
				isNull( arguments.result ) ? javacast( "null", "" ) : arguments.result,
				isNull( arguments.failure ) ? javacast( "null", "" ) : arguments.failure
			);
			if ( !isStruct( raw ) ) return details;
			if (
				raw.keyExists( "outcome" ) && isSimpleValue( raw.outcome ) && listFind(
					"success,error,timeout,connection_error,cancelled,rejected,unknown",
					raw.outcome
				)
			)
				details.outcome = raw.outcome;
			// A thrown callback cannot be classified as successful.
			if ( arguments.failed && details.outcome == "success" ) details.outcome = "error";
			if (
				raw.keyExists( "statusCode" ) && isNumeric( raw.statusCode ) && raw.statusCode >= 100 && raw.statusCode < 600 && raw.statusCode == int(
					raw.statusCode
				)
			)
				details[ "http.status_class" ] = int( raw.statusCode / 100 ) & "xx";
			if (
				raw.keyExists( "retryCount" ) && isNumeric( raw.retryCount ) && raw.retryCount >= 0 && raw.retryCount <= 2147483647 && int(
					raw.retryCount
				) == raw.retryCount
			)
				details[ "retries" ] = raw.retryCount;
			if (
				raw.keyExists( "circuitState" ) && isSimpleValue( raw.circuitState ) && listFind(
					"open,closed,half_open",
					raw.circuitState
				)
			)
				details[ "circuit.state" ] = raw.circuitState;
		} catch ( any unavailable ) {
		}
		return details;
	}
	private function complete(
		required string name,
		required struct details,
		required numeric duration,
		required struct state
	){
		try {
			if ( arguments.state.keyExists( "previous" ) ) variables.telemetry.setScope( arguments.state.previous );
		} catch ( any unavailable ) {
		}
		try {
			if ( arguments.state.keyExists( "span" ) ) {
				arguments.state.span.setAttribute( "dependency.outcome", arguments.details.outcome );
			}
		} catch ( any unavailable ) {
		}
		try {
			if ( arguments.state.keyExists( "span" ) ) {
				arguments.state.span.finish(
					arguments.details.outcome == "timeout" ? "deadline_exceeded" : (
						arguments.details.outcome == "success" ? "ok" : "internal_error"
					)
				);
			}
		} catch ( any unavailable ) {
		}
		var attrs = {
			"dependency.name" : arguments.name,
			"outcome"         : arguments.details.outcome
		};
		for ( var field in [ "http.status_class", "circuit.state" ] ) {
			if ( arguments.details.keyExists( field ) ) attrs[ field ] = arguments.details[ field ];
		}
		try {
			variables.telemetry.counter( "dependency.calls", 1, attrs );
		} catch ( any unavailable ) {
		}
		try {
			variables.telemetry.distribution(
				"dependency.duration",
				arguments.duration,
				attrs,
				"millisecond"
			);
		} catch ( any unavailable ) {
		}
		try {
			if ( arguments.details.keyExists( "retries" ) )
				variables.telemetry.distribution(
					"dependency.retries",
					arguments.details.retries,
					attrs
				);
		} catch ( any unavailable ) {
		}
	}

}
