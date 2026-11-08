import { webview } from '@kit.ArkWeb';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { scanBarcode } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'DshMobile';

/*
 * HarmonyOS port of deepseek-harness-mobile.
 * Upstream runs `dsh web` inside a proot Ubuntu container on the phone.
 * HarmonyOS has no proot/root container, so this port keeps what matters:
 * the mobile adaptation layer (early-polyfill.js / inject.js / mobile.css)
 * injected into a dsh web UI served by a host on the LAN.
 */
@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State url: string = '';
  @State draft: string = '';
  @State error: string = '';
  @State hint: string = '';
  private early: string = '';
  private inject: string = '';
  private css: string = '';
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
      this.css = decoder.decodeToString(rm.getRawFileContentSync('mobile.css'));
    } catch (e) {
      hilog.error(0x0000, TAG, 'read rawfile failed: %{public}s', JSON.stringify(e));
    }
  }

  private loadPrefs(): void {
    preferences.getPreferences(this.getUIContext().getHostContext()!, 'dsh_mobile')
      .then((p: preferences.Preferences) => {
        this.prefs = p;
        const saved = p.getSync('serverUrl', '') as string;
        if (saved.length > 0) {
          this.draft = saved;
        }
      })
      .catch((e: Error) => {
        hilog.warn(0x0000, TAG, 'prefs unavailable: %{public}s', e.message);
      });
  }

  private connect(): void {
    const target = this.draft.trim();
    if (target.length === 0) {
      this.error = 'Please enter the dsh web URL';
      return;
    }
    this.error = '';
    this.hint = '';
    this.lastInjectedUrl = '';
    this.url = target;
    if (this.prefs !== undefined) {
      this.prefs.putSync('serverUrl', target);
      this.prefs.flush();
    }
  }

  private styleScript(): string {
    // Upstream mobile.css turns the left sidebar into an overlay drawer whenever
    // dsh's sidebar is expanded, which it is on first paint at phone widths — so
    // the drawer (and its scrim) appears by itself. Fighting the class made
    // inject.js re-add it on every mutation (measured: open/close/open every
    // ~500ms). Instead pin the visuals: never show the drawer or scrim unless we
    // explicitly opt in with body.dsh-user-drawer.
    const overrides = 'div[class*="_sidebarCol"]{display:none!important}' +
      '#dsh-mobile-drawer-mask{display:none!important}' +
      'body.dsh-user-drawer div[class*="_sidebarCol"]{display:flex!important;position:fixed!important;' +
      'left:0;top:0;bottom:0;width:82vw!important;max-width:82vw!important;z-index:2147483600!important;' +
      'box-shadow:0 0 24px rgba(0,0,0,.28)!important;overflow:auto!important;background:#fff!important}';
    return '(function(){var id="dsh-mobile-css";var old=document.getElementById(id);if(old){old.remove();}' +
      'var s=document.createElement("style");s.id=id;s.textContent=' + JSON.stringify(this.css) + ';' +
      '(document.head||document.documentElement).appendChild(s);' +
      'var oid="dsh-mobile-override";var o=document.getElementById(oid);if(o){o.remove();}' +
      'var s2=document.createElement("style");s2.id=oid;s2.textContent=' + JSON.stringify(overrides) + ';' +
      '(document.head||document.documentElement).appendChild(s2);' +
      'if(!window.__dshOutsideTap){window.__dshOutsideTap=true;' +
      'document.addEventListener("click",function(ev){' +
      'if(!document.body.classList.contains("dsh-user-drawer"))return;' +
      'var p=document.querySelector("div[class*=_sidebarCol]");' +
      'if(p&&p.contains(ev.target))return;' +
      'document.body.classList.remove("dsh-user-drawer");},true);}' +
      '})();';
  }

  /**
   * Apply the upstream mobile adaptation layer exactly once per document.
   * dsh's token entry redirects (token -> cookie -> app route), so onPageEnd
   * fires for intermediate hops; re-running inject.js on each hop re-applies the
   * sidebar gating rules and makes the right sidebar slide in repeatedly.
   */
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
    this.controller.runJavaScript(guarded)
      .catch((e: Error) => {
        hilog.warn(0x0000, TAG, 'inject failed: %{public}s', e.message);
      });
    // Probe the drawer/rightbar state once the upstream script settled.
    setTimeout(() => {
      this.controller.runJavaScript(
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
      this.controller.runJavaScript(
        '(function(){try{var w=innerWidth,out=[];var all=document.querySelectorAll("body *");' +
        'for(var i=0;i<all.length&&out.length<6;i++){var e=all[i];var r=e.getBoundingClientRect();' +
        'if(r.width===0&&r.height===0)continue;' +
        'if(r.right>w+2||r.left<-2||r.width>w+2){' +
        'out.push((e.className&&e.className.toString().slice(0,26)||e.tagName)+"|x"+Math.round(r.left)+' +
        '"|w"+Math.round(r.width)+"|r"+Math.round(r.right));}}' +
        'return JSON.stringify({w:w,n:out.length,items:out});}catch(e){return "ERR:"+e.message;}})()')
        .then((r: string) => { hilog.info(0x0000, TAG, 'overflow %{public}s', r); })
        .catch(() => {});
    }, 1500);
    this.settle();
  }

  /**
   * No class fighting: the sidebar column and its scrim are pinned by the CSS
   * overrides in styleScript(). dsh expands the sidebar on first paint at phone
   * widths, and upstream inject.js mirrors that into a drawer; removing the class
   * made it re-add on every mutation (measured open/close/open every ~500ms), so
   * we keep the state stable and only reveal the drawer on explicit request.
   */
  private settle(): void {
    setTimeout(() => {
      this.controller.runJavaScript(
        '(function(){try{var m=document.getElementById("dsh-mobile-drawer-mask");' +
        'if(m){m.style.display="none";}document.body.classList.remove("dsh-user-drawer");' +
        'return "ok";}catch(e){return "ERR";}})()')
        .then((r: string) => { hilog.info(0x0000, TAG, 'settle %{public}s', r); })
        .catch(() => {});
    }, 1200);
  }

  /** Reveal/hide the sessions drawer on demand (our own opt-in class). */
  private toggleSessions(): void {
    this.controller.runJavaScript(
      '(function(){try{document.body.classList.toggle("dsh-user-drawer");' +
      'return document.body.classList.contains("dsh-user-drawer")?"open":"closed";' +
      '}catch(e){return "ERR";}})()')
      .then((r: string) => { hilog.info(0x0000, TAG, 'sessions %{public}s', r); })
      .catch(() => {});
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
    this.draft = this.url;
    this.url = '';
    this.lastInjectedUrl = '';
  }

  /**
   * Open the system scanner and use the decoded URL directly.
   * The host prints a QR of `<base>/?token=<single-use token>`; scanning it is
   * the fastest path because the token never has to be typed or read.
   */
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

  @Builder
  setupView() {
    Column({ space: 16 }) {
      Text('DSH Mobile').fontSize(34).fontWeight(FontWeight.Bold)
      Text('HarmonyOS port · connect to a dsh web host').fontSize(14).fontColor('#666666')
      TextInput({ placeholder: 'http://<host>:<port>/?token=...', text: $$this.draft })
        .width('100%').height(48).margin({ top: 12 })
      Button('Connect').width('100%').height(44).onClick(() => this.connect())
      Button('Scan QR code')
        .width('100%').height(44)
        .backgroundColor('#0A59F7')
        .onClick(() => this.scan())
      if (this.hint.length > 0) {
        Text(this.hint).fontSize(13).fontColor('#E84026').textAlign(TextAlign.Center)
      }
      if (this.error.length > 0) {
        Text(this.error).fontSize(13).fontColor('#E84026')
      }
      Text('Run `dsh web` on a PC/server, then paste the URL it prints.\nThe token is single-use; a server restart issues a new one.')
        .fontSize(12).fontColor('#999999').textAlign(TextAlign.Center).margin({ top: 8 })
    }
    .width('100%').height('100%').padding(28).justifyContent(FlexAlign.Center)
    .backgroundColor('#F5F5F7')
  }

  @Builder
  webView() {
    Column() {
      // Slim opaque bar instead of a floating translucent pill: the pill sat on
      // top of the dsh UI and read as a permanent overlay ("蒙层").
      Row() {
        Text('DSH Mobile').fontSize(13).fontColor('#666666')
        Blank()
        Button('Setup')
          .fontSize(12).height(30).padding({ left: 14, right: 14 })
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => {
            this.lastInjectedUrl = '';
            this.url = '';
          })
      }
      .width('100%').height(44).padding({ left: 16, right: 12 })
      .backgroundColor('#FFFFFF')

      Web({ src: this.url, controller: this.controller })
        .layoutWeight(1).width('100%')
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .fileAccess(true)
        .mixedMode(MixedMode.All)
        .onPageBegin(() => {
          if (this.early.length > 0) {
            this.controller.runJavaScript(this.early).catch(() => {});
          }
        })
        .onPageEnd((e: OnPageEndEvent) => {
          this.injectOnce(e.url);
        })
        .onHttpErrorReceive((e: OnHttpErrorReceiveEvent) => {
          const code = e.response.getResponseCode();
          if ((code === 401 || code === 403) && e.request.isMainFrame()) {
            this.handleHttpError(e.request.getRequestUrl());
          }
        })
    }
    .width('100%').height('100%')
  }

  build() {
    Column() {
      if (this.url.length === 0) {
        this.setupView()
      } else {
        this.webView()
      }
    }
    .width('100%').height('100%')
  }
}
