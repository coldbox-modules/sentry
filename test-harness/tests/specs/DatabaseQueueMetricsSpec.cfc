component extends="testbox.system.BaseSpec" {

	function run(){
		describe( "Optional cbq database metrics", function(){
			it( "emits configured idle queues, retains dynamic queues, and does not fabricate zero on failure", function(){
				var samples   = {};
				var rows      = [];
				var failed    = false;
				var telemetry = {
					captureQueueMetrics : function( name, depth, age ){
						samples[ name ] = { "depth" : depth, "age" : age };
					}
				};
				var config = {
					getWorkerPoolDefinitions : function(){
						return {
							"worker" : {
								getQueue : function(){
									return [ "mail", "pdf" ];
								}
							}
						};
					}
				};
				var sampler = new sentry.models.telemetry.DatabaseQueueMetrics(
					telemetry,
					config,
					function(){
						return new tests.resources.QueueMetricsQuery( rows, failed );
					}
				);
				expect( sampler.capture() ).toBeTrue();
				expect( samples.mail.depth ).toBe( 0 );
				expect( samples.pdf.age ).toBe( 0 );
				rows = [
					{
						"queue"  : "dynamic",
						"depth"  : 2,
						"oldest" : createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000 - 120
					}
				];
				expect( sampler.capture() ).toBeTrue();
				expect( samples.dynamic.depth ).toBe( 2 );
				expect( samples.dynamic.age ).toBeGTE( 120 );
				var lastSuccess = sampler.getDiagnostics().lastSuccessAt;
				failed          = true;
				samples         = {};
				expect( sampler.capture() ).toBeFalse();
				expect( samples ).toBeEmpty();
				expect( sampler.getDiagnostics().lastSuccessAt ).toBe( lastSuccess );
				expect( sampler.getDiagnostics().failures ).toBe( 1 );
				failed = false;
				rows   = [];
				expect( sampler.capture() ).toBeTrue();
				expect( samples.dynamic.depth ).toBe( 0 );
			} );
			it( "bounds remembered queues and lifetime label cardinality", function(){
				var count   = 0;
				var queue   = "first";
				var sampler = new sentry.models.telemetry.DatabaseQueueMetrics(
					{
						captureQueueMetrics : function(){
							count++;
						}
					},
					{
						getWorkerPoolDefinitions : function(){
							return {};
						}
					},
					function(){
						return new tests.resources.QueueMetricsQuery( [ { "queue" : queue, "depth" : 1, "oldest" : 0 } ] );
					},
					"cbq_jobs",
					1
				);
				expect( sampler.capture() ).toBeTrue();
				queue = "another";
				expect( sampler.capture() ).toBeTrue();
				expect( count ).toBe( 2 );
				expect( sampler.getDiagnostics().omittedQueues ).toBe( 1 );
			} );
			it(
				title = "compiles the installed qb public API with dialect-aware identifiers",
				body  = function(){
					for ( var dialect in [ "Postgres", "MySQL", "SqlServer" ] ) {
						var grammar = createObject( "component", "qb.models.Grammars." & dialect & "Grammar" ).init();
						var builder = prepareMock(
							new qb.models.Query.QueryBuilder( grammar = grammar, paginationCollector = {} )
						);
						builder.$( "get", [] );
						var sampler = new sentry.models.telemetry.DatabaseQueueMetrics(
							{
								captureQueueMetrics : function(){
								}
							},
							{
								getWorkerPoolDefinitions : function(){
									return {};
								}
							},
							function(){
								return builder;
							}
						);
						expect( sampler.capture() ).toBeTrue();
						var sql = builder.toSQL();
						expect( sql ).toInclude( "min(" & grammar.wrapValue( "createdDate" ) & ") AS oldest" );
						for ( var field in [ "completedDate", "failedDate", "reservedDate" ] ) {
							expect( sql ).toInclude( grammar.wrapValue( field ) & " IS NULL" );
						}
						expect( sql ).toInclude( "GROUP BY" );
					}
				},
				skip = function(){
					var source = createObject( "java", "java.lang.System" ).getenv( "SENTRY_QB_SOURCE" );
					return isNull( source ) || !len( source );
				}
			);
		} );
	}

}
