import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const skillRoot = path.join(__dirname, '..');
const scriptsDir = path.join(skillRoot, 'scripts');

function powershellArgs(script, args = []) {
  return ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(scriptsDir, script), ...args];
}

test('resolve-plan-dir.ps1 rejects invalid active ids and chooses newest valid plan with task_plan', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'planning-ps-resolve-'));
  const planRoot = path.join(temp, '.planning');
  await mkdir(path.join(planRoot, 'bad-newer'), { recursive: true });
  await mkdir(path.join(planRoot, '2026-06-10-good'), { recursive: true });
  await writeFile(path.join(planRoot, '2026-06-10-good', 'task_plan.md'), '# Task Plan\n', 'utf8');
  await writeFile(path.join(planRoot, '.active_plan'), '..\\outside', 'utf8');

  const { stdout } = await execFileAsync('powershell.exe', powershellArgs('resolve-plan-dir.ps1', [planRoot]));

  assert.equal(stdout.trim(), path.join(planRoot, '2026-06-10-good'));
});

test('check-complete.ps1 uses the active plan directory when no plan file is passed', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'planning-ps-complete-'));
  const planRoot = path.join(temp, '.planning');
  const activeDir = path.join(planRoot, '2026-06-10-active');
  await mkdir(activeDir, { recursive: true });
  await writeFile(path.join(planRoot, '.active_plan'), '2026-06-10-active', 'utf8');
  await writeFile(
    path.join(activeDir, 'task_plan.md'),
    ['### Phase 1', '- **Status:** complete', '### Phase 2', '- **Status:** pending'].join('\n'),
    'utf8',
  );

  const { stdout } = await execFileAsync('powershell.exe', powershellArgs('check-complete.ps1'), {
    cwd: temp,
    windowsHide: true,
  });

  assert.match(stdout, /Task in progress \(1\/2 phases complete\)/);
});

test('init-session.ps1 supports slug mode and records active plan', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'planning-ps-init-'));

  await execFileAsync('powershell.exe', powershellArgs('init-session.ps1', ['-PlanDir', 'Quick Spike']), {
    cwd: temp,
    windowsHide: true,
  });

  const activePlan = (await readFile(path.join(temp, '.planning', '.active_plan'), 'utf8')).trim();
  assert.match(activePlan, /^\d{4}-\d{2}-\d{2}-quick-spike$/);
  await readFile(path.join(temp, '.planning', activePlan, 'task_plan.md'), 'utf8');
  await readFile(path.join(temp, '.planning', activePlan, 'findings.md'), 'utf8');
  await readFile(path.join(temp, '.planning', activePlan, 'progress.md'), 'utf8');
});
