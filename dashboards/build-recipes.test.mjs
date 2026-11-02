import test from "node:test";
import assert from "node:assert/strict";
import { buildRecipes } from "./build-recipes.mjs";

const config = {
	backendProject: "sample-api",
	frontendProject: "sample-web",
	environment: "production",
	readinessDescription: "GET ready/",
	phaseField: "span.description",
};

test("requires consumer scopes and rejects query injection", () => {
	for (const key of ["backendProject", "frontendProject", "environment"]) {
		assert.throws(() => buildRecipes({ ...config, [key]: undefined }));
		assert.throws(() =>
			buildRecipes({ ...config, [key]: "api OR project:other" }),
		);
	}
	assert.throws(() => buildRecipes({ ...config, phaseField: "span.name" }));
	assert.throws(() => buildRecipes({ ...config, readinessDescription: "" }));
});

test("readiness and application recipes form an explicit, disjoint split", () => {
	const { widgets } = buildRecipes(config);
	const app = widgets.find(
		(w) => w.title === "Backend non-readiness latency",
	);
	const counts = widgets.find(
		(w) => w.title === "Backend non-readiness count",
	);
	const ready = widgets.find(
		(w) => w.title === "Readiness availability observations",
	);
	assert.equal(app.conditions, counts.conditions);
	assert.equal(
		app.conditions.replace("!span.description:", "span.description:"),
		ready.conditions,
	);
	assert(!ready.conditions.includes("span.status:ok"));
});

test("each queue gauge has per-pool sample coverage without legacy labels or zero filling", () => {
	const { widgets } = buildRecipes(config);
	for (const name of ["queue.depth", "queue.oldest_age"]) {
		const gauge = widgets.find((w) => w.title === `${name} by worker pool`);
		const samples = widgets.find(
			(w) => w.title === `${name} sample coverage`,
		);
		assert.deepEqual(gauge.groupBy, ["queue.name"]);
		assert.equal(gauge.conditions, samples.conditions);
		assert(samples.fields[0].startsWith("count(value,"));
		assert(gauge.conditions.includes("has:queue.name"));
	}
	assert(!JSON.stringify(widgets).includes("messaging.destination.name"));
});

test("phase recipes retain distinct operations and verified field without summing phases", () => {
	const phases = buildRecipes(config).widgets.find(
		(w) => w.title === "Backend inclusive phases",
	);
	assert.deepEqual(phases.groupBy, ["span.op", "span.description"]);
	assert(phases.conditions.includes("span.op:[app.phase,app.navigation]"));
	assert(!phases.fields.some((f) => f.startsWith("sum(")));
	const custom = buildRecipes({
		...config,
		phaseField: "app.phase",
	}).widgets.find((w) => w.title === phases.title);
	assert.deepEqual(custom.groupBy, ["span.op", "app.phase"]);
});
