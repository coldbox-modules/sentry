/**
*********************************************************************************
* Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
* www.ortussolutions.com
* ---
* Module Config.
*/
component {

	// Module Properties
	this.title 				= "sentry";
	this.author 			= "Ortus Solutions";
	this.webURL 			= "https://www.ortussolutions.com";
	this.description 		= "A module to log and send bug reports to Sentry";
	this.version 			= "@build.version@+@build.number@";
	// If true, looks for views in the parent first, if not found, then in the module. Else vice-versa
	this.viewParentLookup 	= true;
	// If true, looks for layouts in the parent first, if not found, then in module. Else vice-versa
	this.layoutParentLookup = true;

	// STATIC SCRUB FIELDS
	variables.SCRUB_FIELDS 	= [ "passwd", "password", "password_confirmation", "secret", "confirm_password", "secret_token", "APIToken", "x-api-token" ];
	variables.SCRUB_HEADERS 	= [ "x-api-token", "Authorization" ];

	/**
	* Configure
	*/
	function configure(){
		settings = {
			// Sentry token
			"ServerSideToken" = "",
		    // Enable the Sentry LogBox Appender Bridge
		    "enableLogBoxAppender" = true,
		    // Min/Max levels for appender
		    "levelMin" = "FATAL",
		    "levelMax" = "ERROR",
		    // Enable/disable error logging
		    "enableExceptionLogging" = true,
		    // Data sanitization, scrub fields and headers, replaced with * at runtime
		    "scrubFields" 	= [],
		    "scrubHeaders" 	= [] 
		};

	}

	/**
	 * Fired when the module is registered and activated.
	 */
	function onLoad(){
		// Incorporate defaults into settings
		settings.scrubFields.addAll( SCRUB_FIELDS );
		settings.scrubHeaders.addAll( SCRUB_HEADERS );
		
		// Load the LogBox Appenders
		if( settings.enableLogBoxAppender ){
			loadAppenders();
		}
	}

	/**
	 * Fired when the module is unregistered and unloaded
	 */
	function onUnload(){

	}

	/**
	 * Trap exceptions and send them to Sentry
	 */
	function onException( event, interceptData, buffer ){
		if( !settings.enableExceptionLogging ){
			return;
		}
		var sentryService = wirebox.getInstance( "SentryService@sentry" );
		// create log body
		var logBody = sentryService.exceptionToLogBody( interceptData.exception );
		sentryService.sendToSentry(
			logBody = logBody,
			level 	= "error"
		);
	}

	//**************************************** PRIVATE ************************************************//	

	/**
	 * Load LogBox Appenders
	 */
	private function loadAppenders(){
		// Get config
		var logBoxConfig 	= controller.getLogBox().getConfig();
		var rootConfig 		= "";

		// Register tracer appender
		rootConfig = logBoxConfig.getRoot();
		logBoxConfig.appender( 
			name 		= "sentry_appender", 
			class 		= "#moduleMapping#.models.SentryAppender",
			levelMin 	= settings.levelMin,
			levelMax 	= settings.levelMax
		);
		logBoxConfig.root( 
			levelMin = rootConfig.levelMin,
			levelMax = rootConfig.levelMax,
			appenders= listAppend( rootConfig.appenders, "sentry_appender") 
		);

		// Store back config
		controller.getLogBox().configure( logBoxConfig );
	}

}
