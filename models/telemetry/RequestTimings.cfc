/** One instance per request/operation. Caller owns eligibility and response header publication. */
component {

	function init(
		required any telemetry,
		array names         = [],
		numeric maxSamples  = 64,
		boolean emitMetrics = false
	){
		variables.telemetry   = arguments.telemetry;
		variables.emitMetrics = arguments.emitMetrics;
		variables.names       = [];
		for ( var name in arguments.names ) {
			if (
				!isNull( name ) && isSimpleValue( name ) && variables.names.len() < 32 && len( name ) > 0 && len(
					name
				) <= 48 &&
				reFind( "^[a-zA-Z]", name ) && !reFind( "[^a-zA-Z0-9_]", name ) && !arrayFindNoCase(
					variables.names,
					name
				)
			) {
				variables.names.append( name );
			}
		}
		variables.maxSamples = max( 0, min( 64, arguments.maxSamples ) );
		variables.samples    = 0;
		variables.metrics    = {};
		variables.tokens     = createObject( "java", "java.util.concurrent.ConcurrentHashMap" ).init();
		variables.clock      = createObject( "java", "java.lang.System" );
		return this;
	}
	function begin( required string name ){
		if ( !variables.names.find( arguments.name ) || variables.samples >= variables.maxSamples ) {
			return {};
		}
		variables.samples++;
		var state = {
			"name"    : arguments.name,
			"started" : variables.clock.nanoTime()
		};
		try {
			state.span = variables.telemetry.startSpan( arguments.name, "app.phase" );
		} catch ( any unavailable ) {
		}
		var token = { "id" : createUUID() };
		variables.tokens.put( token.id, state );
		return token;
	}
	function finish( required struct token, string status = "ok" ){
		var state = {};
		try {
			if ( !arguments.token.keyExists( "id" ) || !isSimpleValue( arguments.token.id ) ) {
				return;
			}
			// Atomic removal claims a private handle once, without trusting caller metadata.
			state = variables.tokens.remove( toString( arguments.token.id ) );
			if ( isNull( state ) ) {
				return;
			}
		} catch ( any unavailable ) {
			return;
		}
		try {
			var name     = state.name;
			var metric   = variables.metrics[ name ] ?: { "duration" : 0, "count" : 0 };
			var duration = max( 0, ( variables.clock.nanoTime() - state.started ) / 1000000 );
			metric.duration += duration;
			metric.count++;
			variables.metrics[ name ] = metric;
		} catch ( any unavailable ) {
		}
		try {
			if ( variables.emitMetrics && !isNull( local.duration ) )
				variables.telemetry.distribution(
					"http.server.phase.duration",
					duration,
					{ "phase" : state.name },
					"millisecond"
				);
		} catch ( any unavailable ) {
		}
		finishSpan( state, arguments.status );
	}
	private function finishSpan( required struct state, required string status ){
		try {
			if ( arguments.state.keyExists( "span" ) ) {
				arguments.state.span.finish( arguments.status );
			}
		} catch ( any unavailable ) {
		}
	}
	function measure( required string name, required function callback ){
		var token  = begin( arguments.name );
		var status = "ok";
		try {
			return arguments.callback();
		} catch ( any failure ) {
			status = "internal_error";
			rethrow;
		} finally {
			finish( token, status );
		}
	}
	function snapshot(){
		return duplicate( variables.metrics );
	}
	function toServerTiming(){
		var headers = [];
		for ( var name in variables.names ) {
			if ( variables.metrics.keyExists( name ) ) {
				headers.append( name & ";dur=" & ( round( variables.metrics[ name ].duration * 100 ) / 100 ) );
			}
		}
		return arrayToList( headers, ", " );
	}

}
