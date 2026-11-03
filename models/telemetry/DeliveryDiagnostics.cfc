/** Local, content-free envelope outcomes. Never emits telemetry about its own failures. */
component {

	function init( numeric capacity = 64 ){
		variables.capacity     = max( 1, min( 4096, arguments.capacity ) );
		variables.pending      = [];
		variables.counts       = {};
		variables.lastAccepted = 0;
		variables.lastAttempt  = 0;
		variables.untracked    = 0;
		variables.id           = createUUID();
		return this;
	}
	function record( required any receipt ){
		lock name="sentry-delivery-#variables.id#" type="exclusive" timeout="2" {
			poll();
			variables.lastAttempt = epoch();
			var status            = arguments.receipt.getStatus();
			if ( status == "queued" ) {
				if ( variables.pending.len() < variables.capacity ) {
					variables.pending.append( { "receipt" : arguments.receipt, "created" : epoch() } );
				} else {
					variables.untracked++;
				}
			} else {
				count( status );
			}
		}
	}
	function snapshot(){
		lock name="sentry-delivery-#variables.id#" type="exclusive" timeout="2" {
			poll();
			var oldest = 0;
			for ( var entry in variables.pending ) {
				oldest = max( oldest, epoch() - entry.created );
			}
			return {
				"outcomes"             : duplicate( variables.counts ),
				"pending"              : variables.pending.len(),
				"oldestPendingSeconds" : oldest,
				"lastAttemptAt"        : variables.lastAttempt,
				"lastAcceptedAt"       : variables.lastAccepted,
				"untracked"            : variables.untracked
			};
		}
	}
	private function poll(){
		for ( var i = variables.pending.len(); i >= 1; i-- ) {
			var status = variables.pending[ i ].receipt.getStatus();
			if ( status != "queued" ) {
				count( status );
				variables.pending.deleteAt( i );
			}
		}
	}
	private function count( required string status ){
		if ( !listFind( "accepted,rejected,dropped,failed,disabled,filtered,invalid", arguments.status ) ) {
			return;
		}
		variables.counts[ arguments.status ] = ( variables.counts[ arguments.status ] ?: 0 ) + 1;
		if ( arguments.status == "accepted" ) {
			variables.lastAccepted = epoch();
		}
	}
	private function epoch(){
		return createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000;
	}

}
