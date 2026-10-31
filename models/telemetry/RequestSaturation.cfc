/** Process-local observed requests; bounded storage and monotonic ages. */
component {

	function init(
		required any telemetry,
		numeric capacity           = 4096,
		numeric longRunningSeconds = 30
	){
		variables.telemetry = arguments.telemetry;
		variables.capacity  = max( 1, min( 4096, int( arguments.capacity ) ) );
		variables.threshold = max( 0, arguments.longRunningSeconds );
		variables.clock     = createObject( "java", "java.lang.System" );
		variables.active    = {};
		variables.untracked = 0;
		variables.timeouts  = 0;
		variables.id        = createUUID();
		return this;
	}
	function begin(){
		var token= {};
		lock name="sentry-requests-#variables.id#" type="exclusive" timeout="2" {
			if ( structCount( variables.active ) >= variables.capacity ) {
				variables.untracked++;
				return token;
			}
			token                                           = { "id" : createUUID() };
			variables.active[ hash( token.id, "SHA-256" ) ] = variables.clock.nanoTime();
		}
		return token;
	}
	function finish( required struct token, boolean timedOut = false ){
		if ( !arguments.token.keyExists( "id" ) || !isSimpleValue( arguments.token.id ) ) return false;
		var key  = hash( arguments.token.id, "SHA-256" );
		lock name="sentry-requests-#variables.id#" type="exclusive" timeout="2" {
			if ( !variables.active.keyExists( key ) ) return false;
			variables.active.delete( key );
			if ( arguments.timedOut ) variables.timeouts++;
		}
		if ( arguments.timedOut ) {
			try {
				variables.telemetry.counter( "http.server.timeouts", 1 );
			} catch ( any unavailable ) {
			}
		}
		return true;
	}
	function snapshot(){
		lock name="sentry-requests-#variables.id#" type="exclusive" timeout="2" {
			var result = {
				"active"          : structCount( variables.active ),
				"oldestSeconds"   : 0,
				"longRunning"     : 0,
				"timeouts"        : variables.timeouts,
				"untrackedStarts" : variables.untracked
			};
			var now = variables.clock.nanoTime();
			for ( var key in variables.active ) {
				var age              = max( 0, ( now - variables.active[ key ] ) / 1000000000 );
				result.oldestSeconds = max( result.oldestSeconds, age );
				if ( age >= variables.threshold ) result.longRunning++;
			}
			return result;
		}
	}
	function capture(){
		var result = snapshot();
		variables.telemetry.gauge( "http.server.active_requests", result.active );
		variables.telemetry.gauge(
			"http.server.oldest_active",
			result.oldestSeconds,
			{},
			"second"
		);
		variables.telemetry.gauge( "http.server.long_running", result.longRunning );
		variables.telemetry.gauge( "http.server.untracked_starts.total", result.untrackedStarts );
		return result;
	}

}
