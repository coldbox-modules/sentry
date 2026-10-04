/** Opt-in structured logs. Does not capture a second error event or log extraInfo. */
component extends="coldbox.system.logging.AbstractAppender" {

	function init(
		required name,
		struct properties = {},
		layout            = "",
		numeric levelMin  = 0,
		numeric levelMax  = 3
	){
		super.init( argumentCollection = arguments );
		return this;
	}
	function logMessage( required any logEvent ){
		try {
			var category = arguments.logEvent.getCategory();
			var allow    = getProperty( "categories", [ "app." ] );
			var accepted = false;
			for ( var prefix in allow ) {
				if ( left( category, len( prefix ) ) == prefix ) {
					accepted = true;
				}
			}
			if ( !accepted || reFindNoCase( "sentry|qb|coldbox|bindings", category ) ) {
				return;
			}
			var service = propertyExists( "sentryService" ) ? getProperty( "sentryService" ) : application.wirebox.getInstance( "SentryService@sentry" );
			service.captureLog(
				getProperty( "messageMode", "sanitized" ) == "category" ? "Application diagnostic" : arguments.logEvent.getMessage(),
				lCase( this.logLevels.lookup( arguments.logEvent.getSeverity() ) ),
				{ category : category }
			);
		} catch ( any ignored ) {
		}
	}

}
