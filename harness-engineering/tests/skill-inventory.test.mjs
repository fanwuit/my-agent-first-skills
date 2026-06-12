import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(__dirname, '..', '..');
const scriptPath = path.join(repoRoot, 'harness-engineering', 'scripts', 'check-skill-inventory.mjs');

async function makeRepo(readme) {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'skill-inventory-'));
  await mkdir(path.join(temp, 'alpha-skill', 'scripts'), { recursive: true });
  await mkdir(path.join(temp, 'beta-skill'), { recursive: true });
  await writeFile(path.join(temp, 'alpha-skill', 'SKILL.md'), '---\nname: alpha-skill\n---\n', 'utf8');
  await writeFile(path.join(temp, 'alpha-skill', 'scripts', 'check-alpha.mjs'), 'console.log("ok");\n', 'utf8');
  await writeFile(path.join(temp, 'beta-skill', 'SKILL.md'), '---\nname: beta-skill\n---\n', 'utf8');
  await writeFile(path.join(temp, 'README.md'), readme, 'utf8');
  return temp;
}

test('skill inventory check passes for the current repository', async () => {
  const { stdout } = await execFileAsync(process.execPath, [scriptPath, '--repo', repoRoot]);
  assert.match(stdout, /Skill inventory check passed/);
});

test('skill inventory check rejects missing table rows and assets', async () => {
  const repo = await makeRepo(`# Test\n\n- 启用的非 system skills：2 个。\n\n| 能力域 | Skills | 功能 | 是否启用 |\n|---|---|---|---|\n| A | \`alpha-skill\` | alpha | 是 |\n`);

  await assert.rejects(
    execFileAsync(process.execPath, [scriptPath, '--repo', repo]),
    /README skill table missing enabled skill: beta-skill|README important asset inventory missing: alpha-skill\/scripts\/check-alpha\.mjs/,
  );
});

test('skill inventory check rejects stale table rows', async () => {
  const repo = await makeRepo(`# Test\n\n- 启用的非 system skills：3 个。\n\n| 能力域 | Skills | 功能 | 是否启用 |\n|---|---|---|---|\n| A | \`alpha-skill\` | alpha | 是 |\n| B | \`beta-skill\` | beta | 是 |\n| C | \`deleted-skill\` | stale | 是 |\n\n- \`scripts/check-alpha.mjs\`\n`);

  await assert.rejects(
    execFileAsync(process.execPath, [scriptPath, '--repo', repo]),
    /README enabled skill count is 3, expected 2|README skill table lists missing or disabled skill: deleted-skill/,
  );
});
