// Proves an assembled kernel starts with VibeWand's profile and opens a session
// over the Agent Client Protocol. No model is called and no key is needed.
import { spawn } from 'node:child_process';
import { cpSync, mkdtempSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const root = resolve(process.argv[2]);
const home = mkdtempSync(join(tmpdir(), 'vibewand-kernel-smoke-'));
cpSync(join(root, 'profile'), join(home, 'profiles', 'vibewand'), { recursive: true });
// The runtime resolves the profile's packages from beside the profile, as the app arranges at launch.
symlinkSync(join(root, 'node_modules'), join(home, 'profiles', 'vibewand', 'node_modules'));
const kernel = spawn(join(root, 'node', 'bin', 'node'),
  [join(root, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'), '--profile', 'vibewand'],
  { cwd: home, env: { PATH: '/usr/bin:/bin', HOME: home, DSH_HOME: home, DEEPSEEK_API_KEY: 'unused' }, stdio: ['pipe', 'pipe', 'inherit'] });

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
