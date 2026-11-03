component implements="sentry.models.telemetry.adapters.IDependencyClassifier" {

	struct function classify( any result, any failure ){
		return {
			"outcome"    : isNull( arguments.failure ) ? "rejected" : "timeout",
			"statusCode" : 503,
			"retryCount" : 1
		};
	}

}
