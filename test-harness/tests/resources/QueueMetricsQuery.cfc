/** Deterministic queue provider boundary; dialect compilation is tested with optional real qb. */
component {

	function init( array rows = [], boolean fail = false ){
		variables.rows = arguments.rows;
		variables.fail = arguments.fail;
		return this;
	}
	function from(){
		return this;
	}
	function select(){
		return this;
	}
	function selectRaw(){
		return this;
	}
	function whereNull(){
		return this;
	}
	function groupBy(){
		return this;
	}
	function getGrammar(){
		return {
			wrapValue : function( name ){
				return """" & name & """";
			}
		};
	}
	function get(){
		if ( variables.fail ) {
			throw( type = "DatabaseUnavailable" );
		}
		return variables.rows;
	}

}
