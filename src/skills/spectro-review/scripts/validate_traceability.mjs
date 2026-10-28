import path from 'node:path';
import { parseArgs, existingDir, isFile, readUtf8, writeJson, emitError } from '../../shared/runtime.mjs';

export async function validateTraceability({ featureId, projectRoot = process.cwd(), reviewId = '' }) {
  const root = await existingDir(projectRoot, 'ProjectRoot'), featureDir = path.join(root, '.spectro', 'features', featureId);
  const specPath = path.join(featureDir, 'spec.md'), tasksPath = path.join(featureDir, 'tasks.md');
  if (!await isFile(specPath) || !await isFile(tasksPath)) throw new Error('Required artifact not found: spec.md or tasks.md');
  const spec = await readUtf8(specPath), tasks = await readUtf8(tasksPath), plan = await isFile(path.join(featureDir, 'plan.md')) ? await readUtf8(path.join(featureDir, 'plan.md')) : '';
  let selectedReview = reviewId; if (!selectedReview) { const reviews = (await import('node:fs/promises')).readdir(path.join(featureDir, 'reviews'), { withFileTypes: true }).catch(() => []); selectedReview = (await reviews).filter((x) => x.isDirectory()).map((x) => x.name).sort().at(-1); }
  if (!selectedReview) throw new Error('No review directory found.');
  const reviewDir = path.join(featureDir, 'reviews', selectedReview), requirementIds = [...new Set([...spec.matchAll(/\b(?:FR|NFR|CON)-\d+\b/g)].map((m) => m[0]))].sort(), acceptanceIds = [...new Set([...spec.matchAll(/\bAC-\d+\b/g)].map((m) => m[0]))].sort(), taskIds = [...new Set([...tasks.matchAll(/\bTASK(?:-[A-Z]+)?-\d+\b/g)].map((m) => m[0]))].sort();
  const sections = [...tasks.matchAll(/^##\s+(TASK(?:-[A-Z]+)?-\d+).*?(?=^##\s+TASK|\z)/gms)];
  const requirements = requirementIds.map((id) => ({ id, linked_tasks: sections.filter((m) => m[0].includes(id)).map((m) => m[1]), appears_in_plan: plan.includes(id) }));
  const acceptance = acceptanceIds.map((id) => ({ id, appears_in_plan_or_tasks: (plan + '\n' + tasks).includes(id), validation_hint: new RegExp(`(?:test|validat|gate|evidence).{0,180}${id}|${id}.{0,180}(?:test|validat|gate|evidence)`, 'is').test(plan + '\n' + tasks) }));
  const result = { schema_version: '1.0', feature_id: featureId, review_id: selectedReview, requirements, acceptance_criteria: acceptance, task_ids: taskIds, uncovered_requirements: requirements.filter((x) => !x.linked_tasks.length).map((x) => x.id), uncovered_acceptance_criteria: acceptance.filter((x) => !x.validation_hint).map((x) => x.id) };
  result.result = result.uncovered_requirements.length || result.uncovered_acceptance_criteria.length ? 'gaps' : 'complete'; await writeJson(path.join(reviewDir, 'traceability.json'), result); return result;
}
const args = parseArgs(); try { const result = await validateTraceability({ featureId: args.featureId, projectRoot: args.projectRoot || process.cwd(), reviewId: args.reviewId || '' }); console.log(JSON.stringify(result, null, 2)); process.exitCode = result.result === 'complete' ? 0 : 1; } catch (error) { emitError(error); process.exitCode = 1; }
