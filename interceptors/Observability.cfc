/** Optional ColdBox request lifecycle. */
component {

	property name="sentry" inject="SentryService@sentry";
	function onRequestCapture( event, interceptData ){
		try {
			var telemetry = variables.sentry.getObservability();
			var settings  = variables.sentry.getSettings();
			if ( !settings.enableRequestTracing ) {
				return;
			}
			if ( isCustomFunction( settings.requestFilter ) && !settings.requestFilter( arguments.event ) ) {
				return;
			}
			var headers = getHTTPRequestData( false ).headers;
			var trusted = isCustomFunction( settings.trustIncomingTrace ) ? settings.trustIncomingTrace(
				headers,
				arguments.event
			) : settings.trustIncomingTrace;
			var state = {
				previous : telemetry.getScope(),
				span     : telemetry.startTransaction(
					requestName( arguments.event ),
					"http.server",
					headers,
					trusted
				)
			};
			arguments.event.setPrivateValue( "_sentryRequest", state );
			telemetry.setScope( { span : state.span, requestState : state } );
		} catch ( any ignored ) {
		}
	}
	function preProcess( event, interceptData ){
		try {
			var state = arguments.event.getPrivateValue( "_sentryRequest", {} );
			if ( state.keyExists( "span" ) ) {
				state.span.rename( requestName( arguments.event ) );
				arguments.event.setPrivateValue( "sentryTraceHeaders", variables.sentry.getTraceHeaders() );
			}
		} catch ( any ignored ) {
		}
	}
	function postProcess( event, interceptData ){
		complete( arguments.event );
	}
	function onException( event, interceptData ){
		try {
			var state = arguments.event.getPrivateValue( "_sentryRequest", {} );
			if ( state.keyExists( "span" ) ) {
				state.span.setStatus( "internal_error" );
			}
		} catch ( any ignored ) {
		}
	}
	private function complete( required any event ){
		try {
			var state = arguments.event.getPrivateValue( "_sentryRequest", {} );
			if ( state.keyExists( "span" ) ) {
				state.span.rename( requestName( arguments.event ) );
				variables.sentry.endRequest();
			}
		} catch ( any ignored ) {
		}
	}
	private function requestName( required any event ){
		var route = arguments.event.getCurrentRoute();
		if ( !isSimpleValue( route ) || !len( route ) ) {
			route = arguments.event.getCurrentEvent();
		}
		return arguments.event.getHTTPMethod() & " " & route;
	}

}
