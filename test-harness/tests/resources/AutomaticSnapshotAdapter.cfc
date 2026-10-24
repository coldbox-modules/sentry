component implements="sentry.models.telemetry.adapters.ISnapshotAdapter" {

	struct function sample( required struct context ){
		return {
			"active"            : 2,
			"max"               : 4,
			"configuredWorkers" : 3,
			"activeExecutions"  : 1,
			"password"          : "PRIVATE"
		};
	}

}
