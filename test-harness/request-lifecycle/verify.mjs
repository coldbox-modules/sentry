import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';

// Only the caller's loopback fixture is accepted. No Sentry ingestion is involved.
const base = new URL(process.argv[2] || 'http://127.0.0.1:60339/request-lifecycle/');
assert.equal(base.hostname, '127.0.0.1');
const report = async (reset = false) => {
  const result = await fetch(new URL(`report.cfm${reset ? '?reset=1' : ''}`, base)).then(r => r.json());
  return JSON.parse(JSON.stringify(result).replace(/"RECORDS":/g, '"records":').replace(/"HOOKS":/g, '"hooks":'));
};
const request = async action => {
  const start = Date.now();
  const response = await fetch(new URL(`index.cfm?event=Responses.${action}`, base), { redirect: 'manual' });
  const bytes = Buffer.from(await response.arrayBuffer());
  const end = Date.now();
  if (action === 'binary') {
    assert.equal(response.status, 200);
    assert.equal(bytes.toString('hex'), '0001027f80ff');
    assert.equal(response.headers.get('cache-control'), 'private, no-store');
    assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
    assert.match(response.headers.get('content-type'), /^application\/octet-stream/);
  } else if (action === 'streamed') {
    assert.equal(response.status, 200);
    assert.equal(bytes.toString(), 'stream-onestream-two');
  } else if (action === 'redirect') assert.equal(response.status, 302);
  else if (action === 'failure') {
    assert.equal(response.status, 500);
    assert.match(bytes.toString(), /original lifecycle failure/);
  } else assert.equal(response.status, 200);
  return { action, start, end, responseMs: end - start };
};

await request('text'); // initialize and warm up compilation before timing assertions
await report(true);
const binaryResponse = await request('binary');
// Observe completion before allowing another ColdBox request to run on the worker.
const immediate = await report();
assert.equal(immediate.records.length, 1, 'binary must finish without a later request');
assert(immediate.hooks.includes('abort'));
const binary = immediate.records[0];
assert.equal(binary.transaction, 'GET Responses.binary');
assert(binary.timestamp * 1000 <= binaryResponse.end + 25);
assert(binary.timestamp * 1000 >= binaryResponse.start - 25);
const finishedAt = binary.timestamp;
await new Promise(resolve => setTimeout(resolve, 1200));
const responses = [binaryResponse];
for (const action of ['text', 'slow', 'noRender', 'streamed', 'aborted', 'redirect', 'failure']) responses.push(await request(action));
responses.push(...await Promise.all(Array.from({ length: 12 }, (_, i) => request(i % 2 ? 'binary' : 'text'))));
const result = await report();
assert.equal(result.records.length, responses.length, 'one transaction per response');
assert.equal(new Set(result.records.map(r => r.contexts.trace.trace_id)).size, responses.length);
assert.equal(result.records.find(r => r.event_id === binary.event_id).timestamp, finishedAt);
const slow = result.records.find(r => r.transaction === 'GET Responses.slow');
assert((slow.timestamp - slow.start_timestamp) * 1000 >= 240, 'real slow request must stay slow');
assert.equal(result.records.find(r => r.transaction === 'GET Responses.failure').contexts.trace.status, 'internal_error');
for (const record of result.records) {
  for (const span of record.spans) {
    assert.equal(span.trace_id, record.contexts.trace.trace_id);
    assert.equal(span.parent_span_id, record.contexts.trace.span_id);
    assert(span.timestamp >= span.start_timestamp);
    // Millisecond wall-clock resolution can differ by <1ms from the elapsed clock.
    assert(span.timestamp <= record.timestamp + 0.002);
  }
}
const evidence = { binaryResponse, responses: responses.length, records: result.records.length, result };
if (process.argv[3]) await writeFile(process.argv[3], JSON.stringify(evidence, null, 2));
console.log(JSON.stringify({ passed: true, responses: responses.length, binaryResponseMs: binaryResponse.responseMs,
  binarySpanMs: (binary.timestamp - binary.start_timestamp) * 1000, slowSpanMs: (slow.timestamp - slow.start_timestamp) * 1000 }));
