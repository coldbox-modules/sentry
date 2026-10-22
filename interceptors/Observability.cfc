/** Optional ColdBox request lifecycle. */
component {

	property name="sentry" inject="SentryService@sentry";
	function onRequestCapture( event, interceptData ){
		try {
			var telemetry = variables.sentry.getObservability();
			var settings  = variables.sentry.getSettings();
			if ( !settings.enableRequestTracing && !( settings.enableMetrics && settings.enableRequestSaturation ) ) {
				return;
			}
			if ( isCustomFunction( settings.requestFilter ) && !settings.requestFilter( arguments.event ) ) {
				return;
			}

			if ( arguments.event.getPrivateValue( "_sentryRequest", {} ).keyExists( "previous" ) ) return;
			var state = { "previous" : telemetry.getScope() };
			if ( settings.enableRequestTracing ) {
				var headers = getHTTPRequestData( false ).headers;
				var trusted = isCustomFunction( settings.trustIncomingTrace ) ? settings.trustIncomingTrace(
					headers,
					arguments.event
				) : settings.trustIncomingTrace;
				state[ "span" ] = telemetry.startTransaction(
					requestName( arguments.event ),
					"http.server",
					headers,
					trusted
				);
			}
			state[ "saturationToken" ] = telemetry.beginRequestObservation();
			arguments.event.setPrivateValue( "_sentryRequest", state );
			var next               = structCopy( state.previous );
			next[ "requestState" ] = state;
			if ( state.keyExists( "span" ) ) next[ "span" ] = state.span;
			telemetry.setScope( next );
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
		var state = {};
		try {
			state = arguments.event.getPrivateValue( "_sentryRequest", {} );
			if ( state.keyExists( "span" ) ) state.span.setStatus( "internal_error" );
		} catch ( any ignored ) {
		} finally {
			try {
				finishExceptionObservation( state );
			} catch ( any ignored ) {
			}
		}
	}

	function finishExceptionObservation( required struct state ){
		if ( arguments.state.keyExists( "saturationToken" ) )
			variables.sentry.finishRequestObservation( arguments.state.saturationToken );
		// Keep an existing trace available to the module's exception capture. Application onRequestEnd closes it.
		if ( !arguments.state.keyExists( "span" ) ) variables.sentry.endRequest( statusCode = 500 );
	}

	private function complete( required any event ){
		try {
			var state = arguments.event.getPrivateValue( "_sentryRequest", {} );
			if ( state.keyExists( "previous" ) ) {
				try {
					if ( state.keyExists( "span" ) ) state.span.rename( requestName( arguments.event ) );
				} finally {
					variables.sentry.endRequest();
				}
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
