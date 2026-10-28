import path from 'node:path';
import { existingFile, parseArgs, readJson, emitError } from '../../shared/runtime.mjs';

export async function validateGates(reportPath) {
  const report = await readJson(await existingFile(reportPath, 'ReportPath')), errors = [];
  for (const field of ['schema_version', 'feature_id', 'execution_id', 'project_root', 'code_revision', 'config_hash', 'started_at', 'duration_ms', 'gates', 'result']) if (report[field] === undefined || report[field] === null) errors.push(`Missing field: ${field}`);
  if (report.project_root && !path.isAbsolute(String(report.project_root))) errors.push('Invalid project_root: must be an absolute path');
  if (report.schema_version !== '1.0') errors.push(`Unsupported schema_version: ${report.schema_version}`);
  if (!['passed', 'failed', 'blocked', 'error'].includes(report.result)) errors.push(`Invalid aggregate result: ${report.result}`);
  for (const gate of report.gates || []) {
    for (const field of ['id', 'name', 'required', 'status', 'command', 'duration_ms', 'diagnostics', 'evidence']) if (gate[field] === undefined || gate[field] === null) errors.push(`${gate.name}: missing field ${field}`);
    if (!['passed', 'failed', 'blocked', 'error', 'skipped'].includes(gate.status)) errors.push(`${gate.name}: invalid status ${gate.status}`);
    if (gate.output_directory === undefined || gate.output_files === undefined || gate.output_file_count === undefined) errors.push(`${gate.name}: missing output contract`);
    if (gate.output_directory !== undefined) {
      if (!gate.output_directory || path.isAbsolute(gate.output_directory)) errors.push(`${gate.name}: output_directory must be relative`);
      const expected = path.resolve(report.project_root, '.spectro', 'features', report.feature_id, 'outputs', report.execution_id);
      const resolved = path.resolve(report.project_root, gate.output_directory);
      if (path.relative(expected, resolved).startsWith('..')) errors.push(`${gate.name}: output_directory escapes the execution output directory`);
    }
    if (!Array.isArray(gate.output_files)) errors.push(`${gate.name}: output_files must be a list`);
    else if (Number(gate.output_file_count) !== gate.output_files.length) errors.push(`${gate.name}: output_file_count does not match output_files`);
  }
  return errors;
}
const args = parseArgs(); try { const errors = await validateGates(args.reportPath); if (errors.length) { errors.forEach((e) => console.error(e)); process.exitCode = 1; } else console.log(`Gate report is valid: ${args.reportPath}`); } catch (error) { emitError(error); process.exitCode = 1; }
