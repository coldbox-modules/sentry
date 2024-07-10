/**
 *********************************************************************************
 * Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
 * www.ortussolutions.com
 * ---
 * Appender for Sentry leveraging the Sentry service
 */
component extends="coldbox.system.logging.AbstractAppender" accessors=true {

	/**
	 * Constructor
	 */
	function init(
		required name,
		struct properties = structNew(),
		layout            = "",
		numeric levelMin  = 0,
		numeric levelMax  = 4
	){
		super.init( argumentCollection = arguments );

		// Get sentry Service from WireBox if it's not already passed to the appender
		if ( !propertyExists( "sentryService" ) ) {
			// wirebox must be in application scope.
			setProperty( "sentryService", application.wirebox.getInstance( "SentryService@sentry" ) );
		}

		return this;
	}

	/**
	 * Log a message
	 */
	public void function logMessage( required logEvent ){
		var extraInfo = arguments.logEvent.getExtraInfo();
		var level     = this.logLevels.lookup( arguments.logEvent.getSeverity() );
		var message   = arguments.logEvent.getMessage();
		var loggerCat = arguments.logEvent.getcategory();

		if ( level == "warn" ) {
			level = "warning";
		}

		// Is this an exception or not?
		if (
			( isStruct( extraInfo ) || isObject( extraInfo ) )
			&& extraInfo.keyExists( "StackTrace" ) && extraInfo.keyExists( "message" ) && extraInfo.keyExists( "detail" )
		) {
			getProperty( "sentryService" ).captureException(
				exception = extraInfo,
				level     = level,
				message   = message,
				logger    = loggerCat
			);
		} else if (
			( isStruct( extraInfo ) || isObject( extraInfo ) )
			&& extraInfo.keyExists( "exception" ) && isStruct( extraInfo.exception ) && extraInfo.exception.keyExists( "StackTrace" )
		) {
			var trimmedExtra = structCopy( extraInfo );
			trimmedExtra.delete( "exception" );

			getProperty( "sentryService" ).captureException(
				exception      = extraInfo.exception,
				level          = level,
				message        = message,
				logger         = loggerCat,
				additionalData = trimmedExtra
			);
		} else {
			getProperty( "sentryService" ).captureMessage(
				message        = message,
				level          = level,
				logger         = loggerCat,
				additionalData = extraInfo
			);
		}
	}

}
