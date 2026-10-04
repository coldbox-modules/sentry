/** Handles are keyed by immutable execution IDs, never by callback thread or mutable job state. */
component {

	property name      ="sentry" inject="SentryService@sentry";
	variables.attempts = createObject( "java", "java.util.concurrent.ConcurrentHashMap" ).init();
	variables.publishes= createObject( "java", "java.util.concurrent.ConcurrentHashMap" ).init();
	variables.execution= createObject( "java", "java.lang.ThreadLocal" ).init();
	function onCBQJobAdded( event, interceptData ){
		try {
			if ( !variables.sentry.getSettings().enableQueueTracing ) {
				return;
			}
			var job       = arguments.interceptData.job;
			var telemetry = variables.sentry.getObservability();
			for ( var entry in variables.publishes.entrySet() ) {
				if ( telemetry.timestamp() - entry.getValue().created > 3600 ) {
					var expired = variables.publishes.remove( entry.getKey() );
					if ( !isNull( expired ) ) {
						expired.span.finish( "deadline_exceeded" );
						if ( expired.ownsRoot ) {
							expired.root.finish( "deadline_exceeded" );
						}
					}
				}
			}
			var previous = telemetry.getScope();
			var root     = previous.keyExists( "span" ) ? previous.span : telemetry.startTransaction(
				"publish " & ( job.getQueue() ?: "default" ),
				"queue.task"
			);
			telemetry.setScope( { "span" : root } );
			var publish = telemetry.startSpan(
				"publish " & ( job.getQueue() ?: "default" ),
				"queue.publish",
				{ "messaging.destination.name" : job.getQueue() ?: "default" }
			);
			telemetry.setScope( { "span" : publish } );
			var metadata = {
				"headers"    : variables.sentry.getTraceHeaders(),
				"enqueuedAt" : telemetry.timestamp(),
				"publishId"  : telemetry.id()
			};
			telemetry.setScope( previous );
			job.getProperties()[ "__sentry" ] = metadata;
			if ( variables.publishes.size() < 1024 ) {
				variables.publishes.put(
					metadata.publishId,
					{
						"span"     : publish,
						"root"     : root,
						"ownsRoot" : !previous.keyExists( "span" ),
						"created"  : telemetry.timestamp()
					}
				);
			} else {
				publish.finish( "resource_exhausted" );
				if ( !previous.keyExists( "span" ) ) {
					root.finish( "resource_exhausted" );
				}
			}
		} catch ( any ignored ) {
		} finally {
			if ( !isNull( local.previous ) ) {
				telemetry.setScope( previous );
			}
		}
	}
	function onCBQJobPublished( event, interceptData ){
		finishPublish( arguments.interceptData.job, "ok" );
	}
	function onCBQJobPublishException( event, interceptData ){
		finishPublish( arguments.interceptData.job, "internal_error" );
	}
	private function finishPublish( required any job, required string status ){
		try {
			var state = variables.publishes.remove( arguments.job.getProperties()[ "__sentry" ].publishId ?: "" );
			if ( !isNull( state ) ) {
				state.span.finish( arguments.status );
				if ( state.ownsRoot ) {
					state.root.finish( arguments.status );
				}
			}
		} catch ( any ignored ) {
		}
	}
	function onCBQJobAttemptScheduled( event, interceptData ){
		try {
			if ( !variables.sentry.getSettings().enableQueueTracing ) {
				return;
			}
			var telemetry = variables.sentry.getObservability();
			// Bound abandoned work even if a worker never starts after a timeout/shutdown.
			for ( var entry in variables.attempts.entrySet() ) {
				if ( telemetry.timestamp() - entry.getValue().created > 3600 ) {
					entry.getValue().span.finish( "deadline_exceeded" );
					entry.getValue().root.finish( "deadline_exceeded" );
					variables.attempts.remove( entry.getKey() );
				}
			}
			if ( variables.attempts.size() >= 1024 ) {
				return;
			}
			var job      = arguments.interceptData.job;
			var metadata = job.getProperties()[ "__sentry" ] ?: {};
			var root     = telemetry.startTransaction(
				"job " & job.getMapping(),
				"queue.task",
				metadata.headers ?: {},
				true
			);
			var previous = telemetry.getScope();
			var span     = root;
			try {
				telemetry.setScope( { "span" : root } );
				span = telemetry.startSpan( "process " & job.getMapping(), "queue.process" );
			} finally {
				telemetry.setScope( previous );
			}
			span.setAttribute( "messaging.destination.name", job.getQueue() ?: "default" );
			span.setAttribute( "messaging.message.id", toString( job.getId() ) );
			span.setAttribute( "messaging.retry.count", max( 0, arguments.interceptData.attempt - 1 ) );
			span.setAttribute(
				"messaging.message.receive.latency",
				max( 0, ( telemetry.timestamp() - ( metadata.enqueuedAt ?: telemetry.timestamp() ) ) * 1000 )
			);
			variables.attempts.putIfAbsent(
				arguments.interceptData.executionId,
				{
					"span"    : span,
					"root"    : root,
					"exited"  : false,
					"created" : telemetry.timestamp()
				}
			);
		} catch ( any ignored ) {
		}
	}
	function onCBQJobExecutionStarted( event, interceptData ){
		try {
			var attempt = variables.attempts.get( arguments.interceptData.executionId );
			if ( isNull( attempt ) ) {
				return;
			}
			var telemetry = variables.sentry.getObservability();
			var stack     = variables.execution.get() ?: [];
			stack.append( {
				"previous" : telemetry.getScope(),
				"attempt"  : attempt,
				"id"       : arguments.interceptData.executionId
			} );
			variables.execution.set( stack );
			telemetry.setScope( { "span" : attempt.span } );
		} catch ( any ignored ) {
		}
	}
	function onCBQJobExecutionExited( event, interceptData ){
		try {
			var stack = variables.execution.get() ?: [];
			if ( !stack.len() ) {
				return;
			}
			var execution = stack[ stack.len() ];
			if ( execution.id != arguments.interceptData.executionId ) {
				return;
			}
			variables.sentry.getObservability().setScope( execution.previous );
			stack.deleteAt( stack.len() );
			if ( !stack.len() ) {
				variables.execution.remove();
			}
			execution.attempt.exited = true;
			if ( execution.attempt.span.isFinished() ) {
				variables.attempts.remove( execution.id );
			}
		} catch ( any ignored ) {
		}
	}
	function onCBQJobAttemptFinished( event, interceptData ){
		try {
			var attempt = variables.attempts.get( arguments.interceptData.executionId );
			if ( isNull( attempt ) ) {
				return;
			}
			var status = arguments.interceptData.status;
			attempt.span.setAttribute( "messaging.message.released", status == "released" );
			if ( attempt.span.finish( status == "released" ? "ok" : status ) ) {
				var telemetry = variables.sentry.getObservability();
				var previous  = telemetry.getScope();
				try {
					telemetry.setScope( { "span" : attempt.root } );
					variables.sentry.counter( "queue.attempts", 1, { "outcome" : status } );
					variables.sentry.distribution(
						"queue.processing.duration",
						( telemetry.timestamp() - attempt.created ) * 1000,
						{ "outcome" : status },
						"millisecond"
					);
				} finally {
					telemetry.setScope( previous );
				}
				attempt.root.finish( status == "released" ? "ok" : status );
			}
			if ( attempt.exited ) {
				variables.attempts.remove( arguments.interceptData.executionId );
			}
		} catch ( any ignored ) {
		}
	}
	function getPendingAttemptCount(){
		return variables.attempts.size();
	}

}
