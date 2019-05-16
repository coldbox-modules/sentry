/**
*********************************************************************************
* Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
* www.ortussolutions.com
* ---
* Connector to Sentry
*/
component accessors=true singleton {
	
	// DI
	property name="settings" inject="coldbox:moduleSettings:sentry";
	property name="moduleConfig" inject="coldbox:moduleConfig:sentry";
	property name="controller" inject="coldbox";


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
	/** The name of the server, defaults to machine name, then cgi.http_host */
	property name="serverName" type="string";
	/** Log messages async */
	property name="async" type="boolean";
	/** A UDF that generates user information for logged messages. Returns a struct containing keys "id", "email", "username", and anything else. */
	property name="userInfoUDF";
	
	property name="enabled";
	
	

	/**
	 * Constructor
	 */
	function init(){
		return this;
	}

	/**
	 * onDIComplete
	 */	
	function onDIComplete() {
		
		setEnabled( true );
		
		if ( len( settings.sentryUrl ) ) {
			setSentryUrl( settings.sentryUrl );
		}
		
		if( len( settings.DSN ) ) {
			setDSN( settings.DSN );
			parseDSN( settings.DSN );
		} else if( len( settings.publicKey ) && len( settings.privateKey ) && len( settings.projectID ) ) {
			setPublicKey( settings.publicKey );
			setPrivateKey( settings.privateKey );
			setProjectID( settings.projectID );
		} else {
			setPublicKey( '' );
			setPrivateKey( '' );
			setProjectID( 0 );
			setEnabled( false );
			writeDump( var="You must configure in a valid DSN or Project Keys and ID to instantiate the Sentry CFML Client.", output='console' );
		}
		
		setLevels(["fatal","error","warning","info","debug"]);
		
		setRelease( settings.release );
		setEnvironment( settings.environment );
		setServerName( settings.serverName );
		setAsync( settings.async );
		setSentryVersion( settings.sentryVersion );
		setLogger( settings.logger );
		setPlatform( settings.platform );
		
		setUserInfoUDF( settings.userInfoUDF );
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
	private void function parseDSN(required string DSN) {
		var pattern = "^(?:(\w+):)?\/\/(\w+)(:\w+)?@([\w\.-]+)\/(.*)";
		var result 	= reFind(pattern,arguments.DSN,1,true);
		var segments = [];

		for(var i=2; i LTE ArrayLen(result.pos); i++){
			// If the secret key is ommitted, the capture group will have a pos and len of 0
			if( result.len[i] ) {
				segments.append(mid(arguments.DSN, result.pos[i], result.len[i]));
			}
		}
		
		if ( segments.len() == 4 ){
			
			setSentryUrl(segments[1] & "://" & segments[3]);
			setPublicKey(segments[2]);
			setProjectID(segments[4]);
			
		} else if ( segments.len() == 5 ){
			
			setSentryUrl(segments[1] & "://" & segments[4]);
			setPublicKey(segments[2]);
			setPrivateKey(segments[3]);
			setProjectID(segments[5]);
			
		} else {
			throw(message="Error parsing Sentry DSN");			
		} 


	}

	/**
	* Validates that a correct level was set for a capture
	* The allowed levels are:
	* 	"fatal","error","warning","info","debug"
	*/
	private string function validateLevel(required string level) {
		if(!getLevels().findNoCase(arguments.level)) {
			throw( message="Error Type [#arguments.level#] is invalid. Must be one of the following : " & getLevels().toString() );
		}
		return lcase( arguments.level );
	}

	/**
	* Capture a message
	* https://docs.sentry.io/clientdev/interfaces/message/
	*
	* @message the raw message string ( max length of 1000 characters )
	* @level The level to log
	* @path The path to the script currently executing
	* @params an optional list of formatting parameters
	* @cgiVars Parameters to send to Sentry, defaults to the CGI Scope
	* @useThread Option to send post to Sentry in its own thread
	* @userInfo Optional Struct that gets passed to the Sentry User Interface
	* @additionalData Additional metadata to store with the event - passed into the extra attribute
	*/
	public any function captureMessage(
		required string message,
		string level = "info",
		string path = "",
		array params,
		any cgiVars = cgi,
		boolean useThread = getAsync(),
		struct userInfo = {},
		string logger=getLogger(),
		any additionalData
	) {
		if( !getEnabled() ) {
			return;
		}
		var sentryMessage = {};

		arguments.level = validateLevel(arguments.level);

		if (len(trim(arguments.message)) > 1000)
			arguments.message = left(arguments.message,997) & "...";

		sentryMessage = {
			"message" : arguments.message,
			"level" : arguments.level,
			"sentry.interfaces.Message" : {
				"message" : arguments.message
			},
			"logger" = arguments.logger
		};

		if(structKeyExists(arguments,"params")) {
			sentryMessage["sentry.interfaces.Message"]["params"] = arguments.params;
		}


		if ( !isNull(additionalData) ) {
			sentryMessage["extra"] = additionalData;
		}

		capture(
			captureStruct 	: sentryMessage,
			path 			: arguments.path,
			cgiVars 		: arguments.cgiVars,
			useThread 		: arguments.useThread,
			userInfo 		: arguments.userInfo
		);
	}

	/**
	* @exception The exception
	* @level The level to log
	* @path The path to the script currently executing
	* @useThread Option to send post to Sentry in its own thread
	* @userInfo Optional Struct that gets passed to the Sentry User Interface
	* @showJavaStackTrace Passes Java Stack Trace as a string to the extra attribute
	* @oneLineStackTrace Set to true to render only 1 tag context. This is not the Java Stack Trace this is simply for the code output in Sentry
	* @removeTabsOnJavaStackTrace Removes the tab on the child lines in the Stack Trace
	* @additionalData Additional metadata to store with the event - passed into the extra attribute
	* @cgiVars Parameters to send to Sentry, defaults to the CGI Scope
	* @useThread Option to send post to Sentry in its own thread
	* @userInfo Optional Struct that gets passed to the Sentry User Interface	*
	*/
	public any function captureException(
		required any exception,
		string level = "error",
		string path = "",
		boolean oneLineStackTrace = false,
		boolean showJavaStackTrace = false,
		boolean removeTabsOnJavaStackTrace = false,
		any additionalData,
		any cgiVars = cgi,
		boolean useThread = getAsync(),
		struct userInfo = {},
		string message = '',
		string logger=getLogger()
	) {
		if( !getEnabled() ) {
			return;
		}
		var sentryException 		= {
			"logger" = arguments.logger
		};
		
		var sentryExceptionExtra 	= {};
		var file 					= "";
		var fileArray 				= "";
		var currentTemplate 		= "";
		var tagContext 				= arguments.exception.TagContext;
		var i 						= 1;
		var st 						= "";

		arguments.level = validateLevel(arguments.level);

		/*
		* CORE AND OPTIONAL ATTRIBUTES
		* https://docs.sentry.io/clientdev/attributes/
		*/
		sentryException = {
			"message" 	: arguments.exception.message & " " & arguments.exception.detail,
			"level" 	: arguments.level,
			"culprit" 	: arguments.exception.message
		};
		
		if( arguments.message != arguments.exception.message ) {
			sentryException.message = arguments.message & " " & sentryException.message;  
		}

		if (arguments.showJavaStackTrace){
			st = reReplace(arguments.exception.StackTrace, "\r", "", "All");
			if (arguments.removeTabsOnJavaStackTrace)
				st = reReplace(st, "\t", "", "All");
			sentryExceptionExtra["Java StackTrace"] = listToArray(st,chr(10));
		}

		if (!isNull(arguments.additionalData))
			sentryExceptionExtra["Additional Data"] = arguments.additionalData;

		if (structCount(sentryExceptionExtra))
			sentryException["extra"] = sentryExceptionExtra;

		/*
		* EXCEPTION INTERFACE
		* https://docs.sentry.io/clientdev/interfaces/exception/
		*/
		sentryException["sentry.interfaces.Exception"] = {
			"value" : arguments.exception.message & " " & arguments.exception.detail,
			"type" 	: arguments.exception.type & " Error"
		};

		/*
		* STACKTRACE INTERFACE
		* https://docs.sentry.io/clientdev/interfaces/stacktrace/
		*/
		if (arguments.oneLineStackTrace)
			tagContext = [tagContext[1]];

		sentryException["sentry.interfaces.Stacktrace"] = {
			"frames" : []
		};
		
		var stacki = 0;
		for (i=arrayLen(tagContext); i > 0; i--) {
			stacki++;
			var thisTCItem = tagContext[i];
			if (compareNoCase(thisTCItem["TEMPLATE"],currentTemplate)) {
				fileArray = [];
				if (fileExists(thisTCItem["TEMPLATE"])) {
					file = fileOpen(thisTCItem["TEMPLATE"], "read");
					while (!fileIsEOF(file))
						arrayAppend(fileArray, fileReadLine(file));
					fileClose(file);
				}
				currentTemplate = thisTCItem["TEMPLATE"];
			}

			var thisStackItem = {
				"abs_path" 	= thisTCItem["TEMPLATE"],
				"filename" 	= thisTCItem["TEMPLATE"],
				"lineno" 	= thisTCItem["LINE"]
			};

			// The name of the function being called
			if (i == 1)
				thisStackItem["function"] = "column #thisTCItem["COLUMN"]#";
			else
				thisStackItem["function"] = thisTCItem["ID"];

			// for source code rendering
			thisStackItem["pre_context"] = [];
			if (thisTCItem["LINE"]-3 >= 1)
				thisStackItem["pre_context"][1] = fileArray[thisTCItem["LINE"]-3];
			if (thisTCItem["LINE"]-2 >= 1)
				thisStackItem["pre_context"][1] = fileArray[thisTCItem["LINE"]-2];
			if (thisTCItem["LINE"]-1 >= 1)
				thisStackItem["pre_context"][2] = fileArray[thisTCItem["LINE"]-1];
			if (arrayLen(fileArray))
				thisStackItem["context_line"] = fileArray[thisTCItem["LINE"]];

			thisStackItem["post_context"] = [];
			if (arrayLen(fileArray) >= thisTCItem["LINE"]+1)
				thisStackItem["post_context"][1] = fileArray[thisTCItem["LINE"]+1];
			if (arrayLen(fileArray) >= thisTCItem["LINE"]+2)
				thisStackItem["post_context"][2] = fileArray[thisTCItem["LINE"]+2];
				
			sentryException["sentry.interfaces.Stacktrace"]["frames"][stacki] = thisStackItem;
		}
		
		capture(
			captureStruct 	: sentryException,
			path 			: arguments.path,
			cgiVars 		: arguments.cgiVars,
			useThread 		: arguments.useThread,
			userInfo 		: arguments.userInfo
		);
	}

	/**
	* Prepare message to post to Sentry
	*
	* @captureStruct The struct we are passing to Sentry
	* @cgiVars Parameters to send to Sentry, defaults to the CGI Scope
	* @path The path to the script currently executing
	* @useThread Option to send post to Sentry in its own thread
	* @userInfo Optional Struct that gets passed to the Sentry User Interface
	*/
	public void function capture(
		required any captureStruct,
		any cgiVars = cgi,
		string path = "",
		boolean useThread = getAsync(),
		struct userInfo = {}
	) {
		var jsonCapture 	= "";
		var signature 		= "";
		var header 			= "";
		var timeVars 		= getTimeVars();
		var httpRequestData = getHTTPRequestData();

		// Add global metadata
		arguments.captureStruct["event_id"] 	= lcase(replace(createUUID(), "-", "", "all"));
		arguments.captureStruct["timestamp"] 	= timeVars.timeStamp;
		arguments.captureStruct["project"] 		= getProjectID();
		arguments.captureStruct["server_name"] 	= getServerName();
		arguments.captureStruct["platform"] 	= getPlatform();
		arguments.captureStruct["release"] 		= getRelease();
		arguments.captureStruct["environment"] 	= getEnvironment();

		/*
		* User interface
		* https://docs.sentry.io/clientdev/interfaces/user/
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
		var thisUserInfo = {
			'ip_address' = getRealIP()
		};
		
		var userInfoUDF = getUserInfoUDF();
		// If there is a closure to produce user info, call it
		if( isCustomFunction( userInfoUDF ) ) {
			
			// Prepare the request context for the closure to use
			var event = controller.getRequestService().getContext();
			// Call the custon closure to produce user info
			local.tmpUserInfo = userInfoUDF( event, event.getCollection(), event.getPrivateCollection(), controller  );
			
			if( !isNull( local.tmpUserInfo ) && isStruct( local.tmpUserInfo ) ) {
				thisUserInfo.append( local.tmpUserInfo );
			}
			
		}
		if ( !arguments.userInfo.isEmpty() ) {
			thisUserInfo.append( arguments.userInfo );
		}
		
		// Force lowercasing on these since Sentry looks for them
		// Stupid CF won't udpate key casing in-place, so creating a new struct.
		var correctCasingUserInfo = {};
		for( var key in thisUserInfo ) {
			if( listFindNoCase( 'id,email,ip_address,username', key ) ) {
				key = lcase( key );
			}
			correctCasingUserInfo[ key ] = thisUserInfo[ key ];
		}
				
		arguments.captureStruct["sentry.interfaces.User"] = correctCasingUserInfo;

		// Prepare path for HTTP Interface
		arguments.path = trim(arguments.path);
		if (!len(arguments.path))
			arguments.path = "http" & (arguments.cgiVars.server_port_secure ? "s" : "") & "://" & arguments.cgiVars.server_name & arguments.cgiVars.script_name;

		// HTTP interface
		// https://docs.sentry.io/clientdev/interfaces/http/
		arguments.captureStruct["sentry.interfaces.Http"] = {
			"sessions" 		: session,
			"url" 			: arguments.path,
			"method" 		: arguments.cgiVars.request_method,
			"data" 			: sanitizeFields( form ),
			"query_string" 	: sanitizeQueryString( arguments.cgiVars.query_string ),
							// Sentry requires all cookies be strings
			"cookies" 		: cookie.map( function( k, v ) {
								return toString( v );
							} ),
			"env" 			: arguments.cgiVars,
			"headers" 		: sanitizeHeaders( httpRequestData.headers )
		};
		// serialize data
		jsonCapture = serializeJSON(arguments.captureStruct);
		
		// prepare header
		header = "Sentry sentry_version=#getSentryVersion()#, sentry_timestamp=#timeVars.time#, sentry_key=#getPublicKey()#, sentry_secret=#getPrivateKey()#, sentry_client=Sentry/#moduleConfig.version#";
		// post message
		if (arguments.useThread){
			cfthread(
				action 			= "run",
				name 			= "sentry-thread-" & createUUID(),
				header   		= header,
				jsonCapture 	= jsonCapture
			){
				post(header,jsonCapture);
			}
		} else {
			post(header,jsonCapture);
		}
	}

	/**
	* Post message to Sentry
	*/
	private void function post(
		required string header,
		required string json
	) {
		var http = {};
		// send to sentry via REST API Call
		
		cfhttp(
			url 	: getSentryUrl() & "/api/store/",
			method 	: "post",
			timeout : "2",
			result 	: "http"
		){
			cfhttpparam(type="header",name="X-Sentry-Auth",value=arguments.header);
			cfhttpparam(type="body",value=arguments.json);
		}
						
		if( find( "400", http.statuscode ) || find( "500", http.statuscode ) ){
			writeDump( var="Error posting to Sentry: #http.statuscode# - #left( http.filecontent, 1000 )#", output='console' );	 
		// TODO : Honor Sentry’s HTTP 429 Retry-After header any other errors
		} else if (!find("200",http.statuscode)){
			writeDump( var="Error posting to Sentry: #http.statuscode# - #left( http.filecontent, 1000 )#", output='console' );
		}
	}

	/**
	* Get UTC time values
	*/
	private struct function getTimeVars() {
		var time 		= now();
		var timeVars 	= {
			"time" 			: time.getTime(),
			"utcNowTime" 	: dateConvert("Local2UTC", time)
		};
		timeVars.timeStamp = dateformat(timeVars.utcNowTime, "yyyy-mm-dd") & "T" & timeFormat(timeVars.utcNowTime, "HH:mm:ss");
		return timeVars;
	}
	
	/**
	 * Get the host name you are on
	 */
	private function getHostName(){
		try{
			return createObject( "java", "java.net.InetAddress").getLocalHost().getHostName();
		}
		catch(Any e ){
			return cgi.http_host;
		}
	}

	/**
	* Get Real IP, by looking at clustered, proxy headers and locally.
	*/
	private function getRealIP(){
		var headers = GetHttpRequestData().headers;

		// When going through a proxy, the IP can be a delimtied list, thus we take the last one in the list
		
		if( structKeyExists( headers, 'x-cluster-client-ip' ) ){
			return trim( listLast( headers[ 'x-cluster-client-ip' ] ) );
		}
		if( structKeyExists( headers, 'X-Forwarded-For' ) ){
			return trim( listLast( headers[ 'X-Forwarded-For' ] ) );
		}

		return len( cgi.remote_addr ) ? trim( listLast( cgi.remote_addr ) ) : '127.0.0.1';
	}
	

	/**
	 * Sanitize the incoming http headers in the request data struct
	 * @data The HTTP data struct, passed by reference
	 */
	private function sanitizeHeaders( required struct headers ){
		if( structCount( arguments.headers ) ){
			for( var thisHeader in variables.settings.scrubHeaders ){
				// If header found, then sanitize it.
				if( structKeyExists( arguments.headers, thisHeader ) ){
					arguments.headers[ thisHeader ] = "[Filtered]";
				}
			}
		}
		// Sentry requires all headers be strings
		return arguments.headers.map( function( k, v ) {
			return toString( v );
		} );
	}

	/**
	 * Sanitize fields
	 * @data The data fields struct
	 */
	private struct function sanitizeFields( required struct data ){
		if( structCount( arguments.data ) ){
			for( var thisField in variables.settings.scrubFields ){
				// If header found, then sanitize it.
				if( structKeyExists( arguments.data, thisField ) ){
					arguments.data[ thisField ] = "[Filtered]";
				}
			}
		}
		return arguments.data;
	}

	/**
	 * Sanitize the incoming query string
	 * @target The target string to sanitize
	 */
	private function sanitizeQueryString( required string target ){
		var aTarget = listToArray( target, "&" )
			.map( function( item, index, array ){
				var key 	= listFirst( arguments.item, "=" );
				var value 	= listLast( arguments.item, "=" );

				// Sanitize?
				if( arrayContainsNoCase( variables.settings.scrubFields, key ) ){
					value = "[Filtered]";
				}

				return "#key#=#value#";
		} );
		return arrayToList( aTarget, "&" );
	}



}