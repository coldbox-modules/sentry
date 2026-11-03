import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const slug = /^[a-z0-9][a-z0-9_-]*$/;
const quote = (value) => JSON.stringify(value);

/** Offline query recipes for the Sentry widget builder; never writes to Sentry. */
export function buildRecipes(config) {
	for (const key of ["backendProject", "frontendProject", "environment"]) {
		if (typeof config[key] !== "string" || !slug.test(config[key])) {
			throw new Error(`${key} must be an explicit slug`);
		}
	}
	if (
		typeof config.readinessDescription !== "string" ||
		!config.readinessDescription.trim()
	) {
		throw new Error(
			"readinessDescription must match a verified indexed HTTP description",
		);
	}
	if (!["span.description", "app.phase"].includes(config.phaseField)) {
		throw new Error(
			"phaseField must be verified in live data: span.description or app.phase",
		);
	}
	const assets = config.suspectAssetDescriptions ?? [];
	if (
		!Array.isArray(assets) ||
		assets.length > 32 ||
		assets.some(
			(value) =>
				typeof value !== "string" ||
				!value.trim() ||
				value.length > 512 ||
				/[\x00-\x1f*]/.test(value),
		) ||
		new Set(assets).size !== assets.length ||
		assets.includes(config.readinessDescription)
	) {
		throw new Error(
			"suspectAssetDescriptions must be unique exact descriptions, excluding readiness (maximum 32)",
		);
	}
	const backend = `project:${config.backendProject} environment:${config.environment}`;
	const frontend = `project:${config.frontendProject} environment:${config.environment}`;
	const http = `${backend} span.op:http.server`;
	const ready = `span.description:${quote(config.readinessDescription)}`;
	const nonReadiness = `${http} !${ready}`;
	const application = [
		nonReadiness,
		...assets.map((value) => `!span.description:${quote(value)}`),
	].join(" ");
	const queue = `${backend} has:queue.name`;
	const widgets = [];
	const add = (
		title,
		dataset,
		conditions,
		fields,
		groupBy = [],
		description = "",
	) => {
		widgets.push({
			title,
			dataset,
			conditions,
			fields,
			groupBy,
			interval: "1h",
			description,
		});
	};
	add(
		"Backend non-readiness latency",
		"spans",
		application,
		["p50(span.duration)", "p95(span.duration)"],
		[],
		assets.length
			? "Recorded ms, auto-scaled. Excludes readiness and explicitly configured suspect asset routes, which remain in separate investigation charts. Pair with matching counts. No duration or status cutoff."
			: "Recorded ms, auto-scaled. Pair with matching counts. Security probes, errors and suspect asset timings remain included; duration is not necessarily user wait time.",
	);
	add("Backend non-readiness count", "spans", application, ["count()"]);
	if (assets.length) {
		const suspect = `${nonReadiness} span.description:[${assets.map(quote).join(",")}]`;
		add(
			"Suspect asset recorded latency",
			"spans",
			suspect,
			["p50(span.duration)", "p95(span.duration)"],
			[],
			"Investigation only: recorded duration is not established user wait time. Exact consumer-selected routes; no duration or success filter. Pair with matching counts and retain the all-route/release table.",
		);
		add("Suspect asset sample count", "spans", suspect, ["count()"]);
	}
	add(
		"Readiness availability observations",
		"spans",
		`${http} ${ready}`,
		[
			"span.description",
			"release",
			"span.status",
			"count()",
			"p95(span.duration)",
		],
		["span.description", "release", "span.status"],
		"Recorded probes, including failures. No samples does not establish availability or zero traffic.",
	);
	add(
		"Backend routes and releases",
		"spans",
		http,
		["span.description", "release", "count()", "p95(span.duration)"],
		["span.description", "release"],
		"Keep all routes and statuses visible. Investigate suspect asset lifecycle timing separately; do not silently exclude slow spans.",
	);
	for (const fields of [
		["p95(span.duration)"],
		["count()"],
		["sum(span.duration)"],
	]) {
		add(
			`DB ${fields[0]}`,
			"spans",
			`${backend} span.op:db.query`,
			fields,
			[],
			"Observed instrumented queries only. Cumulative span time is workload, not request latency.",
		);
	}
	add(
		"Scrubbed DB shapes by parent transaction",
		"spans",
		`${backend} span.op:db.query`,
		[
			"span.description",
			"transaction",
			"count()",
			"p95(span.duration)",
			"sum(span.duration)",
		],
		["span.description", "transaction"],
		"Separates readiness-related shapes without removing security/readiness checks. Never include SQL bindings.",
	);
	for (const op of ["pageload", "navigation"]) {
		add(
			`Frontend ${op}`,
			"spans",
			`${frontend} span.op:${op}`,
			["count()", "p95(span.duration)"],
			[],
			"Recorded ms, auto-scaled. Count is percentile sample context; pageload duration is not FCP.",
		);
	}
	add(
		"Frontend routes and releases",
		"spans",
		`${frontend} span.op:[pageload,navigation]`,
		["span.op", "transaction", "release", "count()", "p95(span.duration)"],
		["span.op", "transaction", "release"],
	);
	for (const [name, unit] of [
		["jvm.heap.used", "byte"],
		["jvm.threads", "none"],
	]) {
		add(
			name,
			"metrics",
			backend,
			[`avg(value,${name},gauge,${unit})`],
			[],
			"Unsupported or absent metrics remain absent.",
		);
	}
	for (const [name, unit] of [
		["queue.depth", "none"],
		["queue.oldest_age", "second"],
	]) {
		add(
			`${name} by worker pool`,
			"metrics",
			queue,
			[`avg(value,${name},gauge,${unit})`],
			["queue.name"],
			"queue.name is a worker pool. A pool may cover several destinations. Never merge legacy destination series or infer zero from absent samples.",
		);
		add(
			`${name} sample coverage`,
			"metrics",
			queue,
			[`count(value,${name},gauge,${unit})`],
			["queue.name"],
			"Pair with the gauge for each pool and bucket. Zero/no samples means no observation, not an empty pool.",
		);
	}
	add(
		"Backend inclusive phases",
		"spans",
		`${backend} span.op:[app.phase,app.navigation]`,
		["span.op", config.phaseField, "count()", "p95(span.duration)"],
		["span.op", config.phaseField],
		"Verify phaseField by grouping and filtering raw examples. Operations represent different coverage. Inclusive phases overlap: never sum them. Sort by count to keep automatic phases visible.",
	);
	add(
		"Backend telemetry coverage",
		"spans",
		`${backend} span.op:[http.server,db.query,app.phase,app.navigation]`,
		["count()"],
		["span.op"],
		"Compare recent hourly buckets and releases. Span counts are not unique requests or complete unsampled traffic.",
	);
	return {
		schemaVersion: 1,
		defaultPeriod: "7d",
		environment: config.environment,
		widgets,
	};
}

if (
	process.argv[1] &&
	import.meta.url === pathToFileURL(process.argv[1]).href
) {
	if (!process.argv[2])
		throw new Error(
			"Usage: node dashboards/build-recipes.mjs /path/to/consumer-config.json",
		);
	process.stdout.write(
		`${JSON.stringify(buildRecipes(JSON.parse(readFileSync(process.argv[2], "utf8"))), null, 2)}\n`,
	);
}
