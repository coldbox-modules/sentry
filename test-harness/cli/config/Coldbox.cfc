component {

	function configure(){
		coldbox = {
			appName                 : "Sentry CLI regression",
			defaultEvent            : "",
			applicationStartHandler : "",
			requestStartHandler     : "",
			exceptionHandler        : "",
			modulesExternalLocation : [ "/cliModules" ]
		};
		modules = { include : [ "funclinenums", "sentry" ], exclude : [] };
		flash   = { scope : "cache" };
		logBox  = {
			appenders : { console : { class : "coldbox.system.logging.appenders.ConsoleAppender" } },
			root      : { levelmax : "WARN", appenders : "console" }
		};
		moduleSettings = {
			sentry : {
				DSN                            : getSystemSetting( "SENTRY_CLI_TEST_DSN" ),
				async                          : false,
				sentryEventEndpoint            : "envelope",
				enableLogBoxAppender           : false,
				enableExceptionLogging         : false,
				enableStructuredLogBoxAppender : false,
				queryAdapter                   : "none"
			}
		};
	}

}
