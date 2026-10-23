<cfscript>
setting showDebugOutput=false;
bundles = "tests.specs.ObservabilitySpec,tests.specs.TransportFailureSpec,tests.specs.ExecutionIsolationSpec,tests.specs.ReusableObservabilitySpec,tests.specs.DeliveryDiagnosticsSpec,tests.specs.DatabaseQueueMetricsSpec,tests.specs.OperationalReviewSpec,tests.specs.SaturationDependencyWorkerSpec,tests.specs.DatabaseQueueHealthIntegrationSpec";
if ( directoryExists( expandPath( "/cbq/tests" ) ) ) { bundles &= ",cbq.tests.specs.unit.ObservabilityHooksSpec"; }
writeOutput( new testbox.system.TestBox( bundles = bundles ).run( reporter = "json" ) );
</cfscript>
