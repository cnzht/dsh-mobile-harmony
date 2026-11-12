# Tests — dsh-mobile-harmony

A dependency-free test suite for the parts of this HarmonyOS app that can
run outside the WebView. Everything here uses only Node's built-ins
(`node:test` + `node:assert`, plus `node:vm` / `node:child_process` for
harnessing). No npm install, no network, no DevEco, no Harmony SDK.

## Run

```bash
node --test tests/
```

Node 20+ is enough (the suite is developed against Node 24). Expected
result: all tests pass. If a test fails, it means the shipped JS/ArkTS
changed — fix the code or the test, never just delete the assertion.

`tests/index.js` is the entry point that makes the command above work:
this machine's Node 24.22.1 does not expand a directory argument (it
tries to load the directory as a module), so Node resolves `tests/` to
`index.js`, which requires every `*.test.js` next to it. The equivalent
forms `node --test "tests/**/*.test.js"` (each file in its own process)
and bare `node --test` from the repo root also work. Do not put tests in
`index.js` — add a new `*.test.js` and it is picked up automatically.

## What is covered

| File | What it tests |
| --- | --- |
| `tests/polyfills.test.js` | `early-polyfill.js` run in a fresh `vm` context with the modern APIs deleted first, so the polyfills themselves are exercised: `AbortSignal.any` / `AbortSignal.timeout`, `Promise.withResolvers`, `Array.findLast` / `findLastIndex` / `toReversed` / `toSpliced`, `Object.groupBy` / `Map.groupBy`. Includes regressions for `toSpliced(1)`, `groupBy('__proto__')`, and sparse-array holes. |
| `tests/inject.test.js` | `inject.js` against the fake DOM in `tests/support/fake-dom.js`: idempotency guard, the `AbortSignal` fallback (and that its code stays identical to `early-polyfill.js`), viewport meta creation/fixing, the details-column tri-state (open / empty / upstream-collapsed), the sidebar drawer (open via interval, rail button, mask close, session-row enforce), stats-bar tagging (innermost only, separators), popover clamping, tooltip autohide, composer-spacer sizing, the config intercept, and the plugin-adder install flow. |
| `tests/static.test.js` | Both injected JS files pass `node --check`; `mobile.css` braces are balanced; `module.json5` requests only `ohos.permission.INTERNET`; `AppScope/app.json5` bundle name is `cn.cnzht.dshmobile` (v1.0.1 / 1000001); display name is `Harness Mobile` in both string resources, the home title and the About title; no `DeepSeek` / `DSH Mobile` / old author / `experimental` / `鸿蒙` residue in user-visible files (NOTICE.md keeps the factual MIT upstream attribution, CHANGELOG.md and the resubmission checklist are internal records that name the rejected terms); no hardcoded token/password/API key in code or scripts; no signing material is checked in; the injected JS embeds no server URL. |
| `tests/privacy.test.js` | Privacy scan over every tracked file (`git ls-files`): no registered developer name (plain or escaped), no phone number, no email address, no 16+ digit run that could be an App/Developer ID; `developer.json` is gitignored and untracked while `developer.json.example` is tracked and clean. |
| `tests/index-ets.test.js` | `Index.ets` without DevEco: `toTitleList` is extracted from the real source, its ArkTS type annotations stripped, and run (empty/invalid/non-array input, 30-item truncation, stringification); the `connect()` empty-address guard, the main-frame 401/403-only return-to-setup path, the `drawerOpen`-based Sessions button label, `backToSetup` drawer/list cleanup, and the `injectOnce` dedup guard are asserted on the source; the About card shows the developer name from the local developer.json config (no hardcoded name, no old author name or experimental wording); the first-launch privacy dialog exists (state, `privacyAccepted` persistence, 同意/不同意/暂不使用, policy/agreement links, root overlay with no tap-outside dismiss, setup-view banner and footer links); the chat top bar carries the persistent "AI 生成内容" badge and About explains the app provides no AI generation service. |

## The fake DOM (`tests/support/fake-dom.js`)

A minimal `document` / `window` / `Element` / `MutationObserver` /
`requestAnimationFrame` stub with a controllable `FakeClock`
(`setTimeout`/`setInterval`/`Date.now`), so `inject.js`'s 2 s self-check
interval and its 300 ms MutationObserver debounce run deterministically
and never keep the test process alive. It implements the selector subset
`inject.js` actually uses (tag, `#id`, `.class`, `[attr]`/`=`/`*=`/`^=`/`$=` with an optional ` i` flag, descendant and child combinators,
comma groups, `:scope`, `:not(...)`). Anything it does not implement is
out of scope on purpose — if a test needs a new DOM behaviour, extend
the stub in `fake-dom.js` and say so in the test.

Known limits of the stub (deliberate, not bugs):

- `className` is treated as a single attribute value; a class list is
  derived from the whitespace-split tokens, so `classList.contains`
  works but setting `className` to a string with several classes does
  not create separate "classes" for the selector engine beyond the
  token list.
- `getBoundingClientRect` returns the rectangle set by the test via
  `setRect()` (default all zeros); layout is never computed.
- `getComputedStyle` returns the style object set by the test via
  `_computedStyle` (default `position: static`, `display: block`).
- `MutationObserver.fireAll()` must be called explicitly — mutations
  are not auto-detected.
- `window` has a minimal event registry (`addEventListener` /
  `removeEventListener` / `dispatchEvent`); only the `resize` listener
  `inject.js` registers is exercised.
- A bare `vm` context has no `AbortSignal` / `DOMException` globals, so
  the sandbox provides subclasses of the host's `AbortSignal` /
  `AbortController` plus the host `DOMException`. The subclasses exist
  so a test can shadow `.any` / `.timeout` on the copy without ever
  mutating the host classes (deleting them on the host would poison
  every later test in the same process). The context's own intrinsics
  (`Object`, `Array`, `Map`, ...) are copied onto the global object so
  tests can reach them as `ctx.Object` etc.; the fake `Date`
  (clock-driven `Date.now()`) is deliberately left alone.

## What this suite cannot verify

Anything that needs a real HarmonyOS device or DevEco: the ArkTS page
actually rendering, the WebView loading a real dsh URL, the native
`DshNative` bridge methods beyond the stubbed calls, the HAP build,
signing and publishing flow, and the real dsh page's DOM classes that
`inject.js` selects against. Those paths are covered only by the static
and stubbed tests above — a green run here is not a green run on a
device.
