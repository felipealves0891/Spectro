import path from 'node:path';
import { parseArgs, existingDir, isFile, readUtf8, writeUtf8, emitError } from '../../shared/runtime.mjs';

export async function createRemediationTask({ featureId, findingId, severity, description, returnStage = 'implement', projectRoot = process.cwd() }) {
  const root = await existingDir(projectRoot, 'ProjectRoot');
  if (!/^FINDING-\d+$/.test(findingId)) throw new Error('FindingId must use FINDING-### format.');
  if (!['Critical', 'High', 'Medium', 'Low'].includes(severity)) throw new Error(`Unsupported severity: ${severity}`);
  if (!['specify', 'clarify', 'plan', 'implement', 'gates', 'human_review'].includes(returnStage)) throw new Error(`Unsupported return stage: ${returnStage}`);
  const tasksPath = path.join(root, '.spectro', 'features', featureId, 'tasks.md'); if (!await isFile(tasksPath)) throw new Error(`tasks.md not found: ${tasksPath}`);
  const text = await readUtf8(tasksPath); if (text.includes(findingId)) throw new Error(`A remediation task already references ${findingId}.`);
  const numbers = [...text.matchAll(/\bTASK-REV-(\d+)\b/g)].map((m) => Number(m[1])), number = numbers.length ? Math.max(...numbers) + 1 : 1;
  const task = ['', `## TASK-REV-${String(number).padStart(3, '0')} - Remediate ${findingId}`, '', '- **Status:** pending', `- **Finding:** ${findingId}`, `- **Severity:** ${severity}`, `- **Return stage:** ${returnStage}`, `- **Description:** ${description}`, '- **Dependencies:** none', '- **Completion criteria:** Finding is resolved and relevant gates/review evidence are renewed.', '- **Expected tests:** Add or update behavior-focused coverage as required.', ''].join('\n');
  await writeUtf8(tasksPath, text + task); return `TASK-REV-${String(number).padStart(3, '0')}`;
}
const args = parseArgs(); try { const id = await createRemediationTask({ featureId: args.featureId, findingId: args.findingId, severity: args.severity, description: args.description, returnStage: args.returnStage || 'implement', projectRoot: args.projectRoot || process.cwd() }); console.log(`Created ${id} for ${args.findingId}`); } catch (error) { emitError(error); process.exitCode = 1; }
