component{

	// Configure ColdBox Application
	function configure(){

		// coldbox directives
		coldbox = {
			//Application Setup
			appName 				= "Module Tester",

			//Development Settings
			reinitPassword			= "",
			handlersIndexAutoReload = true,
			modulesExternalLocation = [ "/dependencies" ],

			//Implicit Events
			defaultEvent			= "",
			requestStartHandler		= "",
			requestEndHandler		= "",
			applicationStartHandler = "",
			applicationEndHandler	= "",
			sessionStartHandler 	= "",
			sessionEndHandler		= "",
			missingTemplateHandler	= "",

			//Error/Exception Handling
			exceptionHandler		= "",
			onInvalidEvent			= "",
			customErrorTemplate 	= "/coldbox/system/includes/BugReport.cfm",

			//Application Aspects
			handlerCaching 			= false,
			eventCaching			= false
		};

		// environment settings, create a detectEnvironment() method to detect it yourself.
		// create a function with the name of the environment so it can be executed if that environment is detected
		// the value of the environment is a list of regex patterns to match the cgi.http_host.
		environments = {
			development = "localhost,127\.0\.0\.1"
		};

		// Module Directives
		modules = {
			// An array of modules names to load, empty means all of them
			include = [ "funclinenums" ],
			// An array of modules names to NOT load, empty means none
			exclude = []
		};

		//Register interceptors as an array, we need order
		interceptors = [
		];

		//LogBox DSL
		logBox = {
			// Define Appenders
			appenders = {
				files={class="coldbox.system.logging.appenders.RollingFileAppender",
					properties = {
						filename = "tester", filePath="/#appMapping#/logs",
						async = true
					}
				}
			},
			// Root Logger
			root = { levelmax="DEBUG", appenders="*" },
			// Implicit Level Categories
			info = [ "coldbox.system" ]
		};

		moduleSettings = {
			sentry = {
				// Enable the Sentry LogBox Appender Bridge
				"enableLogBoxAppender" : true,
				// Min/Max levels for appender
				"levelMin" : "FATAL",
				"levelMax" : "ERROR",
				// Enable/disable error logging
				"enableExceptionLogging" = true,
				//"publicKey" : getSystemSetting( "SENTRY_PUBLICKEY", "" ),
				//"privateKey" : getSystemSetting( "SENTRY_PRIVATEKEY", "" ),
				//"projectID" : getSystemSetting( "SENTRY_PROJECTID", "" ),
				//"sentryUrl" : getSystemSetting( "SENTRY_URL", "" ),
				DSN : getSystemSetting( "SENTRY_DSN", "" ),
				async : false,
				userInfoUDF = function(){
					return {
						username : 'woodsb',
						email : 'brad@bradwood.com',
						cool : true
					};
				}
			}
		};

		if ( len( getSystemSetting( "SENTRY_QUEUE_HEALTH_DB", "" ) ) ) {
			coldbox.modulesExternalLocation.append( "/queueHealthModules" );
			modules.include.append( "qb" );
			modules.include.append( "str" );
			modules.include.append( "cbq" );
			// Synthetic failures must never use a developer's external SENTRY_DSN.
			moduleSettings.sentry.DSN = "http://public@127.0.0.1:60320/1";
			moduleSettings.sentry.enableLogBoxAppender = false;
			moduleSettings.sentry.enableExceptionLogging = false;
			moduleSettings[ "qb" ] = { defaultGrammar : "PostgresGrammar@qb", defaultOptions : { datasource : "sentryQueueHealth" } };
			moduleSettings[ "cbq" ] = { configPath : "tests.resources.QueueHealthConfig", registerWorkers : false };
		}

	}

	/**
	 * Load the Module you are testing
	 */
	function afterAspectsLoad( event, interceptData, rc, prc ){
		if ( len( getSystemSetting( "SENTRY_QUEUE_HEALTH_DB", "" ) ) ) {
			controller.getWireBox().getBinder().map( "QueueHealthState" ).to( "tests.resources.QueueHealthState" ).asSingleton();
			controller.getWireBox().getBinder().map( "QueueHealthJob" ).to( "tests.resources.QueueHealthJob" );
			controller.getWireBox().getBinder().map( "AutomaticLiveQueries" ).to( "tests.resources.AutomaticLiveQueries" );
		}
		controller.getModuleService()
			.registerAndActivateModule(
				moduleName 		= request.MODULE_NAME,
				invocationPath 	= "moduleroot"
			);
	}

}
