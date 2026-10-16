import { LiveDoc } from '@earendil-works/pi-durable';
import { context, openPilot } from './host.mjs';

const [root, mode, scenario, gate = ''] = process.argv.slice(2);
const emit = row => process.stdout.write(JSON.stringify(row) + '\n');
const deadline = setTimeout(() => process.exit(70), 90000);
let host;
try {
  if (!['init', 'resume', 'inspect'].includes(mode)) throw new Error('invalid pilot command');
  if (scenario === 'real' && mode === 'resume') throw new Error('real-model replay requires separate reconciliation');
  const realModels = scenario === 'real' && mode === 'init' ? await (await import('./real-model.mjs')).existingModels() : undefined;
  host = await openPilot(root, { initialize: mode === 'init', scenario, gate, emit, realModels });
  if (mode === 'inspect') {
    emit({ type: 'snapshot', ...await host.snapshot(), pending: await host.harness.inspect(context) });
  } else {
    let watch;
    if (gate === 'partial') {
      watch = await host.harness.watchDoc(LiveDoc, host.conversation.id, context);
      watch.start(async value => {
        if (value?.generation?.message?.content?.some(part => part.type === 'text' && part.text.length > 0)) await host.pause('partial');
      });
    }
    let submission;
    if (mode === 'init') {
      submission = await host.admit('main', 'Read alpha.txt once using read, then reply PUBLIC_OK. All data are public fixtures.');
      if (scenario === 'delay' && gate === 'admitted') await host.pause('admitted');
      if (['admission', 'steering'].includes(scenario)) {
        await host.admit('follow', 'Public queued command: preserve PILOT_INSTRUCTION.', scenario === 'steering' ? 'steer' : undefined);
        await host.pause('admitted');
      }
    } else {
      const state = await host.snapshot();
      submission = await host.harness.submission(state.requests.main.id, context);
    }
    const result = await submission.wait(context);
    if (['admission', 'steering'].includes(scenario)) {
      const state = await host.snapshot();
      await (await host.harness.submission(state.requests.follow.id, context)).wait(context);
    }
    if (scenario === 'compaction' && mode === 'init') {
      for (let i = 0; i < 3; i++) await (await host.admit(`history-${i}`, `Public fixture detail ${i}.`)).wait(context);
      const compact = await host.conversation.compact('Retain PILOT_INSTRUCTION and the public fixture boundary.', context);
      const { state } = await host.harness.waitForTask(compact, context);
      if (state.outcome.status !== 'completed') throw new Error('compaction failed');
      if (state.outcome.result.submissionId !== undefined) await (await host.harness.submission(state.outcome.result.submissionId, context)).wait(context);
    }
    await host.harness.waitForIdle(context);
    if (watch) await watch.stop();
    emit({ type: 'result', ...await host.snapshot(), submission: result });
  }
} catch (error) {
  // No provider response, credential, transcript, or raw exception is logged.
  emit({ type: 'failure', error: error.name, detail: scenario === 'real' ? 'provider detail withheld' : error.message });
  process.exitCode = 1;
} finally {
  if (host) await host.close();
  clearTimeout(deadline);
  // Provider websocket pools can outlive a completed run. This one-shot host
  // owns them all; exit only AFTER durable close/unlock and stdout delivery.
  process.stdout.write('', () => process.exit(process.exitCode ?? 0));
}
