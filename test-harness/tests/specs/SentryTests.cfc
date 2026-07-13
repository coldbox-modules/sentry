/**
 * My BDD Test
 */
component extends="coldbox.system.testing.BaseTestCase" appMapping="/root" {

	this.loadColdbox = true;

	/*********************************** LIFE CYCLE Methods ***********************************/

	// executes before all suites+specs in the run() method
	function beforeAll(){
		super.beforeAll();
	}

	// executes after all suites+specs in the run() method
	function afterAll(){
		super.afterAll();
	}

	/*********************************** BDD SUITES ***********************************/

	function run(){
		// all your suites go here.
		describe( "Sentry Module", function(){
			beforeEach( function( currentSpec ){
				setup();
			} );

			it( "should register library", function(){
				var service = getSentry();
				expect( service ).toBeComponent();
			} );

			it( "can log message", function(){
				var service = getSentry();
				service.captureMessage( "This is a test message" );
			} );

			it( "can log via LogBox", function(){
				getLogbox().getRootLogger().error( "Custom Boom", { "extra" : "info" } );
			} );

			it( "can log Java exception", function(){
				var getNull = function(){
				};
				try {
					foo = createObject( "java", "java.io.File" ).init( getNull() );
				} catch ( any e ) {
					getLogbox().getRootLogger().error( e.message ?: "Java exception", e );
				}
			} );

			it( "can log exception with no tagContext", function(){
				try {
					throw( "Missing tag Context" );
				} catch ( any e ) {
					var newE = duplicate( e );
					structDelete( newE, "TagContext" );
					getLogbox().getRootLogger().error( "Missing tag Context", newE );
				}
			} );

			it( "can log exception with Extra Error Info", function(){
				try {
					throw( "Extra Error Info" );
				} catch ( any e ) {
					e.NativeErrorCode = "This is my NativeErrorCode";
					e.SQLState        = "This is my SQLState";
					e.Sql             = "This is my Sql";
					e.queryError      = "This is my queryError";
					e.where           = "This is my where";
					e.ErrNumber       = "This is my ErrNumber";
					e.MissingFileName = "This is my MissingFileName";
					e.LockName        = "This is my LockName";
					e.LockOperation   = "This is my LockOperation";
					e.ErrorCode       = "This is my ErrorCode";
					e.ExtendedInfo    = "This is my ExtendedInfo";

					getLogbox().getRootLogger().error( "Extra Error Info", e );
				}
			} );

			it( "should trap exceptions and do logging", function(){
				expect( function(){
					execute( "main.index" );
				} ).toThrow( "ThrownFromMain" );
			} );

			it( "can log a message with extra info automatically added", function(){
				var service = prepareMock( getSentry() );
				service.setEnabled( true );
				service.$( "post" );

				service.addExtraInfoUdf( "queries", function(){
					return [ "foo", "bar" ];
				} );
				service.addExtraInfoUdf( "qb", function(){
					return [ "foo", "bar" ];
				} );
				service.captureMessage( "This is a test message" );
				var extra = deserializeJSON( service.$callLog( "post" ).post[ 1 ][ 4 ] ).extra;
				expect( extra ).toHaveKey( "queries" );
				expect( extra ).toHaveKey( "qb" );
				expect( extra.queries ).toBe( [ "foo", "bar" ] );
				expect( extra.qb ).toBe( [ "foo", "bar" ] );
			} );

			it( "Can capture traceparent data from the http request", function(){
				var service         = prepareMock( getSentry() );
				var testTraceParent = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01";
				service.setEnabled( true );
				service.$(
					method   = "getHTTPDataForRequest",
					callback = function(){
						return {
							"headers" : { "traceparent" : testTraceParent },
							"content" : ""
						};
					}
				);
				service.$( "post" );

				service.captureMessage( "This is a test message" );
				var traceParent = service.$callLog( "post" ).post[ 1 ][ 5 ];
				expect( traceParent ).toBe( testTraceParent );
			} );



			it( "Can capture traceparent data from the cbotel module", function(){
				var service         = prepareMock( getSentry() );
				var testTraceParent = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01";
				service.setEnabled( true );
				service.setColdbox( getController() );

				getController()
					.getRequestService()
					.getContext()
					.setPrivateValue( "openTelemetry", { "traceparent" : testTraceParent } );
				service.$( "post" );
				service.captureMessage( "This is a test message" );
				var traceParent = service.$callLog( "post" ).post[ 1 ][ 5 ];
				expect( traceParent ).toBe( testTraceParent );
			} );

			// ========== Java Stack Trace Parsing Tests ==========

			it( "can parse a simple Java stack trace into exception values", function(){
				var service = prepareMock( getSentry() );
				service.setEnabled( true );
				service.$( "post" );

				var testException = {
					"message"    : "Something failed",
					"detail"     : "",
					"type"       : "application",
					"TagContext" : [],
					"StackTrace" : "java.lang.NullPointerException: null object reference
			at com.example.MyClass.myMethod(MyClass.java:42)
			at com.example.MyClass.otherMethod(MyClass.java:100)
			at org.apache.catalina.core.StandardWrapper.invoke(StandardWrapper.java:500)"
				};

				service.captureException( exception = testException, showJavaStackTrace = true );

				var payload   = deserializeJSON( service.$callLog( "post" ).post[ 1 ][ 4 ] );
				var excValues = payload.exception.values;

				// Should have 2 entries: BoxLang exception + Java exception
				expect( excValues.len() ).toBe( 2 );

				// First entry is the BoxLang CFML exception
				expect( excValues[ 1 ].type ).toBe( "application Error" );
				expect( excValues[ 1 ].stacktrace.frames.len() ).toBe( 0 );

				// Second entry is the parsed Java exception
				expect( excValues[ 2 ].type ).toBe( "java.lang.NullPointerException" );
				expect( excValues[ 2 ].value ).toBe( "null object reference" );
				expect( excValues[ 2 ].stacktrace.frames.len() ).toBe( 3 );

				// Verify first frame parsing
				var frame1 = excValues[ 2 ].stacktrace.frames[ 1 ];
				expect( frame1.function ).toBe( "com.example.MyClass.myMethod" );
				expect( frame1.filename ).toBe( "MyClass.java" );
				expect( frame1.lineno ).toBe( 42 );
				expect( frame1.abs_path ).toBe( "com.example.MyClass" );
			} );

			it( "marks application frames as in_app and framework frames as not", function(){
				var service = prepareMock( getSentry() );
				service.setEnabled( true );
				service.$( "post" );

				var testException = {
					"message"    : "Error",
					"detail"     : "",
					"type"       : "application",
					"TagContext" : [],
					"StackTrace" : "java.io.IOException: file not found
			at com.example.service.FileHelper.read(FileHelper.java:55)
			at org.apache.commons.io.IOUtils.toString(IOUtils.java:2000)
			at java.io.FileInputStream.<init>(FileInputStream.java:138)"
				};

				service.captureException( exception = testException, showJavaStackTrace = true );

				var payload   = deserializeJSON( service.$callLog( "post" ).post[ 1 ][ 4 ] );
				var excValues = payload.exception.values;
				var frames    = excValues[ 2 ].stacktrace.frames;

				// com.example = in_app
				expect( frames[ 1 ].in_app ).toBe( true );
				// org.apache.commons = not in_app
				expect( frames[ 2 ].in_app ).toBe( false );
				// java.io = not in_app
				expect( frames[ 3 ].in_app ).toBe( false );
			} );

			it( "parses Native Method frames without line numbers", function(){
				var service = prepareMock( getSentry() );
				service.setEnabled( true );
				service.$( "post" );

				var testException = {
					"message"    : "Error",
					"detail"     : "",
					"type"       : "expression",
					"TagContext" : [],
					"StackTrace" : "java.lang.NullPointerException
			at java.io.FileInputStream.open0(Native Method)
			at java.io.FileInputStream.open(FileInputStream.java:195)
			at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method)"
				};

				service.captureException( exception = testException, showJavaStackTrace = true );

				var payload = deserializeJSON( service.$callLog( "post" ).post[ 1 ][ 4 ] );
				var frames  = payload.exception.values[ 2 ].stacktrace.frames;

				// Native Method frame — no line number
				expect( frames[ 1 ].lineno ).toBe( 0 );
				expect( frames[ 1 ].function ).toBe( "java.io.FileInputStream.open0" );
				expect( frames[ 1 ].filename ).toBe( "" );

				// Regular frame with line number
				expect( frames[ 2 ].lineno ).toBe( 195 );
				expect( frames[ 2 ].filename ).toBe( "FileInputStream.java" );
			} );

			it( "parses Caused by chains into multiple exception values", function(){
				var service = prepareMock( getSentry() );
				service.setEnabled( true );
				service.$( "post" );

				var testException = {
					"message"    : "Wrapper error",
					"detail"     : "",
					"type"       : "application",
					"TagContext" : [],
					"StackTrace" : "java.lang.RuntimeException: something went wrong
			at com.example.App.main(App.java:10)
			Caused by: java.io.FileNotFoundException: /tmp/missing.txt
			at java.io.FileInputStream.open0(Native Method)
			at java.io.FileInputStream.<init>(FileInputStream.java:138)
			... 3 more"
				};

				service.captureException( exception = testException, showJavaStackTrace = true );

				var payload   = deserializeJSON( service.$callLog( "post" ).post[ 1 ][ 4 ] );
				var excValues = payload.exception.values;

				// Should have 3 entries: BoxLang + RuntimeException + FileNotFoundException
				expect( excValues.len() ).toBe( 3 );

				// Second entry: RuntimeException
				expect( excValues[ 2 ].type ).toBe( "java.lang.RuntimeException" );
				expect( excValues[ 2 ].value ).toBe( "something went wrong" );
				expect( excValues[ 2 ].stacktrace.frames.len() ).toBe( 1 );

				// Third entry: FileNotFoundException
				expect( excValues[ 3 ].type ).toBe( "java.io.FileNotFoundException" );
				expect( excValues[ 3 ].value ).toBe( "/tmp/missing.txt" );
				// "... 3 more" should be skipped, only 2 actual frames
				expect( excValues[ 3 ].stacktrace.frames.len() ).toBe( 2 );
			} );

			it( "does not add Java stack trace entries when showJavaStackTrace is false", function(){
				var service = prepareMock( getSentry() );
				service.setEnabled( true );
				service.$( "post" );

				var testException = {
					"message"    : "Error",
					"detail"     : "",
					"type"       : "application",
					"TagContext" : [ { "TEMPLATE" : "/test.cfm", "LINE" : 1 } ],
					"StackTrace" : "java.lang.RuntimeException: boom
			at com.example.App.main(App.java:10)"
				};

				service.captureException( exception = testException, showJavaStackTrace = false );

				var payload   = deserializeJSON( service.$callLog( "post" ).post[ 1 ][ 4 ] );
				var excValues = payload.exception.values;

				// Should only have 1 entry: BoxLang exception
				expect( excValues.len() ).toBe( 1 );
				expect( excValues[ 1 ].type ).toBe( "application Error" );
			} );

			it( "forces showJavaStackTrace when TagContext is empty", function(){
				var service = prepareMock( getSentry() );
				service.setEnabled( true );
				service.$( "post" );

				var testException = {
					"message"    : "Error",
					"detail"     : "",
					"type"       : "application",
					"TagContext" : [],
					"StackTrace" : "java.lang.NullPointerException
			at com.example.App.run(App.java:25)"
				};

				// Even with showJavaStackTrace defaulting to false,
				// empty TagContext should force it on
				service.captureException( exception = testException );

				var payload   = deserializeJSON( service.$callLog( "post" ).post[ 1 ][ 4 ] );
				var excValues = payload.exception.values;

				expect( excValues.len() ).toBe( 2 );
				expect( excValues[ 2 ].type ).toBe( "java.lang.NullPointerException" );
			} );

			it( "handles exception messages with no colon separator", function(){
				var service = prepareMock( getSentry() );
				service.setEnabled( true );
				service.$( "post" );

				var testException = {
					"message"    : "Error",
					"detail"     : "",
					"type"       : "application",
					"TagContext" : [],
					"StackTrace" : "NullPointerException
			at com.example.App.run(App.java:25)"
				};

				service.captureException( exception = testException, showJavaStackTrace = true );

				var payload   = deserializeJSON( service.$callLog( "post" ).post[ 1 ][ 4 ] );
				var excValues = payload.exception.values;

				expect( excValues.len() ).toBe( 2 );
				expect( excValues[ 2 ].type ).toBe( "NullPointerException" );
			} );

			it( "parses Suppressed exceptions into separate values", function(){
				var service = prepareMock( getSentry() );
				service.setEnabled( true );
				service.$( "post" );

				var testException = {
					"message"    : "Error",
					"detail"     : "",
					"type"       : "application",
					"TagContext" : [],
					"StackTrace" : "java.io.IOException: original error
	at com.example.App.main(App.java:10)
	Suppressed: java.io.IOException: suppressed error
	at com.example.App.helper(App.java:20)
	... 1 more"
				};

				service.captureException( exception = testException, showJavaStackTrace = true );

				var payload   = deserializeJSON( service.$callLog( "post" ).post[ 1 ][ 4 ] );
				var excValues = payload.exception.values;

				// BoxLang + original IOException + suppressed IOException
				expect( excValues.len() ).toBe( 3 );
				expect( excValues[ 2 ].type ).toBe( "java.io.IOException" );
				expect( excValues[ 2 ].value ).toBe( "original error" );
				expect( excValues[ 2 ].stacktrace.frames.len() ).toBe( 1 );
				expect( excValues[ 3 ].type ).toBe( "java.io.IOException" );
				expect( excValues[ 3 ].value ).toBe( "suppressed error" );
				expect( excValues[ 3 ].stacktrace.frames.len() ).toBe( 1 );
			} );

			it( "skips Java stack trace parsing when TagContext is available", function(){
				var service = prepareMock( getSentry() );
				service.setEnabled( true );
				service.$( "post" );

				var testException = {
					"message"    : "Error",
					"detail"     : "",
					"type"       : "application",
					"TagContext" : [ { "TEMPLATE" : "/test.cfm", "LINE" : 1 } ],
					"StackTrace" : "java.lang.RuntimeException: boom
	at com.example.App.main(App.java:10)"
				};

				// Even with showJavaStackTrace=true, TagContext is available
				service.captureException( exception = testException, showJavaStackTrace = true );

				var payload   = deserializeJSON( service.$callLog( "post" ).post[ 1 ][ 4 ] );
				var excValues = payload.exception.values;

				// Should only have 1 entry — CFML frames are sufficient
				expect( excValues.len() ).toBe( 1 );
				expect( excValues[ 1 ].type ).toBe( "application Error" );
			} );
		} );
	}



	private function getSentry(){
		return getWireBox().getInstance( "SentryService@sentry" );
	}

}
