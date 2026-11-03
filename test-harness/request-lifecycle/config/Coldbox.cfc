component {

	function configure(){
		coldbox = {
			appName                 : "Sentry lifecycle fixture",
			reinitPassword          : "",
			defaultEvent            : "Responses.text",
			handlersIndexAutoReload : true,
			modulesExternalLocation : [ "/dependencies" ]
		};
		modules        = { include : [ "funclinenums" ] };
		moduleSettings = {
			sentry : {
				DSN                           : "http://public@127.0.0.1:1/1",
				enableLogBoxAppender          : false,
				enableExceptionLogging        : false,
				enableRequestTracing          : true,
				enableAutomaticRequestTimings : true,
				tracesSampleRate              : 1,
				beforeSendSignal              : function( payload, type ){
					if ( arguments.type == "transaction" ) application.records.add( duplicate( arguments.payload ) );
					return javacast( "null", "" );
				}
			}
		};
	}
	function afterAspectsLoad(){
		controller.getModuleService().registerAndActivateModule( "sentry", "moduleroot" );
	}

}
