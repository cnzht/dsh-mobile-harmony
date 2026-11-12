'use strict';
/**
 * Privacy scan: no author personal data in any tracked file.
 *
 * The registered developer name must live only in the local, gitignored
 * `entry/src/main/resources/rawfile/developer.json` (see
 * `developer.json.example` for the format). The scan covers every file git
 * tracks (`git ls-files`, so the untracked local config is excluded by
 * construction) and also checks for phone numbers, email addresses and
 * long digit runs that could be an App ID / Developer ID.
 *
 * Both name patterns are derived at run time from the local, gitignored
 * developer.json, so this test file itself never contains the name in any
 * form. Without that file (fresh clone) the name checks are skipped; the
 * phone / email / long-digit checks always run.
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');

// Registered developer name, from the local gitignored config (or null
// without it). The escaped form is built from the same value.
function loadDevName() {
  try {
    const cfg = JSON.parse(fs.readFileSync(
      path.join(ROOT, 'entry/src/main/resources/rawfile/developer.json'), 'utf8'));
    return typeof cfg.developerName === 'string' && cfg.developerName.length > 0
      ? cfg.developerName
      : null;
  } catch {
    return null;
  }
}

const DEV_NAME = loadDevName();
const DEV_NAME_ESCAPED = DEV_NAME === null ? null
  : [...DEV_NAME]
    .map((c) => String.fromCharCode(92) + 'u' + c.codePointAt(0).toString(16).padStart(4, '0'))
    .join('');

function trackedFiles() {
  const out = execFileSync('git', ['ls-files'], { cwd: ROOT, encoding: 'utf8' });
  return out.split('\n').filter(Boolean).map((rel) => path.join(ROOT, rel));
}

function isBinary(buf) {
  return buf.includes(0);
}

test('no author personal data in any tracked file', () => {
  const files = trackedFiles();
  assert.ok(files.length > 50, 'expected the repo file list');
  const hits = [];
  for (const file of files) {
    const buf = fs.readFileSync(file);
    if (isBinary(buf)) continue; // e.g. entry/mdbx.dat, screenshots
    const text = buf.toString('utf8');
    const rel = path.relative(ROOT, file);
    if (DEV_NAME !== null && text.includes(DEV_NAME)) hits.push(`${rel}: registered developer name`);
    if (DEV_NAME_ESCAPED !== null && !rel.startsWith('tests' + path.sep) && text.includes(DEV_NAME_ESCAPED)) {
      hits.push(`${rel}: escaped developer name`);
    }
    if (/1[3-9]\d{9}/.test(text)) hits.push(`${rel}: phone-number-like digits`);
    if (/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/.test(text)) {
      hits.push(`${rel}: email-like string`);
    }
    if (/\d{16,}/.test(text)) hits.push(`${rel}: 16+ digit run (possible App/Developer ID)`);
  }
  assert.deepEqual(hits, [], 'personal data found in tracked files');
});

test('developer.json is gitignored and untracked; the example is tracked and clean', () => {
  const ignored = execFileSync(
    'git', ['check-ignore', '-v', 'entry/src/main/resources/rawfile/developer.json'],
    { cwd: ROOT, encoding: 'utf8' });
  assert.match(ignored, /developer\.json/);
  const tracked = execFileSync(
    'git', ['ls-files', 'entry/src/main/resources/rawfile/developer.json'],
    { cwd: ROOT, encoding: 'utf8' });
  assert.equal(tracked.trim(), '');
  const exampleRel = 'entry/src/main/resources/rawfile/developer.json.example';
  const example = fs.readFileSync(path.join(ROOT, exampleRel), 'utf8');
  const cfg = JSON.parse(example);
  assert.equal(typeof cfg.developerName, 'string');
  if (DEV_NAME !== null) {
    assert.ok(!example.includes(DEV_NAME), 'example must not contain the real name');
  }
  // The local config itself must exist on this machine for local builds.
  const local = path.join(ROOT, 'entry/src/main/resources/rawfile/developer.json');
  assert.ok(fs.existsSync(local), 'local developer.json missing on this machine');
  const localCfg = JSON.parse(fs.readFileSync(local, 'utf8'));
  assert.equal(typeof localCfg.developerName, 'string');
});
