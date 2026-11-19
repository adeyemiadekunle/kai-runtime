import { strict as assert } from 'node:assert';
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

// Extract checksum-verified SDK/addon archives into <root>/<version>/sdk
// and <root>/<version>/addon before running this explicit fixture recorder.
if (process.argv.length !== 3) throw new Error('usage: generate-released-journals.mjs <verified-artifact-root>');
const artifactRoot = resolve(process.argv[2]);

const requests = [];
const textOf = message => typeof message.content === 'string' ? message.content : message.content.filter(part => part.type === 'text').map(part => part.text).join('');
const usage = { inputTokens: { total: 1 }, outputTokens: { total: 1 } };
const server = createServer((request, response) => {
  let body = '';
  request.setEncoding('utf8');
  request.on('data', chunk => { body += chunk; });
  request.on('end', () => {
    if (request.method === 'GET') {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ object: 'list', data: [{ id: 'journal/model', type: 'language' }] }));
      return;
    }
    const { prompt } = JSON.parse(body);
    requests.push(prompt);
    const text = textOf(prompt.filter(message => message.role === 'user').at(-1));
    const results = prompt.flatMap(message => Array.isArray(message.content) ? message.content : []).filter(part => part.type === 'tool-result');
    const frames = text === 'use the tool' && results.length === 0
      ? [{ type: 'tool-call', toolCallId: 'released-lookup', toolName: 'lookup', input: { key: 'alpha' } }, { type: 'finish', finishReason: { unified: 'tool-calls', raw: 'tool-calls' }, usage }]
      : [{ type: 'text-delta', id: 'answer', delta: text === 'use the tool' ? 'tool said beta' : `answer to ${text}` }, { type: 'finish', finishReason: { unified: 'stop', raw: 'stop' }, usage }];
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.end(frames.map(frame => `data: ${JSON.stringify(frame)}\n\n`).join('') + 'data: [DONE]\n\n');
  });
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const { port } = server.address();
const localFetch = (input, init) => {
  const url = new URL(String(input?.url ?? input));
  if (url.hostname === 'ai-gateway.vercel.sh' && String(init?.method ?? input?.method ?? 'GET').toUpperCase() === 'GET') return fetch(`http://127.0.0.1:${port}${url.pathname}${url.search}`, init);
  assert.equal(url.origin, `http://127.0.0.1:${port}`, 'fixture must not contact an external endpoint');
  return fetch(input, init);
};
try {
  for (const version of ['0.0.16', '0.0.17']) {
    const root = resolve(artifactRoot, version);
    assert.equal(JSON.parse(await readFile(`${root}/sdk/package/package.json`, 'utf8')).version, version);
    const { createFxEngine, createMemoryPersistence } = await import(pathToFileURL(`${root}/sdk/package/node.js`));
    const store = createMemoryPersistence();
    let calls = 0;
    const engine = await createFxEngine({
      backend: 'native', nativeAddon: `${root}/addon/package/libfx.node`, sessionId: 'released-session',
      fetch: localFetch, apiKey: 'synthetic-fixture-key', gatewayChatUrl: `http://127.0.0.1:${port}/chat`, model: 'journal/model', persistence: store,
      checkpointAfterBytes: 16 * 1024 * 1024,
      tools: [{ name: 'lookup', description: 'Looks up a key', inputSchema: { type: 'object', properties: { key: { type: 'string' } }, required: ['key'] }, execute: async () => { calls += 1; return 'value of alpha is beta'; } }],
    });
    try {
      for (const [text, turnId] of [['remember plums', 'released-text'], ['use the tool', 'released-tool']]) {
        const turn = engine.prompt(text, { turnId });
        for await (const ignored of turn) {}
        assert.equal((await turn.result).stopReason, 'end_turn');
      }
      assert.equal(calls, 1);
      const checkpoint = await engine.checkpoint();
      const fixture = {
        libfx: version, backend: 'native', model: 'journal/model', sessionId: 'released-session',
        toolCalls: calls, checkpoint: Buffer.from(checkpoint).toString('base64'),
        records: store.records.map(record => ({ ...record, data: Buffer.from(record.data).toString('base64') })),
      };
      await writeFile(resolve(artifactRoot, `libfx-${version}-journal.json`), JSON.stringify(fixture, null, 2) + '\n');
      console.log(`Recorded ${version}: ${store.records.length} records, ${checkpoint.length} checkpoint bytes`);
    } finally { await engine.close(); }
  }
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
