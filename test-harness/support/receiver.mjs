// Local byte-preserving envelope receiver. Bind only to loopback.
import http from 'node:http';
const envelopes = [];
let mode = { status: 200, delay: 0, headers: {} };
http.createServer(async (request, response) => {
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Access-Control-Allow-Headers', 'content-type,sentry-trace,baggage');
  response.setHeader('Access-Control-Allow-Methods', 'POST,GET,OPTIONS');
  if (request.method === 'OPTIONS') { response.writeHead(204); response.end(); return; }
  const chunks = []; for await (const chunk of request) chunks.push(chunk);
  const body = Buffer.concat(chunks);
  if (request.url === '/state') { response.setHeader('Content-Type', 'application/json'); response.end(JSON.stringify(envelopes)); return; }
  if (request.url === '/reset') { envelopes.length = 0; mode = body.length ? JSON.parse(body) : { status: 200, delay: 0, headers: {} }; response.end('{}'); return; }
  try {
    let offset = 0;
    function line() { const end = body.indexOf(10, offset); if (end < 0) throw Error('Missing newline'); const value = body.subarray(offset, end).toString(); offset = end + 1; return JSON.parse(value); }
    const header = line(); const items = [];
    while (offset < body.length) {
      const itemHeader = line(); const length = itemHeader.length ?? (body.indexOf(10, offset) < 0 ? body.length - offset : body.indexOf(10, offset) - offset); const bytes = body.subarray(offset, offset + length); offset += length;
      if (bytes.length !== length || (offset < body.length && body[offset++] !== 10)) throw Error('Incorrect byte length');
      items.push({ header: itemHeader, payload: ['attachment', 'replay_recording'].includes(itemHeader.type) ? bytes.toString('base64') : JSON.parse(bytes.toString('utf8')) });
    }
    envelopes.push({ header, items });
    const reply = mode;
    setTimeout(() => { response.writeHead(reply.status ?? 200, reply.headers ?? {}); response.end('{}'); }, reply.delay ?? 0);
  } catch (error) { response.writeHead(400); response.end(error.message); }
}).listen(60320, '127.0.0.1');
