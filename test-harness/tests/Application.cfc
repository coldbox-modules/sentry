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
	rootPath                 = reReplaceNoCase( this.mappings[ "/tests" ], "tests(\\|/)", "" );
	this.mappings[ "/root" ] = rootPath;

	// UPDATE THE NAME OF THE MODULE IN TESTING BELOW
	request.MODULE_NAME = "sentry";

	// The module root path
	moduleRootPath = reReplaceNoCase(
		this.mappings[ "/root" ],
		"#request.module_name#(\\|/)test-harness(\\|/)",
		""
	);
	this.mappings[ "/moduleroot" ]            = moduleRootPath;
	this.mappings[ "/#request.MODULE_NAME#" ] = moduleRootPath & "#request.MODULE_NAME#";


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

		// If hitting the runner or specs, prep our virtual app
		if ( getBaseTemplatePath().replace( expandPath( "/tests" ), "" ).reFindNoCase( "(runner|specs)" ) ) {
			request.coldBoxVirtualApp.startup();
		}

		// Reload for fresh results
		if ( structKeyExists( url, "fwreinit" ) ) {
			if ( structKeyExists( server, "lucee" ) ) {
				pagePoolClear();
			}
			// ormReload();
			request.coldBoxVirtualApp.restart();
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
