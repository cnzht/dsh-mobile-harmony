'use strict';
/**
 * Index.ets — the ArkTS page. There is no DevEco / Harmony SDK on this
 * machine, so the page is tested by (a) extracting the one pure function
 * (toTitleList) from the real source, transpiling its ArkTS type
 * annotations away, and running it, and (b) statically asserting the
 * guarded behaviours in the source: connect() rejects an empty address,
 * only a main-frame 401/403 returns to setup, and the Sessions button
 * label follows drawerOpen (the sessionsOpen bug fixed in this change).
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const INDEX = fs.readFileSync(
  path.join(__dirname, '..', 'entry/src/main/ets/pages/Index.ets'),
  'utf8',
);

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

test('connect: empty address sets the error and does not navigate', () => {
  const body = extractMethodBody(INDEX, 'private connect(): void');
  assert.match(body, /const target = this\.draft\.trim\(\);/);
  assert.match(body, /if \(target\.length === 0\) \{\s*this\.error = 'Please enter the dsh web URL';\s*return;/);
  // The navigation path only runs after that guard.
  assert.ok(body.indexOf("this.url = target;") > body.indexOf('Please enter the dsh web URL'));
  assert.match(body, /this\.loading = true;/);
});

test('http errors: only a main-frame 401/403 returns to setup', () => {
  const handler = extractMethodBody(INDEX, '.onHttpErrorReceive((e: OnHttpErrorReceiveEvent) => {');
  assert.match(handler, /code === 401 \|\| code === 403/);
  assert.match(handler, /e\.request\.isMainFrame\(\)/);
  // handleHttpError is called from exactly one place (this handler).
  const calls = [...INDEX.matchAll(/this\.handleHttpError\(/g)].length;
  assert.equal(calls, 1);
  // handleHttpError itself refills the draft and clears the URL.
  const body = extractMethodBody(INDEX, 'private handleHttpError(url: string): void');
  assert.match(body, /this\.draft = this\.url;/);
  assert.match(body, /this\.url = '';?/);
  assert.match(body, /this\.lastInjectedUrl = '';?/);
});

test('Sessions button: label follows drawerOpen, sessionsOpen is gone', () => {
  assert.match(INDEX, /Button\(this\.drawerOpen \? 'Close' : 'Sessions'\)/);
  assert.doesNotMatch(INDEX, /sessionsOpen/);
});

test('backToSetup: clears the drawer and the session list, not just the URL', () => {
  const body = extractMethodBody(INDEX, 'private backToSetup(): void');
  assert.match(body, /this\.drawerOpen = false;/);
  assert.match(body, /this\.sessionsList = \[\];/);
  assert.match(body, /this\.url = '';?/);
  assert.match(body, /this\.lastInjectedUrl = '';?/);
});

test('toggleSessions / pickSession: both paths close through drawerOpen', () => {
  const toggle = extractMethodBody(INDEX, 'private toggleSessions(): void');
  assert.match(toggle, /if \(this\.drawerOpen\) \{\s*this\.drawerOpen = false;/);
  assert.match(toggle, /this\.drawerOpen = true;/);
  assert.doesNotMatch(toggle, /sessionsOpen/);
  const pick = extractMethodBody(INDEX, 'private pickSession(i: number): void');
  assert.match(pick, /this\.drawerOpen = false;/);
});

test('injectOnce: a repeated URL is not re-injected', () => {
  const body = extractMethodBody(INDEX, 'private injectOnce(url: string): void');
  assert.match(body, /if \(url\.length > 0 && url === this\.lastInjectedUrl\) \{\s*return;/);
  assert.match(body, /window\.__dshMobileAttached/);
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
  // Neither the literal name (built from code points so this test file itself
  // stays clean) nor the ArkTS escape form may appear in the page.
  const name = String.fromCharCode(0x0000, 0x0000);
  assert.ok(!INDEX.includes(name), 'hardcoded developer name in Index.ets');
  assert.ok(!INDEX.includes('\\u0000\\u0000'), 'escaped developer name in Index.ets');
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
  // Setup view keeps a consent banner and permanent policy / agreement links.
  assert.match(INDEX, /使用前请先阅读并同意隐私政策/);
  assert.match(INDEX, /Text\('隐私政策'\)\.fontSize\(12\)/);
  assert.match(INDEX, /Text\('用户协议'\)\.fontSize\(12\)/);
  // The links point at the published policy / agreement pages.
  assert.match(INDEX, /const PRIVACY_URL: string = 'https:\/\/cnzht\.github\.io\/dsh-mobile-harmony\/privacy\.html';/);
  assert.match(INDEX, /const EULA_URL: string = 'https:\/\/cnzht\.github\.io\/dsh-mobile-harmony\/eula\.html';/);
});

test('AI content label: top bar badge and About explanation', () => {
  // The badge sits in the chat top bar, next to the Sessions button.
  assert.match(INDEX, /Text\('AI 生成内容'\)/);
  assert.match(INDEX, /backgroundColor\('#FFF4E0'\)/);
  // About states the content comes from the user's own deployed service.
  const about = extractMethodBody(INDEX, 'aboutCard() {');
  assert.match(about, /会话内容由你自部署的服务生成，本应用仅负责展示，不提供 AI 生成服务/);
});
