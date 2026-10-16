import { DatabaseSync, backup } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import { constants, copyFileSync, existsSync, lstatSync, mkdirSync, readdirSync, realpathSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { lockOwner, privatePath } from './host.mjs';

// [impl->req~agent-platform.pilot-backup~1]
export async function backupPilot(source, destination) {
  process.umask(0o077);
  if (resolve(source) !== source || resolve(destination) !== destination || existsSync(destination)) throw new Error('backup path refused');
  privatePath(dirname(destination), true);
  privatePath(join(source, 'store.sqlite'));
  const release = await lockOwner(source);
  let db;
  try {
    // A held source-owner lock excludes a concurrent Harness. SQLite's backup
    // API includes committed WAL state, unlike copying the bare database file.
    db = new DatabaseSync(join(source, 'store.sqlite'), { readOnly: true });
    mkdirSync(destination, { mode: 0o700 });
    await backup(db, join(destination, 'store.sqlite'));
    for (const subdirectory of ['fixtures', 'artifacts']) {
      const parent = join(source, subdirectory);
      if (realpathSync(parent) !== parent) throw new Error('backup symlink refused');
      mkdirSync(join(destination, subdirectory), { mode: 0o700 });
      for (const name of readdirSync(parent)) {
        const file = join(parent, name), info = lstatSync(file);
        if (!info.isFile() || info.isSymbolicLink() || info.uid !== process.getuid() || (info.mode & 0o077) || info.size > 65536) throw new Error('backup member refused');
        copyFileSync(file, join(destination, subdirectory, name), constants.COPYFILE_EXCL);
      }
    }
    return { database: 'store.sqlite', method: 'node:sqlite backup API', effectsEnabled: false };
  } finally { if (db) db.close(); release(); }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try { console.log(JSON.stringify(await backupPilot(process.argv[2], process.argv[3]))); }
  catch { console.error('pilot backup refused or failed'); process.exitCode = 1; }
}
