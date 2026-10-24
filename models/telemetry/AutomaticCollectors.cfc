/** One bounded background sampler per telemetry service. No request threads, overlapping ticks or duplicate starts. */
component {

	function init(
		required any telemetry,
		required struct settings,
		required any resolver
	){
		variables.telemetry   = arguments.telemetry;
		variables.settings    = arguments.settings;
		variables.resolver    = arguments.resolver;
		variables.running     = createObject( "java", "java.util.concurrent.atomic.AtomicBoolean" ).init( false );
		variables.started     = createObject( "java", "java.util.concurrent.atomic.AtomicBoolean" ).init( false );
		variables.closed      = createObject( "java", "java.util.concurrent.atomic.AtomicBoolean" ).init( false );
		variables.diagnostics = {
			"runs"          : 0,
			"failures"      : 0,
			"lastSuccessAt" : 0,
			"lastFailureAt" : 0,
			"skipped"       : 0
		};
		variables.id = createUUID();
		return this;
	}
	function start(){
		if ( !variables.settings.enabled || !variables.started.compareAndSet( false, true ) || variables.closed.get() )
			return false;
		try {
			var interval = variables.settings.intervalSeconds;
			if ( !isNumeric( interval ) || interval < 1 || interval > 3600 || interval != int( interval ) )
				throw( type = "Sentry.InvalidCollectorInterval" );
			variables.executor = createObject( "java", "java.util.concurrent.Executors" ).newSingleThreadScheduledExecutor();
			var task           = new AutomaticCollectorTask( this );
			// ColdBox proxies establish the engine application context and release Adobe JDBC thread state.
			try {
				task = createObject( "component", "coldbox.system.async.cbproxies.models.Runnable" ).init( task );
			} catch ( any unavailableContext ) {
			}
			variables.executor.scheduleWithFixedDelay(
				createDynamicProxy( task, [ "java.lang.Runnable" ] ),
				javacast( "long", interval ),
				javacast( "long", interval ),
				createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
			);
			return true;
		} catch ( any unavailable ) {
			variables.started.set( false );
			if ( !isNull( variables.executor ) ) variables.executor.shutdownNow();
			record( false );
			return false;
		}
	}
	function tick(){
		if ( variables.closed.get() || !variables.settings.enabled || !variables.telemetry.collectionEnabled() )
			return;
		if ( !variables.running.compareAndSet( false, true ) ) {
			lock name="sentry-auto-#variables.id#" type="exclusive" timeout="2" {
				variables.diagnostics.skipped++;
			}
			return;
		}
		var success  = true;
		var previous = {};
		try {
			previous = variables.telemetry.getScope();
			variables.telemetry.clearScope();
			if ( canCollect() && variables.settings.runtime )
				success = variables.tryCollect( function(){
					variables.telemetry.captureRuntimeGauges();
					return true;
				} ) && success;
			if ( canCollect() && variables.settings.requestSaturation )
				success = variables.tryCollect( function(){
					variables.telemetry.captureRequestSaturation();
					return true;
				} ) && success;
			if ( canCollect() && variables.settings.deliveryDiagnostics )
				success = variables.tryCollect( function(){
					variables.telemetry.deliveryDiagnostics();
					return true;
				} ) && success;
			for (
				var kind in [
					"queueWorkers",
					"databaseQueues",
					"requestExecutors",
					"databasePools"
				]
			) {
				var definitions = variables.settings[ kind ];
				for ( var i = 1; i <= min( 32, definitions.len() ); i++ ) {
					if ( !canCollect() ) break;
					var definition = definitions[ i ];
					try {
						var captured = variables.collectDefinition( kind, definition );
						success      = captured && success;
					} catch ( any unavailable ) {
						success = false;
					}
				}
			}
		} catch ( any unavailable ) {
			success = false;
		} finally {
			try {
				variables.telemetry.setScope( previous );
			} catch ( any ignored ) {
			}
			variables.running.set( false );
			record( success );
		}
	}
	private function canCollect(){
		return !variables.closed.get() && variables.telemetry.collectionEnabled();
	}
	private function tryCollect( required function callback ){
		if ( !canCollect() ) return false;
		try {
			return arguments.callback() != false;
		} catch ( any unavailable ) {
			return false;
		}
	}
	private function collectDefinition( required string kind, required struct definition ){
		var config      = arguments.definition;
		var collectKind = arguments.kind;
		if ( !config.keyExists( "name" ) || !isSimpleValue( config.name ) ) return false;
		if ( !canCollect() ) return false;
		var context = { "name" : config.name, "kind" : collectKind };
		if ( collectKind == "queueWorkers" && config.keyExists( "pool" ) ) {
			return variables.telemetry.captureCBQWorkerHealth(
				config.name,
				variables.resolver.resolve( "Config@cbq" ).getWorkerPool( config.pool )
			);
		}
		if ( collectKind == "databaseQueues" ) {
			var factory = function(){
				if ( !config.keyExists( "queryFactory" ) ) return variables.resolver.resolve( "QueryBuilder@qb" );
				return variables.resolver.call(
					config.queryFactory,
					"newQuery",
					{ "context" : context }
				);
			};
			var adapter  = new DatabaseQueueHealth( factory, config.table ?: "cbq_jobs" );
			var sample   = {};
			var observed = variables.telemetry.captureQueueWorkerHealth( config.name, function(){
				sample = adapter.snapshot( config.queue ?: config.name );
				return sample;
			} );
			if ( observed && canCollect() )
				variables.telemetry.captureQueueMetrics(
					config.queue ?: config.name,
					sample.depth,
					sample.oldestAgeSeconds
				);
			return observed;
		}
		var callback = function(){
			return variables.resolver.call(
				config.adapter,
				"sample",
				{ "context" : context }
			);
		};
		if ( collectKind == "queueWorkers" )
			return variables.telemetry.captureQueueWorkerHealth( config.name, callback );
		if ( collectKind == "requestExecutors" )
			return variables.telemetry.captureRequestExecutor( config.name, callback );
		if ( collectKind == "databasePools" )
			return variables.telemetry.captureDatabasePool( config.name, callback );
		return false;
	}
	private function record( required boolean success ){
		lock name="sentry-auto-#variables.id#" type="exclusive" timeout="2" {
			var now = createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000;
			variables.diagnostics.runs++;
			if ( arguments.success ) variables.diagnostics.lastSuccessAt = now;
			else {
				variables.diagnostics.failures++;
				variables.diagnostics.lastFailureAt = now;
			}
		}
	}
	function diagnostics(){
		lock name="sentry-auto-#variables.id#" type="exclusive" timeout="2" {
			var result          = duplicate( variables.diagnostics );
			result[ "started" ] = variables.started.get() && !variables.closed.get();
			return result;
		}
	}
	function shutdown(){
		variables.closed.set( true );
		if ( !isNull( variables.executor ) ) {
			variables.executor.shutdownNow();
		}
	}

}
