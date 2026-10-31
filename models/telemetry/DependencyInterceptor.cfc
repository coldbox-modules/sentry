/** WireBox AOP advice; method arguments/results are never metric labels. */
component implements="coldbox.system.aop.MethodInterceptor" {

	property name="wirebox" inject="wirebox";
	function invokeMethod( required invocation ) output="false"{
		var call = arguments.invocation;
		var rule = {};
		try {
			var telemetry = variables.wirebox.getInstance( "SentryService@sentry" ).getObservability();
			rule          = telemetry.dependencyRule( call.getTargetMapping().getName(), call.getMethod() );
		} catch ( any unavailable ) {
			return call.proceed();
		}
		if ( !rule.keyExists( "name" ) ) return call.proceed();
		return telemetry.withDependency(
			rule.name,
			function(){
				return call.proceed();
			},
			rule.classify ?: ""
		);
	}

}
