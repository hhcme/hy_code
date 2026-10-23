// Metadata/license preparation only. Never load project code or npm hooks.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const runtime = path.join(root, 'tools/web-language-services');
const lock = JSON.parse(readFileSync(path.join(runtime, 'package-lock.json'), 'utf8'));
const supplements = JSON.parse(readFileSync(path.join(runtime, 'license-supplements.json'), 'utf8'));
const write = process.argv.includes('--write');
const allowed = new Set(['MIT', 'ISC', 'BSD-2-Clause', 'BSD-3-Clause', 'Apache-2.0']);
const digest = data => createHash('sha256').update(data).digest('hex');
const inventory = [];
for (const [relative, item] of Object.entries(lock.packages).sort(([a], [b]) => a.localeCompare(b))) {
  if (!relative) continue;
  if (!relative.startsWith('node_modules/') || relative.includes('..') || !allowed.has(item.license)) {
    throw new Error(`Unexpected package path or license: ${relative}`);
  }
  const directory = path.join(runtime, relative);
  const pkg = JSON.parse(readFileSync(path.join(directory, 'package.json'), 'utf8'));
  if (pkg.version !== item.version || !item.integrity || !item.resolved.startsWith('https://registry.npmjs.org/')) {
    throw new Error(`Lock/runtime mismatch: ${relative}`);
  }
  const destination = `third_party/licenses/npm/${pkg.name.replaceAll('@', '').replaceAll('/', '__')}-${pkg.version}`;
  const retained = {};
  for (const file of readdirSync(directory).sort()) {
    if (!/^(licen[cs]e|copying|copyright|notice|thirdpartynotice)/i.test(file) || !statSync(path.join(directory, file)).isFile()) continue;
    const data = readFileSync(path.join(directory, file));
    if (data.length > 2 * 1024 * 1024) throw new Error(`Oversize license: ${pkg.name}`);
    const target = `${destination}/${file}`;
    if (write) { mkdirSync(path.join(root, destination), { recursive: true }); writeFileSync(path.join(root, target), data); }
    if (digest(readFileSync(path.join(root, target))) !== digest(data)) throw new Error(`Retained text differs: ${target}`);
    retained[target] = digest(data);
  }
  const supplement = supplements[pkg.name];
  if (!Object.keys(retained).length) {
    if (!supplement || supplement.version !== pkg.version) throw new Error(`Missing retained license: ${pkg.name}`);
    if (digest(readFileSync(path.join(root, supplement.retained))) !== supplement.sha256) throw new Error(`Supplement differs: ${pkg.name}`);
    retained[supplement.retained] = supplement.sha256;
  }
  inventory.push({ name: pkg.name, version: pkg.version, license: item.license, archive: item.resolved,
    integrity: item.integrity, retained, ...(supplement ? { supplement } : {}) });
}
const output = `${JSON.stringify(inventory, null, 2)}\n`;
const target = path.join(runtime, 'third-party.json');
if (write) writeFileSync(target, output);
else if (readFileSync(target, 'utf8') !== output) throw new Error('Web third-party inventory is stale; run node scripts/web_tools.mjs --write');
console.log(`PASS: ${inventory.length} locked Web packages and retained notices; no project code loaded`);

// Bundled schemas are original upstream bytes, not executable project config.
const schemaDir = path.join(runtime, 'schemas');
const catalog = JSON.parse(readFileSync(path.join(schemaDir, 'catalog.json'), 'utf8'));
if (catalog.schema !== 1 || !/^[a-f0-9]{40}$/.test(catalog.commit) || catalog.schemas.length > 32) throw new Error('Invalid schema catalog');
for (const notice of [catalog.license, catalog.notice]) {
  if (!notice || !notice.path.startsWith('third_party/licenses/') || notice.path.includes('..') || digest(readFileSync(path.join(root, notice.path))) !== notice.sha256) throw new Error('Schema license/notice changed');
}
const known = new Set();
for (const item of catalog.schemas) {
  if (!/^[a-z0-9-]+\.json$/.test(item.file) || known.has(item.file) || item.uri !== `https://json.schemastore.org/${item.file.slice(0, -5)}` || item.source !== `https://raw.githubusercontent.com/SchemaStore/schemastore/${catalog.commit}/src/schemas/json/${item.file}`) throw new Error('Invalid schema provenance');
  known.add(item.file);
  const body = readFileSync(path.join(schemaDir, item.file));
  if (body.length > 1048576 || digest(body) !== item.sha256) throw new Error('Schema changed: ' + item.file);
  JSON.parse(body);
}
console.log(`PASS: ${known.size} pinned offline schemas and retained Apache-2.0 license`);
