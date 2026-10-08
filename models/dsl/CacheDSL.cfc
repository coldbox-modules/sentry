/** WireBox injection: sentryCache:providerName. */
component implements="coldbox.system.ioc.dsl.IDSLBuilder" {

	function init( required any injector ){
		variables.injector = arguments.injector;
		return this;
	}
	function process(
		required any definition,
		any targetObject,
		any targetID
	){
		var name = listRest( arguments.definition.dsl, ":" );
		return variables.injector
			.getInstance( "SentryService@sentry" )
			.getInstrumentedCache( len( name ) ? name : "default" );
	}

}
