import { createHash } from 'node:crypto';
import { exec, execFileSync } from 'node:child_process';
import { constants } from 'node:fs';
import { access, mkdir, readdir, readFile, realpath, stat, lstat, writeFile } from 'node:fs/promises';
import path from 'node:path';

export const isWindows = process.platform === 'win32';
export const text = (value) => String(value ?? '').replace(/^['"]|['"]$/g, '').replace(/\\"/g, '"');
export const utcNow = () => new Date().toISOString();
export const isValidName = (value) => /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value);
export const asArray = (value) => Array.isArray(value) ? value : value == null ? [] : [value];

export function parseArgs(argv = process.argv.slice(2)) {
  const result = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) throw new Error(`Unsupported argument: ${arg}`);
    const raw = arg.slice(2);
    const [key, inline] = raw.split('=', 2);
    const name = key.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    if (inline !== undefined) result[name] = inline;
    else if (argv[i + 1] && !argv[i + 1].startsWith('--')) result[name] = argv[++i];
    else result[name] = true;
  }
  return result;
}

export async function existingDir(value, label) {
  const resolved = path.resolve(value);
  const info = await stat(resolved).catch(() => null);
  if (!info?.isDirectory()) throw new Error(`${label} must be an accessible directory: ${value}`);
  return await realpath(resolved);
}

export async function existingFile(value, label) {
  const resolved = path.resolve(value);
  const info = await stat(resolved).catch(() => null);
  if (!info?.isFile()) throw new Error(`${label} must be an accessible file: ${value}`);
  return await realpath(resolved);
}

export async function findProjectRoot(startPath = process.cwd()) {
  let current = await existingDir(startPath, 'StartPath');
  while (true) {
    const spectro = path.join(current, '.spectro');
    if ((await stat(spectro).catch(() => null))?.isDirectory()) return current;
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
  throw new Error(`Could not find an ancestor .spectro directory from the initial path: ${startPath}`);
}

export function resolveUnder(root, relative, label = 'Path') {
  const rootAbs = path.resolve(root);
  const candidate = path.resolve(rootAbs, relative);
  const relativePart = path.relative(rootAbs, candidate);
  if (relativePart.startsWith('..') || path.isAbsolute(relativePart)) throw new Error(`${label} escapes the project root: ${relative}`);
  return candidate;
}

export function relativeUnix(root, value) {
  return path.relative(root, value).split(path.sep).join('/');
}

export async function ensureDir(directory) { await mkdir(directory, { recursive: true }); return directory; }
export async function readUtf8(file) { return readFile(file, 'utf8'); }
export async function writeUtf8(file, value) { await ensureDir(path.dirname(file)); await writeFile(file, value, 'utf8'); }
export async function readJson(file) { return JSON.parse(await readUtf8(file)); }
export async function writeJson(file, value) { await writeUtf8(file, `${JSON.stringify(value, null, 2)}\n`); }
export async function sha256(file) {
  const info = await stat(file).catch(() => null);
  if (!info?.isFile()) return null;
  return createHash('sha256').update(await readFile(file)).digest('hex');
}
export function gitRevision(root) {
  try { return execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || 'uncommitted'; }
  catch { return 'uncommitted'; }
}

export function scalar(textValue, key, fallback) {
  const match = textValue.match(new RegExp(`^\\s+${key.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\$&')}:\\s*(.+?)\\s*$`, 'm'));
  return match ? text(match[1].trim()) : fallback;
}
export function listValue(textValue, key) {
  const escaped = key.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\$&');
  const match = textValue.match(new RegExp(`^\\s+${escaped}:\\s*\\[(.*?)\\]\\s*$`, 'm'));
  return match?.[1].trim() ? match[1].split(',').map((v) => text(v.trim())).filter(Boolean) : [];
}
export function commandsValue(textValue) {
  const result = {};
  let inCommands = false;
  for (const line of textValue.split(/\r?\n/)) {
    if (/^\s{2}commands:\s*$/.test(line)) { inCommands = true; continue; }
    if (inCommands && /^\S/.test(line)) { inCommands = false; }
    const match = inCommands && line.match(/^\s{4}([A-Za-z0-9._-]+):\s*(.*)$/);
    if (match) result[match[1]] = text(match[2].trim());
  }
  return result;
}

export async function inventory(directory) {
  const files = [], diagnostics = [];
  const root = await realpath(directory);
  async function visit(current) {
    for (const entry of await readdir(current, { withFileTypes: true })) {
      const full = path.join(current, entry.name);
      const link = await lstat(full);
      if (link.isSymbolicLink()) { diagnostics.push(`Ignored linked output: ${full}`); continue; }
      if (entry.isDirectory()) await visit(full);
      else if (entry.isFile()) files.push(relativeUnix(root, full));
    }
  }
  await visit(root);
  return { files: files.sort(), diagnostics };
}

export async function runCommand(command, { cwd, outputDirectory, timeoutSeconds = 900 } = {}) {
  const env = { ...process.env, SPECTRO_GATE_OUTPUT_DIR: outputDirectory };
  const started = Date.now();
  return await new Promise((resolve) => {
    exec(command, { cwd, env, timeout: Math.max(1, timeoutSeconds) * 1000, windowsHide: true, maxBuffer: 16 * 1024 * 1024 }, (error, stdout = '', stderr = '') => {
      const timedOut = error?.killed || error?.signal === 'SIGTERM' || error?.code === 'ETIMEDOUT';
      const output = `${stdout}${stderr ? `${stdout ? '\n' : ''}${stderr}` : ''}`;
      if (timedOut) resolve({ status: 'blocked', exit_code: 124, error: `Command timed out after ${timeoutSeconds} seconds.`, duration_ms: Date.now() - started, stdout, stderr, output });
      else if (error) resolve({ status: 'failed', exit_code: typeof error.code === 'number' ? error.code : 1, error: error.message, duration_ms: Date.now() - started, stdout, stderr, output });
      else resolve({ status: 'passed', exit_code: 0, duration_ms: Date.now() - started, stdout, stderr, output });
    });
  });
}

export function emitError(error) { console.error(error instanceof Error ? error.message : String(error)); }
export async function isFile(file) { return Boolean((await stat(file).catch(() => null))?.isFile()); }
export async function isDirectory(directory) { return Boolean((await stat(directory).catch(() => null))?.isDirectory()); }
