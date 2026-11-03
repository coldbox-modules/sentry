component extends="coldbox.system.ioc.config.Binder" {

	function configure(){
		wireBox = { scopeRegistration : { enabled : false } };
		map( "SentryService@sentry" ).toValue( getProperty( "service" ) );
		map( "MailClient" ).to( "tests.resources.AutomaticMailClient" );
		map( "Classifier" ).to( "tests.resources.AutomaticClassifier" );
		map( "QueryAdapter" ).to( "tests.resources.AutomaticQueryAdapter" );
		map( "SnapshotAdapter" ).to( "tests.resources.AutomaticSnapshotAdapter" );
	}

}
