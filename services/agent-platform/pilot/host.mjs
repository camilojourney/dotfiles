import { createHash, randomUUID } from 'node:crypto';
import { closeSync, constants, existsSync, fsyncSync, linkSync, lstatSync, mkdirSync, openSync, readFileSync, realpathSync, unlinkSync, writeFileSync } from 'node:fs';
import { isAbsolute, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { BACKGROUND_CONTEXT as context } from '@earendil-works/chord/context';
import { Type } from '@earendil-works/pi-ai';
import { createModels } from '@earendil-works/pi-ai/models';
import { fauxAssistantMessage, fauxProvider, fauxToolCall } from '@earendil-works/pi-ai/providers/faux';
import { createRegistry, defineDoc, defineExtension, defineTool, Harness, hook, InboxDoc, LiveDoc, section, ToolTask } from '@earendil-works/pi-durable';
import { openNodeSqliteStorage } from '@earendil-works/pi-durable/storage/sqlite/node';

export const IDENTITY = Object.freeze({
  registry: 'public-fixture-pilot-v1', durable: '1.3.0',
  reviewedSource: '698a2d23b86a5045dd54554354a5e0cb7e466795',
  artifact: 'sha512-2aD0xead1LH0BBwUBxex28in/PpUJEwyaEiW/nLoTFUcZ/lDYEl6LHX6mGZKJG8tUHzERwJyysDgy0ruidt84w==',
});
const instruction = 'PILOT_INSTRUCTION: use only the supplied public fixture tools; never execute shell commands.';
const fixtures = { 'alpha.txt': 'alpha public fixture\nblue sky\n', 'beta.txt': 'beta public fixture\ngreen field\n' };
const digest = value => createHash('sha256').update(value).digest('hex');
const PilotDoc = defineDoc({ kind: 'app.pilot', version: 1, scope: 'conversation', history: 'latest', fork: 'initial', initial: () => ({}) });
export class AdmissionConflictError extends Error {}
export const scenarios = ['read', 'search', 'stream', 'admission', 'steering', 'keyed', 'unsafe', 'compaction', 'delay', 'real'];
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

export function privatePath(path, directory = false) {
  const info = lstatSync(path);
  if (realpathSync(path) !== path || info.isSymbolicLink() || info.uid !== process.getuid() || (info.mode & 0o077) || (directory ? !info.isDirectory() : !info.isFile())) {
    throw new Error('pilot path is not private, canonical and owned');
  }
}

// [impl->req~agent-platform.pilot-boundary~1]
export function readFixture(root, path) {
  if (typeof path !== 'string' || !Object.hasOwn(fixtures, path)) throw new Error('fixture path refused');
  const file = join(root, 'fixtures', path);
  privatePath(file);
  if (lstatSync(file).size > 65536) throw new Error('fixture size refused');
  return readFileSync(file, 'utf8');
}

// [impl->req~agent-platform.pilot-effects~1]
export function writeArtifact(root, key, payload) {
  if (!/^[a-z0-9-]{1,64}$/.test(key) || typeof payload !== 'string' || Buffer.byteLength(payload) > 4096) throw new Error('artifact input refused');
  const target = join(root, 'artifacts', `${key}.json`);
  privatePath(join(root, 'artifacts'), true);
  const receipt = { key, destination: `${key}.json`, payload, digest: digest(payload) };
  const expected = JSON.stringify(receipt) + '\n';
  function reconcile() {
    privatePath(target);
    if (readFileSync(target, 'utf8') !== expected) throw new Error('artifact identity conflict');
    return { duplicate: true, digest: receipt.digest };
  }
  if (existsSync(target)) return reconcile();
  const temporary = join(root, 'artifacts', `.${randomUUID()}.tmp`);
  const fd = openSync(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, 0o600);
  try { writeFileSync(fd, expected); fsyncSync(fd); } finally { closeSync(fd); }
  let duplicate = false;
  try { linkSync(temporary, target); }
  catch (error) { if (error.code !== 'EEXIST') throw error; reconcile(); duplicate = true; }
  finally { unlinkSync(temporary); }
  const directory = openSync(join(root, 'artifacts'), constants.O_RDONLY);
  try { fsyncSync(directory); } finally { closeSync(directory); }
  if (readFileSync(target, 'utf8') !== expected) throw new Error('artifact read-back failed');
  return { duplicate, digest: receipt.digest };
}

function text(message) {
  return typeof message?.content === 'string' ? message.content : (message?.content ?? []).filter(part => part.type === 'text').map(part => part.text).join('');
}

export async function lockOwner(root) {
  privatePath(root, true);
  const lock = join(root, 'owner.pid');
  // The OS freshness check can refuse a dead current-second lock. Never unlink
  // it ourselves: bounded polling repeats only the native atomic acquisition.
  const until = Date.now() + 2000;
  for (;;) {
    const acquired = spawnSync('/usr/bin/shlock', ['-p', String(process.pid), '-f', lock]);
    if (acquired.error) throw acquired.error;
    if (acquired.status === 0) break;
    if (Date.now() >= until) throw new Error('pilot already owned');
    await sleep(25);
  }
  return () => { if (readFileSync(lock, 'utf8').trim() === String(process.pid)) unlinkSync(lock); };
}

// [impl->req~agent-platform.pilot-recovery~1]
// [impl->req~agent-platform.pilot-boundary~1]
export async function openPilot(root, options = {}) {
  process.umask(0o077);
  const { initialize = false, scenario, gate = '', emit = () => {}, realModels } = options;
  if (!isAbsolute(root) || resolve(root) !== root || !scenarios.includes(scenario)) throw new Error('invalid pilot identity');
  const database = join(root, 'store.sqlite');
  if (initialize) {
    if (existsSync(root)) throw new Error('pilot initialization collision');
    privatePath(realpathSync(resolve(root, '..')), true);
    mkdirSync(root, { mode: 0o700 });
    mkdirSync(join(root, 'fixtures'), { mode: 0o700 });
    mkdirSync(join(root, 'artifacts'), { mode: 0o700 });
    for (const [name, content] of Object.entries(fixtures)) writeFileSync(join(root, 'fixtures', name), content, { flag: 'wx', mode: 0o600 });
  } else if (!existsSync(database)) throw new Error('pilot store missing');
  privatePath(root, true);
  privatePath(join(root, 'fixtures'), true);
  privatePath(join(root, 'artifacts'), true);
  if (!initialize) privatePath(database);
  const unlock = await lockOwner(root);
  let harness;
  try {
    const pause = async (point, extra = {}) => {
      emit({ checkpoint: point, ...extra });
      if (gate === point) await new Promise(() => {});
    };
    const models = realModels ?? createModels();
    if (!realModels) {
      const faux = fauxProvider({ tokensPerSecond: gate === 'partial' ? 20 : 100000, tokenSize: { min: 1, max: 1 } });
      const response = async transcript => {
        if (text(transcript.messages[0]).includes('summarization')) return fauxAssistantMessage(`${instruction}\nPublic fixture summary.`);
        const user = transcript.messages.findLast(message => message.role === 'user');
        const prompt = text(user);
        const last = transcript.messages.at(-1);
        if (last?.role === 'toolResult') return fauxAssistantMessage('Public fixture complete.');
        if (scenario === 'delay') { emit({ checkpoint: 'model-request' }); await sleep(15000); }
        if (scenario === 'stream' && gate === 'partial') return fauxAssistantMessage('public partial '.repeat(100));
        if (['admission', 'steering'].includes(scenario) && gate === 'admitted') await new Promise(() => {});
        if (['stream', 'admission', 'steering', 'compaction', 'delay'].includes(scenario)) return fauxAssistantMessage(`Public answer ${prompt}. ${'detail '.repeat(scenario === 'compaction' ? 200 : 1)}`);
        const name = scenario === 'search' ? 'search' : ['keyed', 'unsafe'].includes(scenario) ? 'artifact' : 'read';
        const args = name === 'search' ? { query: 'blue' } : name === 'artifact' ? { key: 'operation-1', payload: 'public fixture result' } : { path: 'alpha.txt' };
        return fauxAssistantMessage(fauxToolCall(name, args, { id: 'public-call' }), { stopReason: 'toolUse' });
      };
      faux.setResponses(Array.from({ length: 50 }, () => response));
      models.setProvider(faux.provider);
    }
    const registry = createRegistry();
    const tools = [defineTool({
      name: 'read', description: 'Read alpha.txt or beta.txt from the public fixture only.',
      parameters: Type.Object({ path: Type.String() }), replay: 'safe',
      execute: async ({ path }) => {
        await pause('after-intent');
        const output = readFixture(root, path);
        await pause('read-effect');
        return { output: [{ type: 'text', text: output }], ...(scenario === 'real' ? { control: { terminate: true } } : {}) };
      },
    }), defineTool({
      name: 'search', description: 'Search the two public fixture text files.',
      parameters: Type.Object({ query: Type.String({ maxLength: 80 }) }), replay: 'safe',
      execute: async ({ query }) => ({ output: [{ type: 'text', text: Object.keys(fixtures).filter(name => readFixture(root, name).includes(query)).join('\n') }] }),
    })];
    if (['keyed', 'unsafe'].includes(scenario)) tools.push(defineTool({
      name: 'artifact', description: 'Create one immutable keyed public artifact, never overwrite.',
      parameters: Type.Object({ key: Type.String(), payload: Type.String() }),
      replay: scenario === 'unsafe' ? 'unsafe' : 'safe',
      execute: async ({ key, payload }) => {
        const effect = writeArtifact(root, key, payload);
        await pause('artifact-effect', effect);
        return { output: [{ type: 'text', text: 'Artifact verified.' }] };
      },
    }));
    registry.install(defineExtension({ name: IDENTITY.registry, tools, sections: [section('pilot', () => instruction)], hooks: [hook(ToolTask, { beforeTool: () => pause('before-intent') })] }));
    harness = await Harness.open(await openNodeSqliteStorage(database), {
      models, registry, settings: { retry: { enabled: false }, progress: { partialIntervalMs: 10 },
        compaction: { enabled: false, keepRecentTokens: 50, reserveTokens: 1024, backgroundTokens: 0 },
        stream: { maxTokens: 256, timeoutMs: 60000, maxRetries: 0 } },
      onReport: () => emit({ type: 'runtime-report' }),
    }, context);
    let conversation;
    if (initialize) {
      conversation = await harness.root(context, { agent: { model: realModels ? { provider: 'openai-codex', modelId: 'gpt-6.1-sol' } : { provider: 'faux', modelId: 'faux-1' }, instructions: instruction },
        init: async (tx, conversationId) => { Object.assign(await tx.doc(PilotDoc, conversationId), { identity: IDENTITY, scenario, requests: {}, fixtures: Object.fromEntries(Object.entries(fixtures).map(([key, value]) => [key, digest(value)])) }); } });
    } else {
      conversation = await harness.conversation(1, context);
    }
    const app = conversation && await harness.snapshot(PilotDoc, conversation.id, context);
    if (!app || JSON.stringify(app.identity) !== JSON.stringify(IDENTITY) || app.scenario !== scenario) throw new Error('pilot identity mismatch');
    async function verifyFixtures() {
      for (const [name, hash] of Object.entries(app.fixtures)) if (digest(readFixture(root, name)) !== hash) throw new Error('fixture identity mismatch');
    }
    await verifyFixtures();
    const host = {
      harness, conversation, scenario, pause, verifyFixtures,
      async admit(key, content, whenBusy) {
        const hash = digest(content);
        await conversation.commit(async tx => {
          const doc = await tx.doc(PilotDoc, conversation.id);
          if (Object.hasOwn(doc.requests, key)) {
            if (doc.requests[key].digest !== hash) throw new AdmissionConflictError('request payload mismatch');
          } else {
            doc.requests[key] = { digest: hash };
          }
        }, context);
        const submission = await conversation.submit({ type: 'input', content, requestId: key, ...(whenBusy ? { whenBusy } : {}) }, context);
        await conversation.commit(async tx => { (await tx.doc(PilotDoc, conversation.id)).requests[key].id = submission.id; }, context);
        return submission;
      },
      async snapshot() {
        const state = await harness.snapshot(PilotDoc, conversation.id, context);
        const live = await harness.snapshot(LiveDoc, conversation.id, context);
        const inbox = await harness.snapshot(InboxDoc, conversation.id, context);
        const entries = (await conversation.entries({ order: 'ascending' }, 1000, undefined, context)).items;
        const view = await conversation.watch(context);
        const committedEntryCount = view.value.entries.length;
        await view.stop();
        const modelContext = await conversation.context(context);
        return { ...state, entries: entries.map(entry => ({ id: entry.id, kind: entry.kind, stopReason: entry.model?.[0]?.stopReason, model: entry.model?.[0]?.model, provider: entry.model?.[0]?.provider })),
          queued: inbox?.items?.length ?? 0, partialLength: text(live?.generation?.message).length,
          toolErrors: entries.filter(entry => entry.kind === 'pi.tool-result' && entry.model?.[0]?.isError).length,
          compactions: entries.filter(entry => entry.kind === 'pi.compaction').length,
          instructionRetained: JSON.stringify(modelContext).includes('PILOT_INSTRUCTION'), committedEntryCount };
      },
      async close() { try { await harness.close(context); } finally { unlock(); } },
    };
    return host;
  } catch (error) { if (harness) await harness.close(context); unlock(); throw error; }
}

export { context, sleep };
