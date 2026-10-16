import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { openPilot, writeArtifact, readFixture, IDENTITY } from './host.mjs';
import { backupPilot } from './backup.mjs';

const scratch = realpathSync(mkdtempSync(join(tmpdir(), 'durable-pilot-')));
const childPath = fileURLToPath(new URL('./cli.mjs', import.meta.url));
function directory(name) { return join(scratch, name); }
function child(root, mode, scenario, gate = '') {
  const proc = spawn(process.execPath, [childPath, root, mode, scenario, gate], { stdio: ['ignore', 'pipe', 'pipe'] });
  const rows = [];
  let output = '', stderr = '';
  proc.stdout.on('data', chunk => {
    output += chunk;
    let index;
    while ((index = output.indexOf('\n')) >= 0) {
      const line = output.slice(0, index); output = output.slice(index + 1);
      rows.push(JSON.parse(line));
    }
  });
  proc.stderr.on('data', chunk => { stderr += chunk; });
  const done = new Promise((resolve, reject) => {
    const timer = setTimeout(() => { proc.kill('SIGKILL'); reject(new Error(`child timeout: ${scenario}/${gate}`)); }, 30000);
    proc.on('close', (code, signal) => { clearTimeout(timer); resolve({ code, signal, rows, stderr }); });
  });
  return { proc, rows, done };
}
async function reached(worker, point) {
  for (let count = 0; count < 500; count++) {
    const found = worker.rows.find(row => row.checkpoint === point);
    if (found) return found;
    if (worker.proc.exitCode !== null) throw new Error(JSON.stringify(await worker.done));
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  worker.proc.kill('SIGKILL');
  throw new Error(`checkpoint not reached: ${point}`);
}
async function crash(name, scenario, point) {
  const root = directory(name);
  const worker = child(root, 'init', scenario, point);
  const checkpoint = await reached(worker, point);
  assert.equal(worker.proc.kill('SIGKILL'), true);
  assert.equal((await worker.done).signal, 'SIGKILL');
  const inspect = await child(root, 'inspect', scenario).done;
  assert.equal(inspect.code, 0, JSON.stringify(inspect));
  const before = inspect.rows.find(row => row.type === 'snapshot');
  if (scenario === 'unsafe') {
    const backup = root + '-pending-backup';
    await backupPilot(root, backup);
    const restored = await child(backup, 'inspect', scenario).done;
    assert.equal(restored.code, 0);
    assert.deepEqual(restored.rows[0].requests, before.requests);
    assert.deepEqual(restored.rows[0].entries, before.entries);
    assert.ok(restored.rows[0].pending.tasks.some(task => task.record.kind === 'pi.tool' && task.record.state.checkpoint.replay === 'unsafe'));
    assert.equal(restored.rows.some(row => row.checkpoint === 'artifact-effect'), false);
    assert.equal(readdirSync(join(backup, 'artifacts')).length, 1);
  }
  const resumed = await child(root, 'resume', scenario).done;
  assert.equal(resumed.code, 0, JSON.stringify(resumed));
  return { root, before, checkpoint, resumed: resumed.rows.find(row => row.type === 'result'), events: resumed.rows };
}

let readOnlyPassed = false;

// [utest->req~agent-platform.pilot-recovery~1]
test('read-only recovery precedes granting the keyed mutation', async () => {
  for (const point of ['before-intent', 'after-intent', 'read-effect']) {
    const result = await crash(`read-${point}`, 'read', point);
    assert.equal(result.resumed.submission.status, 'done');
    assert.equal(result.resumed.toolErrors, 0);
    assert.equal(result.resumed.requests.main.id, result.before.requests.main.id);
    assert.equal(result.resumed.entries.filter(entry => entry.kind === 'pi.user').length, 1);
    assert.equal(result.resumed.committedEntryCount, result.resumed.entries.length);
    assert.equal(result.events.filter(row => row.checkpoint === 'read-effect').length, 1);
  }
  const search = await child(directory('search'), 'init', 'search').done;
  assert.equal(search.code, 0, JSON.stringify(search));
  assert.equal(search.rows.find(row => row.type === 'result').toolErrors, 0);
  const partial = await crash('partial', 'stream', 'partial');
  assert.ok(partial.before.partialLength > 0);
  assert.ok(partial.resumed.entries.some(entry => entry.stopReason === 'aborted'));
  assert.equal(partial.resumed.submission.status, 'done');
  const admitted = await crash('admission', 'admission', 'admitted');
  assert.equal(admitted.before.queued, 1);
  assert.equal(admitted.resumed.requests.follow.id, admitted.before.requests.follow.id);
  assert.equal(admitted.resumed.submission.status, 'done');
  assert.ok(admitted.resumed.entries.filter(entry => entry.kind === 'pi.user').length >= 2);
  const steered = await crash('steering', 'steering', 'admitted');
  assert.equal(steered.before.queued, 1);
  assert.equal(steered.resumed.requests.follow.id, steered.before.requests.follow.id);
  assert.equal(steered.resumed.submission.status, 'done');
  const compact = await child(directory('compaction'), 'init', 'compaction').done;
  assert.equal(compact.code, 0, JSON.stringify(compact));
  const compacted = compact.rows.find(row => row.type === 'result');
  assert.ok(compacted.compactions >= 1);
  assert.equal(compacted.instructionRetained, true);
  const reopened = await child(directory('compaction'), 'inspect', 'compaction').done;
  assert.equal(reopened.code, 0);
  assert.equal(reopened.rows[0].compactions, compacted.compactions);
  assert.equal(reopened.rows[0].instructionRetained, true);
  readOnlyPassed = true;
});

// [utest->req~agent-platform.pilot-effects~1]
// [utest->req~agent-platform.pilot-backup~1]
test('keyed target reconciles after effect-before-result; unsafe stays interrupted', async t => {
  if (!readOnlyPassed) { t.skip('read-only recovery has not passed'); return; }
  const safe = await crash('keyed', 'keyed', 'artifact-effect');
  assert.equal(safe.resumed.toolErrors, 0);
  assert.equal(safe.events.filter(row => row.checkpoint === 'artifact-effect').length, 1);
  assert.equal(safe.events.find(row => row.checkpoint === 'artifact-effect').duplicate, true);
  assert.deepEqual(readdirSync(join(safe.root, 'artifacts')), ['operation-1.json']);
  const artifact = JSON.parse(readFileSync(join(safe.root, 'artifacts/operation-1.json')));
  assert.equal(artifact.payload, 'public fixture result');
  assert.equal(writeArtifact(safe.root, 'operation-1', 'public fixture result').duplicate, true);
  assert.throws(() => writeArtifact(safe.root, 'operation-1', 'changed'), /identity conflict/);
  assert.equal(writeArtifact(safe.root, 'operation-2', 'another authorized fixture').duplicate, false);
  assert.equal(readdirSync(join(safe.root, 'artifacts')).length, 2);
  const unsafe = await crash('unsafe', 'unsafe', 'artifact-effect');
  assert.equal(unsafe.resumed.toolErrors, 1);
  assert.equal(unsafe.events.filter(row => row.checkpoint === 'artifact-effect').length, 0);
  assert.equal(readdirSync(join(unsafe.root, 'artifacts')).length, 1);
});

// [utest->req~agent-platform.pilot-boundary~1]
test('single owner, store identity, fixture scope, and payload mismatch refuse', async () => {
  const root = directory('boundary');
  const host = await openPilot(root, { initialize: true, scenario: 'read' });
  try {
    await assert.rejects(openPilot(root, { scenario: 'read' }), /already owned/);
    assert.throws(() => readFixture(root, '../outside'), /fixture path/);
    const submission = await host.admit('identity', 'first public input');
    assert.equal((await host.admit('identity', 'first public input')).id, submission.id);
    await assert.rejects(host.admit('identity', 'different public input'), /payload mismatch/);
  } finally { await host.close(); }
  await assert.rejects(openPilot(directory('missing'), { scenario: 'read' }), /missing/);
  await assert.rejects(openPilot(root, { scenario: 'search' }), /identity mismatch/);
  const reopened = await openPilot(root, { scenario: 'read' });
  try {
    assert.deepEqual((await reopened.snapshot()).identity, IDENTITY);
    const file = join(root, 'fixtures/alpha.txt');
    writeFileSync(file, 'changed fixture');
    await assert.rejects(reopened.verifyFixtures(), /fixture identity/);
  } finally { await reopened.close(); }
});

console.log(`pilot test evidence retained at ${scratch}`);
