import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(__dirname, '..', '..');

async function readRepoText(relativePath) {
  return readFile(path.join(repoRoot, relativePath), 'utf8');
}

test('layer progression maps governed implementation entry into implementation routing', async () => {
  const layerProgression = await readRepoText('harness-engineering/references/layer-progression.md');
  const harnessSkill = await readRepoText('harness-engineering/SKILL.md');
  const readme = await readRepoText('README.md');

  assert.match(layerProgression, /\|\s*`readiness`\s*\|[^\n]*`governed-implementation-entry`/);
  assert.match(layerProgression, /\|\s*`implementation`\s*\|[^\n]*`governed-implementation-entry`/);
  assert.match(layerProgression, /Implementation Entry Record.*mechanical credential/i);
  assert.match(harnessSkill, /Implementation Entry Record.*mechanical credential/i);
  assert.match(readme, /Implementation Entry Record.*mechanical credential/i);
});

test('entry docs preserve lightweight routing without weakening companion containment', async () => {
  const agents = await readRepoText('AGENTS.md');
  const harnessSkill = await readRepoText('harness-engineering/SKILL.md');
  const readme = await readRepoText('README.md');

  assert.match(agents, /Fast Path/);
  assert.match(agents, /Trivial Safe Change/);
  assert.match(agents, /Governed Path/);
  assert.match(harnessSkill, /fast-path/);
  assert.match(harnessSkill, /trivial-safe-change/);
  assert.match(harnessSkill, /governed-path/);
  assert.match(harnessSkill, /lazy|insufficient|only when/i);
  assert.match(readme, /check:fast/);
  assert.match(readme, /check:governance/);
  assert.match(agents, /companion workflows run only after harness selects the current layer/i);
  assert.match(harnessSkill, /companion workflows run only after harness selects the current layer/i);
});

test('dashboard skill delegates implementation to harness visualization by default', async () => {
  const dashboard = await readRepoText('harness-status-dashboard/SKILL.md');
  const readme = await readRepoText('README.md');

  assert.match(dashboard, /default implementation/i);
  assert.match(dashboard, /harness-visualization\/scripts\/harness-status\.mjs/);
  assert.doesNotMatch(dashboard, /新增一个 report 脚本/);
  assert.match(readme, /dashboard.*解释\/诊断/s);
  assert.match(readme, /visualization.*默认实现/s);
});

test('find-docs README documents external openai-docs dependency and fallback', async () => {
  const readme = await readRepoText('README.md');

  assert.match(readme, /system `openai-docs`/);
  assert.match(readme, /official OpenAI docs fallback/i);
});

test('README and governance docs preserve check frequency boundaries', async () => {
  const readme = await readRepoText('README.md');
  const checkFrequency = await readRepoText('harness-engineering/references/check-frequency.md');
  const documentGardener = await readRepoText('document-gardener/SKILL.md');
  const completion = await readRepoText('review-next-governance/references/completion-review-branch.md');

  assert.match(readme, /迭代中优先跑 targeted checks/);
  assert.match(readme, /阶段收口.*check:all/s);
  assert.match(checkFrequency, /During iteration: run targeted checks/i);
  assert.match(documentGardener, /scan-only/i);
  assert.match(completion, /不等于每次都要写持久化 verification record/);
});

test('status display contract is centralized in harness visualization reference', async () => {
  const dashboard = await readRepoText('harness-status-dashboard/SKILL.md');
  const visualization = await readRepoText('harness-visualization/SKILL.md');
  const statusContract = await readRepoText('harness-visualization/references/status-contract.md');

  assert.match(dashboard, /harness-visualization\/references\/status-contract\.md/);
  assert.match(visualization, /references\/status-contract\.md/);
  assert.match(statusContract, /Task Packet Checklist Rule/);
  assert.match(statusContract, /Current ready.*scheduling item/s);
});

test('QA Release Monitor Retro practices remain local-owner evidence only', async () => {
  const readme = await readRepoText('README.md');
  const lifecycle = await readRepoText('harness-engineering/references/local-qa-release-monitor-retro.md');

  assert.match(readme, /不引入外部 lifecycle adapter/);
  assert.match(lifecycle, /do not approve new product scope/i);
  assert.match(lifecycle, /Do not tag, publish, deploy, push, open PR, or create commits/i);
});
