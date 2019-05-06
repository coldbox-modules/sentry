/**
* My Event Handler Hint
*/
component extends="coldbox.system.EventHandler"{

	/**
	* Executes before all handler actions
	*/
	any function preHandler( event, rc, prc, action, eventArguments ){
		log.error( "Sending some info to Sentry" );
	}

	/**
	* Index
	*/
	any function index( event, rc, prc ){
		event.throwAnException();
	}

	// Run on first init
	any function onAppInit( event, rc, prc ){
	}

}