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
					getLogbox().getRootLogger().error( e.message, e );
				}
			} );

			it( "can log exception with no tagContext", function(){
				try {
					throw( "Missing tag Context" );
				} catch ( any e ) {
					var newE = {};
					for ( var key in e ) {
						if ( key != "TagContext" ) {
							newE[ key ] = e[ key ];
						}
					}
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
		} );
	}



	private function getSentry(){
		return getWireBox().getInstance( "SentryService@sentry" );
	}

}
