'use strict';
/**
 * Standalone variant regression tests.
 *
 * The standalone branch is the offline-only build: no server, no account,
 * no permissions, no network requests at all. The home screen is a static
 * demo page bundled in rawfile, and the privacy policy / user agreement
 * are bundled local files. These tests pin that down so a later merge from
 * main cannot silently reintroduce the online connect flow.
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');

function read(rel) {
  return fs.readFileSync(path.join(ROOT, rel), 'utf8');
}

const INDEX = read('entry/src/main/ets/pages/Index.ets');
const DEMO = read('entry/src/main/resources/rawfile/local-demo.html');
const POLICY = read('entry/src/main/resources/rawfile/privacy.html');
const EULA = read('entry/src/main/resources/rawfile/eula.html');

test('standalone: WebView loads only the bundled demo page, never a remote URL', () => {
  assert.match(INDEX, /@State pageSrc: string = \$rawfile\('local-demo\.html'\);/);
  assert.match(INDEX, /Web\(\{ src: this\.pageSrc, controller: this\.controller \}\)/);
  assert.doesNotMatch(INDEX, /https?:\/\//);
  assert.doesNotMatch(INDEX, /github\.io/);
  assert.doesNotMatch(INDEX, /Web\(\{ src: this\.url/);
});

test('standalone: no setup / connect / scan / remote-injection leftovers', () => {
  assert.doesNotMatch(INDEX, /private connect\(\)|scanBarcode|setupView|backToSetup/);
  assert.doesNotMatch(INDEX, /handleHttpError|onHttpErrorReceive|injectOnce|styleScript/);
  assert.doesNotMatch(INDEX, /openLink|openGithub|serverUrl/);
  assert.doesNotMatch(INDEX, /Scan QR/);
  assert.doesNotMatch(INDEX, /\bdraft\b/);
  assert.doesNotMatch(INDEX, /token/i);
  assert.doesNotMatch(INDEX, /early-polyfill|inject\.js|mobile\.css/);
});

test('standalone: module.json5 requests no permissions at all', () => {
  const src = read('entry/src/main/module.json5');
  assert.doesNotMatch(src, /requestPermissions/);
  assert.doesNotMatch(src, /ohos\.permission\./);
});

test('standalone: demo page is honest local sample content', () => {
  // Labels that must be present.
  assert.match(DEMO, /本地演示/);
  assert.match(DEMO, /<span class="ai-badge">AI 生成内容<\/span>/);
  assert.match(DEMO, /不连接任何服务器/);
  assert.match(DEMO, /静态/);
  assert.match(DEMO, /不是实时生成/);
  // A sample workspace: session list + a sample conversation.
  assert.match(DEMO, /示例会话：入门介绍/);
  assert.match(DEMO, /示例会话：写作提纲/);
  assert.match(DEMO, /示例会话：代码评审/);
  assert.match(DEMO, /id="sessionList"/);
  assert.match(DEMO, /id="messages"/);
  // The bridge the native Sessions drawer uses (same convention as online).
  assert.match(DEMO, /window\.__dshListSessions = function/);
  assert.match(DEMO, /window\.__dshClickSession = function/);
  // Fully self-contained: no network, no external resources, no secrets.
  assert.doesNotMatch(DEMO, /https?:\/\//);
  assert.doesNotMatch(DEMO, /<link\b/);
  assert.doesNotMatch(DEMO, /<script\s+src=/);
  assert.doesNotMatch(DEMO, /token/i);
  assert.doesNotMatch(DEMO, /deepseek/i);
  assert.doesNotMatch(DEMO, /DSH Mobile/i);
  assert.doesNotMatch(DEMO, /鸿蒙/);
});

test('standalone: demo page inline script parses', () => {
  const m = DEMO.match(/<script>([\s\S]*?)<\/script>/);
  assert.ok(m, 'expected one inline <script> block');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-demo-'));
  const file = path.join(dir, 'demo-inline.js');
  try {
    fs.writeFileSync(file, m[1]);
    execFileSync(process.execPath, ['--check', file], { stdio: 'pipe' });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('standalone: privacy policy and agreement are bundled local files', () => {
  assert.match(INDEX, /\$rawfile\('privacy\.html'\)/);
  assert.match(INDEX, /\$rawfile\('eula\.html'\)/);
  for (const [name, text] of [['privacy.html', POLICY], ['eula.html', EULA]]) {
    assert.doesNotMatch(text, /href="https?:\/\//, `${name}: external link`);
    assert.doesNotMatch(text, /href='https?:\/\//, `${name}: external link`);
    assert.doesNotMatch(text, /deepseek/i, `${name}: brand residue`);
    assert.doesNotMatch(text, /DSH Mobile/i, `${name}: brand residue`);
    assert.doesNotMatch(text, /鸿蒙/, `${name}: brand residue`);
  }
  // The bundled policy describes the offline variant, not the online one.
  assert.match(POLICY, /完全不联网/);
  assert.match(POLICY, /不申请任何权限/);
  assert.doesNotMatch(POLICY, /ohos\.permission\.INTERNET/);
  assert.doesNotMatch(POLICY, /扫码/);
  assert.match(EULA, /不连接任何服务器/);
  assert.match(EULA, /本地单机演示版/);
  assert.doesNotMatch(EULA, /ohos\.permission\.INTERNET/);
});

test('standalone: version is 1.0.2 / 1000002 everywhere it is declared', () => {
  const app = read('AppScope/app.json5');
  assert.match(app, /"versionName"\s*:\s*"1\.0\.2"/);
  assert.match(app, /"versionCode"\s*:\s*1000002/);
  const pkg = read('entry/oh-package.json5');
  assert.match(pkg, /"version"\s*:\s*"1\.0\.2"/);
});

test('standalone: native drawer, About and privacy dialog are kept', () => {
  assert.match(INDEX, /sessionsDrawer\(\) \{/);
  assert.match(INDEX, /aboutCard\(\) \{/);
  assert.match(INDEX, /privacyCard\(\) \{/);
  assert.match(INDEX, /private toggleSessions\(\): void/);
  assert.match(INDEX, /private pickSession\(i: number\): void/);
  assert.match(INDEX, /p\.getSync\('privacyAccepted', false\)/);
  // The developer-name mechanism is unchanged from the online variant.
  assert.match(INDEX, /getRawFileContentSync\('developer\.json'\)/);
  assert.match(INDEX, /Text\(this\.developerName\.length > 0 \? 'Developer: ' \+ this\.developerName : 'Developer'\)/);
  // About's repo line is plain text: no link opening anywhere in the page.
  assert.match(INDEX, /Text\('Repo: github\.com\/cnzht\/dsh-mobile-harmony'\)/);
  assert.doesNotMatch(INDEX, /openLink|openGithub/);
});
