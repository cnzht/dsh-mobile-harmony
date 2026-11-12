'use strict';
/**
 * early-polyfill.js — run in a fresh vm context with the modern APIs
 * removed first, so the file under test (not Node's natives) is what
 * actually defines them. Covers AbortSignal.any/timeout,
 * Promise.withResolvers, Array findLast/findLastIndex/toReversed/
 * toSpliced and Object/Map.groupBy, including the regressions fixed
 * in this change (toSpliced without deleteCount, __proto__ groupBy,
 * sparse-array holes).
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const { createContext, loadScript } = require('./support/fake-dom');

function freshPolyfillContext() {
  const env = createContext({ deleteModern: true });
  loadScript(env.ctx, 'entry/src/main/resources/rawfile/early-polyfill.js');
  return env;
}

// Arrays created inside the vm context have the context's Array
// prototype, so node:assert/strict's deepEqual (which checks prototypes)
// rejects them against host literals. Spread them into host arrays first.
const asHost = (arr) => [...arr];

test('early-polyfill is idempotent: second load is a no-op', () => {
  const env = freshPolyfillContext();
  const anyBefore = env.ctx.AbortSignal.any;
  loadScript(env.ctx, 'entry/src/main/resources/rawfile/early-polyfill.js');
  assert.equal(env.ctx.AbortSignal.any, anyBefore);
  assert.equal(env.ctx.window.__dshEarlyPolyfill, true);
});

test('AbortSignal.any: already-aborted input aborts immediately with its reason', () => {
  const { ctx } = freshPolyfillContext();
  const c1 = new ctx.AbortController();
  const reason = new ctx.DOMException('boom', 'AbortError');
  c1.abort(reason);
  const c2 = new ctx.AbortController();
  const combined = ctx.AbortSignal.any([c1.signal, c2.signal]);
  assert.equal(combined.aborted, true);
  assert.equal(combined.reason, reason);
});

test('AbortSignal.any: aborts when any input aborts, ignores nulls', async () => {
  const { ctx } = freshPolyfillContext();
  const a = new ctx.AbortController();
  const b = new ctx.AbortController();
  const combined = ctx.AbortSignal.any([null, a.signal, b.signal]);
  assert.equal(combined.aborted, false);
  b.abort(new ctx.DOMException('b', 'AbortError'));
  assert.equal(combined.aborted, true);
  assert.equal(combined.reason.name, 'AbortError');
  a.abort();
  assert.equal(combined.aborted, true);
});

test('AbortSignal.any: empty list never aborts', () => {
  const { ctx } = freshPolyfillContext();
  const combined = ctx.AbortSignal.any([]);
  assert.equal(combined.aborted, false);
});

test('AbortSignal.timeout: aborts after the delay with TimeoutError', () => {
  const env = freshPolyfillContext();
  const signal = env.ctx.AbortSignal.timeout(20);
  assert.equal(signal.aborted, false);
  // The polyfill uses the sandbox's setTimeout, which is the fake clock —
  // advancing real time would never fire it.
  env.clock.advance(20);
  assert.equal(signal.aborted, true);
  assert.equal(signal.reason.name, 'TimeoutError');
});

test('Promise.withResolvers: resolve/reject wire through', async () => {
  const { ctx } = freshPolyfillContext();
  const d = ctx.Promise.withResolvers();
  assert.equal(typeof d.promise.then, 'function');
  d.resolve(42);
  assert.equal(await d.promise, 42);
  const d2 = ctx.Promise.withResolvers();
  d2.reject(new Error('nope'));
  await assert.rejects(d2.promise, /nope/);
});

test('Array.findLast / findLastIndex: last match, thisArg, no match', () => {
  const { ctx } = freshPolyfillContext();
  const arr = [1, 2, 3, 2, 1];
  assert.equal(ctx.Array.prototype.findLast.call(arr, (x) => x === 2), 2);
  assert.equal(ctx.Array.prototype.findLastIndex.call(arr, (x) => x === 2), 3);
  assert.equal(ctx.Array.prototype.findLast.call(arr, (x) => x === 9), undefined);
  assert.equal(ctx.Array.prototype.findLastIndex.call(arr, (x) => x === 9), -1);
  const receiver = { threshold: 2 };
  assert.equal(
    ctx.Array.prototype.findLast.call(arr, function (x) { return x > this.threshold; }, receiver),
    3,
  );
});

test('Array.findLastIndex skips sparse holes (regression)', () => {
  const { ctx } = freshPolyfillContext();
  const sparse = [1, , 3]; // hole at index 1
  // A predicate that only matches `undefined` must not "find" the hole.
  assert.equal(ctx.Array.prototype.findLastIndex.call(sparse, (x) => x === undefined), -1);
  assert.equal(ctx.Array.prototype.findLast.call(sparse, (x) => x === undefined), undefined);
  // And a normal search still sees the real elements.
  assert.equal(ctx.Array.prototype.findLastIndex.call(sparse, (x) => x === 3), 2);
});

test('Array.toReversed: returns a reversed copy, original untouched', () => {
  const { ctx } = freshPolyfillContext();
  const arr = [1, 2, 3];
  assert.deepEqual(asHost(ctx.Array.prototype.toReversed.call(arr)), [3, 2, 1]);
  assert.deepEqual(arr, [1, 2, 3]);
});

test('Array.toSpliced: with deleteCount, and without it (regression)', () => {
  const { ctx } = freshPolyfillContext();
  const toSpliced = ctx.Array.prototype.toSpliced;
  assert.deepEqual(asHost(toSpliced.call([1, 2, 3, 4], 1, 1)), [1, 3, 4]);
  assert.deepEqual(asHost(toSpliced.call([1, 2, 3, 4], 1, 0, 9)), [1, 9, 2, 3, 4]);
  // Regression: toSpliced(1) must delete to the end, like the native one,
  // not return an unchanged copy (old code passed deleteCount=undefined
  // to splice, which deletes nothing).
  assert.deepEqual(asHost(toSpliced.call([1, 2, 3, 4], 1)), [1]);
  assert.deepEqual(asHost(toSpliced.call([1, 2, 3, 4])), [1, 2, 3, 4]);
  assert.deepEqual(asHost(toSpliced.call([1, 2, 3, 4], -1)), [1, 2, 3]);
  const orig = [1, 2, 3, 4];
  toSpliced.call(orig, 1);
  assert.deepEqual(orig, [1, 2, 3, 4]);
});

test('Object.groupBy: groups by key, preserves order, null prototype', () => {
  const { ctx } = freshPolyfillContext();
  const out = ctx.Object.groupBy(
    [{ g: 'a', v: 1 }, { g: 'b', v: 2 }, { g: 'a', v: 3 }],
    (x) => x.g,
  );
  assert.deepEqual(asHost(out.a.map((x) => x.v)), [1, 3]);
  assert.deepEqual(asHost(out.b.map((x) => x.v)), [2]);
  assert.equal(ctx.Object.getPrototypeOf(out), null);
});

test('Object.groupBy: "__proto__" is a real group (regression)', () => {
  const { ctx } = freshPolyfillContext();
  const out = ctx.Object.groupBy([{ k: '__proto__' }, { k: 'a' }], (x) => x.k);
  assert.equal(Object.prototype.hasOwnProperty.call(out, '__proto__'), true);
  assert.equal(out['__proto__'].length, 1);
  // The group must survive serialisation (the old plain-{} target silently
  // turned it into the object's prototype and dropped it from JSON).
  assert.match(JSON.stringify(out), /__proto__/);
  assert.equal(ctx.Object.getPrototypeOf(out), null);
});

test('Map.groupBy: groups into a Map keyed by the callback result', () => {
  const { ctx } = freshPolyfillContext();
  const out = ctx.Map.groupBy([1, 2, 3, 4], (x) => (x % 2 === 0 ? 'even' : 'odd'));
  assert.equal(out instanceof ctx.Map, true);
  assert.deepEqual(asHost(out.get('even')), [2, 4]);
  assert.deepEqual(asHost(out.get('odd')), [1, 3]);
});
