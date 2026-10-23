// Narrow launch adapter for pinned upstream servers. No project module loading,
// network transport, schema catalog downloads or local filesystem URL resolver.
import { createRequire } from 'node:module';
import { createSchemaReader } from './schema-runtime.mjs';

const require = createRequire(import.meta.url);
const mode = process.argv[2];
if (mode !== 'json' && mode !== 'yaml') throw new Error('Expected json or yaml service');
// argv[2] is ours; the upstream transport still sees --stdio.
process.argv.splice(2, 1);
const yamlRequire = createRequire(new URL('../node_modules/yaml-language-server/package.json', import.meta.url));
const { createConnection } = mode === 'yaml' ? yamlRequire('vscode-languageserver/node') : require('vscode-languageserver/node');
const connection = createConnection();
const content = createSchemaReader(connection);
console.log = (...values) => connection.console.log(values.map(String).join(' '));
console.error = (...values) => connection.console.error(values.map(String).join(' '));
process.on('unhandledRejection', error => { connection.console.error(String(error)); setImmediate(() => process.exit(1)); });
if (mode === 'json') {
  const { startServer } = require('../node_modules/vscode-langservers-extracted/lib/json-language-server/jsonServer.js');
  startServer(connection, {
    timer: {
      setImmediate(callback, ...args) { const id = setImmediate(callback, ...args); return { dispose: () => clearImmediate(id) }; },
      setTimeout(callback, ms, ...args) { const id = setTimeout(callback, ms, ...args); return { dispose: () => clearTimeout(id) }; }
    },
    file: { getContent: content }, http: { getContent: content }, configureHttpRequests() {}
  });
} else {
  const [{ YAMLServerInit }, { SettingsState }, { workspaceContext }] = await Promise.all([
    import('../node_modules/yaml-language-server/out/src/yamlServerInit.js'),
    import('../node_modules/yaml-language-server/out/src/yamlSettings.js'),
    import('../node_modules/yaml-language-server/out/src/languageservice/services/schemaRequestHandler.js')
  ]);
  const settings = new SettingsState();
  settings.schemaStoreEnabled = false;
  settings.kubernetesCRDStoreEnabled = false;
  const telemetry = { send() {}, sendError() {}, sendTrack() {} };
  new YAMLServerInit(connection, settings, workspaceContext, content, telemetry).start();
}
