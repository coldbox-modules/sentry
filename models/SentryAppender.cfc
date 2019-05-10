/**
*********************************************************************************
* Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
* www.ortussolutions.com
* ---
* Appender for Sentry leveraging the Sentry service
*/
component extends="coldbox.system.logging.AbstractAppender" accessors=true{
	
	/**
	* Constructor
	*/
	function init( 
		required name,
		struct properties=structnew(),
		layout="",
		numeric levelMin=0,
		numeric levelMax=4
	){
		super.init( argumentCollection=arguments );
		
		// Get sentry Service, wirebox must be in application scope.
		variables.sentryService = application.wirebox.getInstance( "SentryService@sentry" );
		
		return this;
	}

	/**
	 * Log a message
	 */
	public void function logMessage( required coldbox.system.logging.LogEvent logEvent ){
		var extraInfo = arguments.logEvent.getExtraInfo();

		// Is this an exception or not?
		if( isStruct( extraInfo ) && structKeyExists( extraInfo, "StackTrace" ) ){
			
			variables.sentryService.captureMessage(
				message	= arguments.logEvent.getMessage(),
				level 	= this.logLevels.lookup( arguments.logEvent.getSeverity() ),
				logger = arguments.logEvent.getcategory() 
			);
				
		} else {
			
			variables.sentryService.captureException(
				exception = extraInfo,
				level 	= this.logLevels.lookup( arguments.logEvent.getSeverity() ),
				message = arguments.logEvent.getMessage(),
				logger = arguments.logEvent.getcategory()
			);
				
		}
	}

}