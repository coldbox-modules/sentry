/** Delegates the complete provider surface; never inspects or serializes cached values. */
component {

	function init( required any provider, required any telemetry ){
		variables[ "provider" ]  = arguments.provider;
		variables[ "telemetry" ] = arguments.telemetry;
		return this;
	}
	function get( required any objectKey ){
		return read( "get", arguments );
	}
	function getQuiet( required any objectKey ){
		return read( "getQuiet", arguments );
	}
	function lookup( required any objectKey ){
		return read( "lookup", arguments, true );
	}
	function lookupQuiet( required any objectKey ){
		return read( "lookupQuiet", arguments, true );
	}
	private function read(
		required string method,
		required struct args,
		boolean lookup = false
	){
		var method = arguments.method;
		var params = arguments.args;
		var lookup = arguments.lookup;
		return variables.telemetry.withSpan(
			"cache read",
			function( span ){
				var value = invoke( variables.provider, method, params );
				var hit   = lookup ? value : !isNull( value );
				span.setAttribute( "cache.hit", hit );
				variables.telemetry.counter(
					"cache.read",
					1,
					{ "outcome" : hit ? "hit" : "miss" }
				);
				return value;
			},
			"cache.get",
			{
				"cache.key"  : normalizeKey( params.objectKey ),
				"cache.name" : variables.provider.getName()
			}
		);
	}
	function set(){
		return mutate( "set", arguments, "cache.put" );
	}
	function setQuiet(){
		return mutate( "setQuiet", arguments, "cache.put" );
	}
	function clear(){
		return mutate( "clear", arguments, "cache.remove" );
	}
	function clearQuiet(){
		return mutate( "clearQuiet", arguments, "cache.remove" );
	}
	function clearAll(){
		return mutate( "clearAll", arguments, "cache.flush" );
	}
	private function mutate(
		required string method,
		required struct args,
		required string op
	){
		var method = arguments.method;
		var params = arguments.args;
		return variables.telemetry.withSpan(
			"cache write",
			function( span ){
				var result = invoke( variables.provider, method, params );
				span.setAttribute( "cache.write", true );
				return result;
			},
			arguments.op,
			{
				"cache.key"  : normalizeKey( params.objectKey ?: params[ "1" ] ?: "all" ),
				"cache.name" : variables.provider.getName()
			}
		);
	}
	function getOrSet(
		required any objectKey,
		required function produce,
		any timeout,
		any lastAccessTimeout,
		struct extra = {}
	){
		var args = arguments;
		return variables.telemetry.withSpan(
			"cache getOrSet",
			function( span ){
				var produced = false;
				var callback = function(){
					produced = true;
					return args.produce();
				};
				var params          = structCopy( args );
				params[ "produce" ] = callback;
				var result          = invoke( variables.provider, "getOrSet", params );
				span.setAttribute( "cache.hit", !produced );
				return result;
			},
			"cache.get",
			{ "cache.key" : normalizeKey( arguments.objectKey ) }
		);
	}
	private function normalizeKey( required any key ){
		return "sha256:" & left( lCase( hash( toString( arguments.key ), "SHA-256" ) ), 16 );
	}
	function onMissingMethod( required string missingMethodName, required struct missingMethodArguments ){
		return invoke(
			variables.provider,
			arguments.missingMethodName,
			arguments.missingMethodArguments
		);
	}

}
