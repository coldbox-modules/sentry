/** Framework-independent telemetry; execution scopes are never kept on a singleton. */
component {

	function init( required any owner, required struct settings ){
		variables[ "owner" ]    = arguments.owner;
		variables[ "settings" ] = arguments.settings;
		variables.settings.append( defaults(), false );
		variables.adapterResolver = new AdapterResolver();
		normalizeAutomaticSettings();
		variables.queryAdapterConfigured = false;
		variables.closed                 = createObject( "java", "java.util.concurrent.atomic.AtomicBoolean" ).init( false );
		variables.requests               = new RequestSaturation(
			this,
			variables.settings.maxObservedRequests,
			variables.settings.requestLongRunningSeconds
		);
		variables.dependencies = new MetricLabels( variables.settings.dependencyNames );
		variables.executors    = new HealthSampler(
			this,
			variables.settings.requestExecutorNames,
			{
				"active"   : { "name" : "http.server.executor.active", "unit" : "none" },
				"max"      : { "name" : "http.server.executor.max", "unit" : "none" },
				"queued"   : { "name" : "http.server.executor.queued", "unit" : "none" },
				"rejected" : {
					"name" : "http.server.executor.rejected.total",
					"unit" : "none"
				}
			},
			"executor.name"
		);
		variables.workers = new HealthSampler(
			this,
			variables.settings.queueWorkerNames,
			{
				"configuredWorkers" : { "name" : "queue.workers.configured", "unit" : "none" },
				"activeWorkers"     : { "name" : "queue.workers.active", "unit" : "none" },
				"activeExecutions"  : { "name" : "queue.executions.active", "unit" : "none" },
				"lastHeartbeatAt"   : { "name" : "queue.worker.heartbeat_age", "unit" : "second" },
				"runnable"          : { "name" : "queue.backlog.runnable", "unit" : "none" },
				"delayed"           : { "name" : "queue.backlog.delayed", "unit" : "none" },
				"reserved"          : { "name" : "queue.backlog.reserved", "unit" : "none" },
				"staleReservations" : { "name" : "queue.reservations.stale", "unit" : "none" },
				"retries"           : { "name" : "queue.retries.total", "unit" : "none" },
				"exhausted"         : { "name" : "queue.exhausted.total", "unit" : "none" }
			},
			"worker.name"
		);
		variables.delivery                = new DeliveryDiagnostics( variables.settings.maxPendingEnvelopes );
		variables[ "scope" ]              = createObject( "java", "java.lang.ThreadLocal" ).init();
		variables[ "completionFailures" ] = createObject( "java", "java.util.concurrent.atomic.AtomicLong" ).init(
			0
		);
		variables[ "sequence" ]  = createObject( "java", "java.util.concurrent.atomic.AtomicLong" ).init( 0 );
		variables[ "transport" ] = new EnvelopeTransport(
			variables.settings,
			owner.getSentryUrl() & "/api/" & owner.getProjectID() & "/envelope/",
			"Sentry sentry_version=7,sentry_key=" & owner.getPublicKey() & ",sentry_client=sentry.cfml/3.0.0",
			owner.getEnabled()
		);
		variables[ "buffers" ]  = { "log" : [], "trace_metric" : [] };
		variables[ "bufferId" ] = createUUID();
		if ( variables.settings.enableLogs || variables.settings.enableMetrics ) {
			variables.flusher = createObject( "java", "java.util.concurrent.Executors" ).newSingleThreadScheduledExecutor();
			variables.flusher.scheduleWithFixedDelay(
				createDynamicProxy( new SignalFlusher( this ), [ "java.lang.Runnable" ] ),
				javacast( "long", 5 ),
				javacast( "long", 5 ),
				createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
			);
		}
		variables.collectors = new AutomaticCollectors(
			this,
			variables.settings.automaticCollectors,
			variables.adapterResolver
		);
		if ( collectionEnabled() ) variables.collectors.start();
		return this;
	}
	function defaults(){
		return {
			"tracesSampleRate"               : 0,
			"maxSpans"                       : 1000,
			"transportTimeout"               : 2000,
			"maxPendingEnvelopes"            : 64,
			"enableDeliveryDiagnostics"      : false,
			"enableRequestTracing"           : false,
			"enableRequestSaturation"        : false,
			"maxObservedRequests"            : 4096,
			"requestLongRunningSeconds"      : 30,
			"requestExecutorNames"           : [],
			"dependencyNames"                : [],
			"queueWorkerNames"               : [],
			"queryAdapter"                   : "none",
			"enableQueueTracing"             : false,
			"enableQueueJobMetrics"          : false,
			"queueMetricDestinations"        : [],
			"enableLogs"                     : false,
			"enableStructuredLogBoxAppender" : false,
			"logMessageMode"                 : "sanitized",
			"enableMetrics"                  : false,
			"enableMonitors"                 : false,
			"monitorSlugs"                   : [],
			"beforeSendSignal"               : "",
			"beforeSendFeedback"             : "",
			"tracePropagationTargets"        : [],
			"browser"                        : {},
			"trustIncomingTrace"             : false,
			"requestFilter"                  : "",
			"attributeFilter"                : "",
			"enableAutomaticRequestTimings"  : false,
			"publishServerTiming"            : false,
			"serverTimingFilter"             : "",
			"automaticCollectors"            : {
				enabled             : false,
				intervalSeconds     : 60,
				runtime             : true,
				requestSaturation   : true,
				deliveryDiagnostics : false,
				queueWorkers        : [],
				databaseQueues      : [],
				requestExecutors    : [],
				databasePools       : []
			},
			"dependencyAdapters"              : [],
			"dependencyAdapterGenerationPath" : "/coldbox/system/aop/tmp",
			"requestTimingNames"              : [],
			"operationNames"                  : [],
			"providerNames"                   : [],
			"databasePoolNames"               : []
		};
	}
	function registerBoxLangQueries( required string applicationName, string databaseSystem = "other" ){
		var runtime  = createObject( "java", "ortus.boxlang.runtime.BoxRuntime" ).getInstance();
		var listener = new BoxLangQueryListener(
			this,
			arguments.applicationName,
			arguments.databaseSystem
		);
		runtime.getInterceptorService().register( listener );
		variables.nativeQueryListener = listener;
		return listener;
	}
	function configureQueryInstrumentation( required string applicationName ){
		if ( variables.queryAdapterConfigured ) return variables.settings.queryAdapter;
		variables.queryAdapterConfigured = true;
		var selected                     = variables.settings.queryAdapter;
		if ( !isSimpleValue( selected ) || !listFind( "none,qb,lucee,auto,boxlang", selected ) ) {
			try {
				var configured = variables.adapterResolver.call(
					selected,
					"configure",
					{
						"context" : {
							"telemetry"       : this,
							"applicationName" : arguments.applicationName
						}
					}
				);
				if ( isStruct( configured ) ) {
					if ( configured.keyExists( "shutdown" ) && isCustomFunction( configured.shutdown ) )
						variables.queryAdapterShutdown = configured.shutdown;
					selected = configured.mode;
				} else {
					selected = configured;
				}
				if ( !isSimpleValue( selected ) || !listFind( "none,qb,lucee,auto,boxlang,custom", selected ) )
					selected = "none";
			} catch ( any unavailable ) {
				selected = "none";
			}
		}
		variables.settings.queryAdapter = selected;
		if ( selected == "auto" || selected == "boxlang" ) {
			try {
				createObject( "java", "ortus.boxlang.runtime.events.BoxEvent" ).valueOf( "ON_QUERY_EXECUTE_ERROR" );
				registerBoxLangQueries( arguments.applicationName, variables.settings.databaseSystem ?: "other" );
				variables.settings.queryAdapter = "boxlang";
			} catch ( any unavailable ) {
				variables.settings.queryAdapter = "qb";
			}
		}
		return variables.settings.queryAdapter;
	}
	function setAdapterInjector( required any injector ){
		variables.adapterResolver.setInjector( arguments.injector );
		return this;
	}
	function collectionEnabled(){
		return variables.settings.enableMetrics && variables.owner.getEnabled();
	}
	function automaticCollectorDiagnostics(){
		return variables.collectors.diagnostics();
	}
	function collectAutomaticMetrics(){
		variables.collectors.tick();
	}
	function startAutomaticCollectors(){
		if ( collectionEnabled() ) return variables.collectors.start();
		return false;
	}
	private function normalizeAutomaticSettings(){
		var collectorDefaults = defaults().automaticCollectors;
		if ( !isStruct( variables.settings.automaticCollectors ) )
			variables.settings.automaticCollectors = { "enabled" : false };
		variables.settings.automaticCollectors.append( collectorDefaults, false );
		for (
			var flag in [
				"enabled",
				"runtime",
				"requestSaturation",
				"deliveryDiagnostics"
			]
		) {
			if ( !isBoolean( variables.settings.automaticCollectors[ flag ] ) )
				variables.settings.automaticCollectors[ flag ] = collectorDefaults[ flag ];
		}
		for (
			var kind in [
				"queueWorkers",
				"databaseQueues",
				"requestExecutors",
				"databasePools"
			]
		) {
			if ( !isArray( variables.settings.automaticCollectors[ kind ] ) )
				variables.settings.automaticCollectors[ kind ] = [];
		}
		if ( !isArray( variables.settings.dependencyAdapters ) ) variables.settings.dependencyAdapters = [];
		variables.dependencyRules = [];
		for ( var i = 1; i <= min( 32, variables.settings.dependencyAdapters.len() ); i++ ) {
			var rule = variables.settings.dependencyAdapters[ i ];
			if (
				!isStruct( rule ) || !rule.keyExists( "name" ) || !rule.keyExists( "mapping" ) || !rule.keyExists( "methods" ) || !isSimpleValue(
					rule.name
				) || !isSimpleValue( rule.mapping ) || !isArray( rule.methods )
			)
				continue;
			if (
				!new MetricLabels( [ rule.name ] ).contains( rule.name ) || !len( rule.mapping ) || reFind(
					"[^A-Za-z0-9_.@:/-]",
					rule.mapping
				)
			)
				continue;
			var methods = [];
			for ( var method in rule.methods ) {
				if (
					!isNull( method ) && isSimpleValue( method ) && methods.len() < 16 && len( method ) && !reFind(
						"[^A-Za-z0-9_]",
						method
					) && !arrayFindNoCase( methods, method )
				)
					methods.append( method );
			}
			if ( methods.len() )
				variables.dependencyRules.append( {
					"name"     : rule.name,
					"mapping"  : rule.mapping,
					"methods"  : methods,
					"classify" : rule.classify ?: ""
				} );
		}
		addAdapterNames( "dependencyNames", variables.dependencyRules );
		addAdapterNames( "queueWorkerNames", variables.settings.automaticCollectors.queueWorkers );
		addAdapterNames( "queueWorkerNames", variables.settings.automaticCollectors.databaseQueues );
		addAdapterNames( "requestExecutorNames", variables.settings.automaticCollectors.requestExecutors );
		addAdapterNames( "databasePoolNames", variables.settings.automaticCollectors.databasePools );
	}
	private function addAdapterNames( required string setting, required array definitions ){
		var names = variables.settings[ arguments.setting ];
		for ( var i = 1; i <= min( 32, arguments.definitions.len() ); i++ ) {
			var definition = arguments.definitions[ i ];
			if (
				isStruct( definition ) && definition.keyExists( "name" ) && isSimpleValue( definition.name ) && names.len() < 32 && new MetricLabels( [ definition.name ] ).contains(
					definition.name
				) && !arrayFindNoCase( names, definition.name )
			)
				names.append( definition.name );
		}
		variables.settings[ arguments.setting ] = names;
	}
	function dependencyBindings(){
		var result = [];
		for ( var rule in variables.dependencyRules )
			result.append( {
				"mapping" : rule.mapping,
				"methods" : duplicate( rule.methods )
			} );
		return result;
	}
	function dependencyRule( required string mapping, required string method ){
		for ( var rule in variables.dependencyRules ) {
			if (
				compareNoCase( rule.mapping, arguments.mapping ) == 0 && arrayFindNoCase(
					rule.methods,
					arguments.method
				)
			)
				return rule;
		}
		return {};
	}
	function finishRequestTimings( required struct state, string status = "ok" ){
		try {
			if ( !arguments.state.keyExists( "timings" ) ) return;
			for ( var token in arguments.state.handlerTokens )
				arguments.state.timings.finish( token, arguments.status );
			arguments.state.handlerTokens = [];
			if ( arguments.state.keyExists( "renderToken" ) ) {
				arguments.state.timings.finish( arguments.state.renderToken, arguments.status );
				arguments.state.delete( "renderToken" );
			}
		} catch ( any unavailable ) {
		}
	}
	function getRequestTimings(){
		var scope = getScope();
		if ( scope.keyExists( "requestState" ) && scope.requestState.keyExists( "timings" ) )
			return scope.requestState.timings;
		return javacast( "null", "" );
	}

	function percentageEligible(
		required string key,
		required string opaqueId,
		required numeric percentage
	){
		if ( !len( arguments.opaqueId ) || arguments.percentage <= 0 ) {
			return false;
		}
		if ( arguments.percentage >= 100 ) {
			return true;
		}
		var prefix = left( hash( arguments.key & ":" & lCase( arguments.opaqueId ), "SHA-256" ), 8 );
		return ( inputBaseN( prefix, 16 ) % 100 ) + 1 <= arguments.percentage;
	}
	function getMaxSpans(){
		return variables.settings.maxSpans;
	}
	function timestamp(){
		return createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000;
	}
	function id(){
		return lCase( replace( createUUID(), "-", "", "all" ) );
	}
	function responseStatus(){
		try {
			return getPageContext().getResponse().getStatus();
		} catch ( any ignored ) {
		}
		try {
			return getBoxContext().getResponse().getStatus();
		} catch ( any ignored ) {
		}
		return 200;
	}
	function endRequest( numeric statusCode = 0, boolean timedOut = false ){
		var current = getScope();
		if ( !current.keyExists( "requestState" ) ) {
			return;
		}
		try {
			finishRequestTimings( current.requestState, arguments.timedOut ? "deadline_exceeded" : "ok" );
			if ( current.requestState.keyExists( "span" ) ) {
				var span = current.requestState.span;
				if ( !span.isFinished() ) {
					var code = arguments.statusCode > 0 ? arguments.statusCode : responseStatus();
					span.setAttribute( "http.response.status_code", code );
					if ( code >= 500 ) {
						span.setStatus( "internal_error" );
					}
					counter(
						"http.server.requests",
						1,
						{
							"route"                     : span.toPayload().description,
							"http.response.status_code" : code
						}
					);
					distribution(
						"http.server.duration",
						max( 0, timestamp() - span.toPayload().start_timestamp ) * 1000,
						{ "route" : span.toPayload().description },
						"millisecond"
					);
					span.finish();
					flushSignals();
				}
			}
		} finally {
			try {
				if ( current.requestState.keyExists( "saturationToken" ) )
					finishRequestObservation( current.requestState.saturationToken, arguments.timedOut );
			} catch ( any unavailable ) {
			}
			setScope( current.requestState.previous );
		}
	}
	function getScope(){
		return variables.scope.get() ?: {};
	}
	function setScope( required struct scope ){
		variables.scope.set( arguments.scope );
	}
	function clearScope(){
		variables.scope.remove();
	}
	function startTransaction(
		required string name,
		string op       = "http.server",
		struct headers  = {},
		boolean trusted = false
	){
		var parent  = arguments.trusted ? parseHeaders( arguments.headers ) : {};
		var sampled = variables.owner.getEnabled() && (
			parent.keyExists( "sampled" ) ? parent.sampled : rand() < variables.settings.tracesSampleRate
		);
		var data = {
			"trace_id"        : parent.trace_id ?: id(),
			"span_id"         : left( id(), 16 ),
			"op"              : arguments.op,
			"description"     : safeName( arguments.name ),
			"start_timestamp" : timestamp(),
			"status"          : "ok",
			"data"            : {}
		};
		if ( parent.keyExists( "parent_span_id" ) ) {
			data[ "parent_span_id" ] = parent.parent_span_id;
		}
		return new Span( this, data, sampled ).setBaggage( parent.baggage ?: "" );
	}
	function startSpan(
		required string name,
		string op         = "function",
		struct attributes = {}
	){
		var current = getScope();
		if ( !current.keyExists( "span" ) || current.span.isFinished() ) {
			return new Span(
				this,
				{
					"trace_id"    : id(),
					"span_id"     : left( id(), 16 ),
					"op"          : arguments.op,
					"description" : arguments.op == "db.query" ? scrubSQL( arguments.name ) : safeName(
						arguments.name
					),
					"start_timestamp" : timestamp(),
					"data"            : {},
					"status"          : "ok"
				},
				false
			);
		}
		var parent = current.span.getContext();
		return new Span(
			this,
			{
				"trace_id"       : parent.trace_id,
				"span_id"        : left( id(), 16 ),
				"parent_span_id" : parent.span_id,
				"op"             : arguments.op,
				"description"    : arguments.op == "db.query" ? scrubSQL( arguments.name ) : safeName(
					arguments.name
				),
				"start_timestamp" : timestamp(),
				"status"          : "ok",
				"data"            : sanitizeAttributes( arguments.attributes )
			},
			current.span.isSampled(),
			current.span.getRoot()
		);
	}
	function withSpan(
		required string name,
		required function callback,
		string op         = "function",
		struct attributes = {}
	){
		var previous = getScope();
		var span     = startSpan(
			arguments.name,
			arguments.op,
			arguments.attributes
		);
		var next       = structCopy( previous );
		next[ "span" ] = span;
		setScope( next );
		try {
			return arguments.callback( span );
		} catch ( any failure ) {
			span.setStatus( "internal_error" );
			rethrow;
		} finally {
			setScope( previous );
			finishSafely( span );
		}
	}
	function withTraceContext(
		required struct context,
		required function callback,
		string name = "background",
		string op   = "task"
	){
		var previous = getScope();
		var span     = startTransaction(
			arguments.name,
			arguments.op,
			arguments.context,
			true
		);
		setScope( { "span" : span } );
		try {
			return arguments.callback( span );
		} catch ( any failure ) {
			span.setStatus( "internal_error" );
			rethrow;
		} finally {
			setScope( previous );
			finishSafely( span );
		}
	}
	private function finishSafely( required any span ){
		try {
			arguments.span.finish();
		} catch ( any unavailable ) {
			variables.completionFailures.incrementAndGet();
		}
	}
	function getCompletionFailureCount(){
		return variables.completionFailures.get();
	}
	function getTraceHeaders( string url = "" ){
		if ( len( arguments.url ) && !isPropagationTarget( arguments.url ) ) {
			return {};
		}
		var current = getScope();
		if ( !current.keyExists( "span" ) ) {
			return {};
		}
		var context = current.span.getContext();
		var baggage = current.span.getBaggage();
		if ( !find( "sentry-public_key=", baggage ) ) {
			baggage = listAppend( baggage, "sentry-public_key=" & variables.owner.getPublicKey() );
		}
		return {
			"sentry-trace" : context.trace_id & "-" & context.span_id & "-" & ( context.sampled ? "1" : "0" ),
			"baggage"      : baggage & ",sentry-trace_id=" & context.trace_id & ",sentry-sampled=" & (
				context.sampled ? "true" : "false"
			)
		};
	}
	function parseHeaders( required struct headers ){
		var trace = headers[ "sentry-trace" ] ?: "";
		if (
			!reFindNoCase( "^[a-f0-9]{32}-[a-f0-9]{16}(-[01])?$", trace ) || reFind(
				"^0{32}-|^[^-]+-0{16}",
				trace
			)
		) {
			return {};
		}
		var parts  = listToArray( trace, "-" );
		var result = {
			"trace_id"       : lCase( parts[ 1 ] ),
			"parent_span_id" : lCase( parts[ 2 ] )
		};
		if ( parts.len() == 3 ) {
			result[ "sampled" ] = parts[ 3 ] == "1";
		}
		var members = [];
		for ( var member in listToArray( left( arguments.headers[ "baggage" ] ?: "", 8192 ) ) ) {
			// Carry trusted, technical dynamic sampling context only; never a raw transaction/user label.
			if (
				reFind(
					"^sentry-(public_key|release|environment|sample_rate|sample_rand)=[A-Za-z0-9._%+-]{1,256}$",
					trim( member )
				)
			) {
				members.append( trim( member ) );
			}
		}
		result[ "baggage" ] = members.toList();
		return result;
	}
	function getTraceContext(){
		var current = getScope();
		return current.keyExists( "span" ) ? current.span.getContext() : {};
	}
	function completeTransaction( required any transaction ){
		try {
			var data                   = arguments.transaction.toPayload();
			var event                  = baseEvent();
			event[ "type" ]            = "transaction";
			event[ "transaction" ]     = data.description;
			event[ "start_timestamp" ] = data.start_timestamp;
			event[ "timestamp" ]       = data.timestamp;
			event[ "contexts" ]        = {
				"trace" : {
					"trace_id" : data.trace_id,
					"span_id"  : data.span_id,
					"op"       : data.op,
					"status"   : data.status,
					"data"     : data.data
				}
			};
			if ( data.keyExists( "parent_span_id" ) ) {
				event.contexts.trace[ "parent_span_id" ] = data.parent_span_id;
			}
			event[ "spans" ] = [];
			for ( var child in arguments.transaction.getChildren() ) {
				if ( event.spans.len() < variables.settings.maxSpans ) {
					event.spans.append( child.toPayload() );
				}
			}
			sendSignal( "transaction", event, "transaction" );
		} catch ( any ignored ) {
		}
	}
	function baseEvent(){
		return {
			"event_id"    : id(),
			"timestamp"   : timestamp(),
			"platform"    : "cfml",
			"release"     : variables.settings.release,
			"environment" : variables.settings.environment
		};
	}
	function sendSignal(
		required string type,
		required struct payload,
		required string category,
		array attachments = [],
		boolean wait      = false
	){
		var receipt = sendSignalReceipt( argumentCollection = arguments );
		if ( variables.settings.enableDeliveryDiagnostics ) {
			try {
				variables.delivery.record( receipt );
			} catch ( any unavailable ) {
				variables.completionFailures.incrementAndGet();
			}
		}
		return receipt;
	}
	function deliveryDiagnostics(){
		var result          = variables.delivery.snapshot();
		result[ "enabled" ] = variables.settings.enableDeliveryDiagnostics;
		return result;
	}
	function newRequestTimings( boolean automatic = false ){
		var names = arguments.automatic ? [ "handler", "render" ] : [];
		for ( var name in variables.settings.requestTimingNames ) {
			// RequestTimings owns validation and deduplication for both manual and automatic names.
			if ( !isNull( name ) ) names.append( name );
		}
		return new RequestTimings( this, names, 64, arguments.automatic );
	}

	/** Consumer supplies a supported pool adapter. Never inspect engine internals or JDBC credentials. */
	function captureDatabasePool( required string name, required function sample ){
		if ( !variables.settings.enableMetrics || !variables.settings.databasePoolNames.find( arguments.name ) ) {
			return false;
		}
		try {
			var values = arguments.sample();
			var fields = {
				"active"   : "db.pool.active",
				"idle"     : "db.pool.idle",
				"max"      : "db.pool.max",
				"waiters"  : "db.pool.waiters",
				"timeouts" : "db.pool.timeouts.total"
			};
			for ( var field in fields ) {
				if ( values.keyExists( field ) && isNumeric( values[ field ] ) && values[ field ] >= 0 ) {
					gauge(
						fields[ field ],
						values[ field ],
						{ "db.pool.name" : arguments.name }
					);
				}
			}
			if (
				values.keyExists( "active" ) && values.keyExists( "max" ) && isNumeric( values.active ) && isNumeric(
					values.max
				) && values.max > 0 && values.active >= 0 && values.active <= values.max
			) {
				gauge(
					"db.pool.utilization",
					values.active / values.max,
					{ "db.pool.name" : arguments.name },
					"ratio"
				);
			}
			return true;
		} catch ( any unavailable ) {
			return false;
		}
	}
	function beginRequestObservation(){
		if (
			!variables.settings.enableMetrics || !variables.settings.enableRequestSaturation || !variables.owner.getEnabled()
		)
			return {};
		try {
			return variables.requests.begin();
		} catch ( any unavailable ) {
			return {};
		}
	}
	function finishRequestObservation( required struct token, boolean timedOut = false ){
		try {
			return variables.requests.finish( argumentCollection = arguments );
		} catch ( any unavailable ) {
			return false;
		}
	}
	function requestSaturation(){
		return variables.requests.snapshot();
	}
	function captureRequestSaturation(){
		if (
			!variables.settings.enableMetrics || !variables.settings.enableRequestSaturation || !variables.owner.getEnabled()
		)
			return {};
		try {
			return variables.requests.capture();
		} catch ( any unavailable ) {
			return {};
		}
	}
	function captureRequestExecutor( required string name, required function sample ){
		if ( !variables.settings.enableMetrics || !variables.owner.getEnabled() ) return false;
		return variables.executors.capture( argumentCollection = arguments );
	}
	function requestExecutorDiagnostics( required string name ){
		return variables.executors.diagnostics( arguments.name );
	}
	function captureQueueWorkerHealth( required string name, required function sample ){
		if ( !variables.settings.enableMetrics || !variables.owner.getEnabled() ) return false;
		return variables.workers.capture( argumentCollection = arguments );
	}
	function queueWorkerDiagnostics( required string name ){
		return variables.workers.diagnostics( arguments.name );
	}
	function captureCBQWorkerHealth( required string name, required any pool ){
		var workerPool = arguments.pool;
		return captureQueueWorkerHealth( arguments.name, function(){
			var sample = { "configuredWorkers" : workerPool.getQuantity() };
			try {
				// ColdBox's unsupported getActiveCount fallback is zero; require the taskMethods capability.
				var stats = workerPool.getExecutor().getStats();
				if (
					stats.keyExists( "features" ) && stats.features.keyExists( "taskMethods" ) && stats.features.taskMethods && stats.keyExists( "activeCount" )
				)
					sample[ "activeExecutions" ] = stats.activeCount;
			} catch ( any unavailable ) {
			}
			return sample;
		} );
	}

	function withDependency(
		required string name,
		required function callback,
		any classify = ""
	){
		if (
			!variables.settings.enableMetrics || !variables.owner.getEnabled() || !variables.dependencies.contains(
				arguments.name
			)
		)
			return arguments.callback();
		var scope = {};
		try {
			scope = getScope();
		} catch ( any unavailable ) {
			return arguments.callback();
		}
		if ( scope.keyExists( "dependencyObservations" ) && scope.dependencyObservations.find( arguments.name ) )
			return arguments.callback();
		var classifier = arguments.classify;
		if ( !isCustomFunction( classifier ) && ( !isSimpleValue( classifier ) || len( classifier ) ) ) {
			var descriptor = classifier;
			classifier     = function( result, failure ){
				return variables.adapterResolver.call(
					descriptor,
					"classify",
					{
						"result"  : isNull( arguments.result ) ? javacast( "null", "" ) : arguments.result,
						"failure" : isNull( arguments.failure ) ? javacast( "null", "" ) : arguments.failure
					}
				);
			};
		}
		return new Dependency( this ).run( arguments.name, arguments.callback, classifier );
	}

	function withOperation(
		required string name,
		required function callback,
		string provider = "",
		any classify    = ""
	){
		if (
			!variables.settings.operationNames.find( arguments.name ) || (
				len( arguments.provider ) && !variables.settings.providerNames.find( arguments.provider )
			)
		) {
			return arguments.callback();
		}
		return new Operation( this ).run( argumentCollection = arguments );
	}
	private function sendSignalReceipt(
		required string type,
		required struct payload,
		required string category,
		array attachments = [],
		boolean wait      = false
	){
		var data = arguments.payload;
		try {
			var filter = arguments.type == "feedback" ? variables.settings.beforeSendFeedback : variables.settings.beforeSendSignal;
			if ( isCustomFunction( filter ) ) {
				data = filter( data, arguments.type );
				if ( isNull( data ) ) {
					return new Receipt( arguments.payload.event_id ?: id(), "filtered" );
				}
			}
			var items = [ { "type" : arguments.type, "payload" : data } ];
			for ( var attachment in arguments.attachments ) {
				if ( !isBinary( attachment.data ) || arrayLen( attachment.data ) > 2097152 ) {
					return new Receipt( data.event_id ?: id(), "invalid" );
				}
				items.append( {
					"type"    : "attachment",
					"payload" : attachment.data,
					"headers" : {
						"filename" : reReplace(
							attachment.filename ?: "attachment.bin",
							"[^a-zA-Z0-9._-]",
							"_",
							"all"
						),
						"content_type" : attachment.contentType ?: "application/octet-stream"
					}
				} );
			}
			return variables.transport.send(
				data.event_id ?: id(),
				items,
				arguments.category,
				arguments.wait
			);
		} catch ( any ignored ) {
			return new Receipt( arguments.payload.event_id ?: id(), "failed" );
		}
	}
	function captureFeedback(
		required string message,
		string page              = "",
		string associatedEventId = "",
		string replayId          = "",
		array attachments        = [],
		boolean wait             = false
	){
		var data           = baseEvent();
		data[ "type" ]     = "feedback";
		data[ "level" ]    = "info";
		data[ "contexts" ] = {
			"feedback" : {
				"message" : trim( arguments.message ),
				"url"     : safePageURL( arguments.page )
			}
		};
		if ( len( arguments.associatedEventId ) ) {
			if ( !reFindNoCase( "^[a-f0-9]{32}$", arguments.associatedEventId ) ) {
				return new Receipt( data.event_id, "invalid" );
			}
			data.contexts.feedback[ "associated_event_id" ] = arguments.associatedEventId;
		}
		if ( len( arguments.replayId ) ) {
			if ( !reFindNoCase( "^[a-f0-9]{32}$", arguments.replayId ) ) {
				return new Receipt( data.event_id, "invalid" );
			}
			data.contexts.feedback[ "replay_id" ] = arguments.replayId;
		}
		var context = getTraceContext();
		if ( !context.isEmpty() ) {
			data.contexts[ "trace" ] = context;
		}
		if (
			!len( data.contexts.feedback.message ) || createObject( "java", "java.lang.String" )
				.init( data.contexts.feedback.message )
				.codePointCount( 0, len( data.contexts.feedback.message ) ) > 4096
		) {
			return new Receipt( data.event_id, "invalid" );
		}
		return sendSignal(
			"feedback",
			data,
			"user_report",
			arguments.attachments,
			arguments.wait
		);
	}
	function withQuerySpan(
		required string sql,
		required function callback,
		string databaseSystem  = "other",
		boolean cached         = false,
		boolean queryOfQueries = false
	){
		var queryCallback = arguments.callback;
		return withSpan(
			scrubSQL( arguments.sql ),
			function( span ){
				var previous         = getScope();
				var next             = structCopy( previous );
				next.manualQuerySpan = span;
				setScope( next );
				try {
					return queryCallback( span );
				} finally {
					setScope( previous );
				}
			},
			arguments.queryOfQueries ? "db.query.qoq" : ( arguments.cached ? "db.query.cache" : "db.query" ),
			{
				"db.system"    : arguments.databaseSystem,
				"db.operation" : uCase( listFirst( trim( arguments.sql ), " " ) ),
				"db.cached"    : arguments.cached
			}
		);
	}
	function withHttpSpan(
		required string url,
		required function callback,
		string method = "GET"
	){
		var destination  = safeURL( arguments.url );
		var headers      = getTraceHeaders( arguments.url );
		var httpCallback = arguments.callback;
		return withSpan(
			arguments.method & " " & destination,
			function( span ){
				return httpCallback( span, headers );
			},
			"http.client",
			{
				"http.request.method" : arguments.method,
				"server.address"      : destination
			}
		);
	}
	function isPropagationTarget( required string url ){
		try {
			var destination = createObject( "java", "java.net.URI" ).create( arguments.url );
			for ( var target in variables.settings.tracePropagationTargets ) {
				var trusted = createObject( "java", "java.net.URI" ).create( target );
				if (
					destination.getScheme() == trusted.getScheme() && destination.getHost() == trusted.getHost() && destination.getPort() == trusted.getPort() && isNull(
						destination.getUserInfo()
					)
				) {
					return true;
				}
			}
		} catch ( any ignored ) {
		}
		return false;
	}
	function captureLog(
		required string message,
		string level      = "info",
		struct attributes = {}
	){
		if ( !variables.settings.enableLogs ) {
			return;
		}
		var levels = {
			"info"    : 9,
			"warn"    : 13,
			"warning" : 13,
			"error"   : 17,
			"fatal"   : 21
		};
		if ( !levels.keyExists( lCase( arguments.level ) ) ) {
			return;
		}
		var data = {
			"timestamp"       : timestamp(),
			"level"           : lCase( arguments.level ),
			"severity_number" : levels[ lCase( arguments.level ) ],
			"body"            : sanitizeText( arguments.message ),
			"attributes"      : typedAttributes( arguments.attributes )
		};
		var context        = getTraceContext();
		data[ "trace_id" ] = context.trace_id ?: id();
		if ( context.keyExists( "span_id" ) ) {
			data[ "span_id" ] = context.span_id;
		}
		bufferSignal( "log", data );
	}
	function counter(
		required string name,
		numeric value     = 1,
		struct attributes = {},
		string unit       = "none"
	){
		metric( type = "counter", argumentCollection = arguments );
	}
	function gauge(
		required string name,
		required numeric value,
		struct attributes = {},
		string unit       = "none"
	){
		metric( type = "gauge", argumentCollection = arguments );
	}
	function distribution(
		required string name,
		required numeric value,
		struct attributes = {},
		string unit       = "none"
	){
		metric( type = "distribution", argumentCollection = arguments );
	}
	private function metric(
		required string type,
		required string name,
		required numeric value,
		struct attributes = {},
		string unit       = "none"
	){
		if ( !variables.settings.enableMetrics ) {
			return;
		}
		var attrs                            = typedAttributes( arguments.attributes );
		attrs[ "sentry.timestamp.sequence" ] = {
			"type"  : "integer",
			"value" : variables.sequence.getAndIncrement()
		};
		var data = {
			"timestamp"  : timestamp(),
			"name"       : safeName( arguments.name ),
			"value"      : arguments.value,
			"type"       : arguments.type,
			"unit"       : arguments.unit,
			"attributes" : attrs
		};
		var context        = getTraceContext();
		data[ "trace_id" ] = context.trace_id ?: id();
		if ( context.keyExists( "span_id" ) ) {
			data[ "span_id" ] = context.span_id;
		}
		bufferSignal( "trace_metric", data );
	}
	private function bufferSignal( required string type, required struct entry ){
		lock name="sentry-buffer-#variables.bufferId#" type="exclusive" timeout="2" {
			variables.buffers[ arguments.type ].append( arguments.entry );
			if ( variables.buffers[ arguments.type ].len() >= 100 ) {
				flushSignals();
			}
		}
	}
	function flushSignals(){
		lock name="sentry-buffer-#variables.bufferId#" type="exclusive" timeout="2" {
			for ( var type in variables.buffers ) {
				if ( !variables.buffers[ type ].isEmpty() ) {
					var items                 = variables.buffers[ type ];
					variables.buffers[ type ] = [];
					sendSignal(
						type,
						{ "items" : items },
						type == "log" ? "log_item" : "metric"
					);
				}
			}
		}
	}
	function captureCheckIn(
		required string slug,
		required string status,
		string checkInId     = "",
		numeric duration     = 0,
		struct monitorConfig = {}
	){
		var checkId = len( arguments.checkInId ) ? arguments.checkInId : id();
		if (
			!variables.settings.enableMonitors || (
				variables.settings.monitorSlugs.len() && !variables.settings.monitorSlugs.find( arguments.slug )
			)
		) {
			return checkId;
		}
		var data = {
			"check_in_id"  : checkId,
			"monitor_slug" : arguments.slug,
			"status"       : arguments.status,
			"environment"  : variables.settings.environment,
			"release"      : variables.settings.release,
			"duration"     : arguments.duration
		};
		if ( !arguments.monitorConfig.isEmpty() ) {
			data[ "monitor_config" ] = arguments.monitorConfig;
		}
		sendSignal( "check_in", data, "monitor" );
		return checkId;
	}
	function withMonitor(
		required string slug,
		required function callback,
		struct monitorConfig = {}
	){
		var checkId = captureCheckIn(
			arguments.slug,
			"in_progress",
			"",
			0,
			arguments.monitorConfig
		);
		var started = timestamp();
		try {
			var result = arguments.callback();
			captureCheckIn(
				arguments.slug,
				"ok",
				checkId,
				timestamp() - started
			);
			return result;
		} catch ( any failure ) {
			captureCheckIn(
				arguments.slug,
				"error",
				checkId,
				timestamp() - started
			);
			rethrow;
		}
	}
	function captureQueueMetrics(
		required string destination,
		required numeric depth,
		required numeric oldestAgeSeconds
	){
		gauge(
			"queue.depth",
			max( 0, arguments.depth ),
			{ "messaging.destination.name" : safeName( arguments.destination ) }
		);
		gauge(
			"queue.oldest_age",
			max( 0, arguments.oldestAgeSeconds ),
			{ "messaging.destination.name" : safeName( arguments.destination ) },
			"second"
		);
	}
	function captureRuntimeGauges(){
		if ( !variables.settings.enableMetrics ) {
			return {};
		}
		return new RuntimeMetrics( this ).capture();
	}
	function getBrowserConfig(){
		var browser = variables.settings.browser;
		return {
			"dsn"                      : browser.dsn ?: "",
			"environment"              : variables.settings.environment,
			"release"                  : variables.settings.release,
			"tracesSampleRate"         : browser.tracesSampleRate ?: variables.settings.tracesSampleRate,
			"tracePropagationTargets"  : variables.settings.tracePropagationTargets,
			"enabled"                  : browser.enabled ?: false,
			"localVerification"        : browser.localVerification ?: false,
			"replaysSessionSampleRate" : 0,
			"replaysOnErrorSampleRate" : 0
		};
	}
	function sanitizeAttributes( required struct attributes ){
		var result = {};
		for ( var key in arguments.attributes ) {
			// Sentry's cache convention uses an array. Keep this exception narrow:
			// arbitrary structures, bindings and cached values remain excluded.
			if ( key == "cache.key" && isArray( arguments.attributes[ key ] ) ) {
				var keys = [];
				for ( var item in arguments.attributes[ key ] ) {
					if ( !isSimpleValue( item ) || keys.len() >= 100 ) {
						continue;
					}
					keys.append( sanitizeText( left( toString( item ), 512 ) ) );
				}
				result[ key ] = keys;
				continue;
			}
			if (
				reFindNoCase(
					"password|token|secret|authorization|cookie|binding|payload|body|email|username|card|bank|result",
					key
				) || !isSimpleValue( arguments.attributes[ key ] )
			) {
				continue;
			}
			var value                  = arguments.attributes[ key ];
			result[ left( key, 128 ) ] = isNumeric( value ) || isBoolean( value ) ? value : sanitizeText(
				left( toString( value ), 512 )
			);
		}
		if ( isCustomFunction( variables.settings.attributeFilter ) ) {
			try {
				return variables.settings.attributeFilter( result );
			} catch ( any ignored ) {
				return {};
			}
		}
		return result;
	}
	private function typedAttributes( required struct attributes ){
		var result                   = {};
		var safe                     = sanitizeAttributes( arguments.attributes );
		safe[ "sentry.environment" ] = variables.settings.environment;
		safe[ "sentry.release" ]     = variables.settings.release;
		for ( var key in safe ) {
			// Logs and trace metrics have scalar typed attributes only.
			if ( !isSimpleValue( safe[ key ] ) ) {
				continue;
			}
			result[ key ] = {
				"type" : isBoolean( safe[ key ] ) && !isNumeric( safe[ key ] ) ? "boolean" : (
					isNumeric( safe[ key ] ) ? "double" : "string"
				),
				"value" : safe[ key ]
			};
		}
		return result;
	}
	function sanitizeText( required string text ){
		return reReplaceNoCase(
			arguments.text,
			"(password|token|secret|authorization|cookie|api[_-]?key)\s*[:=]\s*\S+",
			"\1=[Filtered]",
			"all"
		);
	}
	function safeName( required string name ){
		var sanitizedName = reReplaceNoCase(
			arguments.name,
			"[a-f0-9]{8}-[a-f0-9-]{27,}|/[0-9]+(?=/|$)",
			"/:id",
			"all"
		);
		return left(
			reReplace(
				listFirst( listFirst( sanitizedName, "?" ), "##" ),
				"[\r\n]",
				"",
				"all"
			),
			256
		);
	}
	function safePageURL( required string url ){
		try {
			var uri  = createObject( "java", "java.net.URI" ).create( arguments.url );
			var path = uri.getPath() ?: "/";
			if ( reFindNoCase( "token|password|payment|checkout|invite|kiosk|login|reset", path ) ) {
				path = "/[private-page]";
			}
			return safeURL( arguments.url ) & safeName( path );
		} catch ( any ignored ) {
			return "";
		}
	}
	function safeURL( required string url ){
		try {
			var uri = createObject( "java", "java.net.URI" ).create( arguments.url );
			if ( isNull( uri.getHost() ) || !listFindNoCase( "http,https", uri.getScheme() ?: "" ) ) {
				return "";
			}
			return uri.getScheme() & "://" & uri.getHost() & ( uri.getPort() > 0 ? ":" & uri.getPort() : "" );
		} catch ( any ignored ) {
			return "";
		}
	}
	function scrubSQL( required string sql ){
		// Unsupported quoting is discarded rather than risking exporting literals.
		if ( find( "$", arguments.sql ) || find( "`", arguments.sql ) || find( "\\", arguments.sql ) ) {
			return uCase( listFirst( trim( arguments.sql ), " " ) ) & " [Filtered]";
		}
		var scrubbed = reReplace(
			arguments.sql,
			"(?s)/\*.*?\*/|--[^\r\n]*",
			" ",
			"all"
		);
		scrubbed = reReplace(
			scrubbed,
			"'([^']|'')*'|""([^""]|"""")*""",
			"?",
			"all"
		);
		scrubbed = reReplace( scrubbed, "\b[0-9]+(\.[0-9]+)?\b", "?", "all" );
		if ( find( "'", scrubbed ) || find( """", scrubbed ) ) {
			return "[Filtered SQL]";
		}
		return left( reReplace( scrubbed, "\s+", " ", "all" ), 1024 );
	}
	function getTransport(){
		return variables.transport;
	}
	function flush( numeric timeoutMilliseconds = 2000 ){
		flushSignals();
		return variables.transport.flush( arguments.timeoutMilliseconds );
	}
	function shutdown( numeric timeoutMilliseconds = 2000 ){
		if ( !variables.closed.compareAndSet( false, true ) ) return true;
		variables.collectors.shutdown();
		try {
			if ( !isNull( variables.queryAdapterShutdown ) ) variables.queryAdapterShutdown();
		} catch ( any unavailable ) {
		}
		if ( !isNull( variables.nativeQueryListener ) ) {
			createObject( "java", "ortus.boxlang.runtime.BoxRuntime" )
				.getInstance()
				.getInterceptorService()
				.unregister(
					createObject( "java", "ortus.boxlang.runtime.interop.DynamicObject" ).of(
						variables.nativeQueryListener
					)
				);
		}
		if ( !isNull( variables.flusher ) ) {
			variables.flusher.shutdown();
		}
		flushSignals();
		clearScope();
		return variables.transport.shutdown( arguments.timeoutMilliseconds );
	}

}
