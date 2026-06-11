import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const scriptPath = path.join(__dirname, '..', 'scripts', 'check-entry-record.mjs');

async function writeRecord(content) {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'entry-record-'));
  const file = path.join(temp, 'record.md');
  await writeFile(file, content, 'utf8');
  return file;
}

test('check-entry-record accepts a complete implementation entry record', async () => {
  const file = await writeRecord(`Implementation Entry Record:
- Current layer: implementation
- Target: docs and scripts
- Scope: focused governance cleanup
- Contract evidence: tests/example.test.mjs
- Readiness gate: pass
- Packetization: not-needed
- Verification command: npm run check:all
- Review / Next state file: README.md
- Stop conditions: stop on scope expansion
`);

  const { stdout } = await execFileAsync(process.execPath, [scriptPath, file]);
  assert.match(stdout, /check passed/);
});

test('check-entry-record rejects placeholders and invalid gate fields', async () => {
  const file = await writeRecord(`Implementation Entry Record:
- Current layer: implementation
- Target: docs and scripts
- Scope: TODO
- Contract evidence: tests/example.test.mjs
- Readiness gate: maybe
- Packetization: unknown
- Verification command: npm run check:all
- Review / Next state file: README.md
- Stop conditions: stop on scope expansion
`);

  await assert.rejects(
    execFileAsync(process.execPath, [scriptPath, file]),
    /Empty or placeholder value: Scope|Readiness gate must include pass or fail|Packetization must include/,
  );
});
