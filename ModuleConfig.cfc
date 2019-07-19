/**
*********************************************************************************
* Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
* www.ortussolutions.com
* ---
* Module Config.
*/
component {

	// Module Properties
	this.title 				= 'sentry';
	this.author 			= 'Ortus Solutions';
	this.webURL 			= 'https://www.ortussolutions.com';
	this.description 		= 'A module to log and send bug reports to Sentry';
	this.version 			= '@build.version@+@build.number@';
	// If true, looks for views in the parent first, if not found, then in the module. Else vice-versa
	this.viewParentLookup 	= true;
	// If true, looks for layouts in the parent first, if not found, then in module. Else vice-versa
	this.layoutParentLookup = true;
	this.dependencies = [ 'funclinenums' ];

	// STATIC SCRUB FIELDS
	variables.SCRUB_FIELDS 	= [ 'passwd', 'password', 'password_confirmation', 'secret', 'confirm_password', 'secret_token', 'APIToken', 'x-api-token', 'fwreinit' ];
	variables.SCRUB_HEADERS 	= [ 'x-api-token', 'Authorization' ];

	/**
	* Configure
	*/
	function configure(){
		settings = {
			// Sentry token
			'ServerSideToken' = '',
		    // Enable the Sentry LogBox Appender Bridge
		    'enableLogBoxAppender' = true,
		    'async' = true,
		    // Min/Max levels for appender
		    'levelMin' = 'FATAL',
		    'levelMax' = 'ERROR',
		    // Enable/disable error logging
		    'enableExceptionLogging' = true,
		    // Data sanitization, scrub fields and headers, replaced with "[Filtered]" at runtime
		    'scrubFields' 	= [],
		    'scrubHeaders' 	= [],
		    'release' = '',
			'environment' = controller.getSetting( 'environment' ),
			'DSN' = '',
			'publicKey' = '',
			'privateKey' = '',
			'projectID' = 0,
			'sentryUrl' = 'https://sentry.io',
			'serverName' = cgi.server_name,
			'appRoot' = expandPath('/'),
			'sentryVersion' = 7,
			// This is not arbityrary but must be a specific value. Leave as "cfml"
			//  https://docs.sentry.io/development/sdk-dev/attributes/
			'platform' = 'cfml',
			'logger' = controller.getSetting( 'appName' ),
			'userInfoUDF' = ''
		};
				
		// Try to look up the release based on a box.json
		var boxJSONPath = expandPath( '/' & appmapping & '/box.json' );
		if( fileExists( boxJSONPath ) ) {
			var boxJSONRaw = fileRead( boxJSONPath );
			if( isJSON( boxJSONRaw ) ) {
				var boxJSON = deserializeJSON( boxJSONRaw );
				if( boxJSON.keyExists( 'version' ) ) {
					settings.release = boxJSON.version;
					if( boxJSON.keyExists( 'slug' ) ) {
						settings.release = boxJSON.slug & '@' & settings.release;
					} else if( boxJSON.keyExists( 'name' ) ) {
						settings.release = boxJSON.name & '@' & settings.release;
					}
				}
			}
		}

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
		var sentryService = wirebox.getInstance( 'SentryService@sentry' );
		
		sentryService.captureException(
			exception	= interceptData.exception,
			level 	= 'error' 
		);
			}

	//**************************************** PRIVATE ************************************************//	

	/**
	 * Load LogBox Appenders
	 */
	private function loadAppenders(){
		// Get config
		var logBoxConfig 	= controller.getLogBox().getConfig();
		var rootConfig 		= '';

		// Register tracer appender
		rootConfig = logBoxConfig.getRoot();
		logBoxConfig.appender( 
			name 		= 'sentry_appender', 
			class 		= '#moduleMapping#.models.SentryAppender',
			levelMin 	= settings.levelMin,
			levelMax 	= settings.levelMax
		);
		logBoxConfig.root( 
			levelMin = rootConfig.levelMin,
			levelMax = rootConfig.levelMax,
			appenders= listAppend( rootConfig.appenders, 'sentry_appender')
		);

		// Store back config
		controller.getLogBox().configure( logBoxConfig );
	}

}
