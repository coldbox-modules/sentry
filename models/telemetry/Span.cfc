/** A handle may be completed from any thread. Only the first completion wins. */
component {

	function init(
		required any telemetry,
		required struct data,
		boolean sampled = false,
		any root
	){
		variables[ "baggage" ]   = "";
		variables[ "telemetry" ] = arguments.telemetry;
		variables[ "data" ]      = arguments.data;
		variables[ "sampled" ]   = arguments.sampled;
		variables[ "isRoot" ]    = isNull( arguments.root );
		variables[ "root" ]      = arguments.root ?: this;
		variables[ "done" ]      = createObject( "java", "java.util.concurrent.atomic.AtomicBoolean" ).init( false );
		variables[ "children" ]  = createObject( "java", "java.util.concurrent.ConcurrentLinkedQueue" ).init();
		variables[ "id" ]        = createUUID();
		return this;
	}
	function getContext(){
		return {
			"trace_id" : variables.data.trace_id,
			"span_id"  : variables.data.span_id,
			"sampled"  : variables.sampled
		};
	}
	function rename( required string name ){
		variables.data[ "description" ] = variables.telemetry.safeName( arguments.name );
		return this;
	}
	function setBaggage( required string value ){
		variables.baggage = arguments.value;
		return this;
	}
	function getBaggage(){
		return variables.isRoot ? variables.baggage : variables.root.getBaggage();
	}
	function getRoot(){
		return variables.root;
	}
	function isSampled(){
		return variables.sampled;
	}
	function isFinished(){
		return variables.done.get();
	}
	function setAttribute( required string name, required any value ){
		lock name="sentry-span-#variables.id#" type="exclusive" timeout="2" throwOnTimeout="false" {
			if ( !isFinished() ) {
				variables.data.data[ arguments.name ] = arguments.value;
			}
		}
		return this;
	}
	function setStatus( required string status ){
		lock name="sentry-span-#variables.id#" type="exclusive" timeout="2" throwOnTimeout="false" {
			if ( !isFinished() ) {
				variables.data[ "status" ] = arguments.status;
			}
		}
		return this;
	}
	function addChild( required any child ){
		if ( variables.children.size() < variables.telemetry.getMaxSpans() ) {
			variables.children.add( arguments.child );
		}
	}
	/** Queue execution starts on the worker, which may be later than scheduling. */
	function markStarted( required numeric timestamp ){
		lock name="sentry-span-#variables.id#" type="exclusive" timeout="2" throwOnTimeout="false" {
			if ( isFinished() ) {
				return false;
			}
			variables.data[ "start_timestamp" ] = arguments.timestamp;
		}
		return true;
	}

	function finish( string status = "" ){
		lock name="sentry-span-#variables.id#" type="exclusive" timeout="2" throwOnTimeout="false" {
			if ( !variables.done.compareAndSet( false, true ) ) {
				return false;
			}
			if ( len( arguments.status ) ) {
				variables.data[ "status" ] = arguments.status;
			}
			variables.data[ "timestamp" ] = variables.telemetry.timestamp();
			if ( variables.sampled ) {
				if ( variables.isRoot ) {
					variables.telemetry.completeTransaction( this );
				} else {
					variables.root.addChild( this );
				}
			}
		}
		return true;
	}
	function toPayload(){
		var payload       = duplicate( variables.data );
		payload[ "data" ] = variables.telemetry.sanitizeAttributes( payload.data );
		return payload;
	}
	function getChildren(){
		var children = [];
		for ( var child in variables.children.toArray() ) {
			children.append( child );
		}
		return children;
	}

}
