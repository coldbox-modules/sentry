<cfscript>
setting showDebugOutput=false;
if ( structKeyExists( url, "reset" ) ) {
	application.records.clear();
	application.hooks.clear();
}
writeOutput( serializeJSON( { records : application.records.toArray(), hooks : application.hooks.toArray() } ) );
</cfscript>
