import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import test from 'node:test';
const require = createRequire(import.meta.url);
const ts = require('typescript');
function load(path, env) {
  const calls = [];
  const client = { auth: {}, rpc() { assert.equal(this, client); return 'bound'; } };
  const exports = {};
  const code = ts.transpileModule(readFileSync(new URL(path, import.meta.url), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  vm.runInNewContext(code, { exports, process: { env }, require(name) {
    assert.equal(name, '@supabase/supabase-js');
    return { createClient(...args) { calls.push(args); return client; } };
  } });
  return { exports, calls };
}
for (const env of [{}, { NEXT_PUBLIC_SUPABASE_URL: 'https://example.supabase.co' },
  { NEXT_PUBLIC_SUPABASE_ANON_KEY: 'unit-test-key' },
  { NEXT_PUBLIC_SUPABASE_URL: ' ', NEXT_PUBLIC_SUPABASE_ANON_KEY: ' ' }]) {
  test(`missing configuration creates no Supabase client (${Object.keys(env).join(',')})`, () => {
    const browser = load('../app/crm/supabase-client.ts', env);
    assert.equal(browser.exports.crmSupabaseConfigured, false);
    assert.throws(() => browser.exports.crmSupabase.auth, /environment is not configured/);
    assert.equal(browser.calls.length, 0);
    const server = load('../lib/ai/server-supabase.ts', env);
    assert.equal(server.exports.supabaseConfigured(), false);
    assert.throws(() => server.exports.serverSupabase({}), /environment is not configured/);
    assert.equal(server.exports.serverAdminSupabase(), null);
    assert.equal(server.calls.length, 0);
  });
}
test('configured clients use supplied environment and preserve method context', () => {
  const env = { NEXT_PUBLIC_SUPABASE_URL: 'https://example.supabase.co', NEXT_PUBLIC_SUPABASE_ANON_KEY: 'unit-test-key' };
  const browser = load('../app/crm/supabase-client.ts', env);
  assert.equal(browser.calls.length, 0);
  assert.equal(browser.exports.crmSupabase.rpc(), 'bound');
  assert.equal(browser.exports.crmSupabase.rpc(), 'bound');
  assert.equal(browser.calls.length, 1);
  assert.deepEqual(browser.calls[0].slice(0, 2), Object.values(env));
  const server = load('../lib/ai/server-supabase.ts', env);
  server.exports.serverSupabase({ headers: { get: () => 'Bearer unit-test-token' } });
  assert.deepEqual(server.calls[0].slice(0, 2), Object.values(env));
  assert.equal(server.calls[0][2].global.headers.Authorization, 'Bearer unit-test-token');
});
