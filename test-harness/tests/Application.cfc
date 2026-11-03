/**
********************************************************************************
Copyright 2005-2007 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
www.ortussolutions.com
********************************************************************************
*/
component {

	request.MODULE_NAME = "sentry";

	// APPLICATION CFC PROPERTIES
	this.name               = "ColdBoxTestingSuite" & hash( getCurrentTemplatePath() );
	this.sessionManagement  = true;
	this.sessionTimeout     = createTimespan( 0, 0, 15, 0 );
	this.applicationTimeout = createTimespan( 0, 0, 15, 0 );
	this.setClientCookies   = true;

	// Create testing mapping
	this.mappings[ "/tests" ] = getDirectoryFromPath( getCurrentTemplatePath() );

	// The application root
	rootPath                      = reReplaceNoCase( this.mappings[ "/tests" ], "tests(\\|/)", "" );
	this.mappings[ "/root" ]      = rootPath;
	this.mappings[ "/sentryAOP" ] = rootPath & ".engine/aop";

	// UPDATE THE NAME OF THE MODULE IN TESTING BELOW
	request.MODULE_NAME = "sentry";

	// The module root path
	moduleRootPath = reReplaceNoCase(
		this.mappings[ "/root" ],
		"#request.module_name#(\\|/)test-harness(\\|/)",
		""
	);
	this.mappings[ "/moduleroot" ]            = moduleRootPath;
	this.mappings[ "/#request.MODULE_NAME#" ] = reReplaceNoCase( rootPath, "test-harness(\\|/)", "" );
	this.mappings[ "/moduleroot/sentry" ]     = this.mappings[ "/sentry" ];
	cbqSource                                 = createObject( "java", "java.lang.System" ).getenv( "SENTRY_CBQ_SOURCE" );
	if ( !isNull( cbqSource ) && len( cbqSource ) ) {
		this.mappings[ "/cbq" ] = cbqSource;
	}
	this.mappings[ "/dependencies" ] = this.mappings[ "/sentry" ] & "/modules";
	qbSource                         = createObject( "java", "java.lang.System" ).getenv( "SENTRY_QB_SOURCE" );
	if ( !isNull( qbSource ) && len( qbSource ) ) {
		this.mappings[ "/qb" ]          = qbSource;
		this.mappings[ "/cbpaginator" ] = qbSource & "/modules/cbpaginator";
	}
	// Explicit local-only integration fixture. The dedicated database must already exist.
	queueHealthDatabase = createObject( "java", "java.lang.System" ).getenv( "SENTRY_QUEUE_HEALTH_DB" );
	if ( !isNull( queueHealthDatabase ) && len( queueHealthDatabase ) ) {
		if (
			!reFind( "^sentry_queue_health_[a-z0-9_]+", queueHealthDatabase ) || reFind(
				"[^a-z0-9_]",
				queueHealthDatabase
			)
		)
			throw( type = "Sentry.UnsafeIntegrationDatabase" );
		this.mappings[ "/queueHealthModules" ]  = rootPath & "modules";
		this.datasources[ "sentryQueueHealth" ] = {
			"class"            : "org.postgresql.Driver",
			"connectionString" : "jdbc:postgresql://127.0.0.1:5432/" & queueHealthDatabase,
			"username"         : "postgres",
			"password"         : "",
			"connectionLimit"  : 6
		};
		if ( structKeyExists( server, "lucee" ) ) {
			this.datasources.sentryQueueHealth[ "bundleName" ]    = "org.postgresql.jdbc";
			this.datasources.sentryQueueHealth[ "bundleVersion" ] = "42.6.0";
		} else if ( !structKeyExists( server, "boxlang" ) ) {
			this.datasources[ "sentryQueueHealth" ] = {
				"driver"   : "postgresql",
				"host"     : "127.0.0.1",
				"port"     : 5432,
				"database" : queueHealthDatabase,
				"username" : "postgres",
				"password" : ""
			};
		}
	}



	/**
	 * Fires on every test request. It builds a Virtual ColdBox application for you
	 *
	 * @targetPage The requested page
	 */
	public boolean function onRequestStart( targetPage ){
		// Set a high timeout for long running tests
		setting requestTimeout   ="9999";
		// New ColdBox Virtual Application Starter
		request.coldBoxVirtualApp= new coldbox.system.testing.VirtualApp();

		// Reload before startup: a partially activated optional integration must not block recovery.
		if ( structKeyExists( url, "fwreinit" ) ) {
			try {
				request.coldBoxVirtualApp.shutdown();
			} catch ( any incompleteStartup ) {
				createObject( "java", "java.lang.System" ).err.println(
					"Test harness cleanup failed: " & incompleteStartup.message
				);
			}
			structDelete( application, "cbController" );
			structDelete( application, "wirebox" );
			structDelete( application, "cachebox" );
		}
		if ( getBaseTemplatePath().replace( expandPath( "/tests" ), "" ).reFindNoCase( "(runner|specs)" ) ) {
			request.coldBoxVirtualApp.startup();
		}

		return true;
	}

	/**
	 * Fires when the testing requests end and the ColdBox application is shutdown
	 */
	public void function onRequestEnd( required targetPage ){
		request.coldBoxVirtualApp.shutdown();
	}

}
