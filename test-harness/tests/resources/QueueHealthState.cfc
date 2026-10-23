/** Shared in-memory gates survive real job serialization and worker-thread boundaries. */
component singleton {

	function init(){
		variables.runs = createObject( "java", "java.util.concurrent.ConcurrentHashMap" ).init();
		return this;
	}
	function create( required string id ){
		var state = {
			"started" : createObject( "java", "java.util.concurrent.CountDownLatch" ).init( 1 ),
			"release" : createObject( "java", "java.util.concurrent.CountDownLatch" ).init( 1 ),
			"handled" : createObject( "java", "java.util.concurrent.atomic.AtomicInteger" ).init( 0 )
		};
		variables.runs.put( arguments.id, state );
		return state;
	}
	function get( required string id ){
		return variables.runs.get( arguments.id );
	}
	function releaseAll(){
		for ( var id in variables.runs.keySet().toArray() ) {
			variables.runs.get( id ).release.countDown();
		}
	}
	function clear(){
		releaseAll();
		variables.runs.clear();
	}

}
