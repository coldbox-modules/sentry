component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "PostgreSQL query descriptions", function(){
			beforeEach( function(){
				variables.service   = new sentry.models.SentryService( { DSN : "", databaseSystem : "postgresql" } );
				variables.telemetry = variables.service.getObservability();
			} );
			afterEach( function(){
				variables.service.shutdown();
			} );
			it( "keeps qualified identifiers while scrubbing strings, bindings and numbers", function(){
				var sql      = "SELECT ""users"".""id"", ""users"".""column42"" FROM ""public"".""users"" WHERE ""email"" = 'private@example.test' AND ""id"" = 42 AND ""role"" = ?";
				var expected = "SELECT ""users"".""id"", ""users"".""column42"" FROM ""public"".""users"" WHERE ""email"" = ? AND ""id"" = ? AND ""role"" = ?";
				expect( variables.telemetry.scrubSQL( sql ) ).toBe( expected );
				// qb sanitizes before startSpan, which sanitizes again.
				expect( variables.telemetry.scrubSQL( variables.telemetry.scrubSQL( sql ) ) ).toBe( expected );
			} );
			it( "preserves escaped identifier quotes and punctuation inside identifiers", function(){
				expect(
					variables.telemetry.scrubSQL( "SELECT ""a""""b"", ""part.42"", ""--column"", ""/*column*/"", ""O'Brien"" FROM ""MixedCase""" )
				).toBe( "SELECT ""a""""b"", ""part.42"", ""--column"", ""/*column*/"", ""O'Brien"" FROM ""MixedCase""" );
			} );
			it( "redacts escaped strings and treats comment markers inside strings as data", function(){
				expect(
					variables.telemetry.scrubSQL( "SELECT 'O''Brien', '--private', '/*private*/', '""private""', ''" )
				).toBe( "SELECT ?, ?, ?, ?, ?" );
			} );
			it( "removes line and nested block comments without exporting their contents", function(){
				var sql = "SELECT ""id"" /* outer private /* nested */ still private */ FROM ""users"" -- 'private""" & chr(
					10
				) & "WHERE ""id"" = 42";
				expect( variables.telemetry.scrubSQL( sql ) ).toBe( "SELECT ""id"" FROM ""users"" WHERE ""id"" = ?" );
			} );
			it( "redacts decimal and exponential values without altering unquoted identifier digits", function(){
				expect(
					variables.telemetry.scrubSQL( "SELECT column42 FROM ""table42"" WHERE n IN (123, -4.5, .75, 1e6, 2.5E-3)" )
				).toBe( "SELECT column42 FROM ""table42"" WHERE n IN (?, -?, ?, ?, ?)" );
				expect(
					variables.telemetry.scrubSQL( "SELECT répétition2 WHERE n IN (1_000, 1.2_5e1_0, 0xCAFE, 0o755, 0b101)" )
				).toBe( "SELECT répétition2 WHERE n IN (?, ?, ?, ?, ?)" );
			} );
			it( "preserves identifier whitespace and bounds long descriptions without splitting quotes", function(){
				expect( variables.telemetry.scrubSQL( "SELECT ""my  column"" FROM ""my  table""" ) ).toBe( "SELECT ""my  column"" FROM ""my  table""" );
				var sql         = "SELECT " & repeatString( """identifier"", ", 90 ) & """final"" FROM ""users"" WHERE ""email"" = 'private'";
				var description = variables.telemetry.scrubSQL( sql );
				expect( len( description ) ).toBeLTE( 1024 );
				expect( description ).toInclude( """identifier""" );
				expect( variables.telemetry.scrubSQL( description ) ).toBe( description );
			} );
			it( "honors the native listener dialect independently of the default", function(){
				variables.service.setEnabled( true );
				var settings              = variables.service.getSettings();
				settings.tracesSampleRate = 1;
				settings.databaseSystem   = "other";
				var root                  = variables.service.startTransaction( "native query privacy" );
				variables.service.setEnabled( false );
				variables.telemetry.setScope( { span : root } );
				var listener = variables.service.createLuceeQueryListener( databaseSystem = "postgresql" );
				var args     = { sql : "SELECT ""id"" FROM ""users"" WHERE ""email"" = 'private'" };
				listener.before( {}, args );
				listener.after( {}, args, {}, {} );
				expect( root.getChildren().len() ).toBe( 1 );
				expect( root.getChildren()[ 1 ].toPayload().description ).toBe( "SELECT ""id"" FROM ""users"" WHERE ""email"" = ?" );
			} );
			it( "fails closed for incomplete quotes, comments and unsupported quoting", function(){
				for (
					var sql in [
						"SELECT 'private",
						"SELECT ""unfinished",
						"SELECT /* private",
						"SELECT $$private$$",
						"SELECT $tag$private$tag$",
						"SELECT `private`",
						"SELECT E'private" & chr( 92 ) & "'more-private'"
					]
				) {
					expect( variables.telemetry.scrubSQL( sql ) ).toBe( "[Filtered SQL]" );
				}
			} );
			it( "retains conservative double-quote redaction for other and unknown dialects", function(){
				expect( variables.telemetry.scrubSQL( "SELECT ""private"" FROM ""users""", "mysql" ) ).toBe( "SELECT ? FROM ?" );
				expect( variables.telemetry.scrubSQL( "SELECT ""private"" FROM ""users""", "other" ) ).toBe( "SELECT ? FROM ?" );
			} );
			it( "uses span database attributes for all query operations, with and without parents", function(){
				var sql      = "SELECT ""id"" FROM ""users"" WHERE ""email"" = 'private'";
				var expected = "SELECT ""id"" FROM ""users"" WHERE ""email"" = ?";
				for ( var parented in [ false, true ] ) {
					if ( parented ) {
						variables.telemetry.setScope( { span : variables.service.startTransaction( "parent" ) } );
					}
					for ( var op in [ "db.query", "db.query.cache", "db.query.qoq" ] ) {
						var span = variables.telemetry.startSpan( sql, op, { "db.system" : "postgresql" } );
						expect( span.toPayload().description ).toBe( expected );
						var other = variables.telemetry.startSpan( sql, op, { "db.system" : "other" } );
						expect( other.toPayload().description ).notToInclude( """users""" );
					}
				}
			} );
			it( "honors the manual wrapper dialect before either sanitization pass", function(){
				var sql = "SELECT ""id"" FROM ""users"" WHERE ""email"" = 'private'";
				variables.telemetry.withQuerySpan(
					sql,
					function( span ){
						expect( span.toPayload().description ).toBe( "SELECT ""id"" FROM ""users"" WHERE ""email"" = ?" );
					},
					"postgresql"
				);
				variables.telemetry.withQuerySpan(
					sql,
					function( span ){
						expect( span.toPayload().description ).toBe( "SELECT ? FROM ? WHERE ? = ?" );
					},
					"other"
				);
			} );
		} );
	}

}
