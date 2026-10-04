/** Delivery acknowledgement. HTTP acceptance is distinct from enqueueing. */
component {

	function init(
		required string eventId,
		string state = "queued",
		any future,
		any transport,
		string category = "error"
	){
		variables[ "id" ]        = arguments.eventId;
		variables[ "state" ]     = arguments.state;
		variables[ "future" ]    = arguments.future ?: javacast( "null", "" );
		variables[ "transport" ] = arguments.transport ?: javacast( "null", "" );
		variables[ "category" ]  = arguments.category;
		variables[ "code" ]      = 0;
		variables[ "observed" ]  = createObject( "java", "java.util.concurrent.atomic.AtomicBoolean" ).init( false );
		return this;
	}
	function getEventId(){
		return variables.id;
	}
	function getStatus(){
		if ( variables.state == "queued" && variables.future.isDone() ) {
			awaitDelivery( 1 );
		}
		return variables.state;
	}
	function getStatusCode(){
		getStatus();
		return variables.code;
	}
	function isAccepted(){
		return getStatus() == "accepted";
	}
	function awaitDelivery( numeric timeoutMilliseconds = 2000 ){
		if ( variables.state != "queued" ) {
			return this;
		}
		try {
			var response = variables.future.get(
				javacast( "long", arguments.timeoutMilliseconds ),
				createObject( "java", "java.util.concurrent.TimeUnit" ).MILLISECONDS
			);
			variables[ "code" ]  = response.statusCode();
			variables[ "state" ] = variables.code >= 200 && variables.code < 300 ? "accepted" : "rejected";
			if ( variables.observed.compareAndSet( false, true ) ) {
				variables.transport.observeResponse( response );
			}
		} catch ( any failure ) {
			// A wait timeout leaves the request pending; network failures complete it.
			if ( variables.future.isDone() ) {
				variables[ "state" ] = "failed";
			}
		}
		return this;
	}

}
