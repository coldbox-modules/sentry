/** Optional cbq database-provider adapter. No polling thread or installed-module mutation. */
component {

	function init(
		required any telemetry,
		required any config,
		required function queryFactory,
		string table      = "cbq_jobs",
		numeric maxQueues = 64
	){
		variables.telemetry    = arguments.telemetry;
		variables.config       = arguments.config;
		variables.queryFactory = arguments.queryFactory;
		variables.table        = arguments.table;
		variables.maxQueues    = max( 1, min( 256, arguments.maxQueues ) );
		variables.observed     = {};
		variables.diagnostics  = {
			"lastSuccessAt" : 0,
			"lastFailureAt" : 0,
			"failures"      : 0,
			"omittedQueues" : 0
		};
		variables.id = createUUID();
		return this;
	}
	function capture(){
		lock name="sentry-queue-sampler-#variables.id#" type="exclusive" timeout="2" throwOnTimeout="false" {
			try {
				var queues      = {};
				var definitions = variables.config.getWorkerPoolDefinitions();
				for ( var key in definitions ) {
					var names = definitions[ key ].getQueue();
					for ( var name in isArray( names ) ? names : [ names ] ) {
						queues[ queueKey( name ) ] = { "name" : name, "stats" : { "depth" : 0, "oldest" : 0 } };
					}
				}
				var query = variables.queryFactory();
				var rows  = query
					.from( variables.table )
					.select( "queue" )
					.selectRaw( "count(*) AS depth" )
					.selectRaw( "min(" & query.getGrammar().wrapValue( "createdDate" ) & ") AS oldest" )
					.whereNull( "completedDate" )
					.whereNull( "failedDate" )
					.whereNull( "reservedDate" )
					.groupBy( "queue" )
					.get();
				for ( var row in rows ) {
					queues[ queueKey( row.queue ) ] = { "name" : row.queue, "stats" : row };
				}
				for ( var key in variables.observed ) {
					if ( !queues.keyExists( key ) ) {
						queues[ key ] = {
							"name"  : variables.observed[ key ],
							"stats" : { "depth" : 0, "oldest" : 0 }
						};
					}
				}
				var now                             = createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000;
				var emitted                         = 0;
				variables.diagnostics.omittedQueues = 0;
				var ordered                         = [];
				for ( var key in queues ) {
					ordered.append( queues[ key ].name );
				}
				arraySort( ordered, "text" );
				for ( var name in ordered ) {
					var key = queueKey( name );
					if (
						emitted >= variables.maxQueues || (
							!variables.observed.keyExists( key ) && structCount( variables.observed ) >= variables.maxQueues
						)
					) {
						variables.diagnostics.omittedQueues++;
						continue;
					}
					var stats = queues[ key ].stats;
					variables.telemetry.captureQueueMetrics(
						name,
						stats.depth,
						stats.depth ? max( 0, now - stats.oldest ) : 0
					);
					if ( structCount( variables.observed ) < variables.maxQueues ) {
						variables.observed[ key ] = name;
					}
					emitted++;
				}
				variables.diagnostics.lastSuccessAt = now;
				return true;
			} catch ( any unavailable ) {
				variables.diagnostics.failures++;
				variables.diagnostics.lastFailureAt = createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000;
				return false;
			}
		}
		return false;
	}
	/** Hash exact labels internally: CFML structs and BoxLang Java-map adapters fold string key case. */
	private function queueKey( required string name ){
		return hash( arguments.name, "SHA-256", "UTF-8" );
	}
	function getDiagnostics(){
		lock name="sentry-queue-sampler-#variables.id#" type="exclusive" timeout="2" {
			return duplicate( variables.diagnostics );
		}
	}

}
