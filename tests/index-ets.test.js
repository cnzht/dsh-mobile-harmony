'use strict';
/**
 * Index.ets — the ArkTS page (standalone variant). There is no DevEco /
 * Harmony SDK on this machine, so the page is tested by (a) extracting the
 * one pure function (toTitleList) from the real source, transpiling its
 * ArkTS type annotations away, and running it, and (b) statically
 * asserting the guarded behaviours in the source: the Sessions button
 * label follows drawerOpen (the sessionsOpen bug fixed in this change),
 * and the privacy consent dialog remembers its choice.
 * The online variant's connect/scan/setup flow does not exist here:
 * standalone.test.js asserts that none of it remains.
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const INDEX = fs.readFileSync(
  path.join(__dirname, '..', 'entry/src/main/ets/pages/Index.ets'),
  'utf8',
);

/**
 * Registered developer name, read from the local, gitignored
 * developer.json (see developer.json.example). Returns null on a fresh
 * clone without the file, so the name never appears in this test file in
 * any form — not as text, not as code points, not as an escape sequence.
 */
function loadDevName() {
  try {
    const cfg = JSON.parse(fs.readFileSync(
      path.join(__dirname, '..', 'entry/src/main/resources/rawfile/developer.json'), 'utf8'));
    return typeof cfg.developerName === 'string' && cfg.developerName.length > 0
      ? cfg.developerName
      : null;
  } catch {
    return null;
  }
}

/** Extract the body of a method by brace matching from its signature. */
function extractMethodBody(src, signature) {
  const start = src.indexOf(signature);
  assert.ok(start >= 0, `method not found: ${signature}`);
  const brace = src.indexOf('{', start);
  let depth = 0;
  for (let i = brace; i < src.length; i++) {
    if (src[i] === '{') depth++;
    if (src[i] === '}') {
      depth--;
      if (depth === 0) return src.slice(brace + 1, i);
    }
  }
  throw new Error(`unbalanced braces in ${signature}`);
}

/** Minimal ArkTS -> JS for toTitleList: strip its type annotations. */
function toTitleList() {
  const body = extractMethodBody(INDEX, 'private toTitleList(raw: string): string[]');
  const js = body
    .replace(/: string\[\]/g, '')
    .replace(/: Object/g, '')
    .replace(/ as Object/g, '')
    .replace(/ as string\[\]/g, '');
  const warnings = [];
  const hilog = { warn() { warnings.push('warn'); } };
  const fn = new Function('raw', 'hilog', 'TAG', js); // eslint-disable-line no-new-func
  return { fn: (raw) => fn(raw, hilog, 'DshMobile'), warnings };
}

test('toTitleList: empty string and empty array give []', () => {
  const { fn } = toTitleList();
  assert.deepEqual(fn(''), []);
  assert.deepEqual(fn('[]'), []);
});

test('toTitleList: parses a JSON array of titles', () => {
  const { fn } = toTitleList();
  assert.deepEqual(fn('["Alpha","Beta"]'), ['Alpha', 'Beta']);
});

test('toTitleList: invalid JSON gives [] instead of throwing', () => {
  const { fn, warnings } = toTitleList();
  assert.deepEqual(fn('not json at all'), []);
  assert.deepEqual(fn('{broken'), []);
  assert.ok(warnings.length >= 2, 'parse failures should be logged');
});

test('toTitleList: non-array JSON gives []', () => {
  const { fn } = toTitleList();
  assert.deepEqual(fn('{"a":1}'), []);
  assert.deepEqual(fn('"hello"'), []);
  assert.deepEqual(fn('42'), []);
  assert.deepEqual(fn('null'), []);
});

test('toTitleList: truncates to the first 30 titles', () => {
  const { fn } = toTitleList();
  const titles = Array.from({ length: 35 }, (_, i) => `S${i}`);
  const out = fn(JSON.stringify(titles));
  assert.equal(out.length, 30);
  assert.equal(out[0], 'S0');
  assert.equal(out[29], 'S29');
});

test('toTitleList: non-string items are stringified, like the UI expects', () => {
  const { fn } = toTitleList();
  assert.deepEqual(fn('[1,2,null]'), ['1', '2', 'null']);
});

test('Sessions button: label follows drawerOpen, sessionsOpen is gone', () => {
  assert.match(INDEX, /Button\(this\.drawerOpen \? 'Close' : 'Sessions'\)/);
  assert.doesNotMatch(INDEX, /sessionsOpen/);
});

test('toggleSessions / pickSession: both paths close through drawerOpen', () => {
  const toggle = extractMethodBody(INDEX, 'private toggleSessions(): void');
  assert.match(toggle, /if \(this\.drawerOpen\) \{\s*this\.drawerOpen = false;/);
  assert.match(toggle, /this\.drawerOpen = true;/);
  assert.doesNotMatch(toggle, /sessionsOpen/);
  const pick = extractMethodBody(INDEX, 'private pickSession(i: number): void');
  assert.match(pick, /this\.drawerOpen = false;/);
});

test('About: developer name comes from local developer.json, never hardcoded', () => {
  // The registered name lives only in the gitignored local config
  // (developer.json, see developer.json.example); the page must never
  // carry it as a literal or as an escape sequence.
  assert.match(INDEX, /@State developerName: string = '';/);
  assert.match(INDEX, /developer\.json/);
  const read = extractMethodBody(INDEX, 'private readAssets(): void');
  // A separate try/catch reads the config, so a missing file cannot break
  // the early/inject/css assets loaded by the same method.
  assert.match(read, /getRawFileContentSync\('developer\.json'\)/);
  assert.match(read, /JSON\.parse\(raw\) as DeveloperConfig/);
  assert.match(read, /cfg\.developerName/);
  // The About card shows the configured name, or a bare label when absent.
  const about = extractMethodBody(INDEX, 'aboutCard() {');
  assert.match(about, /Text\(this\.developerName\.length > 0 \? 'Developer: ' \+ this\.developerName : 'Developer'\)/);
  assert.match(about, /Text\('About Harness Mobile'\)/);
  // Neither the literal name nor the ArkTS escape form may appear in the
  // page. The name comes from the local developer.json (see loadDevName);
  // without that file the check is skipped.
  const name = loadDevName();
  if (name !== null) {
    assert.ok(!INDEX.includes(name), 'hardcoded developer name in Index.ets');
    const escaped = [...name]
      .map((c) => '\\u' + c.codePointAt(0).toString(16).padStart(4, '0'))
      .join('');
    assert.ok(!INDEX.includes(escaped), 'escaped developer name in Index.ets');
  }
  assert.doesNotMatch(INDEX, /沛沛0518/);
  assert.doesNotMatch(INDEX, /experimental/i);
  assert.doesNotMatch(INDEX, /Use at your own risk/);
  assert.doesNotMatch(INDEX, /deepseek/i);
});

test('privacy consent: first-launch dialog exists and the choice is remembered', () => {
  // State + dialog builder exist.
  assert.match(INDEX, /@State privacyOpen: boolean = false;/);
  assert.match(INDEX, /@State privacyDeclined: boolean = false;/);
  assert.match(INDEX, /privacyCard\(\)/);
  // First launch opens it unless preferences already record consent.
  const load = extractMethodBody(INDEX, 'private loadPrefs(): void');
  assert.match(load, /p\.getSync\('privacyAccepted', false\)/);
  assert.match(load, /if \(!accepted\) \{\s*this\.privacyOpen = true;/);
  // 同意 persists the flag and closes; 不同意 shows the hint; 暂不使用 closes
  // but leaves the setup-view banner (privacyDeclined stays true).
  const accept = extractMethodBody(INDEX, 'private acceptPrivacy(): void');
  assert.match(accept, /this\.privacyOpen = false;/);
  assert.match(accept, /this\.prefs\.putSync\('privacyAccepted', true\);/);
  const decline = extractMethodBody(INDEX, 'private declinePrivacy(): void');
  assert.match(decline, /this\.privacyDeclined = true;/);
  const later = extractMethodBody(INDEX, 'private openPrivacyLater(): void');
  assert.match(later, /this\.privacyOpen = false;/);
  // The dialog offers the policy / agreement links and all three choices.
  const card = extractMethodBody(INDEX, 'privacyCard() {');
  assert.match(card, /隐私政策/);
  assert.match(card, /用户协议/);
  assert.match(card, /Button\('同意'\)/);
  assert.match(card, /Button\('不同意'\)/);
  assert.match(card, /Button\('暂不使用'\)/);
  assert.match(card, /需要同意隐私政策才能使用本应用/);
  // The dialog is rendered at the page root (same overlay pattern as About)
  // and has no tap-outside dismiss, so consent cannot be bypassed by accident.
  const build = extractMethodBody(INDEX, 'build() {');
  assert.match(build, /if \(this\.privacyOpen\) \{\s*Column\(\) \{\s*this\.privacyCard\(\)/);
  // Standalone: the policy / agreement links open bundled local files,
  // never an external URL.
  assert.match(INDEX, /\$rawfile\('privacy\.html'\)/);
  assert.match(INDEX, /\$rawfile\('eula\.html'\)/);
  assert.doesNotMatch(INDEX, /github\.io/);
  const openPrivacy = extractMethodBody(INDEX, 'private openPrivacyPage(): void');
  assert.match(openPrivacy, /this\.pageSrc = \$rawfile\('privacy\.html'\);/);
  assert.match(openPrivacy, /this\.onPolicyPage = true;/);
  const openEula = extractMethodBody(INDEX, 'private openEulaPage(): void');
  assert.match(openEula, /this\.pageSrc = \$rawfile\('eula\.html'\);/);
  const back = extractMethodBody(INDEX, 'private backToDemo(): void');
  assert.match(back, /this\.pageSrc = \$rawfile\('local-demo\.html'\);/);
  assert.match(back, /this\.onPolicyPage = false;/);
});

test('AI content label: top bar badge and About explanation', () => {
  // The badge sits in the chat top bar, next to the Sessions button.
  assert.match(INDEX, /Text\('AI 生成内容'\)/);
  assert.match(INDEX, /backgroundColor\('#FFF4E0'\)/);
  // About states the demo page is static sample text, not live generation.
  const about = extractMethodBody(INDEX, 'aboutCard() {');
  assert.match(about, /演示页内容为本地静态示例，仅作功能演示；本应用不提供 AI 生成服务，也不连接任何服务器/);
});
