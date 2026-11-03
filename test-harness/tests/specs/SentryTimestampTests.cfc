/**
 * Timestamp serialization must work without CFML date-mask compatibility.
 */
component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "Sentry timestamps", function(){
			it( "keeps UTC months and minutes distinct", function(){
				var service = createMock( "sentry.models.SentryService" );
				makePublic( service, "getTimeVars" );
				var samples = [
					{
						"instant" : "2026-09-14T00:49:38Z",
						"unix"    : "1789346978"
					},
					{
						"instant" : "2026-09-14T00:49:38.900Z",
						"iso"     : "2026-09-14T00:49:38Z",
						"unix"    : "1789346978"
					},
					{
						"instant" : "2026-01-01T00:00:00Z",
						"unix"    : "1767225600"
					},
					{
						"instant" : "2026-12-31T23:12:59Z",
						"unix"    : "1798758779"
					}
				];
				for ( var sample in samples ) {
					var reference = createObject( "java", "java.util.Date" ).init(
						createObject( "java", "java.time.Instant" ).parse( sample.instant ).toEpochMilli()
					);
					var timestamps = service.getTimeVars( reference );

					expect( timestamps.iso ).toBe( sample.iso ?: sample.instant );
					expect( timestamps.unix ).toBe( sample.unix );
				}
			} );
			it( "uses the current instant when no time is supplied", function(){
				var service = createMock( "sentry.models.SentryService" );
				makePublic( service, "getTimeVars" );
				var instant = createObject( "java", "java.time.Instant" );
				var before  = instant.now().getEpochSecond();

				var timestamps = service.getTimeVars();
				var parsed     = instant.parse( timestamps.iso );

				expect( parsed.getEpochSecond() ).toBe( val( timestamps.unix ) );
				expect( parsed.getEpochSecond() ).toBeGTE( before );
				expect( parsed.getEpochSecond() ).toBeLTE( instant.now().getEpochSecond() );
			} );
			it( "uses the JVM clock at millisecond boundaries without applying an engine time-server offset", function(){
				var service = createMock( "sentry.models.SentryService" );
				makePublic( service, "getTimeVars" );
				var millis = 1792707331943;
				service.$property(
					"timestampClock",
					"variables",
					{
						currentTimeMillis : function(){
							return millis;
						}
					}
				);
				for ( var offset in [ 0, 56, 57 ] ) {
					millis         = 1792707331943 + offset;
					var timestamps = service.getTimeVars();
					expect( timestamps.unix ).toBe( offset == 57 ? "1792707332" : "1792707331" );
					expect( timestamps.iso ).toBe( offset == 57 ? "2026-10-22T22:15:32Z" : "2026-10-22T22:15:31Z" );
				}
				var reference = createObject( "java", "java.util.Date" ).init( javacast( "long", 1792707331943 ) );
				expect( service.getTimeVars( reference ).unix ).toBe( "1792707331" );
			} );
			it( "uses the same valid UTC timestamp for the event and envelope", function(){
				var service = createMock( "sentry.models.SentryService" );
				service.$property(
					"cgi",
					"variables",
					{
						"server_name" : "example.test",
						"remote_addr" : "127.0.0.1"
					}
				);
				service.init( {
					"DSN"                 : "https://synthetic@example.test/1",
					"async"               : false,
					"sentryEventEndpoint" : "envelope"
				} );
				service.$( "getHTTPDataForRequest", { "headers" : {}, "content" : "" } );
				service.$( "post" );
				service.$property(
					"timestampClock",
					"variables",
					{
						currentTimeMillis : function(){
							return 1792707331943;
						}
					}
				);
				var instant = createObject( "java", "java.time.Instant" );

				service.captureMessage(
					message   = "Synthetic timestamp test",
					cgiVars   = {},
					useThread = false
				);

				var captured = service.$callLog( "post" ).post[ 1 ];
				var parsed   = instant.parse( captured[ 3 ] );
				expect( deserializeJSON( captured[ 4 ] ).timestamp ).toBe( captured[ 3 ] );
				expect( parsed.getEpochSecond() ).toBe( 1792707331 );
				expect( captured[ 3 ] ).toBe( "2026-10-22T22:15:31Z" );
			} );
		} );
	}

}
