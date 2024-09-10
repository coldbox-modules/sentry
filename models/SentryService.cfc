/**
 *********************************************************************************
 * Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
 * www.ortussolutions.com
 * ---
 * Connector to Sentry
 */
component accessors=true singleton {

	// DI
	property name="wirebox"          inject="wirebox";
	property name="functionLineNums" inject="functionLineNums@funclinenums";

	property name="settings";
	property name="moduleConfig";
	property name="coldbox";

	property name="levels" type="array";

	/** The environment name, such as ‘production’ or ‘staging’. */
	property name="environment" type="string";
	/** Default logger name */
	property name="logger" type="string";
	/** Name of platform sending the messages */
	property name="platform" type="string";
	/** The release version of the application. */
	property name="release" type="string";
	/** A DSN string to connect to Sentry's API, the values can also be passed as individual arguments */
	property name="DSN" type="string";

	/** The ID Sentry Project */
	property name="projectID";
	/** The Public Key for your Sentry Account */
	property name="publicKey";
	/** The Private Key for your Sentry Account */
	property name="privateKey";

	/**  The Sentry API url which defaults to https://sentry.io */
	property name="sentryUrl" type="string";
	/**  The Sentry version */
	property name="sentryVersion" type="string";
	/**  Which Sentry endpoint to send events to, could be "store" or "envelope"  */
	property name="sentryEventEndpoint" type="string";
	/** The name of the server, defaults to machine name, then cgi.http_host */
	property name="serverName" type="string";
	/** Log messages async */
	property name="async" type="boolean";
	/** A UDF that generates user information for logged messages. Returns a struct containing keys "id", "email", "username", and anything else. */
	property name="userInfoUDF";
	/** A dictionary of UDFs to add to the `extra` information. Each function is called and put in the `extra` struct under the provided key. */
	property name="extraInfoUDFs";

	property name="enabled";

	// Additional tags
	property name="tags";



	/**
	 * Constructor
	 */
	function init( struct settings = {} ){
		setSettings( arguments.settings );
		// If we have settings passed to the init, this is likely not
		// in WireBox context so just configure now
		if ( arguments.settings.count() ) {
			configure();
		}
		setModuleConfig( { version : "2.0.0" } );

		return this;
	}

	private function getDefaultSettings(){
		// These are a duplicate of what's in the ModuleConfig.  I don't like
		// having the here as well, but this is so this service can be used outside
		// of ColdBox and not require the ModuleConfig.cfc
		return {
			// Enable the Sentry LogBox Appender Bridge
			"enableLogBoxAppender"   : true,
			"async"                  : true,
			// Min/Max levels for appender
			"levelMin"               : "FATAL",
			"levelMax"               : "ERROR",
			// Enable/disable error logging
			"enableExceptionLogging" : true,
			// Whether to include client cookies when sending request information to Sentry
			"sendCookies"            : false,
			// Whether to include POST data (e.g. FORM) when sending request information to Sentry
			"sendPostData"           : false,
			// Data sanitization, scrub fields and headers, replaced with "[Filtered]" at runtime
			"scrubFields"            : [
				"passwd",
				"password",
				"password_confirmation",
				"secret",
				"confirm_password",
				"secret_token",
				"APIToken",
				"x-api-token",
				"fwreinit"
			],
			"scrubHeaders"        : [ "x-api-token", "Authorization" ],
			"release"             : "",
			"environment"         : "production",
			"DSN"                 : "",
			"publicKey"           : "",
			"privateKey"          : "",
			"projectID"           : 0,
			"sentryUrl"           : "https://sentry.io",
			"serverName"          : cgi.server_name,
			"appRoot"             : expandPath( "/" ),
			"sentryVersion"       : 7,
			"sentryEventEndpoint" : "store",
			// This is not arbitrary but must be a specific value. Leave as "cfml"
			//  https://docs.sentry.io/development/sdk-dev/attributes/
			"platform"            : "cfml",
			"logger"              : "sentry",
			"userInfoUDF"         : "",
			"extraInfoUdfs"       : {},
			"showJavaStackTrace"  : false,
			"throwOnPostError"    : false
		};
	}

	/**
	 * onDIComplete
	 */
	function onDIComplete(){
		// If we have WireBox, see if we can get ColdBox
		if ( !isNull( wirebox ) ) {
			// backwards compat with older versions of ColdBox
			if ( wirebox.isColdBoxLinked() ) {
				setSettings( wirebox.getInstance( dsl = "coldbox:moduleSettings:sentry" ) );
				setModuleConfig( wirebox.getInstance( dsl = "coldbox:moduleConfig:sentry" ) );
				// CommandBox supports generic box namespace
			} else {
				setSettings( wirebox.getInstance( dsl = "box:moduleSettings:sentry" ) );

				setModuleConfig( wirebox.getInstance( dsl = "box:moduleConfig:sentry" ) );
			}
			setColdBox( wirebox.getColdBox() );
		}

		configure();
	}

	function configure(){
		setEnabled( true );
		// Add in default settings
		settings.append( getDefaultSettings(), false );

		if ( len( settings.sentryUrl ) ) {
			setSentryUrl( settings.sentryUrl );
		}

		if ( len( settings.DSN ) ) {
			setDSN( settings.DSN );
			parseDSN( settings.DSN );
		} else if ( len( settings.publicKey ) && len( settings.privateKey ) && len( settings.projectID ) ) {
			setPublicKey( settings.publicKey );
			setPrivateKey( settings.privateKey );
			setProjectID( settings.projectID );
		} else {
			setPublicKey( "" );
			setPrivateKey( "" );
			setProjectID( 0 );
			setEnabled( false );
			writeDump(
				var    = "You must configure in a valid DSN or Project Keys and ID to instantiate the Sentry CFML Client.",
				output = "console"
			);
		}

		setLevels( [ "fatal", "error", "warning", "info", "debug" ] );

		setRelease( settings.release );
		setEnvironment( settings.environment );
		setServerName( settings.serverName );
		setAsync( settings.async );
		setSentryVersion( settings.sentryVersion );
		setSentryEventEndpoint( settings.sentryEventEndpoint );
		setLogger( settings.logger );
		setPlatform( settings.platform );

		setUserInfoUDF( settings.userInfoUDF );
		setExtraInfoUDFs( settings.extraInfoUDFs );

		settings.appRoot = normalizeSlashes( settings.appRoot );

		// in a non ColdBox context, ensure functionLineNums exists
		// so this service can still be used if functionLineNums
		// is not passed in
		if ( isNull( variables.functionLineNums ) ) {
			setFunctionLineNums( {
				findTagContextFunction : function(){
					return "";
				}
			} );
		}
	}

	/**
	 * Parses a valid Sentry DSN
	 *
	 * {PROTOCOL}://{PUBLIC_KEY}:{SECRET_KEY}@{HOST}/{PATH}{PROJECT_ID}
	 * or
	 * {PROTOCOL}://{PUBLIC_KEY}@{HOST}/{PATH}{PROJECT_ID}
	 *
	 * https://docs.sentry.io/clientdev/overview/#parsing-the-dsn
	 */
	private void function parseDSN( required string DSN ){
		var pattern  = "^(?:(\w+):)?\/\/(\w+):?(\w+)?@([\w\.\-:]+)\/(.*)";
		var result   = reFind( pattern, arguments.DSN, 1, true );
		var segments = [];

		for ( var i = 2; i LTE arrayLen( result.pos ); i++ ) {
			// If the secret key is ommitted, the capture group will have a pos and len of 0
			if ( result.len[ i ] ) {
				segments.append(
					mid(
						arguments.DSN,
						result.pos[ i ],
						result.len[ i ]
					)
				);
			}
		}

		if ( segments.len() == 4 ) {
			setSentryUrl( segments[ 1 ] & "://" & segments[ 3 ] );
			setPublicKey( segments[ 2 ] );
			setProjectID( segments[ 4 ] );
		} else if ( segments.len() == 5 ) {
			setSentryUrl( segments[ 1 ] & "://" & segments[ 4 ] );
			setPublicKey( segments[ 2 ] );
			setPrivateKey( segments[ 3 ] );
			setProjectID( segments[ 5 ] );
		} else {
			throw( message = "Error parsing Sentry DSN" );
		}
	}

	/**
	 * Validates that a correct level was set for a capture
	 * The allowed levels are:
	 * 	"fatal","error","warning","info","debug"
	 * if you pass "warn", we'll switch it to "warning"
	 */
	private string function validateLevel( required string level ){
		if ( arguments.level == "warn" ) {
			arguments.level = "warning";
		}

		if ( !getLevels().findNoCase( arguments.level ) ) {
			throw(
				message = "Error Type [#arguments.level#] is invalid. Must be one of the following : " & getLevels().toString()
			);
		}
		return lCase( arguments.level );
	}

	/**
	 * Capture a message
	 * https://develop.sentry.dev/sdk/event-payloads/message/
	 *
	 * @message        the raw message string ( max length of 1000 characters )
	 * @level          The level to log
	 * @path           The path to the script currently executing
	 * @params         an optional list of formatting parameters
	 * @cgiVars        Parameters to send to Sentry, defaults to the CGI Scope
	 * @useThread      Option to send post to Sentry in its own thread
	 * @userInfo       Optional Struct that gets passed to the Sentry User Interface
	 * @additionalData Additional metadata to store with the event - passed into the extra attribute
	 * @tags           Optional. A struct of tags for this event. Each tag must be less than 200 characters.
	 * @fingerprint    Optional An array of strings used to dictate the deduplication of this event.
	 */
	public any function captureMessage(
		required string message,
		string level = "info",
		string path  = "",
		array params,
		any cgiVars       = cgi,
		boolean useThread = getAsync(),
		struct userInfo   = {},
		string logger     = getLogger(),
		any additionalData,
		struct tags       = {},
		array fingerprint = []
	){
		if ( !getEnabled() ) {
			return;
		}
		var sentryMessage = {};

		arguments.level = validateLevel( arguments.level );

		if ( len( trim( arguments.message ) ) > 1000 ) arguments.message = left( arguments.message, 997 ) & "...";

		sentryMessage = {
			"message"  : arguments.message,
			"level"    : arguments.level,
			"logentry" : { "formatted" : arguments.message },
			"logger"   : arguments.logger
		};

		if ( structKeyExists( arguments, "params" ) ) {
			sentryMessage[ "logentry" ][ "params" ] = arguments.params;
		}
		// Add tags
		if ( !structIsEmpty( arguments.tags ) ) {
			sentryMessage[ "tags" ] = arguments.tags;
		}

		// Add fingerprint
		if ( arrayLen( arguments.fingerprint ) ) {
			sentryMessage[ "fingerprint" ] = arguments.fingerprint;
		}


		if ( !isNull( additionalData ) ) {
			if ( !isStruct( additionalData ) ) {
				additionalData = { "Additional Data" : additionalData };
			}
			sentryMessage[ "extra" ] = additionalData;
		}

		capture(
			captureStruct: sentryMessage,
			path         : arguments.path,
			cgiVars      : arguments.cgiVars,
			useThread    : arguments.useThread,
			userInfo     : arguments.userInfo
		);
	}

	/**
	 * @exception                  The exception
	 * @level                      The level to log
	 * @path                       The path to the script currently executing
	 * @oneLineStackTrace          Set to true to render only 1 tag context. This is not the Java Stack Trace this is simply for the code output in Sentry
	 * @showJavaStackTrace         Passes Java Stack Trace as a string to the extra attribute
	 * @removeTabsOnJavaStackTrace Removes the tab on the child lines in the Stack Trace
	 * @additionalData             Additional metadata to store with the event - passed into the extra attribute
	 * @cgiVars                    Parameters to send to Sentry, defaults to the CGI Scope
	 * @useThread                  Option to send post to Sentry in its own thread
	 * @userInfo                   Optional Struct that gets passed to the Sentry User Interface
	 * @message                    Optional message name to output
	 * @logger                     Optional logger to use
	 * @tags                       Optional. A struct of tags for this event. Each tag must be less than 200 characters.
	 * @fingerprint                Optional An array of strings used to dictate the deduplication of this event.
	 */
	public any function captureException(
		required any exception,
		string level                       = "error",
		string path                        = "",
		boolean oneLineStackTrace          = false,
		boolean showJavaStackTrace         = settings.showJavaStackTrace,
		boolean removeTabsOnJavaStackTrace = false,
		any additionalData,
		any cgiVars       = cgi,
		boolean useThread = getAsync(),
		struct userInfo   = {},
		string message    = "",
		string logger     = getLogger(),
		struct tags       = {},
		array fingerprint = []
	){
		if ( !getEnabled() ) {
			return;
		}

		// Ensure expected keys exist
		arguments.exception.StackTrace = arguments.exception.StackTrace ?: "";
		arguments.exception.type       = arguments.exception.type ?: "";
		arguments.exception.detail     = arguments.exception.detail ?: "";
		arguments.exception.TagContext = arguments.exception.TagContext ?: [];
		arguments.exception.message    = arguments.exception.message ?: "";

		var sentryExceptionExtra = {};
		var file                 = "";
		var fileArray            = "";
		var currentTemplate      = "";
		var tagContext           = arguments.exception.TagContext;
		var i                    = 1;
		var st                   = "";

		// If there's no tag context, include the stack trace instead
		if ( !tagContext.len() ) {
			arguments.showJavaStackTrace = true;
		}

		arguments.level = validateLevel( arguments.level );

		/*
		 * CORE AND OPTIONAL ATTRIBUTES
		 * https://develop.sentry.dev/sdk/event-payloads/
		 */
		var sentryException = {
			"level"   : arguments.level,
			"logger"  : arguments.logger,
			"message" : arguments.exception.message & " " & arguments.exception.detail
		};


		// Add tags
		if ( !structIsEmpty( arguments.tags ) ) {
			sentryException[ "tags" ] = arguments.tags;
		}

		// Add fingerprint
		if ( arrayLen( arguments.fingerprint ) ) {
			sentryException[ "fingerprint" ] = arguments.fingerprint;
		}

		if ( arguments.message != arguments.exception.message ) {
			sentryException.message = arguments.message & " " & sentryException.message;
		}

		if ( arguments.showJavaStackTrace ) {
			st = reReplace(
				arguments.exception.StackTrace,
				"\r",
				"",
				"All"
			);
			if ( arguments.removeTabsOnJavaStackTrace ) st = reReplace( st, "\t", "", "All" );
			sentryExceptionExtra[ "Java StackTrace" ] = listToArray( st, chr( 10 ) );
		}

		if ( !isNull( arguments.additionalData ) ) {
			sentryExceptionExtra[ "Additional Data" ] = arguments.additionalData;
		}

		// Applies to type = "database". Native error code associated with exception. Database drivers typically provide error codes to diagnose failing database operations. Default value is -1.
		if ( structKeyExists( arguments.exception, "NativeErrorCode" ) ) {
			sentryExceptionExtra[ "DataBase" ][ "NativeErrorCode" ] = arguments.exception.NativeErrorCode;
		}

		// Applies to type = "database". SQLState associated with exception. Database drivers typically provide error codes to help diagnose failing database operations. Default value is 1.
		if ( structKeyExists( arguments.exception, "SQLState" ) ) {
			sentryExceptionExtra[ "DataBase" ][ "SQL State" ] = arguments.exception.SQLState;
		}

		// Applies to type = "database". The SQL statement sent to the data source.
		if ( structKeyExists( arguments.exception, "Sql" ) ) {
			sentryExceptionExtra[ "DataBase" ][ "SQL" ] = arguments.exception.Sql;
		}

		// Applies to type ="database". The error message as reported by the database driver.
		if ( structKeyExists( arguments.exception, "queryError" ) ) {
			sentryExceptionExtra[ "DataBase" ][ "Query Error" ] = arguments.exception.queryError;
		}

		// Applies to type= "database". If the query uses the cfqueryparam tag, query parameter name-value pairs.
		if ( structKeyExists( arguments.exception, "where" ) ) {
			sentryExceptionExtra[ "DataBase" ][ "Where" ] = arguments.exception.where;
		}

		// Applies to type = "expression". Internal expression error number.
		if ( structKeyExists( arguments.exception, "ErrNumber" ) ) {
			sentryExceptionExtra[ "expression" ][ "Error Number" ] = arguments.exception.ErrNumber;
		}

		// Applies to type = "missingInclude". Name of file that could not be included.
		if ( structKeyExists( arguments.exception, "MissingFileName" ) ) {
			sentryExceptionExtra[ "missingInclude" ][ "Missing File Name" ] = arguments.exception.MissingFileName;
		}

		// Applies to type = "lock". Name of affected lock (if the lock is unnamed, the value is "anonymous").
		if ( structKeyExists( arguments.exception, "LockName" ) ) {
			sentryExceptionExtra[ "lock" ][ "Lock Name" ] = arguments.exception.LockName;
		}

		// Applies to type = "lock". Operation that failed (Timeout, Create Mutex, or Unknown).
		if ( structKeyExists( arguments.exception, "LockOperation" ) ) {
			sentryExceptionExtra[ "lock" ][ "Lock Operation" ] = arguments.exception.LockOperation;
		}

		// Applies to type = "custom". String error code.
		if (
			structKeyExists( arguments.exception, "ErrorCode" ) && len( arguments.exception.ErrorCode ) && arguments.exception.ErrorCode != "0"
		) {
			sentryExceptionExtra[ "custom" ][ "Error Code" ] = arguments.exception.ErrorCode;
		}

		// Applies to type = "application" and "custom". Custom error message; information that the default exception handler does not display.
		if ( structKeyExists( arguments.exception, "ExtendedInfo" ) && len( arguments.exception.ExtendedInfo ) ) {
			sentryExceptionExtra[ "application" ][ "Extended Info" ] = isJSON( arguments.exception.ExtendedInfo ) ? deserializeJSON(
				arguments.exception.ExtendedInfo
			) : arguments.exception.ExtendedInfo;
		}

		if ( structCount( sentryExceptionExtra ) ) sentryException[ "extra" ] = sentryExceptionExtra;

		/*
		 * EXCEPTION INTERFACE
		 * https://https://develop.sentry.dev/sdk/event-payloads/exception/
		 */
		var currentException = {
			"value"      : arguments.exception.message & " " & arguments.exception.detail,
			"type"       : arguments.exception.type & " Error",
			"stacktrace" : { "frames" : [] }
		};

		sentryException[ "exception" ] = { "values" : [ currentException ] };



		/*
		 * STACKTRACE INTERFACE
		 * https://develop.sentry.dev/sdk/event-payloads/stacktrace/
		 */
		if ( arguments.oneLineStackTrace ) {
			tagContext = [ tagContext[ 1 ] ];
		}

		var stacki = 0;
		for ( i = arrayLen( tagContext ); i > 0; i-- ) {
			stacki++;
			var thisTCItem = tagContext[ i ];
			if ( compareNoCase( thisTCItem[ "TEMPLATE" ], currentTemplate ) ) {
				fileArray = [];
				if ( fileExists( thisTCItem[ "TEMPLATE" ] ) ) {
					file = fileOpen( thisTCItem[ "TEMPLATE" ], "read" );
					while ( !fileIsEOF( file ) ) {
						arrayAppend( fileArray, fileReadLine( file ) );
					}
					fileClose( file );
				}
				currentTemplate = thisTCItem[ "TEMPLATE" ];
			}

			var thisStackItem = {
				"abs_path"     : thisTCItem[ "TEMPLATE" ],
				"filename"     : normalizeSlashes( thisTCItem[ "TEMPLATE" ] ).replace( variables.settings.appRoot, "" ),
				"lineno"       : thisTCItem[ "LINE" ],
				"pre_context"  : [],
				"context_line" : "",
				"post_context" : []
			};

			// The name of the function being called
			var functionName = functionLineNums.findTagContextFunction( thisTCItem );
			if ( len( functionName ) ) {
				thisStackItem[ "function" ] = functionName;
			}

			// for source code rendering
			var fileLen   = arrayLen( fileArray );
			var errorLine = thisTCItem[ "LINE" ];

			if ( errorLine - 3 >= 1 && errorLine - 3 <= fileLen ) {
				thisStackItem.pre_context[ 1 ] = fileArray[ errorLine - 3 ];
			}
			if ( errorLine - 2 >= 1 && errorLine - 2 <= fileLen ) {
				thisStackItem.pre_context[ 2 ] = fileArray[ errorLine - 2 ];
			}
			if ( errorLine - 1 >= 1 && errorLine - 1 <= fileLen ) {
				thisStackItem.pre_context[ 3 ] = fileArray[ errorLine - 1 ];
			}

			if ( errorLine <= fileLen ) {
				thisStackItem[ "context_line" ] = fileArray[ errorLine ];
			}

			if ( fileLen >= errorLine + 1 ) {
				var errorLine1 = errorLine + 1;

				if (errorLine1 != 0) {
					thisStackItem.post_context[ 1 ] = fileArray[ errorLine1 ];
				} else if (fileLen >= errorLine1 + 1) {
					thisStackItem.post_context[ 1 ] = fileArray[ errorLine1 + 1 ];
				}
			}

			if ( fileLen >= errorLine + 2 ) {
				var errorLine2 = errorLine + 2;

				if (errorLine2 != 1) {
					thisStackItem.post_context[ 2 ] = fileArray[ errorLine2 ];
				} else if (fileLen >= errorLine2 + 1) {
					thisStackItem.post_context[ 2 ] = fileArray[ errorLine2 + 1 ];
				}
			}

			currentException[ "stacktrace" ][ "frames" ][ stacki ] = thisStackItem;
		}

		capture(
			captureStruct: sentryException,
			path         : arguments.path,
			cgiVars      : arguments.cgiVars,
			useThread    : arguments.useThread,
			userInfo     : arguments.userInfo
		);
	}

	// recursivley replace any CFC instances with structs
	function structifyObject( o, name = "" ){
		var result = {};
		if ( len( name ) ) {
			// Find a way to communicate what the original CFC instance was, even though it's a struct now
			result[ "__componentName" ] = name;
		}
		return structReduce(
			o,
			function( acc, k, v ){
				if ( !isCustomFunction( v ) ) {
					if ( isObject( v ) ) {
						acc[ k ] = structifyObject( v, getMetadata( v ).name );
					} else if ( isStruct( v ) ) {
						acc[ k ] = structifyObject( v );
					} else {
						acc[ k ] = v;
					}
				}
				return acc;
			},
			result
		);
	}

	/**
	 * Prepare message to post to Sentry
	 *
	 * @captureStruct The struct we are passing to Sentry
	 * @cgiVars       Parameters to send to Sentry, defaults to the CGI Scope
	 * @path          The path to the script currently executing
	 * @useThread     Option to send post to Sentry in its own thread
	 * @userInfo      Optional Struct that gets passed to the Sentry User Interface
	 */
	public void function capture(
		required any captureStruct,
		any cgiVars       = cgi,
		string path       = "",
		boolean useThread = getAsync(),
		struct userInfo   = {}
	){
		var jsonCapture     = "";
		var signature       = "";
		var header          = "";
		var timeVars        = getTimeVars();
		var httpRequestData = getHTTPRequestData();

		// Add global metadata
		arguments.captureStruct[ "event_id" ]    = lCase( replace( createUUID(), "-", "", "all" ) );
		arguments.captureStruct[ "timestamp" ]   = timeVars.iso;
		arguments.captureStruct[ "project" ]     = getProjectID();
		arguments.captureStruct[ "server_name" ] = getServerName();
		arguments.captureStruct[ "platform" ]    = getPlatform();
		arguments.captureStruct[ "release" ]     = getRelease();
		arguments.captureStruct[ "environment" ] = getEnvironment();

		/*
		 * User interface
		 * https://develop.sentry.dev/sdk/event-payloads/user/
		 *
		 * {
		 *     "id" : "unique_id",
		 *     "email" : "foo@example.com",
		 *     "username" : ""my_user",
		 *     "ip_address" : "127.0.0.1"
		 * }
		 *
		 * All other keys are stored as extra information but not specifically processed by sentry.
		 */
		var thisUserInfo = { "ip_address" : getRealIP() };

		var userInfoUDF = getUserInfoUDF();
		// If there is a closure to produce user info, call it
		if ( isCustomFunction( userInfoUDF ) ) {
			// Check for a non-ColdBox context
			if ( isNull( coldbox ) ) {
				// Call the custon closure to produce user info
				local.tmpUserInfo = userInfoUDF();
			} else {
				// Prepare the request context for the closure to use
				var event         = coldbox.getRequestService().getContext();
				// Call the custon closure to produce user info
				local.tmpUserInfo = userInfoUDF(
					event,
					event.getCollection(),
					event.getPrivateCollection()
				);
			}

			if ( !isNull( local.tmpUserInfo ) && isStruct( local.tmpUserInfo ) ) {
				thisUserInfo.append( local.tmpUserInfo );
			}
		}
		if ( !arguments.userInfo.isEmpty() ) {
			thisUserInfo.append( arguments.userInfo );
		}

		// Force lowercasing on these since Sentry looks for them
		// Stupid CF won't udpate key casing in-place, so creating a new struct.
		var correctCasingUserInfo = {};
		for ( var key in thisUserInfo ) {
			if ( listFindNoCase( "id,email,ip_address,username", key ) ) {
				key = lCase( key );
			}
			correctCasingUserInfo[ key ] = thisUserInfo[ key ];
		}

		arguments.captureStruct[ "user" ] = correctCasingUserInfo;

		var extraInfoUdfs = getExtraInfoUdfs();
		for ( var key in extraInfoUdfs ) {
			var extraInfoUdf                          = extraInfoUdfs[ key ];
			arguments.captureStruct[ "extra" ][ key ] = extraInfoUdf();
		}

		// Prepare path for Request Interface
		arguments.path = trim( arguments.path );
		if ( !len( arguments.path ) && structCount( arguments.cgiVars ) ) {
			// leave off script name for SES URLs since rewrites were probably used
			if ( arguments.cgiVars.script_name == "/index.cfm" && len( arguments.cgiVars.path_info ) ) {
				arguments.path = "http" & ( arguments.cgiVars.server_port_secure ? "s" : "" ) & "://" & arguments.cgiVars.server_name & arguments.cgiVars.path_info;
			} else {
				arguments.path = "http" & ( arguments.cgiVars.server_port_secure ? "s" : "" ) & "://" & arguments.cgiVars.server_name & arguments.cgiVars.script_name & arguments.cgiVars.path_info;
			}
		}

		// Request interface
		// https://develop.sentry.dev/sdk/event-payloads/request/
		arguments.captureStruct[ "request" ] = {
			"url"          : arguments.path,
			"method"       : arguments.cgiVars.request_method ?: "GET",
			"query_string" : sanitizeQueryString( arguments.cgiVars.query_string ?: "" ),
			"env"          : sanitizeEnv( arguments.cgiVars ),
			"headers"      : sanitizeHeaders( httpRequestData.headers )
		};

		if ( variables.settings.sendCookies ) {
			arguments.captureStruct[ "request" ][ "cookies" ] = sanitizeFields(
				cookie.map( function( k, v ){
					return toString( v ); // Sentry requires all cookies be strings
				} )
			)
		}

		if ( variables.settings.sendPostData ) {
			if ( !structIsEmpty( form ) ) {
				arguments.captureStruct[ "request" ][ "data" ] = sanitizeFields( form );
			} else {
				arguments.captureStruct[ "request" ][ "data" ] = sanitizeFields(
					isJSON( httpRequestData.content ) ? deserializeJSON( httpRequestData.content ) : {}
				)
			}
		}

		// serialize data
		jsonCapture = serializeJSON( arguments.captureStruct );

		// prepare header
		// https://develop.sentry.dev/sdk/overview/#authentication
		header = "Sentry sentry_version=#getSentryVersion()#, sentry_client=Sentry/#moduleConfig.version#, sentry_key=#getPublicKey()#";
		if ( getSentryEventEndpoint() == "store" ) {
			header &= ", sentry_timestamp=#timeVars.unix#";
		}
		if ( !isNull( getPrivateKey() ) && len( getPrivateKey() ) ) {
			header &= ", sentry_secret=#getPrivateKey()#";
		}

		// post message
		if ( arguments.useThread ) {
			cfthread(
				action      = "run",
				name        = "sentry-thread-" & createUUID(),
				header      = header,
				event_id    = captureStruct.event_id,
				sent_at     = timeVars.iso,
				jsonCapture = jsonCapture
			) {
				post( header, event_id, sent_at, jsonCapture );
			}
		} else {
			post(
				header,
				captureStruct.event_id,
				timeVars.iso,
				jsonCapture
			);
		}
	}

	public SentryService function addExtraInfoUdf( required string key, required function udf ){
		variables.extraInfoUDFs[ arguments.key ] = arguments.udf;
		return this;
	}

	/**
	 * Post message to Sentry
	 */
	private void function post(
		required string header,
		required string event_id,
		required string sent_at,
		required string json
	){
		var http     = {};
		// send to sentry via REST API Call
		var httpBody = arguments.json;

		if ( getSentryEventEndpoint() == "envelope" ) {
			var envelope = [];

			arrayAppend(
				envelope,
				serializeJSON( {
					"event_id" : arguments.event_id,
					"sent_at"  : arguments.sent_at
				} )
			);
			arrayAppend(
				envelope,
				serializeJSON( {
					"type"         : "event",
					"length"       : len( arguments.json ),
					"content_type" : "application/json"
				} )
			);
			arrayAppend( envelope, arguments.json );


			httpBody = arrayToList( envelope, chr( 10 ) ) & chr( 10 );
		}

		cfhttp(
			url     = getSentryUrl() & "/api/" & getProjectID() & "/" & getSentryEventEndpoint() & "/",
			method  = "post",
			timeout = "2",
			result  = "http"
		) {
			cfhttpparam(
				type  = "header",
				name  = "X-Sentry-Auth",
				value = arguments.header
			);
			cfhttpparam( type = "body", value = httpBody );
		}

		if ( find( "400", http.statuscode ) || find( "500", http.statuscode ) || !find( "200", http.statuscode ) ) {
			if ( settings.throwOnPostError ) {
				throw( message = "Error posting to Sentry: #http.statuscode#", detail = http.filecontent );
			} else {
				writeDump(
					var    = "Error posting to Sentry: #http.statuscode# - #left( http.filecontent, 1000 )#",
					output = "console"
				);
			}
			// TODO : Honor Sentry’s HTTP 429 Retry-After header any other errors
		}
	}

	/**
	 * Get UTC time values
	 */
	private struct function getTimeVars(){
		var time     = now();
		var timeVars = {
			"unix" : toString( int( time.getTime() / 1000 ) ),
			"iso"  : dateTimeFormat( time, "yyyy-mm-dd'T'HH:nn:ss'Z'", "UTC" )
		};
		return timeVars;
	}

	/**
	 * Get the host name you are on
	 */
	private function getHostName(){
		try {
			return createObject( "java", "java.net.InetAddress" ).getLocalHost().getHostName();
		} catch ( Any e ) {
			return cgi.http_host;
		}
	}

	/**
	 * Get Real IP, by looking at clustered, proxy headers and locally.
	 */
	private function getRealIP(){
		var headers = getHTTPRequestData().headers;

		// When going through a proxy, the IP can be a delimtied list, thus we take the last one in the list

		if ( structKeyExists( headers, "x-cluster-client-ip" ) ) {
			return trim( listLast( headers[ "x-cluster-client-ip" ] ) );
		}
		if ( structKeyExists( headers, "X-Forwarded-For" ) ) {
			return trim( listFirst( headers[ "X-Forwarded-For" ] ) );
		}

		return len( cgi.remote_addr ) ? trim( listFirst( cgi.remote_addr ) ) : "127.0.0.1";
	}


	/**
	 * Sanitize the incoming http headers in the request data struct
	 *
	 * @data The HTTP data struct, passed by reference
	 */
	private function sanitizeHeaders( required struct headers ){
		if ( structCount( arguments.headers ) ) {
			for ( var thisHeader in variables.settings.scrubHeaders ) {
				// If header found, then sanitize it.
				if ( structKeyExists( arguments.headers, thisHeader ) ) {
					arguments.headers[ thisHeader ] = "[Filtered]";
				}
			}
		}

		if ( !variables.settings.sendCookies && structKeyExists( arguments.headers, "Cookie" ) ) {
			arguments.headers.Cookie = "[Filtered]";
		}

		// Sentry requires all headers be strings
		return arguments.headers.map( function( k, v ){
			return toString( v );
		} );
	}

	/**
	 * Sanitize fields
	 *
	 * @data The data fields
	 */
	private any function sanitizeFields( required any data ){
		if ( !isStruct( arguments.data ) ) {
			return arguments.data;
		}
		if ( structCount( arguments.data ) ) {
			for ( var thisField in variables.settings.scrubFields ) {
				// If field found, then sanitize it.
				if ( structKeyExists( arguments.data, thisField ) ) {
					arguments.data[ thisField ] = "[Filtered]";
				}
			}
		}
		return arguments.data;
	}

	/**
	 * Sanitize env/CGI vars
	 *
	 * @data The data fields
	 */
	private any function sanitizeEnv( required any data ){
		if ( !isStruct( arguments.data ) ) {
			return arguments.data;
		}

		// don't mutate CGI scope
		return arguments.data.map( function( k, v ){
			if ( !variables.settings.sendCookies && k == "http_cookie" ) {
				return "[Filtered]";
			}
			return v;
		} );
	}

	/**
	 * Sanitize the incoming query string
	 *
	 * @target The target string to sanitize
	 */
	private function sanitizeQueryString( required string target ){
		var aTarget = listToArray( target, "&" ).map( function( item, index, array ){
			var key   = listFirst( arguments.item, "=" );
			var value = listLen( arguments.item, "=" GT 1 ) ? listLast( arguments.item, "=" ) : "";

			// Sanitize?
			if ( arrayContainsNoCase( variables.settings.scrubFields, key ) ) {
				value = "[Filtered]";
			}

			return "#key#=#value#";
		} );
		return arrayToList( aTarget, "&" );
	}

	/**
	 * Turns all slashes in a path to forward slashes except for \\ in a Windows UNC network share
	 * Also changes double slashes to a single slash
	 *
	 * @path The path to normalize
	 */
	function normalizeSlashes( string path ){
		var normalizedPath = arguments.path.replace( "\", "/", "all" );
		if ( arguments.path.left( 2 ) == "\\" ) {
			normalizedPath = "\\" & normalizedPath.mid( 3, normalizedPath.len() - 2 );
		}
		return normalizedPath.replace( "//", "/", "all" );
	}

}
