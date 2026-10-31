/** Opt-in named workflow/provider observations; callback values and exception text never enter telemetry. */
component {

	function init( required any telemetry ){
		variables.telemetry = arguments.telemetry;
		return this;
	}
	function run(
		required string name,
		required function callback,
		string provider = "",
		any classify    = ""
	){
		var started = createObject( "java", "java.lang.System" ).nanoTime();
		var state   = {};
		var outcome = "success";
		try {
			state.previous = variables.telemetry.getScope();
			state.span     = variables.telemetry.startSpan(
				arguments.name,
				"app.workflow",
				{
					"workflow.name" : arguments.name,
					"provider.name" : arguments.provider
				}
			);
			var next       = structCopy( state.previous );
			next[ "span" ] = state.span;
			variables.telemetry.setScope( next );
		} catch ( any unavailable ) {
		}
		try {
			var result = arguments.callback();
			if ( isCustomFunction( arguments.classify ) ) {
				outcome = "unknown";
				try {
					var classified = arguments.classify( isNull( local.result ) ? javacast( "null", "" ) : result );
					if (
						isSimpleValue( classified ) && listFind(
							"success,accepted,delivered,retry,timeout,cancelled,failed,unknown",
							classified
						)
					) {
						outcome = classified;
					}
				} catch ( any unavailable ) {
				}
			}
			return isNull( local.result ) ? javacast( "null", "" ) : result;
		} catch ( any failure ) {
			outcome = "failed";
			rethrow;
		} finally {
			complete(
				arguments.name,
				arguments.provider,
				outcome,
				started,
				state
			);
		}
	}
	private function complete(
		required string name,
		required string provider,
		required string outcome,
		required numeric started,
		required struct state
	){
		try {
			if ( arguments.state.keyExists( "previous" ) ) {
				variables.telemetry.setScope( arguments.state.previous );
			}
		} catch ( any unavailable ) {
		}
		try {
			if ( arguments.state.keyExists( "span" ) ) {
				arguments.state.span.setAttribute( "workflow.outcome", arguments.outcome );
			}
		} catch ( any unavailable ) {
		}
		try {
			if ( arguments.state.keyExists( "span" ) ) {
				arguments.state.span.finish(
					arguments.outcome == "failed" ? "internal_error" : (
						arguments.outcome == "timeout" ? "deadline_exceeded" : "ok"
					)
				);
			}
		} catch ( any unavailable ) {
		}
		try {
			var attrs = {
				"workflow.name" : arguments.name,
				"provider.name" : arguments.provider,
				"outcome"       : arguments.outcome
			};
			variables.telemetry.counter( "workflow.operations", 1, attrs );
			variables.telemetry.distribution(
				"workflow.duration",
				max( 0, ( createObject( "java", "java.lang.System" ).nanoTime() - arguments.started ) / 1000000 ),
				attrs,
				"millisecond"
			);
		} catch ( any unavailable ) {
		}
	}

}
