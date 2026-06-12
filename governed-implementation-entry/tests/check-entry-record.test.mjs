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
const scriptPath = path.join(__dirname, '..', 'scripts', 'check-entry-record.mjs');
const fixturePath = path.join(__dirname, 'fixtures', 'valid-entry-record.md');

const implementationRecord = `Implementation Entry Record:
- Current layer: implementation
- Target: docs and scripts
- Scope: focused governance cleanup
- Contract evidence: tests/example.test.mjs
- Readiness gate: pass
- Packetization: not-needed
- Verification command: npm run check:all
- Review / Next state file: README.md
- Stop conditions: stop on scope expansion
`;

async function writeRecord(content) {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'entry-record-'));
  const file = path.join(temp, 'record.md');
  await writeFile(file, content, 'utf8');
  return file;
}

async function makeRepo(records) {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'entry-record-repo-'));
  await mkdir(path.join(temp, 'governed-implementation-entry', 'tests', 'fixtures'), { recursive: true });
  await mkdir(path.join(temp, 'docs', 'remediation'), { recursive: true });
  await writeFile(path.join(temp, 'governed-implementation-entry', 'tests', 'fixtures', 'valid-entry-record.md'), implementationRecord, 'utf8');
  for (const [name, content] of Object.entries(records)) {
    await writeFile(path.join(temp, 'docs', 'remediation', name), content, 'utf8');
  }
  return temp;
}

test('check-entry-record accepts the committed implementation entry fixture', async () => {
  const { stdout } = await execFileAsync(process.execPath, [scriptPath, fixturePath]);
  assert.match(stdout, /Entry record check passed: 1 file\(s\)/);
});

test('check-entry-record accepts a complete implementation entry record', async () => {
  const file = await writeRecord(implementationRecord);

  const { stdout } = await execFileAsync(process.execPath, [scriptPath, file]);
  assert.match(stdout, /Entry record check passed: 1 file\(s\)/);
});

test('check-entry-record accepts a complete trivial safe change entry', async () => {
  const file = await writeRecord(`Trivial Safe Change Entry:
- Target: README.md
- Scope: clarify wording only
- Why trivial: documentation-only wording change with no product behavior impact
- Existing contract or reason not needed: no runtime contract affected
- Verification: npm run check:fast
- Stop conditions: stop if behavior, routing, or package scripts need changes
`);

  const { stdout } = await execFileAsync(process.execPath, [scriptPath, file]);
  assert.match(stdout, /Entry record check passed: 1 file\(s\)/);
});

test('check-entry-record discovers remediation records and the stable fixture', async () => {
  const repo = await makeRepo({
    'alpha整改记录.md': implementationRecord,
    '剩余整改项.md': '# backlog, not an entry record\n',
  });

  const { stdout } = await execFileAsync(process.execPath, [scriptPath, '--repo', repo]);
  assert.match(stdout, /Entry record check passed: 2 file\(s\)/);
});

test('check-entry-record reports discovered invalid remediation records', async () => {
  const repo = await makeRepo({
    'bad整改记录.md': `Implementation Entry Record:
- Current layer: implementation
- Target: docs and scripts
- Scope: TODO
- Contract evidence: tests/example.test.mjs
- Readiness gate: maybe
- Packetization: unknown
- Verification command: npm run check:all
- Review / Next state file: README.md
- Stop conditions: stop on scope expansion
`,
  });

  await assert.rejects(
    execFileAsync(process.execPath, [scriptPath, '--repo', repo]),
    /bad整改记录\.md: Empty or placeholder value: Scope|bad整改记录\.md: Readiness gate must include pass or fail|bad整改记录\.md: Packetization must include/,
  );
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

test('check-entry-record rejects incomplete trivial safe change entries', async () => {
  const file = await writeRecord(`Trivial Safe Change Entry:
- Target: README.md
- Scope: clarify wording only
- Why trivial: TODO
- Verification: npm run check:fast
- Stop conditions: stop on scope expansion
`);

  await assert.rejects(
    execFileAsync(process.execPath, [scriptPath, file]),
    /Empty or placeholder value: Why trivial|Missing field: Existing contract or reason not needed/,
  );
});
