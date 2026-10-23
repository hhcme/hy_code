// HyCode-owned adapter; schema text is pinned build data, never project code.
import { readFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';

const directory = new URL('../schemas/', import.meta.url);
export const catalog = JSON.parse(readFileSync(new URL('catalog.json', directory), 'utf8'));
const bundled = new Map(catalog.schemas.map(item => [item.file.replace(/\.json$/, ''), item]));
const hosts = new Set(['json.schemastore.org', 'www.schemastore.org', 'schemastore.org']);

export function createSchemaReader(connection) {
  const cache = new Map();
  let pending = 0;
  return async uri => {
    if (typeof uri !== 'string' || uri.length > 8192) throw new Error('Invalid schema URI');
    const url = new URL(uri);
    if ((url.protocol === 'https:' || url.protocol === 'http:') && hosts.has(url.hostname) && !url.username && !url.password && !url.port && !url.search) {
      const name = url.pathname.replace(/^\//, '').replace(/\.json$/, '');
      const item = bundled.get(name);
      if (item) {
        if (!cache.has(name)) cache.set(name, readFile(new URL(item.file, directory), 'utf8'));
        return cache.get(name);
      }
    }
    if (url.protocol !== 'file:' || (url.hostname && url.hostname !== 'localhost') || url.search) {
      throw new Error('Schema is not bundled. Network schema downloads are disabled.');
    }
    if (pending >= 8) throw new Error('Too many schema reads');
    pending++;
    try {
      url.hash = '';
      const content = await connection.sendRequest('hycode/schemaContent', url.href);
      if (typeof content !== 'string' || Buffer.byteLength(content) > 1024 * 1024) throw new Error('Invalid schema response');
      return content;
    } finally { pending--; }
  };
}
