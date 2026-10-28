import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pathToFileURL } from 'node:url';
import { ensureDir, findProjectRoot, existingDir, existingFile, isFile, isDirectory, parseArgs, readJson, readUtf8, writeJson, writeUtf8, relativeUnix, sha256, gitRevision, scalar, listValue, commandsValue, inventory, isValidName, emitError } from '../../shared/runtime.mjs';
import { runGate } from './run_gate.mjs';

function aggregate(results) {
  const failed = results.filter((gate) => gate.required && ['failed', 'blocked', 'error'].includes(gate.status));
  if (!failed.length) return 'passed';
  if (failed.some((gate) => gate.status === 'error')) return 'error';
  if (failed.some((gate) => gate.status === 'blocked')) return 'blocked';
  return 'failed';
}

export async function runGates({ featureId = 'workspace', configPath = '.spectro/config.yaml', projectRoot = '', continueOnFailure = false } = {}) {
  const root = projectRoot ? await existingDir(projectRoot, 'ProjectRoot') : await findProjectRoot(process.cwd());
  if (!isValidName(featureId)) throw new Error('FeatureId contains unsupported path characters.');
  const configFullPath = await existingFile(path.resolve(root, configPath), 'ConfigPath');
  const configText = await readUtf8(configFullPath);
  const required = listValue(configText, 'required'), optional = listValue(configText, 'optional');
  const commands = commandsValue(configText), timeoutSeconds = Number(scalar(configText, 'timeout_seconds', '900'));
  const failFast = continueOnFailure ? false : scalar(configText, 'fail_fast', 'true') !== 'false';
  const gateNames = [...new Set([...required, ...optional])];
  if (!gateNames.length) throw new Error('No gates are configured.');
  const featureDir = path.join(root, '.spectro', 'features', featureId);
  const outputsRoot = path.join(featureDir, 'outputs'); await ensureDir(outputsRoot);
  const executionBase = `gate-${new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z')}`;
  let executionId = executionBase, counter = 1;
  while (await isDirectory(path.join(outputsRoot, executionId))) executionId = `${executionBase}-${String(++counter).padStart(2, '0')}`;
  const executionOutputDir = path.join(outputsRoot, executionId), evidenceDir = path.join(executionOutputDir, 'evidence');
  await ensureDir(evidenceDir);
  const started = Date.now(), results = [];
  let blockedByFailFast = false;
  for (let index = 0; index < gateNames.length; index += 1) {
    const gateName = gateNames[index];
    if (!isValidName(gateName)) throw new Error(`Gate name contains unsupported path characters: ${gateName}`);
    const requiredGate = required.includes(gateName), command = commands[gateName] || '';
    const evidencePath = path.join(evidenceDir, `${String(index + 1).padStart(2, '0')}-${gateName}.log`);
    const gateOutputDir = path.join(executionOutputDir, gateName); await ensureDir(gateOutputDir);
    const gate = { id: `GATE-${String(index + 1).padStart(3, '0')}`, name: gateName, required: requiredGate, status: 'skipped', command, exit_code: null, duration_ms: 0, diagnostics: [], evidence: [], output_directory: relativeUnix(root, gateOutputDir), output_files: [], output_file_count: 0 };
    if (blockedByFailFast) { gate.status = 'blocked'; gate.diagnostics = ['Skipped because a previous required gate failed and fail-fast is enabled.']; await writeUtf8(evidencePath, gate.diagnostics.join('\n')); }
    else if (!command.trim()) { gate.status = 'blocked'; gate.diagnostics = [`No command configured for gate '${gateName}'.`]; await writeUtf8(evidencePath, gate.diagnostics.join('\n')); if (requiredGate && failFast) blockedByFailFast = true; }
    else {
      const result = await runGate({ command, workingDirectory: root, outputDirectory: gateOutputDir, timeoutSeconds, evidencePath });
      Object.assign(gate, { status: result.status, exit_code: result.exit_code, duration_ms: result.duration_ms });
      if (result.status !== 'passed' && result.output) gate.diagnostics = [result.output.trim()];
      if (requiredGate && failFast && result.status !== 'passed') blockedByFailFast = true;
    }
    if (await isFile(evidencePath)) gate.evidence = [relativeUnix(root, evidencePath)];
    const found = await inventory(gateOutputDir); gate.output_files = found.files; gate.output_file_count = found.files.length; gate.diagnostics.push(...found.diagnostics);
    results.push(gate);
  }
  const aggregateResult = aggregate(results), report = { schema_version: '1.0', feature_id: featureId, execution_id: executionId, project_root: root, code_revision: gitRevision(root), config_hash: `sha256:${await sha256(configFullPath)}`, artifact_hashes: {}, started_at: new Date(started).toISOString(), duration_ms: Date.now() - started, gates: results, result: aggregateResult };
  for (const name of ['spec.md', 'clarifications.md', 'plan.md', 'tasks.md']) { const hash = await sha256(path.join(featureDir, name)); if (hash) report.artifact_hashes[name] = hash; }
  await ensureDir(featureDir); const reportPath = path.join(featureDir, 'gates.json'); await writeJson(reportPath, report);
  const oldState = await readJson(path.join(featureDir, 'state.json')).catch(() => null), phases = { ...(oldState?.phases || {}) }, attempts = { ...(oldState?.attempts || {}) };
  phases.gates = { status: aggregateResult === 'passed' ? 'completed' : aggregateResult, execution_id: executionId, report: relativeUnix(root, reportPath) };
  const state = { schema_version: '1.0', feature_id: featureId, current_phase: aggregateResult === 'passed' ? 'review' : 'gates', status: aggregateResult === 'passed' ? 'completed' : aggregateResult, phases, attempts, invalidated_executions: oldState?.invalidated_executions || [], last_failure: oldState?.last_failure || null, last_execution_id: executionId, updated_at: new Date().toISOString() };
  await writeJson(path.join(featureDir, 'state.json'), state);
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = parseArgs();
  try { const report = await runGates({ featureId: args.featureId || 'workspace', configPath: args.configPath || '.spectro/config.yaml', projectRoot: args.projectRoot || '', continueOnFailure: Boolean(args.continueOnFailure) }); console.log(JSON.stringify(report, null, 2)); process.exitCode = report.result === 'passed' ? 0 : 1; }
  catch (error) { emitError(error); process.exitCode = 1; }
}
