/**
* My Event Handler Hint
*/
component extends="coldbox.system.EventHandler"{

	/**
	* Executes before all handler actions
	*/
	any function preHandler( event, rc, prc, action, eventArguments ){
		log.error( "Sending some more info to Sentry" );
	}

	/**
	* Index
	*/
	any function index( event, rc, prc ){
		throw( message="Thrown from main.cfc in index method", type="ThrownFromMain" );
	}

	// Run on first init
	any function onAppInit( event, rc, prc ){
	}

}