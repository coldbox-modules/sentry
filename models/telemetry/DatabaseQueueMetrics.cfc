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
						queues[ name ] = { "depth" : 0, "oldest" : 0 };
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
					queues[ row.queue ] = row;
				}
				for ( var name in variables.observed ) {
					if ( !queues.keyExists( name ) ) {
						queues[ name ] = { "depth" : 0, "oldest" : 0 };
					}
				}
				var now                             = createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000;
				var emitted                         = 0;
				variables.diagnostics.omittedQueues = 0;
				var ordered                         = structKeyArray( queues );
				arraySort( ordered, "text" );
				for ( var name in ordered ) {
					if (
						emitted >= variables.maxQueues || (
							!variables.observed.keyExists( name ) && structCount( variables.observed ) >= variables.maxQueues
						)
					) {
						variables.diagnostics.omittedQueues++;
						continue;
					}
					var stats = queues[ name ];
					variables.telemetry.captureQueueMetrics(
						name,
						stats.depth,
						stats.depth ? max( 0, now - stats.oldest ) : 0
					);
					if ( structCount( variables.observed ) < variables.maxQueues ) {
						variables.observed[ name ] = true;
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
	function getDiagnostics(){
		lock name="sentry-queue-sampler-#variables.id#" type="exclusive" timeout="2" {
			return duplicate( variables.diagnostics );
		}
	}

}
