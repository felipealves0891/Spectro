import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { copyFile, readFile } from 'node:fs/promises';
import { ensureDir, existingDir, isDirectory, isFile, parseArgs, writeUtf8, emitError } from '../../shared/runtime.mjs';
import { validate } from './validate_spectro.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const assetRoot = path.resolve(here, '..', 'assets');
const relativeFiles = ['constitution.md', 'config.yaml', 'templates/specification.md', 'templates/clarifications.md', 'templates/plan.md', 'templates/tasks.md', 'templates/review.md'];
const managed = async (file) => (await readFile(file, 'utf8').catch(() => '')).split(/\r?\n/).slice(0, 3).join('\n').includes('spectro-managed: true');

export async function init({ workspacePath = process.cwd(), force = false, dryRun = false, format = 'text' } = {}) {
  const workspace = await existingDir(workspacePath, 'WorkspacePath');
  const root = path.join(workspace, '.spectro');
  const created = [], replaced = [], preserved = [], conflicts = [], warnings = [];
  const add = (list, value) => { if (!list.includes(value)) list.push(value); };
  if (!await isFile(root) && !await isDirectory(root)) { if (!dryRun) await ensureDir(root); add(created, '.spectro'); }
  else if (await isFile(root)) add(conflicts, '.spectro is not a directory'); else add(preserved, '.spectro');
  for (const directory of ['templates', 'features']) {
    const target = path.join(root, directory), rel = `.spectro/${directory}`;
    if (await isFile(target)) add(conflicts, `${rel} is a file`);
    else if (!await isDirectory(target)) { if (!dryRun) await ensureDir(target); add(created, rel); }
    else add(preserved, rel);
  }
  for (const relative of relativeFiles) {
    const destination = path.join(root, relative), source = path.join(assetRoot, relative);
    if (await isDirectory(destination)) { add(conflicts, `${relative} is a directory`); continue; }
    if (!await isFile(source)) { add(conflicts, `missing packaged asset: ${relative}`); continue; }
    const asset = await readFile(source, 'utf8');
    if (!await isFile(destination)) { if (!dryRun) await writeUtf8(destination, asset); add(created, `.spectro/${relative}`); }
    else if ((await readFile(destination, 'utf8')) === asset) add(preserved, `.spectro/${relative}`);
    else if (force && await managed(destination)) { if (!dryRun) await writeUtf8(destination, asset); add(replaced, `.spectro/${relative}`); }
    else add(conflicts, `.spectro/${relative} contains custom or incompatible content`);
  }
  const validation = dryRun ? { structure: 'not_run', config: 'not_run', templates: 'not_run', status: 'not_run', errors: [], warnings: ['dry-run'] } : conflicts.length ? { structure: 'failed', config: 'failed', templates: 'failed', status: 'failed', errors: conflicts, warnings } : await validate(workspace);
  const status = conflicts.length ? 'blocked' : dryRun ? 'completed_with_warnings' : validation.status === 'failed' ? 'failed' : warnings.length ? 'completed_with_warnings' : 'completed';
  return { skill: 'spectro-init', status, workspace, root, created, replaced, preserved, conflicts, validation };
}

const args = parseArgs();
try {
  const report = await init({ workspacePath: args.workspacePath || args.path || process.cwd(), force: Boolean(args.force), dryRun: Boolean(args.dryRun), format: args.format || 'text' });
  if ((args.format || 'text') === 'json') console.log(JSON.stringify(report, null, 2));
  else { console.log(`spectro-init: ${report.status}`); console.log(`workspace: ${report.workspace}`); console.log(`root: ${report.root}`); for (const field of ['created', 'replaced', 'preserved', 'conflicts']) if (report[field].length) console.log(`${field}:\n${report[field].map((v) => `  - ${v}`).join('\n')}`); console.log(`validation: structure=${report.validation.structure}, config=${report.validation.config}, templates=${report.validation.templates}`); }
  process.exitCode = ['blocked', 'failed'].includes(report.status) ? 1 : 0;
} catch (error) { emitError(error); process.exitCode = 1; }
