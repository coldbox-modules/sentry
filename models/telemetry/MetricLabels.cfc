/** Bounded, fixed technical identities. Callers must use the configured spelling. */
component {

	function init( array names = [] ){
		variables.names = [];
		for ( var name in arguments.names ) {
			if (
				!isNull( name ) && isSimpleValue( name ) && variables.names.len() < 32 && len( name ) > 0 && len(
					name
				) <= 48 && !reFind( "[^A-Za-z0-9_.-]", name ) && !arrayFindNoCase( variables.names, name )
			)
				variables.names.append( toString( name ) );
		}
		return this;
	}
	function isAllowed( required string name ){
		return variables.names.find( arguments.name ) > 0;
	}

}
