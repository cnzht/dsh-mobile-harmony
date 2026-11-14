'use strict';
/**
 * Standalone variant regression tests.
 *
 * The standalone branch is the LAN-only build: no public-internet access.
 * The home screen is a static demo page bundled in rawfile, and the privacy
 * policy / user agreement are bundled local files. Connecting to a server
 * is still possible — manual address entry and QR scan are restored from
 * the online variant — but every address is gated by isLanUrl in
 * Index.ets: only 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.1
 * and localhost may connect. These tests pin that down so a later merge
 * from main cannot silently drop the gate (or reintroduce a public URL).
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

test('standalone: WebView defaults to the bundled demo page', () => {
  assert.match(INDEX, /@State pageSrc: Resource = \$rawfile\('local-demo\.html'\);/);
  // The demo view renders the bundled page; the connected view renders the
  // LAN server URL only after connect() has passed the LAN gate.
  assert.match(INDEX, /Web\(\{ src: this\.pageSrc, controller: this\.controller \}\)/);
  assert.match(INDEX, /Web\(\{ src: this\.url, controller: this\.controller \}\)/);
  // Routing: no saved server and no setup request means the demo page.
  assert.match(INDEX, /else \{\s*this\.demoView\(\)/);
  assert.doesNotMatch(INDEX, /github\.io/);
  // No hardcoded remote host anywhere in the page.
  assert.doesNotMatch(INDEX, /https?:\/\/\d+\.\d+\.\d+\.\d+/);
  assert.doesNotMatch(INDEX, /trycloudflare\.com/);
});

test('standalone: setup offers both "local demo" and "connect to LAN server"', () => {
  assert.match(INDEX, /setupView\(\) \{/);
  assert.match(INDEX, /Button\('Connect'\)/);
  assert.match(INDEX, /Button\('Scan QR code'\)/);
  assert.match(INDEX, /Button\('使用本地演示'\)/);
  assert.match(INDEX, /仅支持局域网地址/);
  // The demo top bar also leads back to setup ("连接").
  assert.match(INDEX, /Button\('连接'\)/);
});

test('standalone: connect() gates every address on isLanUrl', () => {
  const start = INDEX.indexOf('private connect(): void {');
  assert.ok(start >= 0, 'connect() not found');
  const body = INDEX.slice(start, INDEX.indexOf('\n  private scan(): void {', start));
  // A bare host:port is normalised, then gated.
  assert.match(body, /if \(target\.indexOf\(':\/\/'\) < 0\) \{\s*target = 'http:\/\/' \+ target;/);
  assert.match(body, /if \(!isLanUrl\(target\)\) \{/);
  assert.match(body, /仅支持局域网地址/);
  assert.match(body, /this\.url = target;/);
  assert.match(body, /this\.showSetup = false;/);
  // The accepted address is remembered for the next launch.
  assert.match(body, /this\.prefs\.putSync\('serverUrl', target\);/);
});

test('standalone: scan() routes the scanned URL through the same gate', () => {
  assert.match(INDEX, /scanBarcode\.startScanForResult/);
  const start = INDEX.indexOf('private scan(): void {');
  assert.ok(start >= 0, 'scan() not found');
  const body = INDEX.slice(start, INDEX.indexOf('\n  /**', start));
  assert.match(body, /this\.draft = value;/);
  assert.match(body, /this\.connect\(\);/);
  // No direct assignment of a scanned URL to this.url anywhere.
  assert.doesNotMatch(body, /this\.url = value/);
});

test('standalone: a saved server auto-connects only if it is still a LAN address', () => {
  const start = INDEX.indexOf('private loadPrefs(): void {');
  assert.ok(start >= 0, 'loadPrefs() not found');
  const body = INDEX.slice(start, INDEX.indexOf('\n  private acceptPrivacy(): void {', start));
  assert.match(body, /const saved = p\.getSync\('serverUrl', ''\) as string;/);
  assert.match(body, /if \(isLanUrl\(saved\)\) \{\s*this\.url = saved;/);
  assert.match(body, /已保存的服务器地址不是局域网地址/);
});

test('standalone: module.json5 requests only INTERNET (LAN sockets need it)', () => {
  const src = read('entry/src/main/module.json5');
  const perms = [...src.matchAll(/"name"\s*:\s*"([^"]+)"/g)].map((m) => m[1])
    .filter((name) => name.startsWith('ohos.permission.'));
  assert.deepEqual(perms, ['ohos.permission.INTERNET']);
});

test('standalone: demo page is honest local sample content', () => {
  // Labels that must be present.
  assert.match(DEMO, /本地演示/);
  assert.match(DEMO, /<span class="ai-badge">AI 生成内容<\/span>/);
  assert.match(DEMO, /只连接局域网内的地址/);
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
  // The bundled policy describes the LAN-only variant, not the offline one.
  assert.match(POLICY, /仅连接局域网/);
  assert.match(POLICY, /不连接公共互联网/);
  assert.match(POLICY, /ohos\.permission\.INTERNET/);
  assert.doesNotMatch(POLICY, /完全不联网/);
  assert.doesNotMatch(POLICY, /不申请任何权限/);
  assert.match(EULA, /不连接公共互联网/);
  assert.match(EULA, /本地单机版/);
  assert.match(EULA, /局域网/);
  assert.doesNotMatch(EULA, /不连接任何服务器/);
});

test('standalone: version is 1.0.3 / 1000003 everywhere it is declared', () => {
  const app = read('AppScope/app.json5');
  assert.match(app, /"versionName"\s*:\s*"1\.0\.3"/);
  assert.match(app, /"versionCode"\s*:\s*1000003/);
  const pkg = read('entry/oh-package.json5');
  assert.match(pkg, /"version"\s*:\s*"1\.0\.3"/);
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
