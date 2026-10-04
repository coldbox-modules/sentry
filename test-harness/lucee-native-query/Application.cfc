component {

	this.name                  = "SentryLuceeNativeQueryVerification";
	this.mappings[ "/sentry" ] = getDirectoryFromPath( getCurrentTemplatePath() ) & "../../";
	configPath                 = getDirectoryFromPath( getCurrentTemplatePath() ) & "../../.tmp/lucee-query-db.json";
	if ( fileExists( configPath ) ) {
		this.datasources.verification = deserializeJSON( fileRead( configPath ) );
		this.datasource               = "verification";
	}
	this.query.listener = {
		before : function( caller, args ){
			return request.listener.before( argumentCollection = arguments );
		},
		after : function( caller, args, result, meta ){
			return request.listener.after( argumentCollection = arguments );
		},
		error : function( args, caller, meta, exception ){
			return request.listener.error( argumentCollection = arguments );
		}
	};
	function onRequestStart( targetPage ){
		request.sentry = new sentry.models.SentryService( {
			DSN              : "http://public@127.0.0.1:60320/1",
			tracesSampleRate : 1
		} );
		request.listener = request.sentry.createLuceeQueryListener( databaseSystem = "postgresql" );
	}
	function onRequestEnd( targetPage ){
		request.sentry.shutdown();
	}

}
