/**
*********************************************************************************
* Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
* www.ortussolutions.com
* ---
* Connector to Sentry
*/
component accessors=true singleton{
	
	/**
	 * Module  Settings
	 */
	property name="settings" type="struct";
	/**
	 * Module Configuration struct
	 */
	property name="moduleConfig" type="struct";
	/**
	 * API Base URL
	 */	
	property name="APIBaseURL" default="https://api.sentry.com/api/1/item/";

	/**
	 * Constructor
	 * @settings The module settings
	 * @settings.inject coldbox:moduleSettings:sentry
	 * @coldbox.inject coldbox
	 */
	function init(
		required struct settings,
		required coldbox 
	){
		// module settings
		variables.settings 	= arguments.settings;
		// coldbox reference
		variables.coldbox 	= arguments.coldbox;
		// module config
		variables.moduleConfig = variables.coldbox.getSetting( "modules" ).sentry;

		return this;
	}

	/**
	 * Send a message to sentry
	 * @message A string message
	 * @metadata A struct of metadata to send alongside the message
	 * @level One of: "critical", "error", "warning", "info", "debug", defaults to "info"
	 *
	 * @return struct 
	 */
	function sendMessage( required string message, struct metadata={}, level="info" ){
		return sendToSentry(
			logBody 	= {
				"message" : {
					"body" : arguments.message
				}
			},
			metadata 	= arguments.metadata,
			level  		= arguments.level
		);
	}

	/**
	 * Sanitize the incoming http headers in the request data struct
	 * @data The HTTP data struct, passed by reference
	 */
	private function sanitizeHeaders( required struct data ){
		if( structCount( arguments.data.headers ) ){
			for( var thisHeader in variables.settings.scrubHeaders ){
				// If header found, then sanitize it.
				if( structKeyExists( arguments.data.headers, thisHeader ) ){
					arguments.data.headers[ thisHeader ] = "*";
				}
			}
		}
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
					arguments.data[ thisField ] = "*";
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
		var aTarget = listToArray( cgi.query_string, "&" )
			.map( function( item, index, array ){
				var key 	= listFirst( arguments.item, "=" );
				var value 	= listLast( arguments.item, "=" );

				// Sanitize?
				if( arrayContainsNoCase( variables.settings.scrubFields, key ) ){
					value = "*";
				}

				return "#key#=#value#";
		} );
		return arrayToList( aTarget, "&" );
	}

	/**
	 * Send a log body to sentry
	 * @logBody The logBody struct to send as a message
	 * @metadata A struct of metadata to send alongside the message
	 * @level One of: "critical", "error", "warning", "info", "debug", defaults to "info"
	 *
	 * @return struct 
	 */
	function sendToSentry( required struct logBody, struct metadata={}, level="info" ){
		var threadName 	= "sentry-#createUUID()#";
		var event 		= variables.coldbox.getRequestService().getContext();
		var httpData 	= getHTTPRequestData();

		// Sanitize headers
		sanitizeHeaders( httpData );

		// ColdBox Environment
		var coldboxEnv = {
			"currentEvent"		: event.getCurrentEvent(),
			"currentRoute"		: event.getCurrentRoute(),
			"currentLayout"		: event.getCurrentLayout(),
			"currentView"		: event.getCurrentView(),
			"currentModule"		: event.getCurrentModule(),
			"currentRoutedURL"	: event.getCurrentRoutedURL()
		};

		// Append to custom metadata
		structAppend( arguments.metadata, coldboxEnv, true );

		// Create payload
		var payload = {
			"access_token" 	: variables.settings.serverSideToken,
			"data" 			: {
				// app environment
				"environment"	: variables.coldbox.getSetting( "environment" ),
				// The main data being sent
				"body" 			: arguments.logBody,
				// Severity level, defaults to "info" for messages
				"level" 		: arguments.level,
				// OS platform
				"platform"		: server.os.name,
				// language
				"language"		: "ColdFusion(CFML)",
				// Framework
				"framework"		: "ColdBox",
				// An identifier for which part of your application this event came from.
				"context" 		: event.getCurrentEvent(),
				// Data about the request this event occurred in.
				"request" 		: {
					// url: full URL where this event occurred, without query string
					"url" 			: listFirst( CGI.REQUEST_URL, "?" ),
					// method: the request method
					"method" 		: httpData.method,
					// query_string: the raw query string
		      		"query_string" 	: sanitizeQueryString( CGI.QUERY_STRING ),
					// Headers
					"headers" 		: httpData.headers,
					// Raw Body
					"body" 			: httpData.content,
					// POST: POST params
		      		"POST" 			: sanitizeFields( FORM ),
		      		// GET: query string params
		      		"GET" 			: sanitizeFields( URL ),
					// IP Address of request
					"user_ip" 		: getRealIP()
				},
				// Server information
				"server" : {
					"host" : getHostName(),
					"root" : CGI.cf_template_path
				},
				// Client Information
				"client" : {
					"browser" : CGI.http_user_agent
				},
				// Custom metadata
				"custom" : arguments.metadata,
				// Libary Used
				"notifier" 		: {
					"name" 		: "ColdBox Sentry Module",
			  		"version"	: variables.moduleConfig.version
				}
			}
		};

		var APIBaseURL = getAPIBaseURL();
		// thread the http call so we are non-blocking
		thread 
			name="#threadName#" 
			action="run"
			payload=payload
		{
			var h = new HTTP( url=variables.APIBaseURL, method="POST" );
			h.addParam( type="BODY", value=serializeJSON( payload ) );
			thread.response = h.send().getPrefix();

			if( server.keyExists( "lucee" ) ){
				systemOutput( "Sent to sentry: #thread.response.toString()#" );
			}
		}
		// return thread information
		return cfthread[ threadName ];
	}

	/**
	 * Convert an exception to log body struct
	 * @exception The exception object
	 */
	public function exceptionToLogBody( required exception ){
		var logBody = {
	        // Option 1: "trace"
			"trace" : marshallStackTrace( arguments.exception )
		};
		return logBody;
	}

	/**
	 * Marshall a stack trace
	 * @exception The exception object
	 */
	private function marshallStackTrace( required exception ){

		/**
		 * Format Frame
		 */
		var formatFrame = function( required stackItem ){
			return {
				"filename" 	: arguments.stackItem.template,
				"lineno" 	: arguments.stackItem.line,
				"colno" 	: arguments.stackItem.column,
				"method" 	: arguments.stackItem.Raw_Trace,
				// The line of code
				"code" 		: arguments.stackItem.codePrintPlain ?: ''
			};
		};

		var trace = {
			"exception": {
				"class" 		: arguments.exception.Type,
				"message" 		: arguments.exception.Message,
				"description"	: arguments.exception.Detail
	        },
			"frames" 			: []
		};

		for( var stackItem in arguments.exception.TagContext ){
			arrayAppend( trace.frames, formatFrame( stackItem ) );
		}

		return trace;
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

		// Very balanced headers
		if( structKeyExists( headers, 'x-cluster-client-ip' ) ){
			return headers[ 'x-cluster-client-ip' ];
		}
		if( structKeyExists( headers, 'X-Forwarded-For' ) ){
			return headers[ 'X-Forwarded-For' ];
		}

		return len( cgi.remote_addr ) ? cgi.remote_addr : '127.0.0.1';
	}
}