/** Invoke exported HTTP interfaces; Adobe reflection cannot access JDK implementation classes. */
component {

	function init(){
		variables.javaClass = createObject( "java", "java.lang.Class" );
		variables.methods   = {
			clientExecutor : resolve(
				"java.net.http.HttpClient$Builder",
				"executor",
				[ "java.util.concurrent.Executor" ]
			),
			clientTimeout : resolve(
				"java.net.http.HttpClient$Builder",
				"connectTimeout",
				[ "java.time.Duration" ]
			),
			clientBuild    : resolve( "java.net.http.HttpClient$Builder", "build" ),
			requestTimeout : resolve(
				"java.net.http.HttpRequest$Builder",
				"timeout",
				[ "java.time.Duration" ]
			),
			requestHeader : resolve(
				"java.net.http.HttpRequest$Builder",
				"header",
				[ "java.lang.String", "java.lang.String" ]
			),
			requestPost : resolve(
				"java.net.http.HttpRequest$Builder",
				"POST",
				[ "java.net.http.HttpRequest$BodyPublisher" ]
			),
			requestBuild : resolve( "java.net.http.HttpRequest$Builder", "build" ),
			sendAsync    : resolve(
				"java.net.http.HttpClient",
				"sendAsync",
				[
					"java.net.http.HttpRequest",
					"java.net.http.HttpResponse$BodyHandler"
				]
			),
			statusCode : resolve( "java.net.http.HttpResponse", "statusCode" ),
			headers    : resolve( "java.net.http.HttpResponse", "headers" ),
			futureDone : resolve( "java.util.concurrent.Future", "isDone" ),
			futureGet  : resolve(
				"java.util.concurrent.Future",
				"get",
				[ "long", "java.util.concurrent.TimeUnit" ]
			)
		};
		return this;
	}
	private function resolve(
		required string owner,
		required string methodName,
		array types = []
	){
		var parameterClasses = arguments.types.map( function( type ){
			if ( type == "long" ) {
				return createObject( "java", "java.lang.Long" ).TYPE;
			}
			return variables.javaClass.forName( type );
		} );
		return variables.javaClass
			.forName( arguments.owner )
			.getMethod( arguments.methodName, javacast( "java.lang.Class[]", parameterClasses ) );
	}
	private function call(
		required string methodName,
		required any target,
		array args = []
	){
		return variables.methods[ arguments.methodName ].invoke(
			arguments.target,
			javacast( "java.lang.Object[]", arguments.args )
		);
	}
	private function duration( required numeric milliseconds ){
		return createObject( "java", "java.time.Duration" ).ofMillis( javacast( "long", arguments.milliseconds ) );
	}
	function createClient( required any executor, required numeric timeoutMilliseconds ){
		var builder = createObject( "java", "java.net.http.HttpClient" ).newBuilder();
		call(
			"clientExecutor",
			builder,
			[ arguments.executor ]
		);
		call(
			"clientTimeout",
			builder,
			[ duration( arguments.timeoutMilliseconds ) ]
		);
		return call( "clientBuild", builder );
	}
	function sendAsync(
		required any client,
		required string url,
		required string auth,
		required any bytes,
		required numeric timeoutMilliseconds
	){
		var builder = createObject( "java", "java.net.http.HttpRequest" ).newBuilder(
			createObject( "java", "java.net.URI" ).create( arguments.url )
		);
		call(
			"requestTimeout",
			builder,
			[ duration( arguments.timeoutMilliseconds ) ]
		);
		call(
			"requestHeader",
			builder,
			[ "X-Sentry-Auth", arguments.auth ]
		);
		call(
			"requestHeader",
			builder,
			[
				"Content-Type",
				"application/x-sentry-envelope"
			]
		);
		call(
			"requestPost",
			builder,
			[ createObject( "java", "java.net.http.HttpRequest$BodyPublishers" ).ofByteArray( arguments.bytes ) ]
		);
		return call(
			"sendAsync",
			arguments.client,
			[
				call( "requestBuild", builder ),
				createObject( "java", "java.net.http.HttpResponse$BodyHandlers" ).discarding()
			]
		);
	}
	function statusCode( required any response ){
		return call( "statusCode", arguments.response );
	}
	function headers( required any response ){
		return call( "headers", arguments.response );
	}
	function isDone( required any future ){
		return call( "futureDone", arguments.future );
	}
	function awaitResponse( required any future, required numeric timeoutMilliseconds ){
		return call(
			"futureGet",
			arguments.future,
			[
				javacast( "long", arguments.timeoutMilliseconds ),
				createObject( "java", "java.util.concurrent.TimeUnit" ).MILLISECONDS
			]
		);
	}

}
