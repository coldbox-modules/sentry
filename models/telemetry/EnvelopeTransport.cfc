/** Bounded, independent Java HTTP transport. No application/cbq worker is used. */
component {

	function init(
		required struct settings,
		required string endpoint,
		required string auth,
		boolean enabled = true
	){
		variables[ "settings" ]  = arguments.settings;
		variables[ "endpoint" ]  = arguments.endpoint;
		variables[ "auth" ]      = arguments.auth;
		variables[ "enabled" ]   = arguments.enabled;
		variables[ "id" ]        = createUUID();
		variables[ "pending" ]   = [];
		variables[ "limits" ]    = {};
		variables[ "dropped" ]   = 0;
		variables[ "responses" ] = { "accepted" : 0, "rejected" : 0 };
		variables[ "closed" ]    = false;
		variables[ "executor" ]  = createObject( "java", "java.util.concurrent.Executors" ).newFixedThreadPool(
			javacast( "int", 2 )
		);
		variables[ "http" ]   = new JavaHttp();
		variables[ "client" ] = variables.http.createClient( variables.executor, settings.transportTimeout );
		return this;
	}
	function send(
		required string eventId,
		required array items,
		string category = "error",
		boolean wait    = false
	){
		var receipt = new Receipt( eventId = arguments.eventId, state = "disabled" );
		if ( !variables.enabled || variables.closed ) {
			return receipt;
		}
		lock name="sentry-transport-#variables.id#" type="exclusive" timeout="2" {
			reap();
			if ( variables.pending.len() >= variables.settings.maxPendingEnvelopes || limited( arguments.category ) ) {
				variables.dropped++;
				return new Receipt( eventId = arguments.eventId, state = "dropped" );
			}
			try {
				var permittedItems = arguments.items.filter( function( item ){
					return item.type != "attachment" || !limited( "attachment" );
				} );
				var bytes  = encodeEnvelope( arguments.eventId, permittedItems );
				var future = variables.http.sendAsync(
					variables.client,
					variables.endpoint,
					variables.auth,
					bytes,
					variables.settings.transportTimeout
				);
				receipt = new Receipt(
					arguments.eventId,
					"queued",
					future,
					this,
					arguments.category
				);
				variables.pending.append( receipt );
			} catch ( any failure ) {
				receipt = new Receipt( arguments.eventId, "failed" );
			}
		}
		if ( arguments.wait ) {
			receipt.awaitDelivery( variables.settings.transportTimeout );
		}
		return receipt;
	}
	function encodeEnvelope( required string eventId, required array items ){
		var output = createObject( "java", "java.io.ByteArrayOutputStream" ).init();
		output.write(
			charsetDecode(
				serializeJSON( {
					"event_id" : arguments.eventId,
					"sent_at"  : createObject( "java", "java.time.Instant" ).now().toString()
				} ) & chr( 10 ),
				"UTF-8"
			)
		);
		for ( var item in arguments.items ) {
			var data = isBinary( item.payload ) ? item.payload : charsetDecode(
				isSimpleValue( item.payload ) ? item.payload : serializeJSON( item.payload ),
				"UTF-8"
			);
			var header = {
				"type"         : item.type,
				"length"       : arrayLen( data ),
				"content_type" : "application/json"
			};
			header.append( item.headers ?: {}, true );
			if ( item.type == "log" || item.type == "trace_metric" ) {
				header[ "item_count" ]   = item.payload.items.len();
				header[ "content_type" ] = item.type == "log" ? "application/vnd.sentry.items.log+json" : "application/vnd.sentry.items.trace-metric+json";
			}
			output.write( charsetDecode( serializeJSON( header ) & chr( 10 ), "UTF-8" ) );
			output.write( data );
			output.write( javacast( "int", 10 ) );
		}
		return output.toByteArray();
	}
	function observeResponse( required any response ){
		lock name="sentry-response-#variables.id#" type="exclusive" timeout="2" {
			var code  = getResponseStatusCode( arguments.response );
			var state = code >= 200 && code < 300 ? "accepted" : "rejected";
			variables.responses[ state ]++;
		}
		var rateHeader = variables.http
			.headers( arguments.response )
			.firstValue( "X-Sentry-Rate-Limits" )
			.orElse( "" );
		for ( var entry in listToArray( rateHeader ) ) {
			var parts = listToArray( entry, ":", true );
			if ( parts.len() >= 2 && isNumeric( parts[ 1 ] ) ) {
				var categories = len( parts[ 2 ] ) ? listToArray( parts[ 2 ], ";" ) : [ "all" ];
				for ( var category in categories ) {
					setLimit( category, val( parts[ 1 ] ) );
				}
			}
		}
		if ( getResponseStatusCode( arguments.response ) == 429 && !len( rateHeader ) ) {
			var retry = variables.http
				.headers( arguments.response )
				.firstValue( "Retry-After" )
				.orElse( "60" );
			var seconds = isNumeric( retry ) ? val( retry ) : 60;
			if ( !isNumeric( retry ) ) {
				try {
					seconds = max(
						0,
						(
							createObject( "java", "java.time.ZonedDateTime" )
								.parse(
									retry,
									createObject( "java", "java.time.format.DateTimeFormatter" ).RFC_1123_DATE_TIME
								)
								.toInstant()
								.toEpochMilli() - epochMillis()
						) / 1000
					);
				} catch ( any ignored ) {
				}
			}
			setLimit( "all", seconds );
		}
	}
	function getResponseStatusCode( required any response ){
		return variables.http.statusCode( arguments.response );
	}
	function isDeliveryDone( required any future ){
		return variables.http.isDone( arguments.future );
	}
	function awaitResponse( required any future, required numeric timeoutMilliseconds ){
		return variables.http.awaitResponse( arguments.future, arguments.timeoutMilliseconds );
	}
	private function setLimit( required string category, required numeric seconds ){
		lock name="sentry-limits-#variables.id#" type="exclusive" timeout="2" {
			variables.limits[ arguments.category ] = max(
				variables.limits[ arguments.category ] ?: 0,
				epochMillis() + arguments.seconds * 1000
			);
		}
	}
	private function limited( required string category ){
		var categories = {
			"log"          : "log_item",
			"trace_metric" : "metric",
			"check_in"     : "monitor"
		};
		arguments.category = categories[ arguments.category ] ?: arguments.category;
		return ( variables.limits.all ?: 0 ) > epochMillis() || ( variables.limits[ arguments.category ] ?: 0 ) > epochMillis();
	}
	private function reap(){
		for ( var i = variables.pending.len(); i >= 1; i-- ) {
			if ( variables.pending[ i ].getStatus() != "queued" ) {
				variables.pending.deleteAt( i );
			}
		}
	}
	private function epochMillis(){
		return createObject( "java", "java.lang.System" ).currentTimeMillis();
	}
	function flush( numeric timeoutMilliseconds = 2000 ){
		var deadline= epochMillis() + arguments.timeoutMilliseconds;
		var snapshot= [];
		lock name   ="sentry-transport-#variables.id#" type="exclusive" timeout="2" {
			if ( !variables.pending.isEmpty() ) {
				snapshot = variables.pending.slice( 1 );
			}
		}
		for ( var receipt in snapshot ) {
			receipt.awaitDelivery( max( 1, deadline - epochMillis() ) );
		}
		return snapshot.isEmpty() || snapshot.every( function( receipt ){
			return receipt.getStatus() != "queued";
		} );
	}
	function shutdown( numeric timeoutMilliseconds = 2000 ){
		variables[ "closed" ] = true;
		var complete          = flush( arguments.timeoutMilliseconds );
		variables.executor.shutdown();
		return complete;
	}
	function getDiagnostics(){
		lock name="sentry-transport-#variables.id#" type="exclusive" timeout="2" {
			reap();
			return {
				"pending"  : variables.pending.len(),
				"accepted" : variables.responses.accepted,
				"rejected" : variables.responses.rejected,
				"dropped"  : variables.dropped,
				"closed"   : variables.closed
			};
		}
	}

}
