component {

	function init( required any telemetry ){
		variables.telemetry = arguments.telemetry;
		return this;
	}
	function run(){
		try {
			variables.telemetry.flushSignals();
		} catch ( any ignored ) {
		}
	}

}
