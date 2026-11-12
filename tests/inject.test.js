'use strict';
/**
 * inject.js — exercised in a vm context against the fake DOM in
 * tests/support/fake-dom.js (no jsdom, no network, no DevEco).
 * inject.js runs its initial pass at load and then reacts through a
 * MutationObserver callback (300 ms debounce) and a 2 s self-check
 * interval; both are driven here by the fake clock / observer registry.
 * The AbortSignal fallback in inject.js is covered too: the context is
 * created with AbortSignal.any/timeout removed first.
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  createContext, loadScript, FakeMutationObserver, REPO_ROOT,
} = require('./support/fake-dom');

const INJECT_REL = 'entry/src/main/resources/rawfile/inject.js';
const WANT_VIEWPORT = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover, interactive-widget=resizes-content';

function loadInject(env) {
  loadScript(env.ctx, INJECT_REL);
  return env;
}

function freshEnv(innerWidth = 390) {
  const env = createContext({ deleteAbortSignalOnly: true, innerWidth });
  FakeMutationObserver.instances.length = 0;
  return env;
}

/** Run the observer's debounced pass (mutation -> 300 ms). */
function flushObserver(env) {
  FakeMutationObserver.fireAll();
  env.clock.advance(300);
}

/** Advance past inject.js's two startup enforce windows (1.2 s + 1.5 s,
 *  3.5 s + 2.5 s): while they run, an already-expanded sidebar is
 *  force-closed by design, so an "open sidebar" fixture built before
 *  they expire would be closed before the test can observe it. */
function pastStartupEnforce(env) {
  env.clock.advance(6100);
}

function el(env, tag, cls, text) {
  const e = env.document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

/** Sidebar fixture: a sidebar column with a toggle that flips the
 *  collapsed child, mimicking dsh's real toggle behaviour. */
function buildSidebar(env, { open = false } = {}) {
  const col = el(env, 'div', 'abc_sidebarCol');
  const collapsed = el(env, 'div', 'xyz_collapsed');
  if (!open) col.appendChild(collapsed);
  const toggle = el(env, 'button', 'abc_toggle', 'toggle');
  toggle.addEventListener('click', () => {
    if (collapsed.parentElement) collapsed.remove();
    else col.appendChild(collapsed);
  });
  col.appendChild(toggle);
  env.document.body.appendChild(col);
  return { col, collapsed, toggle };
}

test('inject.js is idempotent: second load changes nothing', () => {
  const env = freshEnv();
  loadInject(env);
  const pendingBefore = env.clock.pending();
  const railbtnsBefore = env.document.querySelectorAll('#dsh-mobile-railbtn').length;
  loadScript(env.ctx, INJECT_REL);
  assert.equal(env.window.__dshMobileInjected, true);
  assert.equal(env.document.querySelectorAll('#dsh-mobile-railbtn').length, railbtnsBefore);
  assert.equal(env.clock.pending(), pendingBefore, 'second load must not add timers');
});

test('inject.js supplies AbortSignal.any/timeout when the WebView lacks them', async () => {
  const env = freshEnv();
  loadInject(env);
  assert.equal(typeof env.ctx.AbortSignal.any, 'function');
  assert.equal(typeof env.ctx.AbortSignal.timeout, 'function');
  const a = new env.ctx.AbortController();
  const combined = env.ctx.AbortSignal.any([a.signal]);
  a.abort();
  assert.equal(combined.aborted, true);
  const timed = env.ctx.AbortSignal.timeout(10);
  env.clock.advance(10);
  assert.equal(timed.aborted, true);
  assert.equal(timed.reason.name, 'TimeoutError');
});

test('AbortSignal polyfill in inject.js matches early-polyfill.js textually', () => {
  const read = (rel) => fs.readFileSync(path.join(REPO_ROOT, rel), 'utf8');
  const early = read('entry/src/main/resources/rawfile/early-polyfill.js');
  const inject = read('entry/src/main/resources/rawfile/inject.js');
  // Slice from the any() assignment through the end of the timeout()
  // assignment (the `};` closing its `if` guard). The two blocks must
  // stay in sync: early-polyfill runs onPageBegin, inject.js onPageEnd.
  function abortBlock(src) {
    const start = src.indexOf('AbortSignal.any = function');
    const endMarker = '    };\n  }';
    const end = src.indexOf(endMarker, src.indexOf('AbortSignal.timeout = function'));
    assert.ok(start >= 0 && end > start, 'abort polyfill block not found');
    return src.slice(start, end + endMarker.length);
  }
  assert.equal(abortBlock(inject), abortBlock(early));
});

test('ensureViewport: creates the meta tag when it is missing', () => {
  const env = freshEnv();
  assert.equal(env.document.querySelector('meta[name=viewport]'), null);
  loadInject(env);
  const meta = env.document.querySelector('meta[name=viewport]');
  assert.ok(meta, 'meta viewport should be created');
  assert.equal(meta.getAttribute('content'), WANT_VIEWPORT);
  assert.equal(meta.parentElement, env.document.head);
});

test('ensureViewport: fixes a wrong viewport, leaves a correct one alone', () => {
  const env = freshEnv();
  const meta = el(env, 'meta');
  meta.setAttribute('name', 'viewport');
  meta.setAttribute('content', 'width=1024');
  env.document.head.appendChild(meta);
  loadInject(env);
  assert.equal(meta.getAttribute('content'), WANT_VIEWPORT);
  loadInject(env); // idempotent guard: second load is a no-op, meta untouched
  assert.equal(env.document.querySelector('meta[name=viewport]'), meta);
});

test('updateDetailsCol: substantial content opens the panel (mobile)', () => {
  const env = freshEnv();
  loadInject(env);
  const col = el(env, 'div', 'abc_rightbarCol', 'x'.repeat(200));
  col.setAttribute('data-rightbar-col', '');
  env.document.body.appendChild(col);
  flushObserver(env);
  assert.equal(col.classList.contains('dsh-mobile-open'), true);
  assert.equal(col.classList.contains('dsh-mobile-empty'), false);
});

test('updateDetailsCol: placeholder / short text is emptied, never opened', () => {
  const env = freshEnv();
  loadInject(env);
  const placeholder = el(env, 'div', 'abc_rightbarCol', 'Click a tool row to view details here');
  const short = el(env, 'div', 'abc_rightbarCol', 'hi');
  env.document.body.appendChild(placeholder);
  env.document.body.appendChild(short);
  flushObserver(env);
  for (const col of [placeholder, short]) {
    assert.equal(col.classList.contains('dsh-mobile-empty'), true, col.textContent);
    assert.equal(col.classList.contains('dsh-mobile-open'), false);
  }
});

test('updateDetailsCol: upstream-collapsed column stays hidden even with content', () => {
  const env = freshEnv();
  loadInject(env);
  const wrapper = el(env, 'div');
  wrapper.setAttribute('data-rightbar-collapsed', '');
  const col = el(env, 'div', 'abc_rightbarCol', 'y'.repeat(200));
  wrapper.appendChild(col);
  env.document.body.appendChild(wrapper);
  flushObserver(env);
  assert.equal(col.classList.contains('dsh-mobile-open'), false);
  assert.equal(col.classList.contains('dsh-mobile-empty'), true);
});

test('updateDetailsCol: desktop width never opens or empties the panel', () => {
  const env = freshEnv(900);
  loadInject(env);
  const col = el(env, 'div', 'abc_rightbarCol', 'z'.repeat(200));
  env.document.body.appendChild(col);
  flushObserver(env);
  assert.equal(col.classList.contains('dsh-mobile-open'), false);
  assert.equal(col.classList.contains('dsh-mobile-empty'), false);
});

test('sidebar drawer: opens when the sidebar is expanded, mask + rail button appear', () => {
  const env = freshEnv();
  loadInject(env);
  pastStartupEnforce(env);
  const { col } = buildSidebar(env, { open: true });
  assert.ok(col);
  env.clock.advance(2000); // self-check interval drives updateSidebarDrawer
  assert.equal(env.document.body.classList.contains('dsh-mobile-drawer'), true);
  assert.ok(env.document.getElementById('dsh-mobile-drawer-mask'));
  assert.ok(env.document.getElementById('dsh-mobile-railbtn'));
  assert.equal(env.document.body.classList.contains('dsh-mobile-drawer-preopen'), false);
});

test('sidebar drawer: collapsed sidebar leaves the drawer class off', () => {
  const env = freshEnv();
  loadInject(env);
  buildSidebar(env, { open: false });
  env.clock.advance(2000);
  assert.equal(env.document.body.classList.contains('dsh-mobile-drawer'), false);
  assert.equal(env.document.getElementById('dsh-mobile-drawer-mask'), null);
});

test('sidebar drawer: rail button opens a collapsed sidebar', () => {
  const env = freshEnv();
  loadInject(env);
  buildSidebar(env, { open: false });
  const rail = env.document.getElementById('dsh-mobile-railbtn');
  assert.ok(rail);
  rail.click();
  env.clock.advance(700); // openSidebar retry/check delay
  assert.equal(env.document.body.classList.contains('dsh-mobile-drawer'), true);
});

test('sidebar drawer: mask click closes an open drawer', () => {
  const env = freshEnv();
  loadInject(env);
  pastStartupEnforce(env);
  buildSidebar(env, { open: true });
  env.clock.advance(2000);
  assert.equal(env.document.body.classList.contains('dsh-mobile-drawer'), true);
  const mask = env.document.getElementById('dsh-mobile-drawer-mask');
  mask.click();
  // settle (320 ms) clicks the toggle, then a further 320 ms clears the
  // closing class and re-runs updateSidebarDrawer.
  env.clock.advance(1000);
  assert.equal(env.document.body.classList.contains('dsh-mobile-drawer'), false);
  assert.equal(env.document.body.classList.contains('dsh-mobile-drawer-closing'), false);
});

test('session row click enforces the drawer closed', () => {
  const env = freshEnv();
  loadInject(env);
  pastStartupEnforce(env);
  const { col } = buildSidebar(env, { open: true });
  env.clock.advance(2000);
  assert.equal(env.document.body.classList.contains('dsh-mobile-drawer'), true);
  const row = el(env, 'div', 'abc_sessionRow', 'Session 1');
  col.appendChild(row);
  row.click();
  // enforceClosed runs closeSidebar synchronously on the click.
  assert.equal(env.document.body.classList.contains('dsh-mobile-drawer-closing'), true);
  env.clock.advance(1000);
  assert.equal(env.document.body.classList.contains('dsh-mobile-drawer'), false);
});

test('tagStatsBar: composer stats line gets tagged, plain text does not', () => {
  const env = freshEnv();
  loadInject(env);
  const stats = el(env, 'div', '', '3 turns · 2 steps | LLM test | TTFT avg 1s · 120 tok/s');
  const plain = el(env, 'div', '', 'Hello, this is an ordinary chat message.');
  env.document.body.appendChild(stats);
  env.document.body.appendChild(plain);
  flushObserver(env);
  assert.equal(stats.classList.contains('dsh-mobile-stats'), true);
  assert.equal(plain.classList.contains('dsh-mobile-stats'), false);
});

test('tagStatsBar: message timing line gets tagged; only the innermost match is tagged', () => {
  const env = freshEnv();
  loadInject(env);
  const outer = el(env, 'div', '', '04:37 · Ran for 12s · TTFT 1s · 169 tok/s');
  const inner = el(env, 'span', '', '04:37 · Ran for 12s · TTFT 1s · 169 tok/s');
  outer.appendChild(inner);
  env.document.body.appendChild(outer);
  flushObserver(env);
  assert.equal(inner.classList.contains('dsh-mobile-stats'), true);
  assert.equal(outer.classList.contains('dsh-mobile-stats'), false);
});

test('tagStatsBar: "|" separators inside a stats bar are marked', () => {
  const env = freshEnv();
  loadInject(env);
  const bar = el(env, 'div', '', '3 turns · 2 steps | LLM · 120 tok/s');
  const sep = el(env, 'span', '', '|');
  bar.appendChild(sep);
  env.document.body.appendChild(bar);
  flushObserver(env);
  assert.equal(bar.classList.contains('dsh-mobile-stats'), true);
  assert.equal(sep.classList.contains('dsh-mobile-stats-sep'), true);
});

test('clampPopovers: an off-screen popover is pulled back inside the viewport', () => {
  const env = freshEnv();
  loadInject(env);
  const pop = el(env, 'div', 'abc_menu', 'menu');
  pop._computedStyle = { position: 'absolute', display: 'block', overflowX: 'visible', whiteSpace: 'normal', fontSize: '16px' };
  pop.setRect({ left: -10, right: 90, width: 100, height: 40 });
  env.document.body.appendChild(pop);
  flushObserver(env);
  assert.equal(pop.style.left, '6px');
  assert.equal(pop.style.right, 'auto');
});

test('tooltip autohide: a tooltip is armed and hidden after 2.5 s', () => {
  const env = freshEnv();
  const tip = el(env, 'div', '', 'tip text');
  tip.setAttribute('role', 'tooltip');
  env.document.body.appendChild(tip);
  loadInject(env);
  assert.equal(tip.getAttribute('data-dsh-tip-armed'), '1');
  env.clock.advance(2500);
  assert.equal(tip.style.display, 'none');
});

test('fitComposerOverlap: spacer is sized to the composer seat height + 16', () => {
  const env = freshEnv();
  const scroll = el(env, 'div', '');
  scroll.setAttribute('data-conversation-scroll', '');
  scroll.scrollHeight = 1000;
  scroll.clientHeight = 800;
  scroll.scrollTop = 200;
  const seat = el(env, 'div', '');
  seat.setAttribute('data-composer-seat', '');
  seat.setRect({ width: 390, height: 80 });
  scroll.appendChild(seat);
  env.document.body.appendChild(scroll);
  loadInject(env);
  const spacer = env.document.getElementById('dsh-mobile-composer-spacer');
  assert.ok(spacer, 'spacer should be created at load');
  assert.equal(spacer.parentElement, scroll);
  assert.equal(spacer.style.height, '96px'); // max(48, 80 + 0 + 16)
  assert.equal(scroll.style.scrollPaddingBottom, '96px');
});

test('fitComposerOverlap: hero page clears the spacer', () => {
  const env = freshEnv();
  const scroll = el(env, 'div', '');
  scroll.setAttribute('data-conversation-scroll', '');
  scroll.scrollHeight = 1000;
  scroll.clientHeight = 800;
  const seat = el(env, 'div', '');
  seat.setAttribute('data-composer-seat', '');
  seat.setRect({ width: 390, height: 80 });
  scroll.appendChild(seat);
  env.document.body.appendChild(scroll);
  loadInject(env);
  assert.ok(env.document.getElementById('dsh-mobile-composer-spacer'));
  const hero = el(env, 'div', 'abc_composerHero', 'hero');
  seat.appendChild(hero);
  env.clock.advance(2000); // self-check interval re-runs fitComposerOverlap
  assert.equal(env.document.getElementById('dsh-mobile-composer-spacer'), null);
});

test('config intercept: "打开配置文件" goes to the native bridge, not the web handler', () => {
  const env = freshEnv();
  loadInject(env);
  let opened = 0;
  env.window.DshNative = { openConfig() { opened++; } };
  const btn = el(env, 'button', '', '打开配置文件');
  env.document.body.appendChild(btn);
  btn.click();
  assert.equal(opened, 1);
});

test('config intercept: without the native bridge the click is left alone', () => {
  const env = freshEnv();
  loadInject(env);
  const btn = el(env, 'button', '', '打开配置文件');
  env.document.body.appendChild(btn);
  btn.click(); // must not throw and must not create anything
  assert.equal(env.document.getElementById('dsh-mobile-plugin-adder'), null);
});

test('plugin adder: empty name is rejected, install flow reports back', () => {
  const env = freshEnv();
  let installed = null;
  env.window.DshNative = { installPlugin(name) { installed = name; } };
  const dlg = el(env, 'div', '');
  dlg.setAttribute('role', 'dialog');
  const section = el(env, 'div', 'abc_section');
  const heading = el(env, 'div', 'abc_heading', '插件');
  section.appendChild(heading);
  dlg.appendChild(section);
  env.document.body.appendChild(dlg);
  loadInject(env);
  const row = env.document.getElementById('dsh-mobile-plugin-adder');
  assert.ok(row, 'adder row should be injected into the plugin section');
  const input = row.querySelectorAll('input')[0];
  const button = row.querySelectorAll('button')[0];
  const status = row.querySelectorAll('div')[0];
  button.click();
  assert.equal(status.textContent, '请输入插件包名');
  assert.equal(installed, null);
  input.value = 'dsh-plugin-xxx';
  button.click();
  assert.equal(installed, 'dsh-plugin-xxx');
  assert.equal(button.disabled, true);
  env.window.__dshOnPluginInstallResult({ ok: true });
  assert.match(status.textContent, /已安装：dsh-plugin-xxx/);
  assert.equal(input.value, '');
  assert.equal(button.disabled, false);
});
