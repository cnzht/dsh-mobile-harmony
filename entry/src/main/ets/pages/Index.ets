import { webview } from '@kit.ArkWeb';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { scanBarcode } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'DshMobile';

/**
 * Local build config (entry/src/main/resources/rawfile/developer.json).
 * The file is gitignored and never committed: it carries the developer
 * name as registered in the developer center, which the About card must
 * show for the store review but which must not appear in the public repo.
 * See developer.json.example for the format.
 */
interface DeveloperConfig {
  developerName?: string;
}

/**
 * LAN-only gate (standalone variant): only addresses on the local network
 * may be connected to — 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
 * 127.0.0.1 and localhost. Anything else (public IPs, hostnames, missing
 * scheme) is rejected, so the app never reaches the public internet.
 * Pure function on purpose: the test suite runs it directly.
 */
function isLanUrl(raw: string): boolean {
  const url: string = raw.trim();
  const schemeEnd: number = url.indexOf('://');
  if (schemeEnd <= 0) {
    return false;
  }
  const scheme: string = url.substring(0, schemeEnd).toLowerCase();
  if (scheme !== 'http' && scheme !== 'https') {
    return false;
  }
  const rest: string = url.substring(schemeEnd + 3);
  if (rest.length === 0) {
    return false;
  }
  // Host is the part before the first '/', '?' or '#'; strip a trailing port.
  let hostEnd: number = rest.length;
  for (let i = 0; i < rest.length; i++) {
    const c: string = rest.charAt(i);
    if (c === '/' || c === '?' || c === '#') {
      hostEnd = i;
      break;
    }
  }
  let host: string = rest.substring(0, hostEnd);
  const colon: number = host.lastIndexOf(':');
  if (colon >= 0) {
    host = host.substring(0, colon);
  }
  host = host.toLowerCase();
  if (host.length === 0) {
    return false;
  }
  if (host === 'localhost') {
    return true;
  }
  const parts: string[] = host.split('.');
  if (parts.length !== 4) {
    return false;
  }
  const nums: number[] = [];
  for (let i = 0; i < 4; i++) {
    const p: string = parts[i];
    if (p.length === 0) {
      return false;
    }
    for (let j = 0; j < p.length; j++) {
      const ch: string = p.charAt(j);
      if (ch < '0' || ch > '9') {
        return false;
      }
    }
    const n: number = parseInt(p, 10);
    if (n < 0 || n > 255) {
      return false;
    }
    nums.push(n);
  }
  if (nums[0] === 10) {
    return true;
  }
  if (nums[0] === 172 && nums[1] >= 16 && nums[1] <= 31) {
    return true;
  }
  if (nums[0] === 192 && nums[1] === 168) {
    return true;
  }
  if (nums[0] === 127 && nums[1] === 0 && nums[2] === 0 && nums[3] === 1) {
    return true;
  }
  return false;
}

/*
 * Standalone (LAN-only) variant of Harness Mobile.
 *
 * No public-internet access: the app only ever connects to a server on the
 * local network (see isLanUrl above), and the home screen is a static demo
 * page bundled in rawfile (local-demo.html) for use with no server at all.
 * The INTERNET permission stays because LAN sockets need it; it is the only
 * permission the app requests. Privacy policy and user agreement are bundled
 * as local files too (privacy.html / eula.html in rawfile) and shown inside
 * the app. The native Sessions drawer, About card and first-launch privacy
 * consent dialog are kept from the online variant.
 */

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  private connectTimer: number = -1;
  // False once no Web component is mounted: calling into the detached
  // controller throws synchronously (17100001) and used to kill the app.
  private webAlive: boolean = true;
  /** Local demo page bundled in rawfile; policy pages replace it temporarily. */
  @State pageSrc: Resource = $rawfile('local-demo.html');
  /** True while a bundled policy/agreement page is shown instead of the current view. */
  @State onPolicyPage: boolean = false;
  /** Connected LAN server URL; empty means "not connected". */
  @State url: string = '';
  @State draft: string = '';
  @State error: string = '';
  @State hint: string = '';
  /** True while the setup view (manual address / scan / local demo) is shown. */
  @State showSetup: boolean = false;
  @State loading: boolean = true;
  @State sessionsList: string[] = [];
  @State drawerOpen: boolean = false;
  @State aboutOpen: boolean = false;
  /** First-launch privacy consent dialog (AGC review §7.5). */
  @State privacyOpen: boolean = false;
  /** User tapped "不同意" / "暂不使用": show the consent banner until they agree. */
  @State privacyDeclined: boolean = false;
  /** Developer display name, read from the local gitignored developer.json. */
  @State developerName: string = '';
  private early: string = '';
  private inject: string = '';
  private prefs: preferences.Preferences | undefined = undefined;
  /** Last document that already received the mobile adaptation layer. */
  private lastInjectedUrl: string = '';

  aboutToAppear(): void {
    this.readAssets();
    this.loadPrefs();
  }

  private readAssets(): void {
    try {
      const rm = this.getUIContext().getHostContext()!.resourceManager;
      const decoder = util.TextDecoder.create('utf-8');
      this.early = decoder.decodeToString(rm.getRawFileContentSync('early-polyfill.js'));
      this.inject = decoder.decodeToString(rm.getRawFileContentSync('inject.js'));
    } catch (e) {
      hilog.error(0x0000, TAG, 'read rawfile failed: %{public}s', JSON.stringify(e));
    }

    // Developer name is a separate try/catch on purpose: the config file is
    // local-only (see developer.json.example), so a missing file must never
    // block the three assets above — the About card then shows a bare label.
    try {
      const rm = this.getUIContext().getHostContext()!.resourceManager;
      const decoder = util.TextDecoder.create('utf-8');
      const raw = decoder.decodeToString(rm.getRawFileContentSync('developer.json'));
      const cfg = JSON.parse(raw) as DeveloperConfig;
      const name: string | undefined = cfg.developerName;
      if (typeof name === 'string' && name.length > 0) {
        this.developerName = name;
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'developer.json unavailable: %{public}s', JSON.stringify(e));
    }
  }

  private loadPrefs(): void {
    preferences.getPreferences(this.getUIContext().getHostContext()!, 'dsh_mobile')
      .then((p: preferences.Preferences) => {
        this.prefs = p;
        const saved = p.getSync('serverUrl', '') as string;
        if (saved.length > 0) {
          this.draft = saved;
          // A saved server is only trusted if it is still a LAN address:
          // connect straight away so a returning user lands in the workspace.
          if (isLanUrl(saved)) {
            this.url = saved;
            this.loading = true;
          } else {
            this.hint = '已保存的服务器地址不是局域网地址，仅支持局域网连接。';
          }
        }
        // First launch: ask the user to read the privacy policy before use.
        // The choice is remembered in preferences; a missing flag means "not yet agreed".
        const accepted = p.getSync('privacyAccepted', false) as boolean;
        if (!accepted) {
          this.privacyOpen = true;
        }
      })
      .catch((e: Error) => {
        hilog.warn(0x0000, TAG, 'prefs unavailable: %{public}s', e.message);
      });
  }

  private acceptPrivacy(): void {
    this.privacyOpen = false;
    this.privacyDeclined = false;
    if (this.prefs !== undefined) {
      this.prefs.putSync('privacyAccepted', true);
      this.prefs.flush();
    }
  }

  private declinePrivacy(): void {
    this.privacyDeclined = true;
  }

  private openPrivacyLater(): void {
    this.privacyOpen = false;
  }

  /** Show the bundled privacy policy; the top bar offers a way back. */
  private openPrivacyPage(): void {
    this.pageSrc = $rawfile('privacy.html');
    this.onPolicyPage = true;
    this.privacyOpen = false;
  }

  /** Show the bundled user agreement; the top bar offers a way back. */
  private openEulaPage(): void {
    this.pageSrc = $rawfile('eula.html');
    this.onPolicyPage = true;
    this.privacyOpen = false;
  }

  /** Return from a policy page to whatever was underneath (demo / server / setup). */
  private backToDemo(): void {
    this.pageSrc = $rawfile('local-demo.html');
    this.onPolicyPage = false;
  }

  /** "使用本地演示": leave setup and show the bundled demo page. */
  private useLocalDemo(): void {
    this.webAlive = false;
    this.showSetup = false;
    this.url = '';
    this.pageSrc = $rawfile('local-demo.html');
    this.stopConnectWatchdog();
    this.onPolicyPage = false;
  }

  /**
   * Connect to the typed/pasted server URL — but only if it is a LAN
   * address (see isLanUrl). A public address is refused with a plain
   * message instead of connecting, so this build never reaches the
   * public internet.
   */
  private connect(): void {
    let target = this.draft.trim();
    if (target.length === 0) {
      this.error = 'Please enter the dsh web URL';
      return;
    }
    // dsh prints a full URL, but accept a bare host:port too.
    if (target.indexOf('://') < 0) {
      target = 'http://' + target;
    }
    if (!isLanUrl(target)) {
      this.error = '仅支持局域网地址：请输入 10.x.x.x、172.16–31.x.x.x、192.168.x.x 或 localhost 的服务器地址';
      return;
    }
    this.error = '';
    this.hint = '';
    this.lastInjectedUrl = '';
    this.loading = true;
    this.startConnectWatchdog();
    this.url = target;
    this.showSetup = false;
    if (this.prefs !== undefined) {
      this.prefs.putSync('serverUrl', target);
      this.prefs.flush();
    }
  }

  private scan(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    scanBarcode.startScanForResult(ctx)
      .then((result: scanBarcode.ScanResult) => {
        const value = (result.originalValue ?? '').trim();
        hilog.info(0x0000, TAG, 'scan result length: %{public}d', value.length);
        if (value.length === 0) {
          this.error = 'Scan returned an empty result';
          return;
        }
        this.draft = value;
        this.connect();
      })
      .catch((e: Error) => {
        hilog.warn(0x0000, TAG, 'scan cancelled or failed: %{public}s', e.message);
        this.hint = 'Scan cancelled';
      });
  }

  /**
   * A LAN URL that nothing listens on yields a main-frame network error (or no
   * page at all). Upstream behaviour was a silent blank WebView, so surface it:
   * return to setup with the typed URL preserved and a concrete hint.
   */
  private handleConnectFailure(): void {
    hilog.warn(0x0000, TAG, 'main frame failed to load, back to setup');
    this.webAlive = false;
    this.loading = false;
    this.hint = '无法连接服务器：请确认地址、端口与 dsh web 已启动，且手机与服务器在同一局域网';
    this.draft = this.url;
    this.url = '';
    this.showSetup = true;
    this.lastInjectedUrl = '';
    this.stopConnectWatchdog();
  }

  /**
   * ArkWeb throws synchronously with 17100001 ("The WebviewController must be
   * associated with a Web component") when the controller's Web has left the
   * tree - e.g. a delayed probe firing right after a failed connect returned to
   * setup. A throw inside a setTimeout callback is uncaught and terminates the
   * process, so every controller call goes through this guard instead.
   */
  private js(script: string): Promise<string> {
    if (!this.webAlive) {
      hilog.info(0x0000, TAG, 'skip runJavaScript: web view detached');
      return Promise.resolve('');
    }
    try {
      return this.controller.runJavaScript(script);
    } catch (e) {
      this.webAlive = false;
      hilog.warn(0x0000, TAG, 'runJavaScript threw: %{public}s', (e as Error).message);
      return Promise.resolve('');
    }
  }

  /** Safety net for hosts that blackhole the connection (no error event at all). */
  private startConnectWatchdog(): void {
    this.stopConnectWatchdog();
    this.connectTimer = setTimeout(() => {
      this.connectTimer = -1;
      if (this.loading && this.url.length > 0) {
        this.handleConnectFailure();
      }
    }, 20000);
  }

  private stopConnectWatchdog(): void {
    if (this.connectTimer >= 0) {
      clearTimeout(this.connectTimer);
      this.connectTimer = -1;
    }
  }

  /**
   * A consumed/expired token yields a main-frame 401 from dsh's auth fence.
   * Only that precise signal returns to setup: the earlier text heuristic
   * false-positived on ordinary dsh pages and bounced users back to setup.
   */
  private handleHttpError(url: string): void {
    hilog.warn(0x0000, TAG, 'main frame rejected: %{public}s', url);
    if (this.url.length === 0) {
      return;
    }
    this.hint = 'Token 已失效（一次性或服务重启）。请重新粘贴 dsh web 打印的完整 URL。';
    this.webAlive = false;
    this.draft = this.url;
    this.url = '';
    this.showSetup = true;
    this.lastInjectedUrl = '';
    this.stopConnectWatchdog();
  }

  /** Leave the chat view: collapse the drawer state before returning to setup. */
  private backToSetup(): void {
    this.drawerOpen = false;
    this.sessionsList = [];
    this.loading = false;
    this.lastInjectedUrl = '';
    this.url = '';
    this.showSetup = true;
    this.stopConnectWatchdog();
  }

  private styleScript(): string {
    // Upstream mobile.css turns the left sidebar into an overlay drawer whenever
    // dsh's sidebar is expanded, which it is on first paint at phone widths — so
    // the drawer (and its scrim) appears by itself. Fighting the class made
    // inject.js re-add it on every mutation (measured: open/close/open every
    // ~500ms). Instead pin the visuals: never show the drawer or scrim unless we
    // explicitly opt in with body.dsh-user-drawer.
    const overrides = 'body:not(.dsh-user-drawer) div[class*="_sidebarCol"]{display:none!important}' +
      '#dsh-mobile-drawer-mask{display:none!important}' +
      'body.dsh-user-drawer div[class*="_sidebarCol"]{z-index:2147483600!important;' +
      'box-shadow:0 0 24px rgba(0,0,0,.25)!important;background:#fff!important}' +
      'button,[role=button]{min-height:40px!important}' +
      'body{padding-bottom:env(safe-area-inset-bottom,0px)!important}' +
      '[class*=label],[class*=title],[class*=name]{overflow-wrap:break-word!important}' +
      'textarea,[contenteditable=true]{max-height:32vh!important;overflow-y:auto!important}';
    // The upstream 750-line mobile.css was written for the dsh 0.1.5 DOM. Applied
    // to the current build it white-screens the WebView a few seconds after load
    // (inject.js latches layout state from a tree the stylesheet then hides, and
    // its late DOM lookups throw). The file stays in rawfile/ as upstream
    // reference but is no longer injected; the overrides below cover what a phone
    // actually needs (no auto drawer/scrim, 40px touch targets, bounded composer)
    // and are safe to apply from any layout state.
    return '(function(){var oid="dsh-mobile-override";var o=document.getElementById(oid);if(o){o.remove();}' +
      'var s2=document.createElement("style");s2.id=oid;s2.textContent=' + JSON.stringify(overrides) + ';' +
      '(document.head||document.documentElement).appendChild(s2);' +
      'if(!window.__dshErrs){window.__dshErrs=[];' +
      'window.addEventListener("error",function(e){window.__dshErrs.push(String(e.message||"err").slice(0,120));},true);' +
      'window.addEventListener("unhandledrejection",function(e){window.__dshErrs.push(String(e.reason).slice(0,80));});}' +
      'if(!window.__dshOutsideTap){window.__dshOutsideTap=true;' +
      'document.addEventListener("click",function(ev){' +
      'if(!document.body.classList.contains("dsh-user-drawer"))return;' +
      'if(window.__dshOpenGuard&&Date.now()-window.__dshOpenGuard<1500)return;' +
      'var t=ev.target;' +
      'if(t&&t.closest&&t.closest("button[class*=_toggle],button[aria-label*=Sidebar],button[aria-label*=Open]"))return;' +
      'var pnl=document.querySelector("div[class*=_sidebarCol]");' +
      'if(pnl&&pnl.contains(t))return;' +
      'document.body.classList.remove("dsh-user-drawer");},true);}' +
      'if(!window.__dshSessionRows){window.__dshSessionRows=function(){' +
      'var col=document.querySelector("div[class*=_sidebarCol]");if(!col){return [];}' +
      'var all=col.querySelectorAll("[data-row-key]");var out=[];' +
      'for(var i=0;i<all.length;i++){var k=all[i].getAttribute("data-row-key")||"";' +
      'if(k.indexOf("session:")===0){out.push(all[i]);}}' +
      'if(!out.length){var rows=col.querySelectorAll("div[class*=_sessionRow]");' +
      'for(var j=0;j<rows.length;j++){out.push(rows[j]);}}' +
      'return out;};' +
      'window.__dshListSessions=function(){try{var r=window.__dshSessionRows();var t=[];' +
      'for(var i=0;i<r.length;i++){var el=r[i].querySelector("span[class*=_title]");' +
      'var x=el?(el.textContent||""):(r[i].textContent||"");x=x.trim().slice(0,60);t.push(x);}' +
      'return JSON.stringify(t);}catch(e){return "[]";}};' +
      'window.__dshClickSession=function(i){try{if(i<0){var c=document.querySelector("div[class*=_sidebarCol]");' +
      'var nb=c?c.querySelector("button[class*=newSession]"):null;if(nb){nb.click();return "new";}return "none";}' +
      'var r=window.__dshSessionRows();if(i>=r.length){return "oob";}r[i].click();return "ok";}catch(e){return "ERR";}};' +
      // Close the __dshSessionRows guard AND the IIFE opened at the top of this
      // script. (The guard's brace was missing, so the whole style/bridge script
      // was a syntax error and runJavaScript silently rejected it.)
      '}})();'
  }

  private injectOnce(url: string): void {
    if (url.length > 0 && url === this.lastInjectedUrl) {
      return;
    }
    this.lastInjectedUrl = url;
    hilog.info(0x0000, TAG, 'inject mobile layer for %{public}s', url);
    // inject.js must run against the real (un-hidden) layout: applying mobile.css
    // first makes its own DOM lookups throw ("Cannot read properties of null
    // (reading 'tagName')") and leaves the dsh UI half-initialized (blank screen).
    // So keep inject -> CSS order, wrap inject so a throw cannot skip the CSS, and
    // let settle() collapse the drawer state it latches.
    const guarded = '(function(){try{if(window.__dshMobileAttached){return;}window.__dshMobileAttached=true;' +
      'try{\n' + this.inject + '\n}catch(e){}' + this.styleScript() + '}catch(e){}})();';
    this.js(guarded)
      .catch((e: Error) => {
        hilog.warn(0x0000, TAG, 'inject failed: %{public}s', e.message);
      });
    // Probe the drawer/rightbar state once the upstream script settled.
    setTimeout(() => {
      this.js(
        '(function(){try{var b=document.body;var m=document.getElementById("dsh-mobile-drawer-mask");' +
        'var cols=document.querySelectorAll("div[data-rightbar-col],div[class*=_rightbarCol]");' +
        'var sb=document.querySelector("div[class*=_sidebarCol]");' +
        'var open=document.querySelectorAll(".dsh-mobile-open,.dsh-mobile-empty");' +
        'return JSON.stringify({cls:b.className.slice(0,140),mask:!!m,' +
        'maskDisp:m?getComputedStyle(m).display:"-",rbCols:cols.length,openCls:open.length,' +
        'sbW:sb?Math.round(sb.getBoundingClientRect().width):-1,' +
        'vw:innerWidth,vh:innerHeight,dpr:devicePixelRatio,' +
        'title:(document.title||"").slice(0,40),textLen:(b.innerText||"").length,' +
        'snip:(b.innerText||"").slice(0,60),href:(location.href||"").slice(0,90),' +
        'cookies:(document.cookie||"").length,' +
        'sw:document.documentElement.scrollWidth,cw:innerWidth,' +
        'ovf:document.documentElement.scrollWidth>innerWidth+1,' +
        'fs:getComputedStyle(document.documentElement).fontSize,' +
        'roots:document.querySelectorAll("#root,#app,main,[class*=appRoot]").length,' +
        'earlyMark:!!window.__dshMobileEarly});}catch(e){return "ERR:"+e.message;}})()')
        .then((r: string) => { hilog.info(0x0000, TAG, 'probe %{public}s', r); })
        .catch(() => {});
      this.js(
        '(function(){try{var w=innerWidth,out=[];var all=document.querySelectorAll("body *");' +
        'for(var i=0;i<all.length&&out.length<6;i++){var e=all[i];var r=e.getBoundingClientRect();' +
        'if(r.width===0&&r.height===0)continue;' +
        'if(r.right>w+2||r.left<-2||r.width>w+2){' +
        'out.push((e.className&&e.className.toString().slice(0,26)||e.tagName)+"|x"+Math.round(r.left)+' +
        '"|w"+Math.round(r.width)+"|r"+Math.round(r.right));}}' +
        'return JSON.stringify({w:w,n:out.length,items:out});}catch(e){return "ERR:"+e.message;}})()')
        .then((r: string) => { hilog.info(0x0000, TAG, 'overflow %{public}s', r); })
        .catch(() => {});
      this.js(
        '(function(){try{var out=[],all=document.querySelectorAll("body *");' +
        'for(var i=0;i<all.length&&out.length<8;i++){var e=all[i];' +
        'if(!e.clientWidth&&!e.clientHeight)continue;' +
        'if(e.scrollWidth<=e.clientWidth+2)continue;' +
        'var cs=getComputedStyle(e);' +
        'out.push({c:(e.className||e.tagName).toString().slice(0,24),' +
        'sw:e.scrollWidth,cw:e.clientWidth,ov:cs.overflowX,ws:cs.whiteSpace,' +
        't:(e.innerText||"").replace(/\s+/g," ").slice(0,26)});}' +
        'return JSON.stringify({n:out.length,items:out});}catch(e){return "ERR:"+e.message;}})()')
        .then((r: string) => { hilog.info(0x0000, TAG, 'clip %{public}s', r); })
        .catch(() => {});
    }, 1500);
    this.settle();
    setTimeout(() => this.probeSidebar(), 4000);
    setTimeout(() => this.auditButtons(), 5000);
  }

  private settle(): void {
    setTimeout(() => {
      this.js(
        '(function(){try{var b=document.body;' +
        'if(b.classList.contains("dsh-mobile-drawer")){' +
        'var t=document.querySelector("button[class*=_toggle]")||' +
        'document.querySelector("button[aria-label*=收起]")||' +
        'document.querySelector("button[aria-label*=Collapse]");' +
        'if(t){t.click();}else{var m=document.getElementById("dsh-mobile-drawer-mask");if(m){m.click();}}}' +
        'b.classList.remove("dsh-user-drawer");return "closed";' +
        '}catch(e){return "ERR:"+e.message;}})()')
        .then((r: string) => { hilog.info(0x0000, TAG, 'settle %{public}s', r); this.mirrorDrawer(); })
        .catch(() => {});
    }, 2200);
  }

  private toggleSessions(): void {
    if (this.drawerOpen) {
      this.drawerOpen = false;
      return;
    }
    this.js(
      '(function(){try{return window.__dshListSessions?window.__dshListSessions():"[]";' +
      '}catch(e){return "[]";}})()')
      .then((r: string) => {
        hilog.info(0x0000, TAG, 'sessions raw %{public}s', r.slice(0, 120));
        this.sessionsList = this.toTitleList(r);
        this.drawerOpen = true;
      })
      .catch((e: Error) => {
        hilog.warn(0x0000, TAG, 'sessions call failed: %{public}s', e.message);
        this.sessionsList = [];
        this.drawerOpen = true;
      });
  }

  private toTitleList(raw: string): string[] {
    const out: string[] = [];
    if (raw.length === 0) {
      return out;
    }
    // runJavaScript's result is JSON-encoded by ArkWeb: a JS string return value
    // arrives as a quoted JSON string ("\"[...]\""), not as the raw JSON text.
    // Unwrap up to three layers so both shapes yield the same titles.
    let value: string = raw;
    for (let pass = 0; pass < 3; pass++) {
      try {
        const parsed: Object = JSON.parse(value) as Object;
        if (Array.isArray(parsed)) {
          const arr = parsed as string[];
          for (let i = 0; i < arr.length && out.length < 30; i++) {
            out.push(String(arr[i]));
          }
          return out;
        }
        if (typeof parsed === 'string') {
          value = parsed as string;
          continue;
        }
        return out;
      } catch (e) {
        hilog.warn(0x0000, TAG, 'list parse failed');
        return out;
      }
    }
    return out;
  }

  private pickSession(i: number): void {
    this.js(
      '(function(){try{return window.__dshClickSession?window.__dshClickSession(' + i + '):"nodrawer";' +
      '}catch(e){return "ERR";}})()')
      .then((r: string) => { hilog.info(0x0000, TAG, 'pick %{public}s', r); })
      .catch(() => {});
    this.drawerOpen = false;
  }

  @Builder
  sessionsDrawer() {
    Column() {
      Row() {
        Text('Sessions').fontSize(15).fontWeight(FontWeight.Medium)
        Blank()
        Button('Close')
          .fontSize(11).height(26).padding({ left: 10, right: 10 })
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => { this.drawerOpen = false; })
      }
      .width('100%').height(44).padding({ left: 14, right: 10 })

      List({ space: 2 }) {
        ListItem() {
          Text('＋ New session').fontSize(14).fontColor('#0A59F7')
            .width('100%').padding({ left: 14, top: 12, bottom: 12 })
        }
        .onClick(() => this.pickSession(-1))

        if (this.sessionsList.length === 0) {
          ListItem() {
            Text('No sessions in this workspace').fontSize(12).fontColor('#999999')
              .width('100%').padding({ left: 14, top: 16, bottom: 16 })
          }
        }
        ForEach(this.sessionsList, (title: string, idx: number) => {
          ListItem() {
            Column({ space: 2 }) {
              Text(title).fontSize(14).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .padding({ left: 14, right: 12, top: 10, bottom: 10 })
            }
            .width('100%')
          }
          .onClick(() => this.pickSession(idx))
        }, (title: string, idx: number) => title + idx.toString())
      }
      .layoutWeight(1).width('100%')
    }
    .width('82%').height('100%')
    .backgroundColor('#FFFFFF')
    .onClick(() => {})
    .alignItems(HorizontalAlign.Start)
  }

  private probeSidebar(): void {
    this.js(
      '(function(){try{var col=document.querySelector("div[class*=_sidebarCol]");' +
      'if(!col){return "no sidebar col";}' +
      'var rows=[],all=col.querySelectorAll("*");' +
      'for(var i=0;i<all.length&&rows.length<12;i++){var e=all[i];' +
      'var t=(e.innerText||"").replace(/\s+/g," ").trim();' +
      'if(t.length<2||t.length>48)continue;' +
      'var r=e.getBoundingClientRect();' +
      'rows.push({tag:e.tagName,c:(e.className||"").toString().slice(0,26),' +
      'role:e.getAttribute("role")||"",h:Math.round(r.height),t:t.slice(0,34)});}' +
      'return JSON.stringify({n:rows.length,items:rows});}catch(e){return "ERR:"+e.message;}})()')
      .then((r: string) => { hilog.info(0x0000, TAG, 'sidebar %{public}s', r); })
      .catch(() => {});
  }

  private mirrorDrawer(): void {
    this.js(
      '(function(){try{if(window.__dshMirror){return "on";}window.__dshMirror=true;' +
      'var prev=document.body.classList.contains("dsh-mobile-drawer");' +
      'new MutationObserver(function(){' +
      'var cur=document.body.classList.contains("dsh-mobile-drawer");' +
      'if(cur===prev)return;prev=cur;' +
      'if(cur){document.body.classList.add("dsh-user-drawer");}' +
      'else{document.body.classList.remove("dsh-user-drawer");}' +
      '}).observe(document.body,{attributes:true,attributeFilter:["class"]});' +
      'return "mirror";}catch(e){return "ERR";}})()')
      .then((r: string) => { hilog.info(0x0000, TAG, 'mirror %{public}s', r); })
      .catch(() => {});
  }

  private auditButtons(): void {
    this.js(
      '(function(){try{' +
      'function byText(re){var all=document.querySelectorAll("body *");' +
      'for(var i=0;i<all.length;i++){var e=all[i];var t=(e.innerText||"").trim();' +
      'if(t.length&&t.length<40&&re.test(t)){var r=e.getBoundingClientRect();' +
      'if(r.width>20&&r.height>10)return e;}}return null;}' +
      'function tap(e,n){if(!e){console.log("DSHNAV miss "+n);return;}try{e.click();console.log("DSHNAV tap "+n);}catch(x){}}' +
      'tap(byText(/选择一个工作区/),"pick");' +
      'setTimeout(function(){var b=document.querySelectorAll("[class*=workspace],[class*=Workspace],li,[role=listitem]");' +
      'tap(b.length?b[0]:null,"ws1");' +
      'setTimeout(function(){var s=document.querySelectorAll("[class*=session],[class*=Session],[class*=history] li");' +
      'tap(s.length?s[0]:null,"session");' +
      'setTimeout(function(){measure();},1400);},1400);},1200);' +
      'function measure(){var vw=innerWidth,vh=innerHeight;var out={vw:vw,vh:vh,docH:document.documentElement.scrollHeight,' +
      'clipped:[],small:0,boxes:{},title:document.title.slice(0,26),textLen:(document.body.innerText||"").length};' +
      'var ta=document.querySelector("textarea,[contenteditable=true]");' +
      'if(ta){var r=ta.getBoundingClientRect();out.boxes.composer={x:Math.round(r.left),y:Math.round(r.top),' +
      'w:Math.round(r.width),h:Math.round(r.height),bottom:Math.round(r.bottom)};}' +
      'var all=document.querySelectorAll("body *");var w2=0;' +
      'var danger=/删除|清空|中断|停止|delete|clear|stop/i;' +
      'for(var i=0;i<all.length;i++){var e=all[i];if(!e.clientWidth&&!e.clientHeight)continue;' +
      'var cs=getComputedStyle(e);' +
      'if(e.scrollWidth>e.clientWidth+2&&cs.overflowX!=="visible"&&out.clipped.length<6){' +
      'out.clipped.push({c:(e.className||e.tagName).toString().slice(0,20),sw:e.scrollWidth,cw:e.clientWidth,' +
      't:(e.innerText||"").replace(/\s+/g," ").slice(0,22)});}' +
      'var rr=e.getBoundingClientRect();' +
      'if(rr.width>vw+2||rr.left<-2){w2++;}' +
      'if((e.tagName==="BUTTON"||e.getAttribute("role")==="button")&&rr.height>0&&rr.height<36&&!danger.test(e.innerText||""))out.small++;}' +
      'out.overflowX=w2;' +
      'console.log("DSHLAYOUT "+JSON.stringify(out));}' +
      'return "started";}catch(e){return "ERR:"+e.message;}})()')
      .then((r: string) => { hilog.info(0x0000, TAG, 'audit %{public}s', r); })
      .catch(() => {});
  }

  /** About: toggled as an ArkUI overlay (AlertDialog is unreliable on some devices). */
  private showAbout(): void {
    this.aboutOpen = !this.aboutOpen;
  }

  @Builder
  aboutCard() {
    Column({ space: 8 }) {
      Text('About Harness Mobile').fontSize(17).fontWeight(FontWeight.Medium)
      Text('Harness Mobile · 局域网版')
        .fontSize(12).fontColor('#666666').textAlign(TextAlign.Center).maxLines(2)
      Divider().margin({ top: 4, bottom: 4 })
      Text(this.developerName.length > 0 ? 'Developer: ' + this.developerName : 'Developer').fontSize(14)
      // Plain text on purpose: the standalone build must not open any link.
      Text('Repo: github.com/cnzht/dsh-mobile-harmony').fontSize(13).fontColor('#666666')
      Text('License: MIT').fontSize(13).fontColor('#666666')
      Text('可连接局域网内的自部署服务，或使用本地演示；不连接公共互联网，不提供 AI 生成服务。')
        .fontSize(11).fontColor('#999999').textAlign(TextAlign.Center).maxLines(4)
      Button('OK')
        .fontSize(13).height(38).width('100%').margin({ top: 8 })
        .backgroundColor('#0A59F7')
        .onClick(() => { this.aboutOpen = false; })
    }
    .width('86%')
    .padding(20)
    .borderRadius(16)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }

  /** First-launch privacy consent (AGC review §7.5): same root-overlay pattern as About. */
  @Builder
  privacyCard() {
    Column({ space: 10 }) {
      Text('隐私政策').fontSize(17).fontWeight(FontWeight.Medium)
      Text('使用 Harness Mobile 前，请阅读隐私政策与用户协议。')
        .fontSize(13).fontColor('#333333').maxLines(3)
      Text('本应用仅连接局域网内的服务器，不连接公共互联网；不收集任何个人信息。服务器地址与访问令牌仅保存在设备本地，仅用于连接你指定的局域网服务器；会话内容只在你与你的服务器之间传输。')
        .fontSize(12).fontColor('#666666').maxLines(6)
      Row({ space: 16 }) {
        Text('隐私政策').fontSize(13).fontColor('#0A59F7')
          .decoration({ type: TextDecorationType.Underline, color: '#0A59F7' })
          .onClick(() => this.openPrivacyPage())
        Text('用户协议').fontSize(13).fontColor('#0A59F7')
          .decoration({ type: TextDecorationType.Underline, color: '#0A59F7' })
          .onClick(() => this.openEulaPage())
      }
      if (this.privacyDeclined) {
        Text('需要同意隐私政策才能使用本应用。')
          .fontSize(12).fontColor('#E84026').maxLines(2)
      }
      Button('同意').fontSize(13).height(38).width('100%').margin({ top: 4 })
        .backgroundColor('#0A59F7')
        .onClick(() => this.acceptPrivacy())
      Row({ space: 12 }) {
        Button('不同意').fontSize(12).height(32).layoutWeight(1)
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => this.declinePrivacy())
        Button('暂不使用').fontSize(12).height(32).layoutWeight(1)
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => this.openPrivacyLater())
      }
      .width('100%')
    }
    .width('86%')
    .padding(20)
    .borderRadius(16)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  setupView() {
    // Scrollable: the old fixed Column clipped its own content (title/notes cut off)
    // whenever the content was taller than the viewport.
    Scroll() {
      Column({ space: 14 }) {
        Text('Harness Mobile').fontSize(32).fontWeight(FontWeight.Bold)
        Text('局域网版 · 仅连接局域网内的服务器')
          .fontSize(13).fontColor('#666666').textAlign(TextAlign.Center)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        TextInput({ placeholder: 'http://192.168.x.x:<port>/?token=...', text: $$this.draft })
          .width('100%').height(48).margin({ top: 10 })
        Button('Connect').width('100%').height(44).onClick(() => this.connect())
        Button('Scan QR code')
          .width('100%').height(44)
          .backgroundColor('#0A59F7')
          .onClick(() => this.scan())
        Button('使用本地演示')
          .width('100%').height(44)
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => this.useLocalDemo())
        if (this.hint.length > 0) {
          Text(this.hint).fontSize(13).fontColor('#E84026')
            .textAlign(TextAlign.Center).width('100%').maxLines(3)
        }
        if (this.error.length > 0) {
          Text(this.error).fontSize(13).fontColor('#E84026')
            .textAlign(TextAlign.Center).width('100%').maxLines(2)
        }
        if (this.privacyDeclined) {
          Row({ space: 8 }) {
            Text('使用前请先阅读并同意隐私政策。').fontSize(12).fontColor('#E84026').layoutWeight(1)
            Button('查看').fontSize(12).height(28).padding({ left: 12, right: 12 })
              .backgroundColor('#0A59F7')
              .onClick(() => { this.privacyOpen = true; })
          }
          .width('100%')
        }
        Text('仅支持局域网地址（10.x.x.x、172.16–31.x.x.x、192.168.x.x、localhost），不连接公共互联网。在同一局域网的电脑或服务器上运行 `dsh web`，再粘贴它打印的 URL；token 是一次性的。')
          .fontSize(12).fontColor('#999999').textAlign(TextAlign.Center)
          .width('100%').maxLines(4)
        Row({ space: 16 }) {
          Text('隐私政策').fontSize(12).fontColor('#0A59F7')
            .decoration({ type: TextDecorationType.Underline, color: '#0A59F7' })
            .onClick(() => this.openPrivacyPage())
          Text('用户协议').fontSize(12).fontColor('#0A59F7')
            .decoration({ type: TextDecorationType.Underline, color: '#0A59F7' })
            .onClick(() => this.openEulaPage())
        }
        .margin({ top: 2 })
        Button('About')
          .fontSize(12).height(30).padding({ left: 16, right: 16 })
          .backgroundColor('#EBECEF').fontColor('#182431')
          .margin({ bottom: 12 })
          .onClick(() => this.showAbout())
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 40, bottom: 40 })
    }
    .width('100%').height('100%')
    .align(Alignment.Center)
    .scrollBar(BarState.Off)
    .backgroundColor('#F5F5F7')
  }

  @Builder
  demoView() {
    Column() {
      // Slim opaque bar instead of a floating translucent pill: the pill sat on
      // top of the page and read as a permanent overlay ("蒙层").
      Row() {
        Button(this.drawerOpen ? 'Close' : 'Sessions')
          .fontSize(11).height(28).padding({ left: 10, right: 10 })
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => this.toggleSessions())
        // Explicit AI-generated-content label (AGC review): the demo page shows
        // static sample text, and the label stays so the in-app labelling is
        // identical to the online variant.
        Text('AI 生成内容')
          .fontSize(10).fontColor('#B25E00')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#FFF4E0').borderRadius(4)
        Blank()
        Button('连接')
          .fontSize(11).height(28).padding({ left: 10, right: 10 })
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => { this.showSetup = true; })
        Button('i')
          .fontSize(11).height(28).padding({ left: 10, right: 10 })
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => this.showAbout())
      }
      .width('100%').height(34).padding({ left: 12, right: 10 })

      Stack() {
        Web({ src: this.pageSrc, controller: this.controller })
          .width('100%').height('100%')
          .domStorageAccess(true)
          .javaScriptAccess(true)
          .fileAccess(true)
          .onPageBegin(() => {
            this.webAlive = true;
            this.loading = true;
          })
          .onPageEnd(() => {
            this.loading = false;
          })
        if (this.aboutOpen) {
          Column() {
            this.aboutCard()
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#66000000')
          .onClick(() => { this.aboutOpen = false; })
        }
        if (this.drawerOpen) {
          Row() {
            this.sessionsDrawer()
            Blank()
          }
          .width('100%').height('100%')
          .backgroundColor('#33000000')
          .onClick(() => { this.drawerOpen = false; })
        }
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(52).height(52).color('#0A59F7')
            Text('正在加载本地演示…').fontSize(13).fontColor('#666666')
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F5F5F7')
        }
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%')
  }

  @Builder
  webView() {
    Column() {
      // Slim opaque bar instead of a floating translucent pill: the pill sat on
      // top of the dsh UI and read as a permanent overlay ("蒙层").
      Row() {
        Button(this.drawerOpen ? 'Close' : 'Sessions')
          .fontSize(11).height(28).padding({ left: 10, right: 10 })
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => this.toggleSessions())
        // Explicit AI-generated-content label (AGC review): the chat content in
        // the WebView is generated by the user's own deployed service; this app
        // only renders it and provides no AI generation itself.
        Text('AI 生成内容')
          .fontSize(10).fontColor('#B25E00')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#FFF4E0').borderRadius(4)
        Blank()
        Button('i')
          .fontSize(11).height(28).padding({ left: 10, right: 10 })
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => this.showAbout())
        Button('Setup')
          .fontSize(11).height(28).padding({ left: 12, right: 12 })
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => this.backToSetup())
      }
      .width('100%').height(34).padding({ left: 12, right: 10 })

      Stack() {
        Web({ src: this.url, controller: this.controller })
          .width('100%').height('100%')
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .fileAccess(true)
        .mixedMode(MixedMode.All)
        // Chat page: the composer must stay visible when the soft keyboard opens,
        // so resize the layout viewport instead of overlaying it.
        .keyboardAvoidMode(WebKeyboardAvoidMode.RESIZE_CONTENT)
        .onPageBegin(() => {
          this.webAlive = true;
          this.loading = true;
          if (this.early.length > 0) {
            this.js(this.early).catch(() => {});
          }
        })
        .onPageEnd((e: OnPageEndEvent) => {
          this.loading = false;
          this.stopConnectWatchdog();
          this.injectOnce(e.url);
        })
        .onErrorReceive((e: OnErrorReceiveEvent) => {
          // Subresource failures are routine on a chat page (CDN/offline assets);
          // only a failed main frame means "that server is not reachable".
          if (e.request.isMainFrame()) {
            this.handleConnectFailure();
          }
        })
        .onHttpErrorReceive((e: OnHttpErrorReceiveEvent) => {
          const code = e.response.getResponseCode();
          if ((code === 401 || code === 403) && e.request.isMainFrame()) {
            this.handleHttpError(e.request.getRequestUrl());
          }
        })
        if (this.aboutOpen) {
          Column() {
            this.aboutCard()
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#66000000')
          .onClick(() => { this.aboutOpen = false; })
        }
        if (this.drawerOpen) {
          Row() {
            this.sessionsDrawer()
            Blank()
          }
          .width('100%').height('100%')
          .backgroundColor('#33000000')
          .onClick(() => { this.drawerOpen = false; })
        }
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(52).height(52).color('#0A59F7')
            Text('Connecting...').fontSize(13).fontColor('#666666')
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F5F5F7')
        }
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%')
  }

  @Builder
  policyView() {
    Column() {
      Row() {
        Button('‹ 返回')
          .fontSize(11).height(28).padding({ left: 10, right: 10 })
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => this.backToDemo())
        Blank()
        Text('隐私政策 / 用户协议').fontSize(12).fontColor('#666666')
      }
      .width('100%').height(34).padding({ left: 12, right: 10 })

      Web({ src: this.pageSrc, controller: this.controller })
        .width('100%').height('100%')
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .fileAccess(true)
    }
    .width('100%').height('100%')
  }

  build() {
    Stack() {
      Column() {
        if (this.onPolicyPage) {
          this.policyView()
        } else if (this.url.length > 0) {
          this.webView()
        } else if (this.showSetup) {
          this.setupView()
        } else {
          this.demoView()
        }
      }
      .width('100%').height('100%')

      if (this.aboutOpen) {
        Column() {
          this.aboutCard()
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#66000000')
        .onClick(() => { this.aboutOpen = false; })
      }

      // First-launch privacy consent: no tap-outside dismiss — the user must
      // pick 同意 / 不同意 / 暂不使用 explicitly.
      if (this.privacyOpen) {
        Column() {
          this.privacyCard()
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#66000000')
      }
    }
    .width('100%').height('100%')
  }
}
