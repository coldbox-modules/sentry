/** Local HTTP lifecycle fixture. All telemetry is captured in memory; nothing is ingested. */
component {

	this.name                        = "sentry-lifecycle-fixed-" & hash( getCurrentTemplatePath() );
	variables.root                   = getDirectoryFromPath( getCurrentTemplatePath() );
	this.mappings[ "/coldbox" ]      = variables.root & "../coldbox";
	this.mappings[ "/sentry" ]       = variables.root & "../../";
	this.mappings[ "/moduleroot" ]   = variables.root & "../../../";
	this.mappings[ "/dependencies" ] = variables.root & "../../modules";
	function onApplicationStart(){
		application.records   = createObject( "java", "java.util.concurrent.ConcurrentLinkedQueue" ).init();
		application.hooks     = createObject( "java", "java.util.concurrent.ConcurrentLinkedQueue" ).init();
		application.bootstrap = new coldbox.system.Bootstrap( "", variables.root, "", "/request-lifecycle" );
		application.bootstrap.loadColdBox();
		return true;
	}
	function onRequestStart( targetPage ){
		if ( listLast( arguments.targetPage, "/" ) == "report.cfm" ) return true;
		application.hooks.add( "start" );
		return application.bootstrap.onRequestStart( arguments.targetPage );
	}
	function onRequestEnd( targetPage ){
		if ( listLast( arguments.targetPage, "/" ) == "report.cfm" ) return;
		application.hooks.add( "end" );
		application.cbController
			.getWireBox()
			.getInstance( "SentryService@sentry" )
			.endRequest();
	}
	function onAbort( targetPage ){
		application.hooks.add( "abort" );
		application.cbController
			.getWireBox()
			.getInstance( "SentryService@sentry" )
			.endRequest();
	}

}
