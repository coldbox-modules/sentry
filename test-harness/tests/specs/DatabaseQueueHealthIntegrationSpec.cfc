/** Opt-in, loopback PostgreSQL + real cbq DB-provider/worker integration. No mocks at the database/worker boundary. */
component extends="testbox.system.BaseSpec" {

	function run(){
		var database = createObject( "java", "java.lang.System" ).getenv( "SENTRY_QUEUE_HEALTH_DB" );
		if ( isNull( database ) || !len( database ) ) return;
		describe( "Local database queue health and actual cbq workers", function(){
			beforeEach( function(){
				variables.wirebox  = application.cbController.getWireBox();
				variables.config   = variables.wirebox.getInstance( "Config@cbq" );
				variables.key      = "qh_" & lCase( left( replace( createUUID(), "-", "", "all" ), 20 ) );
				variables.table    = "cbq_" & variables.key;
				variables.pool     = javacast( "null", "" );
				variables.service  = javacast( "null", "" );
				variables.taskName = "";
				variables.state    = variables.wirebox.getInstance( "QueueHealthState" );
				variables.state.clear();
				variables.wirebox
					.getInstance( "SchemaBuilder@qb" )
					.create( variables.table, function( t ){
						t.bigIncrements( "id" );
						t.string( "queue" );
						t.longText( "payload" );
						t.bigInteger( "attempts" );
						t.bigInteger( "availableDate" );
						t.bigInteger( "createdDate" );
						t.bigInteger( "reservedDate" ).nullable();
						t.string( "reservedBy" ).nullable();
						t.bigInteger( "completedDate" ).nullable();
						t.bigInteger( "failedDate" ).nullable();
						t.bigInteger( "lastReleasedDate" ).nullable();
						t.index( "queue" );
					} );
				variables.config.registerConnection(
					variables.key,
					"DBProvider@cbq",
					{
						datasource               : "sentryQueueHealth",
						tableName                : variables.table,
						pollIntervalMilliseconds : 50
					},
					"health"
				);
				variables.adapter = new sentry.models.telemetry.DatabaseQueueHealth( function(){
					return variables.wirebox.getInstance( "QueryBuilder@qb" );
				}, variables.table );
				variables.service = new sentry.models.SentryService( {
					DSN              : "http://public@127.0.0.1:60320/1",
					enableMetrics    : true,
					queueWorkerNames : [ "health" ]
				} );
				variables.service.getObservability().setAdapterInjector( variables.wirebox );
			} );

			afterEach( function(){
				var errors = cleanupFixture();
				if ( errors.len() )
					throw( type = "QueueHealthFixtureCleanupFailed", message = errors.toList( "; " ) );
			} );

			it( "samples worker activity and database backlog through a single provider-owned queue adapter", function(){
				startPool();
				var job = publish( "block" );
				expect(
					job.state.started.await(
						javacast( "long", 5 ),
						createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
					)
				).toBeTrue();
				variables.service.shutdown();
				variables.service = new sentry.models.SentryService( {
					DSN                 : "http://public@127.0.0.1:60320/1",
					enableMetrics       : true,
					automaticCollectors : {
						enabled           : true,
						intervalSeconds   : 1,
						runtime           : false,
						requestSaturation : false,
						queues            : [
							{
								name    : "health",
								adapter : "QueueHealthAdapter@cbq",
								options : { workerPool : variables.key }
							}
						]
					}
				} );
				variables.service.getObservability().setAdapterInjector( variables.wirebox );
				var telemetry = prepareMock( variables.service.getObservability() );
				telemetry.$( "gauge" );
				awaitCondition( function(){
					return variables.service.automaticCollectorDiagnostics().runs > 0;
				} );
				expect( variables.service.automaticCollectorDiagnostics().failures ).toBe( 0 );
				var calls    = telemetry.$callLog( "gauge" ).gauge;
				var active   = -1;
				var reserved = -1;
				for ( var call in calls ) {
					if ( call[ 1 ] == "queue.executions.active" ) active = call[ 2 ];
					if ( call[ 1 ] == "queue.backlog.reserved" ) reserved = call[ 2 ];
				}
				expect( active ).toBe( 1 );
				expect( reserved ).toBe( 1 );
				expect( serializeJSON( calls ) ).toInclude( "queue.depth" );
				expect( serializeJSON( calls ) ).toInclude( "queue.oldest_age" );
				job.state.release.countDown();
				awaitCondition( function(){
					return hasTimestamp( row( job.id ), "completedDate" );
				} );
			} );

			it( "loads qb's optional adapter through WireBox and cleans only its owned listeners", function(){
				variables.service.shutdown();
				variables.service = new sentry.models.SentryService( {
					DSN              : "http://public@127.0.0.1:60320/1",
					tracesSampleRate : 1,
					queryAdapter     : "QueryTelemetryAdapter@qb",
					databaseSystem   : "postgresql"
				} );
				var telemetry = variables.service.getObservability();
				telemetry.setAdapterInjector( variables.wirebox );
				var interceptors = application.cbController.getInterceptorService();
				var states       = interceptors.getInterceptionStates();
				var before       = states.keyExists( "preQBExecute" ) ? states.preQBExecute.getInterceptors().size() : 0;
				var extra        = {};
				try {
					variables.wirebox.getInstance( "QueryTelemetryAdapter@qb" );
					expect( telemetry.configureQueryInstrumentation( getApplicationMetadata().name ) ).toBe( "custom" );
					expect( states.preQBExecute.getInterceptors().size() ).toBe( before + 1 );
					var root = variables.service.startTransaction( "qb adapter integration" );
					telemetry.setScope( { span : root, marker : "preserved" } );
					jobQuery().where( "queue", "health" ).get();
					expect( root.getChildren().len() ).toBe( 1 );
					expect( root.getChildren()[ 1 ].toPayload().data[ "db.system" ] ).toBe( "postgresql" );
					expect( root.getChildren()[ 1 ].toPayload().status ).toBe( "ok" );
					expect( function(){
						jobQuery().select( "sentry_health_missing_column" ).get();
					} ).toThrow();
					expect( root.getChildren().len() ).toBe( 2 );
					expect( root.getChildren()[ 2 ].toPayload().status ).toBe( "internal_error" );
					variables.service.withQuerySpan(
						"SELECT 'PRIVATE_QUERY_LITERAL'",
						function( span ){
							return jobQuery().get();
						},
						"postgresql"
					);
					expect( root.getChildren().len() ).toBe( 3 );
					expect( root.getChildren()[ 3 ].toPayload().description ).notToInclude( "PRIVATE_QUERY_LITERAL" );
					expect( telemetry.getScope().span.getContext().span_id ).toBe( root.getContext().span_id );
					expect( telemetry.getScope().marker ).toBe( "preserved" );
					expect( telemetry.getScope().keyExists( "manualQuerySpan" ) ).toBeFalse();
					extra = variables.wirebox
						.getInstance( "QueryTelemetryAdapter@qb" )
						.configure( {
							telemetry       : telemetry,
							applicationName : getApplicationMetadata().name,
							databaseSystem  : "postgresql"
						} );
					expect( states.preQBExecute.getInterceptors().size() ).toBe( before + 2 );
					var pending = { sql : "SELECT 1", pretend : false };
					interceptors.announce( "preQBExecute", pending );
					expect( root.getChildren().len() ).toBe( 3 );
					variables.service.shutdown();
					// Active execution keeps completion hooks until it restores the original scope.
					expect( states.preQBExecute.getInterceptors().size() ).toBe( before + 2 );
					interceptors.announce( "postQBExecute", pending );
					expect( root.getChildren().len() ).toBe( 4 );
					expect( telemetry.getScope().span.getContext().span_id ).toBe( root.getContext().span_id );
					expect( telemetry.getScope().keyExists( "manualQuerySpan" ) ).toBeFalse();
					expect( states.preQBExecute.getInterceptors().size() ).toBe( before + 1 );
					extra.shutdown();
					extra.shutdown();
					expect( states.preQBExecute.getInterceptors().size() ).toBe( before );
				} finally {
					if ( extra.keyExists( "shutdown" ) ) extra.shutdown();
					telemetry.clearScope();
				}
			} );
			it( "samples connection backlog without registering a worker pool", function(){
				seed();
				seed( { queue : "other", availableDate : epoch() + 3600 } );
				expect( variables.config.getWorkerPools().keyExists( variables.key ) ).toBeFalse();
				var adapter  = variables.wirebox.getInstance( "QueueHealthAdapter@cbq" );
				var snapshot = adapter.sample( { options : { connection : variables.key } } );
				expect( snapshot.depth ).toBe( 1 );
				expect( snapshot.runnable ).toBe( 1 );
				expect( snapshot.keyExists( "configuredWorkers" ) ).toBeFalse();
				expect( snapshot.keyExists( "activeExecutions" ) ).toBeFalse();
				var allQueues = adapter.sample( { options : { connection : variables.key, queue : "*" } } );
				expect( allQueues.depth ).toBe( 2 );
				expect( allQueues.delayed ).toBe( 1 );
				expect( variables.config.getWorkerPools().keyExists( variables.key ) ).toBeFalse();
			} );
			it( "uses provider-owned table and datasource settings for multiple queues and wildcard snapshots", function(){
				seed( { availableDate : epoch() } );
				seed( { queue : "other", availableDate : epoch() + 3600 } );
				seed( { queue : "mail' OR 1=1 --", availableDate : epoch() } );
				var provider = variables.config.getConnection( variables.key ).getProvider();
				var selected = provider.getQueueHealth( [ "health", "other" ] );
				expect( selected.depth ).toBe( 2 );
				expect( selected.runnable ).toBe( 1 );
				expect( selected.delayed ).toBe( 1 );
				expect( provider.getQueueHealth( "*" ).depth ).toBe( 3 );
				expect( provider.getQueueHealth( [ "*" ] ).depth ).toBe( 3 );
				expect( provider.getQueueHealth( "mail' OR 1=1 --" ).depth ).toBe( 1 );
			} );
			it( "cleans database and worker registries even when draining reports a failure", function(){
				startPool();
				var job = publish( "block" );
				expect(
					job.state.started.await(
						javacast( "long", 5 ),
						createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
					)
				).toBeTrue();
				var executorName = variables.pool.getExecutor().getName();
				var errors       = cleanupFixture( function(){
					throw( type = "InjectedDrainFailure", message = "synthetic drain failure" );
				} );
				expect( errors.len() ).toBe( 1 );
				expect( errors[ 1 ] ).toInclude( "synthetic drain failure" );
				expect( variables.wirebox.getInstance( "SchemaBuilder@qb" ).hasTable( variables.table ) ).toBeFalse();
				expect( variables.config.getWorkerPools().keyExists( variables.key ) ).toBeFalse();
				expect( variables.config.getConnections().keyExists( variables.key ) ).toBeFalse();
				expect( application.cbController.getAsyncManager().hasExecutor( executorName ) ).toBeFalse();
				expect( isNull( variables.state.get( job.runId ) ) ).toBeTrue();
				variables.pool     = javacast( "null", "" );
				variables.service  = javacast( "null", "" );
				variables.taskName = "";
			} );

			it( "executes an empty aggregate and exports measured zeros", function(){
				assertHealth( 0, 0, 0, 0 );
				expect(
					variables.service.captureQueueWorkerHealth( "health", function(){
						return variables.adapter.snapshot( "health" );
					} )
				).toBeTrue();
			} );
			it( "separates runnable, delayed, claimed and expired rows while excluding terminal and other queues", function(){
				var now = epoch();
				seed( { "availableDate" : now } );
				seed( { "availableDate" : now + 3600 } );
				seed( {
					"reservedDate"  : now,
					"reservedBy"    : "worker",
					"availableDate" : now + 3600
				} );
				seed( {
					"reservedDate"  : now - 10,
					"reservedBy"    : "dead-worker",
					"availableDate" : now - 1
				} );
				seed( {
					"reservedBy"    : "staged-worker",
					"availableDate" : now - 1
				} );
				seed( { completedDate : now } );
				seed( { failedDate : now } );
				seed( { queue : "other" } );
				assertHealth( 1, 1, 3, 2 );
				var quoted = "health' OR 1=1 --";
				seed( { queue : quoted } );
				expect( variables.adapter.snapshot( quoted ).runnable ).toBe( 1 );
				assertHealth( 1, 1, 3, 2 );
			} );
			it( "observes real idle and busy worker activity and reserved jobs until completion", function(){
				startPool( 2 );
				var samples   = [];
				var telemetry = prepareMock( variables.service.getObservability() );
				telemetry
					.$( "gauge" )
					.$callback( function( name, value ){
						samples.append( { name : name, value : value } );
					} );
				expect( variables.service.captureCBQWorkerHealth( "health", variables.pool ) ).toBeTrue();
				expect( metric( samples, "queue.executions.active" ) ).toBe( 0 );
				expect( metric( samples, "queue.workers.configured" ) ).toBe( 2 );
				var job = publish( "block" );
				expect(
					job.state.started.await(
						javacast( "long", 5 ),
						createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
					)
				).toBeTrue();
				assertHealth( 0, 0, 1, 0 );
				samples = [];
				expect( variables.service.captureCBQWorkerHealth( "health", variables.pool ) ).toBeTrue();
				expect( metric( samples, "queue.executions.active" ) ).toBe( 1 );
				job.state.release.countDown();
				awaitCondition( function(){
					return hasTimestamp( row( job.id ), "completedDate" );
				} );
				awaitCondition( function(){
					return variables.pool.getExecutor().getActiveCount() == 0;
				} );
				assertHealth( 0, 0, 0, 0 );
				expect( job.state.handled.get() ).toBe( 1 );
			} );
			it( "keeps delayed jobs out of runnable backlog until an actual worker executes them", function(){
				var job = publish( "ok", 2 );
				assertHealth( 0, 1, 0, 0 );
				startPool();
				awaitCondition( function(){
					return hasTimestamp( row( job.id ), "completedDate" );
				} );
				assertHealth( 0, 0, 0, 0 );
				expect( job.state.handled.get() ).toBe( 1 );
			} );
			it( "reports an expired execution lease and observes a real worker reclaim it", function(){
				var job = publish( "ok", 0, 3 );
				jobQuery()
					.where( "id", job.id )
					.update( {
						"reservedBy"    : "dead-worker",
						"reservedDate"  : epoch() - 30,
						"availableDate" : epoch() - 1,
						"attempts"      : 1
					} );
				assertHealth( 0, 0, 1, 1 );
				startPool();
				awaitCondition( function(){
					return hasTimestamp( row( job.id ), "completedDate" );
				} );
				assertHealth( 0, 0, 0, 0 );
				expect( row( job.id ).attempts ).toBe( 2 );
				expect( job.state.handled.get() ).toBe( 1 );
			} );
			it( "reports and reclaims a staged claim whose execution never started", function(){
				var job = publish( "ok" );
				jobQuery()
					.where( "id", job.id )
					.update( {
						"reservedBy"    : "dead-worker",
						"availableDate" : epoch() - 1
					} );
				assertHealth( 0, 0, 1, 1 );
				startPool();
				awaitCondition( function(){
					return hasTimestamp( row( job.id ), "completedDate" );
				} );
				assertHealth( 0, 0, 0, 0 );
				expect( row( job.id ).attempts ).toBe( 1 );
				expect( job.state.handled.get() ).toBe( 1 );
			} );
			it( "observes a real retry returning to delayed backlog before success", function(){
				var job = publish( "retry", 2, 2 );
				startPool();
				awaitCondition( function(){
					var record = row( job.id );
					return record.attempts == 1 && hasTimestamp( record, "lastReleasedDate" ) && variables.adapter.snapshot( "health" ).delayed == 1;
				} );
				assertHealth( 0, 1, 0, 0 );
				awaitCondition( function(){
					return hasTimestamp( row( job.id ), "completedDate" );
				} );
				assertHealth( 0, 0, 0, 0 );
				expect( row( job.id ).attempts ).toBe( 2 );
				expect( job.state.handled.get() ).toBe( 2 );
			} );
			it( "excludes an actual exhausted job from pending and reserved counts", function(){
				var job = publish( "fail", 0, 1 );
				startPool();
				awaitCondition( function(){
					return hasTimestamp( row( job.id ), "failedDate" );
				} );
				assertHealth( 0, 0, 0, 0 );
				expect( job.state.handled.get() ).toBe( 1 );
			} );
		} );
	}
	private function cleanupFixture( any drain = "" ){
		var drainCallback = arguments.drain;
		var errors        = { "messages" : [] };
		cleanupStep( errors, function(){
			if ( !isNull( variables.service ) ) variables.service.shutdown();
		} );
		// Stop polling before releasing blocked jobs. Preserve their state until all workers exit.
		cleanupStep( errors, function(){
			var scheduler = application.cbController.getSchedulerService().getSchedulers()[ "cbScheduler@cbq" ];
			if ( len( variables.taskName ) && scheduler.hasTask( variables.taskName ) )
				scheduler.removeTask( variables.taskName );
		} );
		cleanupStep( errors, function(){
			variables.state.releaseAll();
		} );
		cleanupStep( errors, function(){
			if ( !isNull( variables.pool ) ) {
				try {
					if ( isCustomFunction( drainCallback ) ) {
						drainCallback();
					} else {
						awaitCondition( function(){
							return variables.pool.getExecutor().getActiveCount() == 0 && variables.pool
								.getExecutor()
								.getQueue()
								.isEmpty();
						}, 5000 );
					}
				} finally {
					variables.pool.shutdown( true, 2 );
					if (
						!variables.pool
							.getExecutor()
							.getNative()
							.awaitTermination(
								javacast( "long", 2 ),
								createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
							)
					)
						throw( type = "QueueHealthWorkerShutdownTimeout" );
				}
			}
		} );
		// Each step runs even if draining or another cleanup step fails.
		cleanupStep( errors, function(){
			if ( !isNull( variables.pool ) ) {
				var name  = variables.pool.getExecutor().getName();
				var async = application.cbController.getAsyncManager();
				if ( async.hasExecutor( name ) ) async.deleteExecutor( name );
			}
		} );
		cleanupStep( errors, function(){
			variables.state.clear();
		} );
		cleanupStep( errors, function(){
			variables.config.getWorkerPools().delete( variables.key );
			variables.config.getConnections().delete( variables.key );
		} );
		cleanupStep( errors, function(){
			variables.wirebox.getInstance( "SchemaBuilder@qb" ).dropIfExists( variables.table );
		} );
		cleanupStep( errors, function(){
			if ( !isNull( variables.service ) ) variables.service.shutdown();
		} );

		return errors.messages;
	}

	private function cleanupStep( required struct errors, required function callback ){
		try {
			arguments.callback();
		} catch ( any failure ) {
			arguments.errors.messages.append( failure.message );
		}
	}
	private function jobQuery(){
		return variables.wirebox.getInstance( "QueryBuilder@qb" ).from( variables.table );
	}
	private function epoch(){
		return createObject( "java", "java.time.Instant" ).now().getEpochSecond();
	}
	private function seed( struct changes = {} ){
		var values = {
			"queue"         : "health",
			"payload"       : "{}",
			"attempts"      : 0,
			"availableDate" : epoch(),
			"createdDate"   : epoch()
		};
		for (
			var column in [
				"queue",
				"payload",
				"attempts",
				"availableDate",
				"createdDate",
				"reservedDate",
				"reservedBy",
				"completedDate",
				"failedDate",
				"lastReleasedDate"
			]
		) {
			if ( arguments.changes.keyExists( column ) ) values[ column ] = arguments.changes[ column ];
		}
		jobQuery().insert( values );
	}
	private function row( required any id ){
		return jobQuery().where( "id", arguments.id ).first();
	}
	private function publish(
		required string mode,
		numeric delay       = 0,
		numeric maxAttempts = 2
	){
		var runId = createUUID();
		var state = variables.state.create( runId );
		variables.wirebox
			.getInstance( "cbq@cbq" )
			.dispatch(
				job        : "QueueHealthJob",
				properties : { runId : runId, mode : arguments.mode },
				connection : variables.key,
				queue      : "health",
				backoff    : arguments.delay,
				timeout    : 10,
				maxAttempts: arguments.maxAttempts
			);
		var record = jobQuery().orderBy( "id", "desc" ).first();
		return { id : record.id, state : state, runId : runId };
	}
	private function startPool( numeric quantity = 1 ){
		variables.pool = variables.config.registerWorkerPool(
			name           : variables.key,
			connectionName : variables.key,
			quantity       : arguments.quantity,
			queue          : "health",
			timeout        : 10,
			shutdownTimeout: 2,
			maxAttempts    : 2
		);
		variables.taskName = "cbq:db-watcher:" & variables.pool.getUniqueId();
		application.cbController.getSchedulerService().getSchedulers()[ "cbScheduler@cbq" ].startupTask(
			variables.taskName
		);
	}
	private function assertHealth(
		required numeric runnable,
		required numeric delayed,
		required numeric reserved,
		required numeric stale
	){
		var snapshot = variables.adapter.snapshot( "health" );
		expect( snapshot.runnable ).toBe( arguments.runnable );
		expect( snapshot.delayed ).toBe( arguments.delayed );
		expect( snapshot.reserved ).toBe( arguments.reserved );
		expect( snapshot.staleReservations ).toBe( arguments.stale );
	}
	private function awaitCondition( required function condition, numeric timeout = 12000 ){
		var end = createObject( "java", "java.lang.System" ).nanoTime() + arguments.timeout * 1000000;
		while ( createObject( "java", "java.lang.System" ).nanoTime() < end ) {
			if ( arguments.condition() ) return;
			sleep( 25 );
		}
		throw(
			type    = "QueueHealthConditionTimeout",
			message = "Local queue condition did not become true before timeout"
		);
	}
	private function hasTimestamp( required struct record, required string field ){
		return arguments.record.keyExists( arguments.field ) && !isNull( arguments.record[ arguments.field ] ) && isNumeric(
			arguments.record[ arguments.field ]
		) && arguments.record[ arguments.field ] > 0;
	}
	private function metric( required array samples, required string name ){
		for ( var sample in arguments.samples ) {
			if ( sample.name == arguments.name ) return sample.value;
		}
		return -1;
	}

}
