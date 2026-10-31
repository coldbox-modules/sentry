component {

	property name="sentry" inject="SentryService@sentry";
	function send( required string message ){
		return { "message" : arguments.message };
	}
	function fail(){
		throw( type = "OriginalDependencyFailure", message = "PRIVATE" );
	}
	function nothing(){
	}
	function manual( required string message ){
		return variables.sentry.withDependency( "mail", function(){
			return "PRIVATE";
		} );
	}

}
