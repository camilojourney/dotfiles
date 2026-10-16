import { join } from 'node:path';
import { homedir } from 'node:os';
import { lstatSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { createModels } from '@earendil-works/pi-ai/models';
import { openaiCodexProvider } from '@earendil-works/pi-ai/providers/openai-codex';

// Existing credential API only. No credential value is extracted, logged,
// forwarded to a child, or persisted in the pilot's SQLite store.
export async function existingModels() {
  const authPath = join(homedir(), '.pi/agent/auth.json');
  const info = lstatSync(authPath);
  if (!info.isFile() || info.isSymbolicLink() || info.uid !== process.getuid() || (info.mode & 0o077)) throw new Error('existing credential store is not private');
  const installed = '/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent';
  const { AuthStorage } = await import(pathToFileURL(join(installed, 'dist/core/auth-storage.js')));
  const models = createModels({ credentials: AuthStorage.create(authPath) });
  models.setProvider(openaiCodexProvider());
  if (!models.getModel('openai-codex', 'gpt-6.1-sol')) throw new Error('exact existing model unavailable');
  return models;
}
