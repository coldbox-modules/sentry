// Run against an actual BoxRunner process; the only network peer is loopback.
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { gunzipSync } from 'node:zlib';

for (const key of ['BOXLANG_JAR', 'RUNWAR_JAR', 'BOXLANG_HOME']) {
  assert.ok(process.env[key], `Set ${key} to an installed BoxLang runtime.`);
}
const envelopes = [];
const receiver = http.createServer(async (request, response) => {
  try {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const raw = Buffer.concat(chunks);
    const body = request.headers['content-encoding'] === 'gzip' ? gunzipSync(raw) : raw;
    let offset = 0;
    const line = () => {
      const end = body.indexOf(10, offset);
      assert.ok(end >= 0, 'Envelope line terminator');
      const value = JSON.parse(body.subarray(offset, end).toString());
      offset = end + 1;
      return value;
    };
    const header = line();
    const items = [];
    while (offset < body.length) {
      const item = line();
      const next = body.indexOf(10, offset);
      const length = item.length ?? (next < 0 ? body.length - offset : next - offset);
      const payload = JSON.parse(body.subarray(offset, offset + length).toString());
      offset += length;
      if (offset < body.length) assert.equal(body[offset++], 10);
      items.push({ header: item, payload });
    }
    envelopes.push({ header, items });
    response.end('{}');
  } catch (error) {
    response.statusCode = 400;
    response.end(error.message);
  }
});
await new Promise(resolve => receiver.listen(0, '127.0.0.1', resolve));
let output = '';
try {
  const child = spawn('java', ['-cp', `${process.env.BOXLANG_JAR}:${process.env.RUNWAR_JAR}`,
    'ortus.boxlang.runtime.BoxRunner', '--bx-config', 'test-harness/cli/boxlang.json', 'test-harness/cli/smoke.bxs'], {
    env: { ...process.env, SENTRY_CLI_TEST_DSN: `http://synthetic@127.0.0.1:${receiver.address().port}/1` },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.on('data', value => { output += value; });
  child.stderr.on('data', value => { output += value; });
  const deadline = setTimeout(() => child.kill('SIGTERM'), 120000);
  const code = await new Promise((resolve, reject) => { child.once('error', reject); child.once('exit', resolve); });
  clearTimeout(deadline);
  assert.equal(code, 0, output);
  assert.match(output, /"passed":true/);
  const events = envelopes.flatMap(envelope => envelope.items).filter(item => item.header.type === 'event').map(item => item.payload);
  assert.equal(events.length, 3, output);
  assert.ok(events.some(event => event.exception?.values?.some(value => value.value?.includes('standalone CLI exception'))), JSON.stringify(events));
  for (const event of events) {
    assert.ok(event.server_name.length > 0, 'Actual host name is retained');
    assert.equal(event.request, undefined, 'CLI must not fabricate an HTTP request');
    assert.equal(event.user?.ip_address, undefined, 'CLI has no remote client IP');
  }
  process.stdout.write(JSON.stringify({ passed: true, events: events.length, actualCli: true, moduleBootstrap: true }) + '\n');
} catch (error) {
  process.stderr.write(output + '\n');
  throw error;
} finally {
  await new Promise(resolve => receiver.close(resolve));
}
