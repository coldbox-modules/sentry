/** Optional ColdBox request lifecycle. */
component {

	property name="sentry" inject="SentryService@sentry";
	function onRequestCapture( event, interceptData ){
		try {
			var telemetry = variables.sentry.getObservability();
			var settings  = variables.sentry.getSettings();
			if (
				!settings.enableRequestTracing && !( settings.enableMetrics && settings.enableRequestSaturation ) && !settings.enableAutomaticRequestTimings
			) {
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
			if ( settings.enableAutomaticRequestTimings ) {
				state[ "timings" ]       = telemetry.newRequestTimings( true );
				state[ "handlerTokens" ] = [];
			}
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
		closeTimings( arguments.state, "internal_error" );
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
					closeTimings( state, "ok" );
					publishTimings( arguments.event, state );
					variables.sentry.endRequest();
				}
			}
		} catch ( any ignored ) {
		}
	}
	function preEvent( event, interceptData ){
		phase( arguments.event, "handler", true );
	}
	function postEvent( event, interceptData ){
		phase( arguments.event, "handler", false );
	}
	function preRender( event, interceptData ){
		phase( arguments.event, "render", true );
	}
	function postRender( event, interceptData ){
		phase( arguments.event, "render", false );
		try {
			publishTimings( arguments.event, arguments.event.getPrivateValue( "_sentryRequest", {} ) );
		} catch ( any ignored ) {
		}
	}
	private function phase(
		required any event,
		required string name,
		required boolean begin
	){
		try {
			var state = arguments.event.getPrivateValue( "_sentryRequest", {} );
			if ( !state.keyExists( "timings" ) ) return;
			if ( arguments.name == "handler" ) {
				if ( arguments.begin ) state.handlerTokens.append( state.timings.begin( "handler" ) );
				else if ( state.handlerTokens.len() ) {
					state.timings.finish( state.handlerTokens[ state.handlerTokens.len() ] );
					state.handlerTokens.deleteAt( state.handlerTokens.len() );
				}
			} else {
				if ( arguments.begin && !state.keyExists( "renderToken" ) )
					state[ "renderToken" ] = state.timings.begin( "render" );
				else if ( !arguments.begin && state.keyExists( "renderToken" ) ) {
					state.timings.finish( state.renderToken );
					state.delete( "renderToken" );
				}
			}
		} catch ( any ignored ) {
		}
	}
	private function closeTimings( required struct state, required string status ){
		variables.sentry.getObservability().finishRequestTimings( arguments.state, arguments.status );
	}

	private function publishTimings( required any event, required struct state ){
		try {
			var settings = variables.sentry.getSettings();
			if ( !settings.publishServerTiming || !arguments.state.keyExists( "timings" ) ) return;
			if ( isCustomFunction( settings.serverTimingFilter ) ) {
				if ( !settings.serverTimingFilter( arguments.event ) ) return;
			} else if ( !isSimpleValue( settings.serverTimingFilter ) || len( trim( settings.serverTimingFilter ) ) )
				return;
			var header = arguments.state.timings.toServerTiming();
			if ( len( header ) ) arguments.event.setHTTPHeader( name = "Server-Timing", value = header );
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
