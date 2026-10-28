import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { existingDir, isDirectory, isFile, parseArgs, readUtf8, emitError } from '../../shared/runtime.mjs';

function result(status, errors = [], warnings = []) {
  return {
    structure: errors.some((e) => e.startsWith('structure:')) ? 'failed' : 'passed',
    config: errors.some((e) => e.startsWith('config:')) ? 'failed' : 'passed',
    templates: errors.some((e) => e.startsWith('templates:')) ? 'failed' : 'passed',
    status, errors, warnings,
  };
}

export async function validate(workspacePath) {
  const workspace = await existingDir(workspacePath, 'WorkspacePath');
  const root = path.join(workspace, '.spectro');
  const errors = [], warnings = [];
  if (!await isDirectory(root)) errors.push('structure: missing .spectro directory');
  for (const directory of ['templates', 'features']) if (!await isDirectory(path.join(root, directory))) errors.push(`structure: missing directory .spectro/${directory}`);
  for (const file of ['constitution.md', 'config.yaml']) if (!await isFile(path.join(root, file))) errors.push(`structure: missing file .spectro/${file}`);
  for (const name of ['specification.md', 'clarifications.md', 'plan.md', 'tasks.md', 'review.md']) {
    const file = path.join(root, 'templates', name);
    if (!await isFile(file)) errors.push(`templates: missing file .spectro/templates/${name}`);
    else if (!(await readUtf8(file)).trim()) errors.push(`templates: empty file .spectro/templates/${name}`);
  }
  const configPath = path.join(root, 'config.yaml');
  if (await isFile(configPath)) {
    const config = await readUtf8(configPath);
    for (const required of ['version:', 'paths:', 'root:', 'features:', 'templates:', 'workflow:', 'states:', 'retry_limit:', 'recovery:', 'gates:']) if (!new RegExp(`^\\s*${required.replace(':', ':')}`, 'm').test(config)) errors.push(`config: missing required key ${required}`);
    if (!/version:\s*["']?1\.0["']?/.test(config)) errors.push('config: unsupported or missing contract version');
    for (const configuredPath of ['.spectro', '.spectro/features', '.spectro/templates']) if (path.isAbsolute(configuredPath)) errors.push(`config: absolute path is not allowed: ${configuredPath}`);
  }
  return result(errors.length ? 'failed' : warnings.length ? 'passed_with_warnings' : 'passed', errors, warnings);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = parseArgs();
  try {
    const value = await validate(args.workspacePath || args.path || process.cwd());
    if (args.asObject) console.log(JSON.stringify(value)); else console.log(JSON.stringify(value, null, 2));
    process.exitCode = value.errors.length ? 1 : 0;
  } catch (error) { emitError(error); process.exitCode = 1; }
}
