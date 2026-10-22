/** Explicit provider snapshots. Missing/invalid measurements stay absent; poll failures never become zeros. */
component {

	function init(
		required any telemetry,
		required array names,
		required struct fields,
		required string label
	){
		variables.telemetry   = arguments.telemetry;
		variables.names       = new MetricLabels( arguments.names );
		variables.fields      = arguments.fields;
		variables.label       = arguments.label;
		variables.diagnostics = {};
		variables.id          = createUUID();
		return this;
	}
	function capture( required string name, required function sample ){
		if ( !variables.names.contains( arguments.name ) ) return false;
		var key = hash( arguments.name, "SHA-256" );
		var now = createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000;
		try {
			var raw = arguments.sample();
			now     = createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000;
			if ( !isStruct( raw ) ) throw( type = "Sentry.InvalidHealthSnapshot" );
			var values = {};
			for ( var field in variables.fields ) {
				if (
					raw.keyExists( field ) && !isNull( raw[ field ] ) && isNumeric( raw[ field ] ) && raw[ field ] >= 0 && raw[
						field
					] <= 1.7976931348623157E308
				) {
					if ( field == "lastHeartbeatAt" ) {
						if ( raw[ field ] > 0 && raw[ field ] <= now ) values[ field ] = now - raw[ field ];
					} else {
						values[ field ] = raw[ field ];
					}
				}
			}
			if ( !structCount( values ) ) throw( type = "Sentry.EmptyHealthSnapshot" );
			var attrs                = {};
			attrs[ variables.label ] = arguments.name;
			for ( var field in values ) {
				var metric = variables.fields[ field ];
				variables.telemetry.gauge(
					metric.name,
					values[ field ],
					attrs,
					metric.unit
				);
			}
			record( key, true, now );
			return true;
		} catch ( any unavailable ) {
			record( key, false, now );
			return false;
		}
	}
	private function record(
		required string key,
		required boolean success,
		required numeric now
	){
		lock name="sentry-health-#variables.id#" type="exclusive" timeout="2" {
			var state = variables.diagnostics[ arguments.key ] ?: {
				"lastSuccessAt" : 0,
				"lastFailureAt" : 0,
				"failures"      : 0
			};
			if ( arguments.success ) {
				state.lastSuccessAt = arguments.now;
			} else {
				state.lastFailureAt = arguments.now;
				state.failures++;
			}
			variables.diagnostics[ arguments.key ] = state;
		}
	}
	function diagnostics( required string name ){
		if ( !variables.names.contains( arguments.name ) ) return {};
		lock name="sentry-health-#variables.id#" type="exclusive" timeout="2" {
			return duplicate(
				variables.diagnostics[ hash( arguments.name, "SHA-256" ) ] ?: {
					"lastSuccessAt" : 0,
					"lastFailureAt" : 0,
					"failures"      : 0
				}
			);
		}
	}

}
