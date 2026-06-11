import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const skillRoot = path.join(__dirname, '..');

test('runner assets execute only named verification presets', async () => {
  const powershell = await readFile(path.join(skillRoot, 'assets', 'run-autonomous-ready-loop.ps1'), 'utf8');
  const bash = await readFile(path.join(skillRoot, 'assets', 'run-autonomous-ready-loop.sh'), 'utf8');

  assert.doesNotMatch(powershell, /Invoke-Expression/);
  assert.doesNotMatch(bash, /\beval\b/);

  for (const preset of ['routing-guardrails', 'harness-visualization-tests', 'all-local-checks']) {
    assert.match(powershell, new RegExp(preset));
    assert.match(bash, new RegExp(preset));
  }

  assert.match(powershell, /Unknown verification preset/);
  assert.match(bash, /Unknown verification preset/);
});
