'use strict';
/**
 * Minimal fake DOM for testing inject.js / early-polyfill.js in Node.
 *
 * No jsdom, no external dependency: only Node built-ins (vm).
 * It implements the small surface inject.js actually touches:
 *  - Element: classList, attributes, children, querySelector(All),
 *    closest, contains, click, getBoundingClientRect, style, isConnected
 *  - Document: createElement, getElementById, querySelector(All),
 *    addEventListener / dispatch, head / body / documentElement
 *  - Window bits: innerWidth, getComputedStyle, MutationObserver,
 *    requestAnimationFrame, visualViewport (absent by default)
 *  - A controllable fake clock for setTimeout / setInterval / Date.now,
 *    so inject.js's 2 s self-check interval and 400 ms enforce loops
 *    stay deterministic and never keep the test process alive.
 *
 * Selector support is deliberately narrow: tag, #id, .class,
 * [attr], [attr="v"|*=v|^=v|$=v] (with optional ` i` flag),
 * descendant (space) and child (>) combinators, comma groups,
 * :scope and :not(<simple compound>). That covers every selector
 * inject.js uses; it is not a general CSS engine.
 */
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

const REPO_ROOT = path.resolve(__dirname, '..', '..');

// ---------------------------------------------------------------- clock
class FakeClock {
  constructor() {
    this.now = 0;
    this._timers = new Map();
    this._nextId = 1;
  }
  setTimeout(fn, ms = 0) {
    const id = this._nextId++;
    this._timers.set(id, { id, fn, due: this.now + Math.max(0, ms), interval: 0, active: true });
    return id;
  }
  setInterval(fn, ms) {
    const id = this._nextId++;
    this._timers.set(id, { id, fn, due: this.now + Math.max(0, ms), interval: Math.max(0, ms), active: true });
    return id;
  }
  clearTimeout(id) { const t = this._timers.get(id); if (t) t.active = false; }
  clearInterval(id) { this.clearTimeout(id); }
  pending() { return [...this._timers.values()].filter((t) => t.active).length; }
  advance(ms) {
    const target = this.now + ms;
    let guard = 0;
    for (;;) {
      let next = null;
      for (const t of this._timers.values()) {
        if (t.active && t.due <= target && (!next || t.due < next.due)) next = t;
      }
      if (!next) break;
      if (++guard > 10000) throw new Error('FakeClock.advance: too many timers (possible loop)');
      this.now = next.due;
      if (next.interval > 0) {
        next.due += next.interval;
      } else {
        next.active = false;
      }
      next.fn();
    }
    this.now = target;
  }
}

// ------------------------------------------------------- selector engine
function splitGroups(selector) {
  const out = [];
  let depth = 0;
  let cur = '';
  for (const ch of selector) {
    if (ch === '[' || ch === '(') depth++;
    if (ch === ']' || ch === ')') depth--;
    if (ch === ',' && depth === 0) { out.push(cur.trim()); cur = ''; } else cur += ch;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}

function parseAttr(text) {
  // text is the inside of [...] without brackets, e.g. class*="_x" i
  const m = text.trim().match(/^([\w-]+)\s*(?:([*^$~|]?=)\s*(?:"([^"]*)"|'([^']*)'|([^\s]+))\s*)?(i)?$/);
  if (!m) throw new Error(`unsupported attribute selector [${text}]`);
  return { name: m[1], op: m[2] || null, value: m[3] ?? m[4] ?? m[5] ?? null, ci: Boolean(m[6]) };
}

function parseCompound(src) {
  const compound = { tag: null, id: null, classes: [], attrs: [], not: null, scope: false };
  let i = 0;
  while (i < src.length) {
    const ch = src[i];
    if (ch === '*') { compound.tag = '*'; i++; continue; }
    if (/[a-zA-Z]/.test(ch)) {
      const m = /^[a-zA-Z][\w-]*/.exec(src.slice(i));
      compound.tag = m[0]; i += m[0].length; continue;
    }
    if (ch === '#') {
      const m = /^#([\w-]+)/.exec(src.slice(i));
      compound.id = m[1]; i += m[0].length; continue;
    }
    if (ch === '.') {
      const m = /^\.([\w-]+)/.exec(src.slice(i));
      compound.classes.push(m[1]); i += m[0].length; continue;
    }
    if (ch === '[') {
      let depth = 0; let j = i;
      while (j < src.length) {
        if (src[j] === '[') depth++;
        if (src[j] === ']') { depth--; if (depth === 0) break; }
        j++;
      }
      compound.attrs.push(parseAttr(src.slice(i + 1, j)));
      i = j + 1; continue;
    }
    if (src.startsWith(':scope', i)) { compound.scope = true; i += 6; continue; }
    if (src.startsWith(':not(', i)) {
      // j starts just after ':not('; depth is 1 because we are already
      // inside the opening paren, and we stop at the matching close.
      let depth = 1; let j = i + 5;
      while (j < src.length) {
        if (src[j] === '(') depth++;
        if (src[j] === ')') { depth--; if (depth === 0) break; }
        j++;
      }
      compound.not = parseCompound(src.slice(i + 5, j));
      i = j + 1; continue;
    }
    throw new Error(`unsupported selector part ${JSON.stringify(src.slice(i))} in ${JSON.stringify(src)}`);
  }
  return compound;
}

// Steps: [{compound, combinator}] where combinator links this step to the
// previous one (' ' descendant, '>' child); first step has null combinator.
function parseGroup(group) {
  const steps = [];
  let i = 0;
  let combinator = null;
  while (i < group.length) {
    while (group[i] === ' ') i++;
    if (group[i] === '>') { combinator = '>'; i++; while (group[i] === ' ') i++; }
    else if (steps.length > 0 && combinator === null) combinator = ' ';
    let j = i;
    let depth = 0;
    while (j < group.length) {
      const ch = group[j];
      if (ch === '[' || ch === '(') depth++;
      if (ch === ']' || ch === ')') depth--;
      if (depth === 0 && (ch === ' ' || ch === '>')) break;
      j++;
    }
    const text = group.slice(i, j).trim();
    if (!text) break;
    steps.push({ compound: parseCompound(text), combinator });
    combinator = null;
    i = j;
  }
  return steps;
}

function attrValue(el, name) {
  if (name === 'class') return el.className || '';
  if (name === 'id') return el.id || '';
  return el.getAttribute(name);
}

function matchCompound(el, compound, scopeEl) {
  if (!el || typeof el.tagName !== 'string') return false;
  if (compound.scope && el !== scopeEl) return false;
  if (compound.tag && compound.tag !== '*' && el.tagName.toLowerCase() !== compound.tag.toLowerCase()) return false;
  if (compound.id && el.id !== compound.id) return false;
  for (const c of compound.classes) {
    if (!el.classList.contains(c)) return false;
  }
  for (const a of compound.attrs) {
    const raw = attrValue(el, a.name);
    if (raw === null || raw === undefined) return false;
    if (a.op === null) continue;
    let hay = String(raw);
    let needle = a.value;
    if (a.ci) { hay = hay.toLowerCase(); needle = needle.toLowerCase(); }
    if (a.op === '=' && hay !== needle) return false;
    if (a.op === '*=' && !hay.includes(needle)) return false;
    if (a.op === '^=' && !hay.startsWith(needle)) return false;
    if (a.op === '$=' && !hay.endsWith(needle)) return false;
    if (a.op === '~=' && !hay.split(/\s+/).includes(needle)) return false;
  }
  if (compound.not && matchCompound(el, compound.not, scopeEl)) return false;
  return true;
}

function matchSteps(el, steps, scopeEl) {
  let current = el;
  for (let s = steps.length - 1; s >= 0; s--) {
    const { compound, combinator } = steps[s];
    if (s === steps.length - 1) {
      if (!matchCompound(current, compound, scopeEl)) return false;
    } else if (combinator === '>') {
      current = current.parentElement;
      if (!current || !matchCompound(current, compound, scopeEl)) return false;
    } else {
      // descendant: walk up until a matching ancestor is found
      let found = null;
      let anc = current.parentElement;
      while (anc) {
        if (matchCompound(anc, compound, scopeEl)) { found = anc; break; }
        anc = anc.parentElement;
      }
      if (!found) return false;
      current = found;
    }
  }
  return true;
}

function matchesSelector(el, selector, scopeEl) {
  return splitGroups(selector).some((group) => matchSteps(el, parseGroup(group), scopeEl));
}

function walk(el, out) {
  out.push(el);
  for (const child of el.children) walk(child, out);
}

// ---------------------------------------------------------------- element
class FakeElement {
  constructor(tagName, ownerDocument) {
    this.tagName = String(tagName).toUpperCase();
    this._doc = ownerDocument || null;
    this.children = [];
    this.parentElement = null;
    this.attributes = {};
    this._classSet = new Set();
    this._text = '';
    this._innerText = undefined;
    this._listeners = {};
    this._rect = { left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0 };
    this._computedStyle = null;
    this.offsetParent = null;
    this.scrollWidth = 0;
    this.clientWidth = 0;
    this.scrollHeight = 0;
    this.clientHeight = 0;
    this.scrollTop = 0;
    this.disabled = false;
    this.value = '';
    this.type = '';
    const self = this;
    this.style = {
      setProperty(k, v) { this[k] = v; },
      removeProperty(k) { delete this[k]; },
      getPropertyValue(k) { return this[k] || ''; },
    };
    this.classList = {
      add(...names) { for (const n of names) self._classSet.add(n); self._syncClass(); },
      remove(...names) { for (const n of names) self._classSet.delete(n); self._syncClass(); },
      toggle(name, force) {
        if (force === undefined) force = !self._classSet.has(name);
        if (force) self._classSet.add(name); else self._classSet.delete(name);
        self._syncClass();
        return force;
      },
      contains(name) { return self._classSet.has(name); },
    };
  }
  _syncClass() { this._className = [...this._classSet].join(' '); }
  get className() { return this._className || ''; }
  set className(v) {
    this._className = String(v || '');
    this._classSet = new Set(this._className.split(/\s+/).filter(Boolean));
  }
  get id() { return this.attributes.id || ''; }
  set id(v) { this.attributes.id = String(v); }
  get parentNode() { return this.parentElement; }
  get firstElementChild() { return this.children[0] || null; }
  get lastElementChild() { return this.children[this.children.length - 1] || null; }
  get childElementCount() { return this.children.length; }
  get textContent() {
    if (this._text !== '') return this._text;
    return this.children.map((c) => c.textContent).join('');
  }
  set textContent(v) { this._text = String(v ?? ''); }
  get innerText() {
    if (this._innerText !== undefined) return this._innerText;
    return this.textContent;
  }
  set innerText(v) { this._innerText = String(v ?? ''); }
  get innerHTML() { return this._innerHTML || ''; }
  set innerHTML(v) { this._innerHTML = String(v ?? ''); this._text = String(v ?? ''); }
  get isConnected() {
    let el = this;
    while (el) {
      if (this._doc && (el === this._doc.documentElement)) return true;
      el = el.parentElement;
    }
    return false;
  }
  getAttribute(name) {
    if (name === 'class') return this.className;
    if (name === 'id') return this.id || null;
    return Object.prototype.hasOwnProperty.call(this.attributes, name) ? this.attributes[name] : null;
  }
  setAttribute(name, value) {
    const v = String(value);
    if (name === 'class') { this.className = v; return; }
    if (name === 'id') { this.attributes.id = v; return; }
    this.attributes[name] = v;
  }
  removeAttribute(name) { delete this.attributes[name]; }
  hasAttribute(name) {
    if (name === 'class') return this.className !== '';
    if (name === 'id') return Boolean(this.id);
    return Object.prototype.hasOwnProperty.call(this.attributes, name);
  }
  appendChild(child) {
    if (child.parentElement) {
      const idx = child.parentElement.children.indexOf(child);
      if (idx >= 0) child.parentElement.children.splice(idx, 1);
    }
    child.parentElement = this;
    if (!child._doc) child._doc = this._doc;
    this.children.push(child);
    return child;
  }
  remove() {
    if (!this.parentElement) return;
    const idx = this.parentElement.children.indexOf(this);
    if (idx >= 0) this.parentElement.children.splice(idx, 1);
    this.parentElement = null;
  }
  querySelector(selector) {
    const all = [];
    for (const child of this.children) walk(child, all);
    for (const el of all) if (matchesSelector(el, selector, this)) return el;
    return null;
  }
  querySelectorAll(selector) {
    const all = [];
    for (const child of this.children) walk(child, all);
    return all.filter((el) => matchesSelector(el, selector, this));
  }
  matches(selector) { return matchesSelector(this, selector, this); }
  closest(selector) {
    let el = this;
    while (el) {
      if (matchesSelector(el, selector, el)) return el;
      el = el.parentElement;
    }
    return null;
  }
  contains(node) {
    let el = node;
    while (el) {
      if (el === this) return true;
      el = el.parentElement;
    }
    return false;
  }
  getBoundingClientRect() { return { ...this._rect }; }
  setRect(rect) { this._rect = { ...this._rect, ...rect }; }
  addEventListener(type, fn) {
    (this._listeners[type] ||= []).push(fn);
  }
  removeEventListener(type, fn) {
    const list = this._listeners[type];
    if (!list) return;
    const i = list.indexOf(fn);
    if (i >= 0) list.splice(i, 1);
  }
  dispatchEvent(event) {
    event.target = event.target || this;
    const listeners = [...(this._listeners[event.type] || [])];
    for (const fn of listeners) {
      if (event._stopped) break;
      fn.call(this, event);
    }
    return !event.defaultPrevented;
  }
  click() {
    const event = makeEvent('click', this);
    // document capture listeners first (inject.js registers its
    // interceptors in capture phase), then the element itself.
    if (this._doc) this._doc._dispatchDocumentEvent(event);
    if (!event._stopped) this.dispatchEvent(event);
    if (!event._stopped && this._doc) this._doc._bubbleEvent(event, this);
  }
}

function makeEvent(type, target, extra = {}) {
  const event = {
    type,
    target,
    defaultPrevented: false,
    _stopped: false,
    preventDefault() { this.defaultPrevented = true; },
    stopPropagation() { this._stopped = true; },
    ...extra,
  };
  return event;
}

class FakeMutationObserver {
  constructor(callback) {
    this._callback = callback;
    this.targets = [];
    FakeMutationObserver.instances.push(this);
  }
  observe(target, options) { this.targets.push({ target, options }); }
  disconnect() {
    this.targets = [];
    const i = FakeMutationObserver.instances.indexOf(this);
    if (i >= 0) FakeMutationObserver.instances.splice(i, 1);
  }
  takeRecords() { return []; }
  fire(records = []) { this._callback(records, this); }
  static fireAll(records = []) {
    for (const obs of [...FakeMutationObserver.instances]) obs.fire(records);
  }
}
FakeMutationObserver.instances = [];

// --------------------------------------------------------------- document
class FakeDocument {
  constructor() {
    this.documentElement = new FakeElement('html', this);
    this.head = new FakeElement('head', this);
    this.body = new FakeElement('body', this);
    this.documentElement.appendChild(this.head);
    this.documentElement.appendChild(this.body);
    this.title = '';
    this.cookie = '';
    this.activeElement = null;
    this._listeners = {};
  }
  createElement(tag) { return new FakeElement(tag, this); }
  getElementById(id) {
    const all = [];
    walk(this.documentElement, all);
    return all.find((el) => el.id === id) || null;
  }
  querySelector(selector) {
    const all = [];
    walk(this.documentElement, all);
    for (const el of all) if (matchesSelector(el, selector, this.documentElement)) return el;
    return null;
  }
  querySelectorAll(selector) {
    const all = [];
    walk(this.documentElement, all);
    return all.filter((el) => matchesSelector(el, selector, this.documentElement));
  }
  addEventListener(type, fn) {
    (this._listeners[type] ||= []).push(fn);
  }
  removeEventListener(type, fn) {
    const list = this._listeners[type];
    if (!list) return;
    const i = list.indexOf(fn);
    if (i >= 0) list.splice(i, 1);
  }
  _dispatchDocumentEvent(event) {
    const listeners = [...(this._listeners[event.type] || [])];
    for (const fn of listeners) {
      if (event._stopped) break;
      fn.call(this, event);
    }
  }
  _bubbleEvent(event, fromEl) {
    let el = fromEl.parentElement;
    while (el && !event._stopped) {
      el.dispatchEvent(event);
      el = el.parentElement;
    }
  }
  dispatch(type, eventInit = {}) {
    const event = makeEvent(type, eventInit.target || this.body, eventInit);
    this._dispatchDocumentEvent(event);
    return event;
  }
}

// ---------------------------------------------------------------- sandbox
function createContext(options = {}) {
  const clock = new FakeClock();
  const document = new FakeDocument();
  // A real WebView has AbortSignal/AbortController/DOMException globals;
  // a bare vm context does not, and the polyfills under test only patch
  // missing static methods on an existing AbortSignal (they never create
  // the class itself). Provide subclasses of the host classes so the
  // tests can delete/shadow `.any`/`.timeout` on the copies without ever
  // mutating the host's AbortSignal (which would poison every later test
  // in the same process). DOMException is only ever constructed, so the
  // host class can be shared directly.
  class CtxAbortSignal extends AbortSignal {}
  class CtxAbortController extends AbortController {}
  const sandbox = {
    console,
    document,
    AbortSignal: CtxAbortSignal,
    AbortController: CtxAbortController,
    DOMException,
    innerWidth: options.innerWidth ?? 390,
    innerHeight: options.innerHeight ?? 844,
    devicePixelRatio: 2,
    location: { href: 'http://192.168.1.10:3100/?token=once' },
    visualViewport: undefined,
    MutationObserver: FakeMutationObserver,
    setTimeout: (fn, ms) => clock.setTimeout(fn, ms),
    setInterval: (fn, ms) => clock.setInterval(fn, ms),
    clearTimeout: (id) => clock.clearTimeout(id),
    clearInterval: (id) => clock.clearInterval(id),
    Date: { now: () => clock.now },
    getComputedStyle: (el) => (el && el._computedStyle) || {
      position: 'static', display: 'block', overflowX: 'visible',
      whiteSpace: 'normal', fontSize: '16px',
    },
    requestAnimationFrame: (cb) => clock.setTimeout(cb, 0),
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  // Minimal window event registry (inject.js registers a resize listener
  // at load; tests can fire it via window.dispatchEvent({ type: 'resize' })).
  const windowListeners = {};
  sandbox.addEventListener = (type, fn) => { (windowListeners[type] || (windowListeners[type] = [])).push(fn); };
  sandbox.removeEventListener = (type, fn) => {
    const list = windowListeners[type];
    if (!list) return;
    const i = list.indexOf(fn);
    if (i >= 0) list.splice(i, 1);
  };
  sandbox.dispatchEvent = (event) => {
    for (const fn of [...(windowListeners[event.type] || [])]) fn.call(sandbox, event);
    return true;
  };
  const ctx = vm.createContext(sandbox);
  // A bare vm context's intrinsics (Object, Array, Map, ...) are not
  // visible as properties from the host, so copy references to them onto
  // the global object; tests then reach them as ctx.Object etc. The fake
  // Date (clock-driven) is deliberately left alone, so Date.now() stays
  // deterministic.
  for (const name of ['Object', 'Array', 'Map', 'Set', 'Promise', 'Error', 'JSON', 'Number', 'String', 'Symbol', 'RegExp', 'Function', 'Boolean']) {
    try { ctx[name] = vm.runInContext(name, ctx); } catch { /* not present */ }
  }
  // Modern APIs live in the vm context's own intrinsics; delete the ones the
  // polyfill under test is supposed to supply, so the test exercises the
  // polyfill and not the host's native implementation.
  if (options.deleteModern) {
    vm.runInContext([
      'if (typeof AbortSignal !== "undefined") { AbortSignal.any = undefined; AbortSignal.timeout = undefined; }',
      'Promise.withResolvers = undefined;',
      'delete Array.prototype.findLast;',
      'delete Array.prototype.findLastIndex;',
      'delete Array.prototype.toReversed;',
      'delete Array.prototype.toSpliced;',
      'Object.groupBy = undefined;',
      'Map.groupBy = undefined;',
    ].join('\n'), ctx);
  }
  if (options.deleteAbortSignalOnly) {
    vm.runInContext(
      'if (typeof AbortSignal !== "undefined") { AbortSignal.any = undefined; AbortSignal.timeout = undefined; }',
      ctx,
    );
  }
  return { ctx, clock, document, window: sandbox };
}

function loadScript(ctx, relPath) {
  const abs = path.join(REPO_ROOT, relPath);
  const src = fs.readFileSync(abs, 'utf8');
  vm.runInContext(src, ctx, { filename: abs });
  return src;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

module.exports = {
  FakeClock,
  FakeElement,
  FakeDocument,
  FakeMutationObserver,
  createContext,
  loadScript,
  makeEvent,
  matchesSelector,
  sleep,
  REPO_ROOT,
};
