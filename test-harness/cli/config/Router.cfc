/** The regression loads the real module without creating an HTTP request. */
component extends="coldbox.system.web.routing.Router" {

	function configure(){
	}
	function startup(){
		return this;
	}

}
