component extends="coldbox.system.EventHandler" {

	function text( event, rc, prc ){
		return "fixture text";
	}
	function binary( event, rc, prc ){
		event.setHTTPHeader( name = "Cache-Control", value = "private, no-store" );
		event.setHTTPHeader( name = "X-Content-Type-Options", value = "nosniff" );
		event.renderData(
			type        = "plain",
			data        = binaryDecode( "0001027f80ff", "hex" ),
			contentType = "application/octet-stream",
			isBinary    = true
		);
	}
	function slow( event, rc, prc ){
		sleep( 250 );
		return "slow response";
	}
	function noRender( event, rc, prc ){
		event.noRender();
	}
	function streamed( event, rc, prc ){
		event.noRender();
		writeOutput( "stream-one" );
		sleep( 40 );
		writeOutput( "stream-two" );
	}
	function aborted( event, rc, prc ){
		abort;
	}
	function redirect( event, rc, prc ){
		relocate( event = "Responses.text" );
	}
	function failure( event, rc, prc ){
		throw( type = "SentryFixture.Original", message = "original lifecycle failure" );
	}
	function report( event, rc, prc ){
		event.renderData(
			type = "json",
			data = {
				records : application.records.toArray(),
				hooks   : application.hooks.toArray(),
				thread  : createObject( "java", "java.lang.Thread" ).currentThread().getName()
			}
		);
	}

}
