component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "Sentry request URLs", function(){
			it( "omits CFML and BoxLang front controllers for rewritten paths", function(){
				for ( var script in [ "/index.cfm", "/index.bxm" ] ) {
					expectCapturedURLs(
						script,
						"/foo/bar",
						"http://example.test/foo/bar"
					);
				}
			} );
			it( "preserves HTTPS for rewritten paths", function(){
				for ( var script in [ "/index.cfm", "/index.bxm" ] ) {
					expectCapturedURLs(
						script,
						"/api/v1/user",
						"https://example.test/api/v1/user",
						true
					);
				}
			} );
			it( "recognizes front controllers without regard to case", function(){
				for ( var script in [ "/INDEX.CFM", "/INDEX.BXM" ] ) {
					expectCapturedURLs(
						script,
						"/foo/bar",
						"http://example.test/foo/bar"
					);
				}
			} );
			it( "preserves front controllers when there is no rewritten path", function(){
				for ( var script in [ "/index.cfm", "/index.bxm" ] ) {
					expectCapturedURLs( script, "", "http://example.test" & script );
				}
			} );
			it( "preserves other scripts and nested front controllers", function(){
				for (
					var script in [
						"/report.cfm",
						"/report.bxm",
						"/app/index.cfm",
						"/app/index.bxm"
					]
				) {
					expectCapturedURLs(
						script,
						"/foo/bar",
						"http://example.test" & script & "/foo/bar"
					);
				}
			} );
			it( "preserves explicitly supplied URLs", function(){
				for ( var script in [ "/index.cfm", "/index.bxm" ] ) {
					expectCapturedURLs(
						script,
						"/foo/bar",
						"https://override.test/index.bxm/explicit",
						false,
						"  https://override.test/index.bxm/explicit  "
					);
				}
			} );
		} );
	}

	private function expectCapturedURLs(
		required string script,
		required string pathInfo,
		required string expected,
		boolean secure = false,
		string path    = ""
	){
		var service = createMock( "sentry.models.SentryService" );
		var cgiVars = {
			"server_name"        : "example.test",
			"remote_addr"        : "127.0.0.1",
			"script_name"        : arguments.script,
			"path_info"          : arguments.pathInfo,
			"server_port_secure" : arguments.secure
		};
		service.$property( "cgi", "variables", cgiVars );
		service.init( {
			"DSN"   : "https://synthetic@example.test/1",
			"async" : false
		} );
		service.$( "getHTTPDataForRequest", { "headers" : {}, "content" : "" } );
		service.$( "post" );
		service.captureMessage(
			message   = "Synthetic URL test",
			path      = arguments.path,
			cgiVars   = cgiVars,
			useThread = false
		);
		service.captureException(
			exception = { "message" : "Synthetic URL exception", "stackTrace" : "" },
			path      = arguments.path,
			cgiVars   = cgiVars,
			useThread = false
		);
		var calls = service.$callLog( "post" ).post;
		expect( calls.len() ).toBe( 2 );
		for ( var captured in calls ) {
			expect( deserializeJSON( captured[ 4 ] ).request.url ).toBe( arguments.expected );
		}
	}

}
