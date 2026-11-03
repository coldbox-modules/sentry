/** Background entry point shields the scheduler from adapter failures. */
component {

	function init( required any collector ){
		variables.collector = arguments.collector;
		return this;
	}
	function run(){
		try {
			variables.collector.tick();
		} catch ( any unavailable ) {
		}
	}

}
