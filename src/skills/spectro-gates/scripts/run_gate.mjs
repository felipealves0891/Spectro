import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { parseArgs, existingDir, ensureDir, writeUtf8, runCommand, emitError } from '../../shared/runtime.mjs';

export async function runGate({ command, workingDirectory, outputDirectory, timeoutSeconds = 900, evidencePath = '' }) {
  const cwd = await existingDir(workingDirectory, 'WorkingDirectory');
  await ensureDir(outputDirectory);
  const output = path.resolve(outputDirectory);
  const result = await runCommand(command, { cwd, outputDirectory: output, timeoutSeconds: Number(timeoutSeconds) });
  const payload = { status: result.status, exit_code: result.exit_code, duration_ms: result.duration_ms, output: result.output || result.error || '' };
  if (evidencePath) await writeUtf8(evidencePath, payload.output);
  return payload;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = parseArgs();
  try {
    const result = await runGate({ command: args.command, workingDirectory: args.workingDirectory || process.cwd(), outputDirectory: args.outputDirectory, timeoutSeconds: args.timeoutSeconds || 900, evidencePath: args.evidencePath || '' });
    console.log(JSON.stringify(result));
    process.exitCode = result.exit_code || 0;
  } catch (error) {
    const result = { status: 'error', exit_code: 1, duration_ms: 0, output: error.message };
    if (args.evidencePath) await writeUtf8(args.evidencePath, result.output).catch(() => {});
    console.log(JSON.stringify(result));
    process.exitCode = 1;
  }
}
