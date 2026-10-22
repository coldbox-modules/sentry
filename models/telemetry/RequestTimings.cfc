/** One instance per request/operation. Caller owns eligibility and response header publication. */
component {

	function init(
		required any telemetry,
		array names        = [],
		numeric maxSamples = 64
	){
		variables.telemetry = arguments.telemetry;
		variables.names     = [];
		for ( var name in arguments.names ) {
			if (
				variables.names.len() < 32 && reFind( "^[a-zA-Z][a-zA-Z0-9_]{0,47}$", name ) && !variables.names.find(
					name
				)
			) {
				variables.names.append( name );
			}
		}
		variables.maxSamples = max( 0, min( 64, arguments.maxSamples ) );
		variables.samples    = 0;
		variables.metrics    = {};
		variables.clock      = createObject( "java", "java.lang.System" );
		return this;
	}
	function begin( required string name ){
		if ( !variables.names.find( arguments.name ) || variables.samples >= variables.maxSamples ) {
			return {};
		}
		variables.samples++;
		var token = {
			"name"    : arguments.name,
			"started" : variables.clock.nanoTime(),
			"done"    : createObject( "java", "java.util.concurrent.atomic.AtomicBoolean" ).init( false )
		};
		try {
			token.span = variables.telemetry.startSpan( arguments.name, "app.phase" );
		} catch ( any unavailable ) {
		}
		return token;
	}
	function finish( required struct token, string status = "ok" ){
		if ( !arguments.token.keyExists( "done" ) || !arguments.token.done.compareAndSet( false, true ) ) {
			return;
		}
		try {
			var name   = arguments.token.name;
			var metric = variables.metrics[ name ] ?: { "duration" : 0, "count" : 0 };
			metric.duration += max( 0, ( variables.clock.nanoTime() - arguments.token.started ) / 1000000 );
			metric.count++;
			variables.metrics[ name ] = metric;
			if ( arguments.token.keyExists( "span" ) ) {
				arguments.token.span.finish( arguments.status );
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
