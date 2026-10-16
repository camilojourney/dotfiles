import assert from 'node:assert/strict';
import { mkdtempSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Readable, Writable } from 'node:stream';
import { test } from 'node:test';
import { openPilot } from './host.mjs';
import { serve } from './central.mjs';

// [utest->req~agent-platform.central-terminal~1]
test('terminal admits keyed input into upstream state, never an extra execution queue', async () => {
  const parent = realpathSync(mkdtempSync(join(tmpdir(), 'durable-central-')));
  const root = join(parent, 'store');
  let host = await openPilot(root, { initialize: true, scenario: 'real' });
  let output = '';
  const write = new Writable({ write(chunk, encoding, next) { output += chunk.toString(); next(); } });
  try {
    await serve(host, { input: Readable.from(['status\nrequest-1 Read alpha.txt\nrequest-1 Read alpha.txt\nrequest-1 changed\nconstructor Read alpha.txt\n../escape nope\n']), output: write });
    const snapshot = await host.snapshot();
    assert.deepEqual(Object.keys(snapshot.requests), ['request-1', 'constructor']);
    assert.equal(snapshot.entries.filter(entry => entry.kind === 'pi.user').length, 2);
    assert.equal(snapshot.toolErrors, 0);
    assert.equal(snapshot.entries.filter(entry => entry.kind === 'pi.tool-result').length, 2);
    assert.equal(output.includes('request payload mismatch'), false);
    assert.equal(output.includes('command refused'), true);
    assert.equal(output.includes('done'), true);
  } finally { await host.close(); }
  host = await openPilot(root, { scenario: 'real' });
  try { assert.deepEqual(Object.keys((await host.snapshot()).requests), ['request-1', 'constructor']); }
  finally { await host.close(); }
});
