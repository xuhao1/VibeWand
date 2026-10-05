// Proves an assembled kernel starts VibeWand's coordinator bundle and opens a
// session over the Agent Client Protocol. The profile is laid out the way the
// app lays it out at launch. The model route is a placeholder: no model is
// called and no key is needed.
import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const root = resolve(process.argv[2]);
const home = mkdtempSync(join(tmpdir(), 'vibewand-kernel-smoke-'));
const profile = join(home, 'profiles', 'vibewand');
mkdirSync(join(profile, 'node_modules'), { recursive: true });
writeFileSync(join(profile, 'package.json'), JSON.stringify({ name: 'dsh-profile-vibewand', private: true, dependencies: {},
  dsh: { profile: { bundles: ['vibewand-coordinator'], patchReload: 'startup' } } }));
writeFileSync(join(profile, 'cordis.yml'), '[]\n');
writeFileSync(join(profile, 'cordis.patch.yml'), '- id: llm-pi-ai\n  config:\n    providers: !!js JSON.parse(process.env.VIBEWAND_ROUTE ?? "{}")\n');
// The harness finds a profile's bundles beside the profile, and a bundle's packages from where the bundle really lives.
symlinkSync(join(root, 'node_modules', 'vibewand-coordinator'), join(profile, 'node_modules', 'vibewand-coordinator'));
const kernel = spawn(join(root, 'node', 'bin', 'node'),
  [join(root, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'), '--profile', 'vibewand'],
  { cwd: home, env: { PATH: '/usr/bin:/bin', HOME: home, DSH_HOME: home, VIBEWAND_MODEL_KEY: 'unused',
      VIBEWAND_MODEL: JSON.stringify({ provider: 'vibewand', model: 'none' }),
      VIBEWAND_ROUTE: JSON.stringify({ vibewand: { api: 'openai-completions', baseURL: 'http://127.0.0.1:9/v1', apiKeyEnv: 'VIBEWAND_MODEL_KEY', models: [{ id: 'none' }] } }) },
    stdio: ['pipe', 'pipe', 'inherit'] });

const finish = (code, message) => {
  if (message) console.error(`kernel smoke test: ${message}`);
  kernel.kill();
  rmSync(home, { recursive: true, force: true });
  process.exit(code);
};
const timer = setTimeout(() => finish(1, 'no answer within 30 s'), 30_000);
const send = (id, method, params) => kernel.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');

let buffer = '';
kernel.stdout.on('data', (chunk) => {
  buffer += chunk;
  for (let end = buffer.indexOf('\n'); end >= 0; end = buffer.indexOf('\n')) {
    const line = buffer.slice(0, end);
    buffer = buffer.slice(end + 1);
    let message;
    try { message = JSON.parse(line); } catch { finish(1, `standard output carried something other than protocol frames: ${line.slice(0, 120)}`); }
    if (message.error) finish(1, `request ${message.id} failed: ${message.error.message}`);
    if (message.id === 1) send(2, 'session/new', { cwd: home, mcpServers: [] });
    if (message.id === 2) {
      clearTimeout(timer);
      finish(message.result?.sessionId ? 0 : 1, message.result?.sessionId ? '' : 'no session was opened');
    }
  }
});
kernel.on('exit', (code) => finish(1, `the kernel exited early with code ${code}`));
send(1, 'initialize', { protocolVersion: 1, clientCapabilities: { fs: { readTextFile: false, writeTextFile: false }, terminal: false } });
