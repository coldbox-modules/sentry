component implements="sentry.models.telemetry.adapters.IQueryFactory" {

	property name="wirebox" inject="wirebox";
	any function newQuery( required struct context ){
		return variables.wirebox.getInstance( "QueryBuilder@qb" );
	}

}
