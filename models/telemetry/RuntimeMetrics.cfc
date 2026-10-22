/** Inexpensive MXBean samples. Unsupported values are omitted, never invented as zero. */
component {

	function init( required any telemetry ){
		variables.telemetry = arguments.telemetry;
		return this;
	}
	function capture(){
		var samples = {};
		var factory = createObject( "java", "java.lang.management.ManagementFactory" );
		try {
			var memory                 = factory.getMemoryMXBean().getHeapMemoryUsage();
			samples[ "jvm.heap.used" ] = { "value" : memory.getUsed(), "unit" : "byte" };
			if ( memory.getMax() > 0 ) {
				samples[ "jvm.heap.max" ] = { "value" : memory.getMax(), "unit" : "byte" };
			}
		} catch ( any unavailable ) {
		}
		try {
			var threads = readAttribute( "java.lang:type=Threading", "ThreadCount" );
			if ( isNumeric( threads ) && threads >= 0 ) {
				samples[ "jvm.threads" ] = { "value" : threads, "unit" : "none" };
			}
		} catch ( any unavailable ) {
		}
		try {
			var cpu = readAttribute( "java.lang:type=OperatingSystem", "ProcessCpuLoad" );
			if ( isNumeric( cpu ) && cpu >= 0 && cpu <= 1 ) {
				samples[ "jvm.cpu.process" ] = { "value" : cpu, "unit" : "ratio" };
			}
		} catch ( any unavailable ) {
		}
		var count     = 0;
		var duration  = 0;
		var supported = false;
		try {
			var beans = callMBean(
				"queryNames",
				[
					"javax.management.ObjectName",
					"javax.management.QueryExp"
				],
				[
					createObject( "java", "javax.management.ObjectName" ).init( "java.lang:type=GarbageCollector,*" ),
					javacast( "null", "" )
				]
			);
			supported = beans.size() > 0;
			for ( var bean in beans.toArray() ) {
				var collections = readAttribute( bean.toString(), "CollectionCount" );
				var time        = readAttribute( bean.toString(), "CollectionTime" );
				if ( collections >= 0 && time >= 0 ) {
					count += collections;
					duration += time;
				} else {
					supported = false;
				}
			}
		} catch ( any unavailable ) {
			supported = false;
		}
		if ( supported ) {
			samples[ "jvm.gc.collections.total" ] = { "value" : count, "unit" : "none" };
			samples[ "jvm.gc.duration.total" ]    = { "value" : duration, "unit" : "millisecond" };
		}
		for ( var name in samples ) {
			try {
				variables.telemetry.gauge(
					name,
					samples[ name ].value,
					{},
					samples[ name ].unit
				);
			} catch ( any unavailable ) {
			}
		}
		return samples;
	}
	function readAttribute( required string bean, required string attribute ){
		return callMBean(
			"getAttribute",
			[
				"javax.management.ObjectName",
				"java.lang.String"
			],
			[
				createObject( "java", "javax.management.ObjectName" ).init( arguments.bean ),
				arguments.attribute
			]
		);
	}
	/** Call the exported interface, never a non-exported JVM implementation class. */
	private function callMBean(
		required string methodName,
		required array types,
		required array args
	){
		var classes   = [];
		var javaClass = createObject( "java", "java.lang.Class" );
		for ( var type in arguments.types ) {
			classes.append( javaClass.forName( type ) );
		}
		var method = javaClass
			.forName( "javax.management.MBeanServerConnection" )
			.getMethod( arguments.methodName, javacast( "java.lang.Class[]", classes ) );
		// Preserve null QueryExp arguments on engines whose CFML arrays omit nulls.
		var reflectArray = createObject( "java", "java.lang.reflect.Array" );
		var nativeArgs   = reflectArray.newInstance(
			javaClass.forName( "java.lang.Object" ),
			javacast( "int", arguments.types.len() )
		);
		for ( var i = 1; i <= arguments.types.len(); i++ ) {
			if ( arrayIsDefined( arguments.args, i ) && !isNull( arguments.args[ i ] ) ) {
				reflectArray.set(
					nativeArgs,
					javacast( "int", i - 1 ),
					arguments.args[ i ]
				);
			}
		}
		return method.invoke(
			createObject( "java", "java.lang.management.ManagementFactory" ).getPlatformMBeanServer(),
			nativeArgs
		);
	}

}
