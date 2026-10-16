import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { AdmissionConflictError, context, openPilot } from './host.mjs';

// [impl->req~agent-platform.central-terminal~1]
export async function serve(host, { input = process.stdin, output = process.stdout } = {}) {
  const emit = row => output.write(JSON.stringify(row) + '\n');
  const lines = createInterface({ input, crlfDelay: Infinity, terminal: false });
  host.harness.resume();
  emit({ type: 'ready', tools: ['read', 'search'], commands: 'status OR request-key public-fixture instruction' });
  try {
    for await (const line of lines) {
      if (line === 'status') { emit({ type: 'snapshot', ...await host.snapshot() }); continue; }
      const match = /^([a-z0-9-]{1,64}) (.{1,4096})$/.exec(line);
      if (!match) { emit({ type: 'refused', detail: 'command refused' }); continue; }
      try {
        const submission = await host.admit(match[1], match[2]);
        emit({ type: 'admitted', id: submission.id, key: match[1] });
        const result = await submission.wait(context);
        emit({ type: 'completed', id: submission.id, status: result.status });
      } catch (error) {
        if (!(error instanceof AdmissionConflictError)) throw error;
        emit({ type: 'refused', detail: 'command refused' });
      }
    }
  } finally { lines.close(); }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  let host;
  try {
    const [root, mode] = process.argv.slice(2);
    if (!['init', 'serve'].includes(mode)) throw new Error('invalid mode');
    const { existingModels } = await import('./real-model.mjs');
    host = await openPilot(root, { initialize: mode === 'init', scenario: 'real', realModels: await existingModels() });
    if (mode === 'serve') await serve(host);
    else console.log(JSON.stringify({ type: 'initialized', model: 'openai-codex/gpt-6.1-sol' }));
  } catch {
    console.error('central Durable host refused or failed');
    process.exitCode = 1;
  } finally {
    if (host) await host.close();
    process.stdout.write('', () => process.exit(process.exitCode ?? 0));
  }
}
