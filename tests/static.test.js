'use strict';
/**
 * Static checks: the shipped JS parses, the CSS is balanced, the app
 * declares only the INTERNET permission under its real bundle name,
 * and no file in the repo carries a hardcoded token / password /
 * private key or signing material.
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');

function read(rel) {
  return fs.readFileSync(path.join(ROOT, rel), 'utf8');
}

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === '.git' || entry.name === 'node_modules') continue;
      walk(full, out);
    } else out.push(full);
  }
  return out;
}

test('both injected JS files pass node --check', () => {
  for (const rel of [
    'entry/src/main/resources/rawfile/early-polyfill.js',
    'entry/src/main/resources/rawfile/inject.js',
  ]) {
    execFileSync(process.execPath, ['--check', path.join(ROOT, rel)], { stdio: 'pipe' });
  }
});

test('mobile.css has balanced braces (comments stripped first)', () => {
  const css = read('entry/src/main/resources/rawfile/mobile.css');
  const noComments = css.replace(/\/\*[\s\S]*?\*\//g, '');
  const open = (noComments.match(/{/g) || []).length;
  const close = (noComments.match(/}/g) || []).length;
  assert.equal(open, close, `unbalanced braces: ${open} open vs ${close} close`);
  assert.ok(open > 50, 'expected a substantial stylesheet');
});

test('module.json5 requests only INTERNET (standalone: LAN-only, sockets need it)', () => {
  const src = read('entry/src/main/module.json5');
  const perms = [...src.matchAll(/"name"\s*:\s*"([^"]+)"/g)].map((m) => m[1])
    .filter((name) => name.startsWith('ohos.permission.'));
  assert.deepEqual(perms, ['ohos.permission.INTERNET']);
});

test('bundle name is cn.cnzht.dshmobile and version is 1.0.2 / 1000002', () => {
  const src = read('AppScope/app.json5');
  assert.match(src, /"bundleName"\s*:\s*"cn\.cnzht\.dshmobile"/);
  assert.match(src, /"versionName"\s*:\s*"1\.0\.2"/);
  assert.match(src, /"versionCode"\s*:\s*1000002/);
});

test('display name is Harness Mobile in the app and ability labels', () => {
  for (const rel of [
    'AppScope/resources/base/element/string.json',
    'entry/src/main/resources/base/element/string.json',
  ]) {
    const src = read(rel);
    assert.match(src, /"value"\s*:\s*"Harness Mobile"/);
    assert.doesNotMatch(src, /DSH Mobile/);
  }
  // The About title in the page must match too, and the home screen is the
  // bundled demo page in this variant, so its heading carries the name.
  const index = read('entry/src/main/ets/pages/Index.ets');
  assert.match(index, /Text\('About Harness Mobile'\)/);
  const demo = read('entry/src/main/resources/rawfile/local-demo.html');
  assert.match(demo, /<h1>Harness Mobile<\/h1>/);
});

/**
 * AGC review remediation: no brand/trademark residue in anything the user
 * (or the reviewer) can see — the page, the labels, the privacy policy,
 * the user agreement, the submission docs, or the README.
 * Deliberately NOT scanned here: NOTICE.md (keeps the factual MIT upstream
 * attribution link, which the license requires), CHANGELOG.md and
 * docs/RESUBMISSION-CHECKLIST.md (internal records that must name the
 * rejected terms to describe what was removed), and tests/ itself (the
 * assertions below spell the forbidden strings out).
 */
test('no DeepSeek / DSH Mobile / old author / experimental / 鸿蒙 residue in user-visible files', () => {
  const rels = [
    'entry/src/main/ets/pages/Index.ets',
    'AppScope/resources/base/element/string.json',
    'entry/src/main/resources/base/element/string.json',
    'entry/src/main/resources/rawfile/mobile.css',
    'docs/PRIVACY.md',
    'docs/EULA.md',
    'docs/privacy.html',
    'docs/eula.html',
    'docs/index.html',
    'docs/AGC-FORM.md',
    'docs/SUBMISSION-NOTES.md',
    'docs/DEMO-SCRIPT.md',
    'docs/APPGALLERY.md',
    'docs/RELEASE-SIGNING.md',
    'README.md',
    'DISCLAIMER.md',
  ];
  const patterns = [
    /deepseek/i,
    /DSH Mobile/i,
    /沛沛0518/,
    /experimental/i,
    /鸿蒙/,
  ];
  const hits = [];
  for (const rel of rels) {
    const text = read(rel);
    for (const re of patterns) {
      const m = re.exec(text);
      if (m) hits.push(`${rel}: ${re} matched ${JSON.stringify(m[0])}`);
    }
  }
  assert.deepEqual(hits, [], 'brand/trademark residue found');
});

test('NOTICE.md still keeps the factual upstream MIT attribution link', () => {
  const src = read('NOTICE.md');
  assert.match(src, /deepseek-harness-mobile/);
  assert.match(src, /MIT License/);
});

test('no hardcoded token / password / API key in code and scripts', () => {
  const roots = [
    'entry/src/main/ets',
    'entry/src/main/resources/rawfile',
    'scripts',
  ];
  const files = roots.flatMap((rel) => walk(path.join(ROOT, rel)));
  assert.ok(files.length > 0);
  const patterns = [
    /-----BEGIN (RSA |EC )?PRIVATE KEY-----/,
    /(token|password|passwd|api[_-]?key|client[_-]?secret)\s*[:=]\s*['"][A-Za-z0-9\-_+/=]{16,}['"]/i,
    /(token|password)\s*:\s*['"][A-Za-z0-9\-_+/=]{16,}['"]/i,
  ];
  const hits = [];
  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    for (const re of patterns) {
      const m = re.exec(text);
      if (m) hits.push(`${path.relative(ROOT, file)}: ${m[0].slice(0, 80)}`);
    }
  }
  assert.deepEqual(hits, [], 'hardcoded secret found');
});

test('no signing material or token files are checked into the repo', () => {
  const files = walk(ROOT);
  const bad = files.filter((f) => /\.(p12|pfx|cer|crt|p7b|key|pem)$/i.test(f)
    || /(^|\/)(token|secret)(s)?\.(txt|json)$/i.test(f));
  assert.deepEqual(bad.map((f) => path.relative(ROOT, f)), []);
});

test('inject.js and early-polyfill.js do not embed a dsh server URL', () => {
  for (const rel of [
    'entry/src/main/resources/rawfile/early-polyfill.js',
    'entry/src/main/resources/rawfile/inject.js',
  ]) {
    const src = read(rel);
    assert.doesNotMatch(src, /https?:\/\/\d+\.\d+\.\d+\.\d+:\d+/);
    assert.doesNotMatch(src, /trycloudflare\.com/);
  }
});
