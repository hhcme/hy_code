import test from 'node:test';
import assert from 'node:assert/strict';
import { catalog, createSchemaReader } from './schema-runtime.mjs';

test('all bundled schemas and their references resolve offline', async () => {
  const reader = createSchemaReader({ sendRequest() { throw new Error('Unexpected host read'); } });
  for (const item of catalog.schemas) {
    const body = JSON.parse(await reader(item.uri));
    assert.equal(typeof body, 'object');
    assert.equal(await reader(item.uri + '.json#fragment'), await reader(item.uri));
    for (const reference of item.externalRefs) JSON.parse(await reader(new URL(reference, item.uri).href));
  }
});
test('unknown network, disguised catalog hosts and non-file protocols are rejected', async () => {
  const reader = createSchemaReader({ sendRequest() { throw new Error('Unexpected host read'); } });
  for (const uri of ['https://127.0.0.1:1/schema', 'https://json.schemastore.org.evil/package', 'https://u:p@json.schemastore.org/package', 'https://json.schemastore.org:123/package', 'ftp://local/file', 'javascript:alert(1)', 'file://remote/private/schema.json']) {
    await assert.rejects(reader(uri));
  }
});
test('local schema reads go through the native boundary and strip fragments', async () => {
  const calls = [];
  const reader = createSchemaReader({ async sendRequest(method, uri) { calls.push([method, uri]); return '{"type":"object"}'; } });
  assert.equal(await reader('file:///tmp/project/schema.json#/defs/a'), '{"type":"object"}');
  assert.deepEqual(calls, [['hycode/schemaContent', 'file:///tmp/project/schema.json']]);
});
test('native response size/type and concurrent schema reads are bounded', async () => {
  for (const body of [null, {}, 'x'.repeat(1024 * 1024 + 1)]) {
    const reader = createSchemaReader({ async sendRequest() { return body; } });
    await assert.rejects(reader('file:///tmp/project/schema.json'));
  }
  const releases = [];
  const reader = createSchemaReader({ sendRequest() { return new Promise(resolve => releases.push(resolve)); } });
  const first = Array.from({ length: 8 }, (_, i) => reader(`file:///tmp/${i}.json`));
  await assert.rejects(reader('file:///tmp/overflow.json'), /Too many/);
  releases.forEach(resolve => resolve('{}'));
  await Promise.all(first);
});
