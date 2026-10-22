<cfscript>
setting showDebugOutput=false;
bundles = "tests.specs.ObservabilitySpec,tests.specs.TransportFailureSpec,tests.specs.ExecutionIsolationSpec,tests.specs.ReusableObservabilitySpec,tests.specs.DeliveryDiagnosticsSpec,tests.specs.DatabaseQueueMetricsSpec";
if ( directoryExists( expandPath( "/cbq/tests" ) ) ) { bundles &= ",cbq.tests.specs.unit.ObservabilityHooksSpec"; }
writeOutput( new testbox.system.TestBox( bundles = bundles ).run( reporter = "json" ) );
</cfscript>
