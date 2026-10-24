/**
 *********************************************************************************
 * Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
 * www.ortussolutions.com
 * ---
 * Module Config.
 */
component {

	// Module Properties
	this.title              = "sentry";
	this.author             = "Ortus Solutions";
	this.webURL             = "https://www.ortussolutions.com";
	this.description        = "A module to log and send bug reports to Sentry";
	this.version            = "@build.version@+@build.number@";
	// If true, looks for views in the parent first, if not found, then in the module. Else vice-versa
	this.viewParentLookup   = true;
	// If true, looks for layouts in the parent first, if not found, then in module. Else vice-versa
	this.layoutParentLookup = true;
	this.cfmapping          = "sentry";
	this.dependencies       = [ "funclinenums" ];

	// STATIC SCRUB FIELDS
	variables.SCRUB_FIELDS = [
		"passwd",
		"password",
		"password_confirmation",
		"secret",
		"confirm_password",
		"secret_token",
		"APIToken",
		"x-api-token",
		"fwreinit"
	];
	variables.SCRUB_HEADERS = [ "x-api-token", "Authorization" ];

	/**
	 * Configure
	 */
	function configure(){
		settings = {
			// Sentry token
			"ServerSideToken"                 : "",
			// Enable the Sentry LogBox Appender Bridge
			"enableLogBoxAppender"            : true,
			"async"                           : true,
			// Min/Max levels for appender
			"levelMin"                        : "FATAL",
			"levelMax"                        : "ERROR",
			// Enable/disable error logging
			"enableExceptionLogging"          : true,
			// Sentry recommends not sending cookie and form data by default
			"sendCookies"                     : false,
			"sendPostData"                    : false,
			// Data sanitization, scrub fields and headers, replaced with "[Filtered]" at runtime
			"scrubFields"                     : [],
			"scrubHeaders"                    : [],
			"release"                         : "",
			"environment"                     : ( !isNull( controller ) ? controller.getSetting( "environment" ) : "" ),
			"DSN"                             : "",
			"publicKey"                       : "",
			"privateKey"                      : "",
			"projectID"                       : 0,
			"sentryUrl"                       : "https://sentry.io",
			// posting to "#sentryUrl#/api/#projectID#/store" is deprecated, but backward compatible
			// set to "envelope" to send events to modern "#sentryUrl#/api/#projectID#/envelope"
			"sentryEventEndpoint"             : "store",
			"serverName"                      : cgi.server_name,
			"appRoot"                         : expandPath( "/" ),
			"sentryVersion"                   : 7,
			// This is not arbitrary but must be a specific value. Leave as "cfml"
			//  https://docs.sentry.io/development/sdk-dev/attributes/
			"platform"                        : "cfml",
			"logger"                          : ( !isNull( controller ) ? controller.getSetting( "appName" ) : "sentry" ),
			"userInfoUDF"                     : "",
			"extraInfoUDFs"                   : {}, // these two settings may be added but they
			"showJavaStackTrace"              : false,
			"throwOnPostError"                : false,
			// Master switch for emitted metrics. Automatic collectors and dependency metrics require it.
			"enableMetrics"                   : false,
			// Record eligible ColdBox request traces; tracesSampleRate controls trace volume.
			"enableRequestTracing"            : false,
			// Track active eligible requests independently of trace sampling.
			"enableRequestSaturation"         : false,
			// Maximum retained active request observations; excess starts are counted as untracked.
			"maxObservedRequests"             : 4096,
			// Age in seconds used by the long-running-request gauge; this does not declare a timeout.
			"requestLongRunningSeconds"       : 30,
			// Observe compatible cbq execution/publish hooks and their attempt durations.
			"enableQueueTracing"              : false,
			// Count compatible cbq terminal completion/failure hooks separately from attempts.
			"enableQueueJobMetrics"           : false,
			// Fixed queue destination labels allowed on attempt/job metrics.
			"queueMetricDestinations"         : [],
			// Keep bounded, process-local envelope outcomes. Acceptance does not prove indexing.
			"enableDeliveryDiagnostics"       : false,
			// Query tracing is off by default. auto/boxlang try native BoxLang hooks; unavailable hooks leave tracing off.
			// qb is an explicit optional integration; lucee requires an application query listener.
			// Also accepts callback(context) or a mapping implementing IQueryAdapter.configure(context).
			"queryAdapter"                    : "none",
			// Optional initial phase names/header order; measure()/begin() also accept ad hoc names without configuration.
			// At most 32 distinct HTTP-safe names per instance. Automatic timing supplies handler/render.
			"requestTimingNames"              : [],
			// Time preEvent/postEvent and preRender/postRender automatically, preserving manual phase APIs.
			"enableAutomaticRequestTimings"   : false,
			// Publish the automatic instance's Server-Timing header when the response still permits headers.
			"publishServerTiming"             : false,
			// Optional callback(event) authorizing header publication; requestFilter still controls collection.
			"serverTimingFilter"              : "",
			// Fixed business workflow names allowed by the manual withOperation API.
			"operationNames"                  : [],
			// Fixed provider names allowed on manual workflow observations.
			"providerNames"                   : [],
			// Fixed names permitted by withDependency; configured dependencyAdapters add their names automatically.
			"dependencyNames"                 : [],
			// Up to 32 {name,mapping,methods:[...],classify:callback|mapping|{mapping,method}} entries.
			// WireBox-created instances are intercepted; classifier mappings implement IDependencyClassifier.classify(result,failure).
			"dependencyAdapters"              : [],
			// Writable WireBox AOP generation mapping, used only when this module registers the Mixer listener.
			"dependencyAdapterGenerationPath" : "/coldbox/system/aop/tmp",
			// Fixed names for the legacy manual worker-health API.
			"queueWorkerNames"                : [],
			// Fixed names for manual queue-health snapshots; configured queues add their names automatically.
			"queueNames"                      : [],
			// Fixed executor names; automatic requestExecutors definitions add their names.
			"requestExecutorNames"            : [],
			// Fixed pool names; automatic databasePools definitions add their names.
			"databasePoolNames"               : [],
			"automaticCollectors"             : {
				// Start one background sampler per service. Disabled by default; also requires enableMetrics and a valid DSN.
				"enabled"             : false,
				// Fixed delay between completed sampling cycles, in seconds, from 1 through 3600. No overlapping cycles.
				"intervalSeconds"     : 60,
				// Sample available heap/thread/CPU/GC values; unsupported values stay absent.
				"runtime"             : true,
				// Emit active/oldest/long-running request gauges; requires enableRequestSaturation.
				"requestSaturation"   : true,
				// Poll local receipt state; never send delivery-health metrics through their own transport.
				"deliveryDiagnostics" : false,
				// Up to 32 {name,adapter:callback|mapping|{mapping,method},options:{...}} definitions. No default provider.
				// One snapshot supplies supported backlog/depth/age/lease fields and worker activity; absent fields stay absent.
				// Adapters follow sample(context); context.options is provider-specific configuration.
				// Example: {name:"mail",adapter:"QueueHealthAdapter@cbq",options:{pool:"outbound"}} (requires cbq's adapter).
				"queues"              : [],
				// Up to 32 {name,adapter} definitions returning active/max/queued/rejected via callback(context) or ISnapshotAdapter.sample(context).
				"requestExecutors"    : [],
				// Up to 32 {name,adapter} definitions returning active/idle/max/waiters/timeouts via callback(context) or ISnapshotAdapter.sample(context).
				"databasePools"       : []
			}
		};

		// Try to look up the release based on a box.json
		if ( !isNull( appmapping ) ) {
			var boxJSONPath = expandPath( "/" & appmapping & "/box.json" );
			if ( fileExists( boxJSONPath ) ) {
				var boxJSONRaw = fileRead( boxJSONPath );
				if ( isJSON( boxJSONRaw ) ) {
					var boxJSON = deserializeJSON( boxJSONRaw );
					if ( boxJSON.keyExists( "version" ) ) {
						settings.release = boxJSON.version;
						if ( boxJSON.keyExists( "slug" ) ) {
							settings.release = boxJSON.slug & "@" & settings.release;
						} else if ( boxJSON.keyExists( "name" ) ) {
							settings.release = boxJSON.name & "@" & settings.release;
						}
					}
				}
			}
		}

		settings.append(
			createObject( "component", "#moduleMapping#.models.telemetry.Observability" ).defaults(),
			false
		);
		interceptors = [
			{ class : "#moduleMapping#.interceptors.QueueObservability" },
			{ class : "#moduleMapping#.interceptors.Observability" },
			{ class : "#moduleMapping#.interceptors.QueryObservability" }
		];
		interceptorSettings = { customInterceptionPoints : [ "onSentryEventCapture" ] };
	}

	/**
	 * Fired when the module is registered and activated.
	 */
	function onLoad(){
		// Initialize only when an explicitly configured integration needs startup work.
		if (
			!isSimpleValue( settings.queryAdapter ) || settings.queryAdapter != "none" || (
				isStruct( settings.automaticCollectors ) && settings.automaticCollectors.keyExists( "enabled" ) && isBoolean(
					settings.automaticCollectors.enabled
				) && settings.automaticCollectors.enabled
			) || ( isArray( settings.dependencyAdapters ) && settings.dependencyAdapters.len() )
		) {
			var telemetry = wirebox.getInstance( "SentryService@sentry" ).getObservability();
			telemetry.setAdapterInjector( wirebox );
			telemetry.configureQueryInstrumentation( getApplicationMetadata().name );
			registerDependencyAdapters( telemetry );
		}

		binder.mapDSL( "sentryCache", "#moduleMapping#.models.dsl.CacheDSL" );
		wirebox.registerDSL( "sentryCache", "#moduleMapping#.models.dsl.CacheDSL" );
		settings.scrubFields.addAll( SCRUB_FIELDS );
		settings.scrubHeaders.addAll( SCRUB_HEADERS );

		if ( settings.enableStructuredLogBoxAppender && settings.enableLogs ) {
			logBox.registerAppender(
				name       = "sentry_structured",
				class      = "#moduleMapping#.models.StructuredLogAppender",
				properties = { "messageMode" : settings.logMessageMode },
				levelMin   = 0,
				levelMax   = 3
			);
			logBox
				.getRootLogger()
				.addAppender( logBox.getAppendersMap( "sentry_structured" )[ "sentry_structured" ] );
		}

		// Load the LogBox Appenders
		if ( settings.enableLogBoxAppender ) {
			loadAppenders();
		}
	}

	private function registerDependencyAdapters( required any telemetry ){
		var bindings = arguments.telemetry.dependencyBindings();
		if ( !bindings.len() ) return;
		if (
			!binder
				.getListeners()
				.some( function( listener ){
					return compareNoCase( listener.class, "coldbox.system.aop.Mixer" ) == 0;
				} )
		) {
			binder.listener(
				class      = "coldbox.system.aop.Mixer",
				properties = { "generationPath" : settings.dependencyAdapterGenerationPath },
				register   = true
			);
		}
		binder
			.mapAspect( "SentryDependencyInterceptor@sentry", false )
			.to( "#moduleMapping#.models.telemetry.DependencyInterceptor" );
		var mappings = [];
		var methods  = [];
		for ( var binding in bindings ) {
			if ( !arrayFindNoCase( mappings, binding.mapping ) ) mappings.append( binding.mapping );
			for ( var method in binding.methods ) {
				if ( !arrayFindNoCase( methods, method ) ) methods.append( method );
			}
		}
		binder.bindAspect(
			binder.match().mappings( mappings.toList() ),
			binder.match().methods( methods.toList() ),
			"SentryDependencyInterceptor@sentry"
		);
	}

	/**
	 * Fired when the module is unregistered and unloaded
	 */
	function onUnload(){
		if ( wirebox.containsInstance( "SentryService@sentry" ) ) {
			wirebox.getInstance( "SentryService@sentry" ).shutdown();
		}
	}

	/**
	 * Trap exceptions and send them to Sentry
	 */
	function onException( event, interceptData, buffer ){
		if ( !settings.enableExceptionLogging ) {
			return;
		}
		if ( wirebox.containsInstance( "SentryService@sentry" ) ) {
			var sentryService = wirebox.getInstance( "SentryService@sentry" );

			sentryService.captureException( exception = interceptData.exception, level = "error" );
		}
	}

	// **************************************** PRIVATE ************************************************//

	/**
	 * Load LogBox Appenders
	 */
	private function loadAppenders(){
		// Get config
		/*var logBoxConfig 	= logBox.getConfig();
		var rootConfig 		= '';

		// Register tracer appender
		rootConfig = logBoxConfig.getRoot();
		logBoxConfig.appender(
			name 		= 'sentry_appender',
			class 		= '#moduleMapping#.models.SentryAppender',
			levelMin 	= settings.levelMin,
			levelMax 	= settings.levelMax
		);
		logBoxConfig.root(
			levelMin = rootConfig.levelMin,
			levelMax = rootConfig.levelMax,
			appenders= listAppend( rootConfig.appenders, 'sentry_appender')
		);

		// Store back config
		logBox.configure( logBoxConfig );*/

		logBox.registerAppender(
			name     = "sentry_appender",
			class    = "#moduleMapping#.models.SentryAppender",
			levelMin = logBox.logLevels[ settings.levelMin ],
			levelMax = logBox.logLevels[ settings.levelMax ]
		);

		var appenders = logBox.getAppendersMap( "sentry_appender" );
		// Register the appender with the root loggger, and turn the logger on.
		var root      = logBox.getRootLogger();
		root.addAppender( appenders[ "sentry_appender" ] );
	}

}
