/** Adapters are callbacks, mapping IDs, objects, or {mapping,method} descriptors. Never cache consumer instances. */
component {

	function init( any injector = "" ){
		variables.injector = arguments.injector;
		return this;
	}
	function setInjector( required any injector ){
		variables.injector = arguments.injector;
		return this;
	}
	function resolve( required string mapping ){
		if ( !isObject( variables.injector ) ) throw( type = "Sentry.AdapterInjectorUnavailable" );
		return variables.injector.getInstance( arguments.mapping );
	}
	function call(
		required any adapter,
		required string method,
		struct args = {}
	){
		if ( isCustomFunction( arguments.adapter ) ) return arguments.adapter( argumentCollection = arguments.args );
		var target     = arguments.adapter;
		var methodName = arguments.method;
		if ( isStruct( target ) && target.keyExists( "mapping" ) ) {
			if ( target.keyExists( "method" ) ) methodName = target.method;
			target = resolve( target.mapping );
		} else if ( isSimpleValue( target ) ) {
			target = resolve( toString( target ) );
		}
		if (
			!isObject( target ) || !isSimpleValue( methodName ) || !reFind(
				"^[A-Za-z_][A-Za-z0-9_]*$",
				methodName
			) || reFind( "[^A-Za-z0-9_]", methodName )
		)
			throw( type = "Sentry.InvalidAdapter" );
		return invoke( target, methodName, arguments.args );
	}

}
