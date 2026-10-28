import path from 'node:path';
import { parseArgs, existingDir, existingFile, ensureDir, readJson, readUtf8, writeJson, writeUtf8, relativeUnix, scalar, emitError } from '../../shared/runtime.mjs';
import { runGate } from './run_gate.mjs';
import { runGates } from './run_gates.mjs';

const categories = new Set(['implementation-defect', 'test-defect', 'environment-failure', 'specification-gap', 'planning-defect', 'needs-human-review']);
const stages = { 'implementation-defect': 'implement', 'test-defect': 'implement', 'environment-failure': 'gates', 'specification-gap': 'clarify', 'planning-defect': 'plan', 'needs-human-review': 'waiting_input' };

export async function recover({ featureId, projectRoot = process.cwd(), configPath = '.spectro/config.yaml', failureCategory = '', gateReportPath = '', correctionCommand = '', resumeGates = false }) {
  const root = await existingDir(projectRoot, 'ProjectRoot');
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(featureId)) throw new Error('FeatureId contains unsupported path characters.');
  const featureDir = path.join(root, '.spectro', 'features', featureId), statePath = path.join(featureDir, 'state.json');
  const reportPath = await existingFile(gateReportPath || path.join(featureDir, 'gates.json'), 'GateReportPath');
  const report = await readJson(reportPath), failedGates = (report.gates || []).filter((gate) => ['failed', 'blocked', 'error'].includes(gate.status));
  if (!failedGates.length) throw new Error('The gate report contains no failed, blocked, or errored gates.');
  const config = await readUtf8(path.resolve(root, configPath)), retryLimit = Number(scalar(config, 'retry_limit', '3')), timeoutSeconds = Number(scalar(config, 'timeout_seconds', '900'));
  const failureKey = failureCategory || (failedGates.some((g) => ['blocked', 'error'].includes(g.status)) ? 'environment-failure' : 'needs-human-review');
  if (!categories.has(failureKey)) throw new Error(`Unsupported failure category: ${failureKey}`);
  const targetStage = stages[failureKey], state = await readJson(statePath).catch(() => ({ schema_version: '1.0', feature_id: featureId, current_phase: 'gates', status: 'failed', phases: {}, attempts: {}, invalidated_executions: [], last_failure: null }));
  state.attempts ||= {};
  const attemptProperty = `${failureKey}:${failedGates.map((g) => g.id).join(',')}`; state.attempts[attemptProperty] = Number(state.attempts[attemptProperty] || 0) + 1;
  const attempt = state.attempts[attemptProperty];
  state.current_phase = targetStage; state.status = attempt > retryLimit ? 'blocked' : 'waiting_input'; state.invalidated_executions = [...(state.invalidated_executions || []), report.execution_id];
  state.invalidation_reason = `Recovery invalidated evidence for ${report.execution_id}.`; state.last_failure = { category: failureKey, stage: targetStage, execution_id: report.execution_id, gate_ids: failedGates.map((g) => g.id), diagnostics: failedGates.map((g) => `${g.name}: ${(g.diagnostics || []).join(' ')}`), detected_at: new Date().toISOString() };
  if (attempt > retryLimit) { state.updated_at = new Date().toISOString(); await writeJson(statePath, state); console.log(`Retry limit exceeded for ${attemptProperty}. State is blocked.`); return 1; }
  if (!correctionCommand) { state.updated_at = new Date().toISOString(); await writeJson(statePath, state); console.log(JSON.stringify(state, null, 2)); return 0; }
  const recoveryOutputDir = path.join(featureDir, 'outputs', report.execution_id, 'recovery', `attempt-${String(attempt).padStart(2, '0')}`), recoveryEvidence = path.join(featureDir, 'outputs', report.execution_id, 'evidence', `recovery-${String(attempt).padStart(2, '0')}.log`);
  await ensureDir(recoveryOutputDir); const correction = await runGate({ command: correctionCommand, workingDirectory: root, outputDirectory: recoveryOutputDir, timeoutSeconds, evidencePath: recoveryEvidence });
  if (correction.status !== 'passed') { state.status = 'failed'; state.last_failure = { category: 'environment-failure', stage: targetStage, correction_status: 'failed', diagnostics: [correction.output] }; state.updated_at = new Date().toISOString(); await writeJson(statePath, state); console.log(JSON.stringify(correction)); return 1; }
  state.status = 'completed'; state.current_phase = targetStage; state.last_failure = { category: failureKey, stage: targetStage, correction_status: 'passed', correction_evidence: relativeUnix(root, recoveryEvidence) }; state.updated_at = new Date().toISOString(); await writeJson(statePath, state); console.log(JSON.stringify(state, null, 2));
  if (resumeGates && targetStage === 'gates') return (await runGates({ featureId, configPath, projectRoot: root })).result === 'passed' ? 0 : 1;
  return 0;
}

const args = parseArgs(); try { process.exitCode = await recover({ featureId: args.featureId, projectRoot: args.projectRoot || process.cwd(), configPath: args.configPath || '.spectro/config.yaml', failureCategory: args.failureCategory || '', gateReportPath: args.gateReportPath || '', correctionCommand: args.correctionCommand || '', resumeGates: Boolean(args.resumeGates) }); } catch (error) { emitError(error); process.exitCode = 1; }
