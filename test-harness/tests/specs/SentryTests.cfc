/**
* My BDD Test
*/
component extends='coldbox.system.testing.BaseTestCase' appMapping='/root'{

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
		describe( 'Sentry Module', function(){

			beforeEach(function( currentSpec ){
				setup();
			});

			it( 'should register library', function(){
				var service = getSentry();
				expect(	service ).toBeComponent();
			});

			it( 'can log message', function(){
				var service = getSentry();
				service.captureMessage( 'This is a test message' );
			});

			it( 'can log via LogBox', function(){
				getLogbox().getRootLogger().error( 'Custom Boom', { "extra" : "info" } );
			});

			it( 'should trap exceptions and do logging', function(){
				expect(	function(){
					execute( 'main.index' );
				}).toThrow( 'ThrownFromMain' );
			});

		});
	}

	private function getSentry(){
		return getWireBox().getInstance( 'SentryService@sentry' );
	}

}