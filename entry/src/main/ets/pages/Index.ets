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
  @State url: string = 'https://gulf-sunglasses-forums-vinyl.trycloudflare.com/?token=M3_gVrDPLtXmFTZHyQ2en57TIMJtdcillHffdgwdbwY';
  @State draft: string = '';
  @State error: string = '';
  @State hint: string = '';
  @State loading: boolean = false;
  @State sessionsOpen: boolean = false;
  @State sessionsList: string[] = [];
  @State drawerOpen: boolean = false;
  @State aboutOpen: boolean = false;
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
    this.loading = true;
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
    const overrides = 'body:not(.dsh-user-drawer) div[class*="_sidebarCol"]{display:none!important}' +
      '#dsh-mobile-drawer-mask{display:none!important}' +
      'body.dsh-user-drawer div[class*="_sidebarCol"]{z-index:2147483600!important;' +
      'box-shadow:0 0 24px rgba(0,0,0,.25)!important;background:#fff!important}' +
      'button,[role=button]{min-height:40px!important}' +
      'body{padding-bottom:env(safe-area-inset-bottom,0px)!important}' +
      '[class*=label],[class*=title],[class*=name]{overflow-wrap:break-word!important}' +
      'textarea,[contenteditable=true]{max-height:32vh!important;overflow-y:auto!important}';
    return '(function(){var id="dsh-mobile-css";var old=document.getElementById(id);if(old){old.remove();}' +
      'var s=document.createElement("style");s.id=id;s.textContent=' + JSON.stringify(this.css) + ';' +
      '(document.head||document.documentElement).appendChild(s);' +
      'var oid="dsh-mobile-override";var o=document.getElementById(oid);if(o){o.remove();}' +
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
      'if(!window.__dshSessionRows){window.__dshSessionRows=function(){' +'var col=document.querySelector("div[class*=_sidebarCol]");if(!col){return [];}' +'var bs=col.querySelectorAll("button"),out=[];var skip=/^(\\u65b0\\u4f1a\\u8bdd|\\u63d2\\u4ef6|\\u81ea\\u52a8\\u5316\\u4efb\\u52a1|\\u66f4\\u591a|\\u8bbe\\u7f6e|\\u641c\\u7d22)$/;' +'for(var i=0;i<bs.length;i++){var b=bs[i];var t=(b.innerText||"").replace(/\\s+/g," ").trim();' +'if(!t||t.length>60)continue;if(skip.test(t))continue;out.push(b);}' +'return out;};' +'window.__dshListSessions=function(){try{var r=window.__dshSessionRows();var t=[];' +'for(var i=0;i<r.length;i++){t.push((r[i].innerText||"").replace(/\\s+/g," ").trim().slice(0,60));}' +'return JSON.stringify(t);}catch(e){return "[]";}};' +'window.__dshClickSession=function(i){try{if(i<0){var c=document.querySelector("div[class*=_sidebarCol]");' +'var nb=c?c.querySelector("button[class*=newSession]"):null;if(nb){nb.click();return "new";}return "none";}' +'var r=window.__dshSessionRows();if(i>=r.length){return "oob";}r[i].click();return "ok";}catch(e){return "ERR";}};' +      '})();'
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
      this.controller.runJavaScript(
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

  /**
   * dsh expands the sidebar on first paint, so upstream inject.js arms its drawer
   * and the scrim shows by itself. Deleting the class made inject.js re-add it on
   * every mutation (measured open/close flipping every ~500ms), so instead drive
   * upstream's own close path once: clicking the scrim runs its collapse animation
   * and leaves dsh genuinely collapsed. Afterwards mirror later open/close into our
   * own opt-in class, which is what the styleScript overrides key on.
   */
  private settle(): void {
    setTimeout(() => {
      this.controller.runJavaScript(
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

  /**
   * Open/close the sessions drawer ourselves.
   * Verified on device: adding body.dsh-user-drawer lifts our CSS hold, and then
   * dsh's own "open sidebar" control gives the column a real 311x699 box; the scrim
   * dsh renders closes it again, and we drop our class on that tap.
   */
  /** Open the native sessions drawer: pull titles from dsh, render natively. */
  private toggleSessions(): void {
    if (this.drawerOpen) {
      this.drawerOpen = false;
      return;
    }
    this.controller.runJavaScript(
      '(function(){try{return window.__dshListSessions?window.__dshListSessions():"[]";' +
      '}catch(e){return "[]";}})()')
      .then((r: string) => {
        this.sessionsList = this.toTitleList(r);
        this.drawerOpen = true;
      })
      .catch(() => {
        this.sessionsList = [];
        this.drawerOpen = true;
      });
  }

  /** Robustly turn the injected JSON (or anything else) into a string[] of titles. */
  private toTitleList(raw: string): string[] {
    const out: string[] = [];
    if (raw.length === 0) {
      return out;
    }
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (Array.isArray(parsed)) {
        const arr = parsed as string[];
        for (let i = 0; i < arr.length && out.length < 30; i++) {
          out.push(String(arr[i]));
        }
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'list parse failed');
    }
    return out;
  }

  private pickSession(i: number): void {
    this.controller.runJavaScript(
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


  /** Leave the chat view: collapse the drawer state before returning to setup. */
  private backToSetup(): void {
    this.sessionsOpen = false;
    this.loading = false;
    this.lastInjectedUrl = '';
    this.url = '';
  }
  /** Debug: dump the dsh sidebar row structure (data source for the native drawer). */
  private probeSidebar(): void {
    this.controller.runJavaScript(
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

  /** Mirror upstream drawer state into our opt-in class so the panel may render. */
  private mirrorDrawer(): void {
    this.controller.runJavaScript(
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
  /**
   * Debug: walk workspace/session selection, then measure the chat page layout
   * (composer geometry, clipped text, overflow, small tap targets).
   */
  private auditButtons(): void {
    this.controller.runJavaScript(
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

  /** About: toggled as an ArkUI overlay (AlertDialog is unreliable on some devices). */
  private showAbout(): void {
    this.aboutOpen = !this.aboutOpen;
  }

  @Builder
  aboutCard() {
    Column({ space: 8 }) {
      Text('About DSH Mobile').fontSize(17).fontWeight(FontWeight.Medium)
      Text('HarmonyOS port of deepseek-harness-mobile')
        .fontSize(12).fontColor('#666666').textAlign(TextAlign.Center).maxLines(2)
      Divider().margin({ top: 4, bottom: 4 })
      Text('Author: \u6c9b\u6c9b0518').fontSize(14)
      Text('Repo: github.com/cnzht/dsh-mobile-harmony').fontSize(13).fontColor('#0A59F7')
        .onClick(() => this.openGithub())
      Text('License: MIT').fontSize(13).fontColor('#666666')
      Text('Personal experimental project, not affiliated with DeepSeek or Huawei. Use at your own risk.')
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

  private openGithub(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ctx.openLink('https://github.com/cnzht')
      .catch((e: Error) => {
        hilog.warn(0x0000, TAG, 'openLink failed: %{public}s', e.message);
        this.hint = 'Cannot open browser';
      });
  }

  @Builder
  setupView() {
    // Scrollable: the old fixed Column clipped its own content (title/notes cut off)
    // whenever the content was taller than the viewport.
    Scroll() {
      Column({ space: 14 }) {
        Text('DSH Mobile').fontSize(32).fontWeight(FontWeight.Bold)
        Text('HarmonyOS port · connect to a dsh web host')
          .fontSize(13).fontColor('#666666').textAlign(TextAlign.Center)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        TextInput({ placeholder: 'http://<host>:<port>/?token=...', text: $$this.draft })
          .width('100%').height(48).margin({ top: 10 })
        Button('Connect').width('100%').height(44).onClick(() => this.connect())
        Button('Scan QR code')
          .width('100%').height(44)
          .backgroundColor('#0A59F7')
          .onClick(() => this.scan())
        if (this.hint.length > 0) {
          Text(this.hint).fontSize(13).fontColor('#E84026')
            .textAlign(TextAlign.Center).width('100%').maxLines(3)
        }
        if (this.error.length > 0) {
          Text(this.error).fontSize(13).fontColor('#E84026')
            .textAlign(TextAlign.Center).width('100%').maxLines(2)
        }
        Text('Run `dsh web` on a PC/server, then paste the URL it prints. The token is single-use.')
          .fontSize(12).fontColor('#999999').textAlign(TextAlign.Center)
          .width('100%').maxLines(4)
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.link')).fontSize(15).fontColor(['#0A59F7'])
          Text('github.com/cnzht')
            .fontSize(13).fontColor('#0A59F7')
            .decoration({ type: TextDecorationType.Underline, color: '#0A59F7' })
        }
        .margin({ top: 6 })
        .onClick(() => this.openGithub())
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
  webView() {
    Column() {
      // Slim opaque bar instead of a floating translucent pill: the pill sat on
      // top of the dsh UI and read as a permanent overlay ("蒙层").
      Row() {
        Button(this.sessionsOpen ? 'Close' : 'Sessions')
          .fontSize(11).height(28).padding({ left: 10, right: 10 })
          .backgroundColor('#EBECEF').fontColor('#182431')
          .onClick(() => this.toggleSessions())
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
          this.loading = true;
          if (this.early.length > 0) {
            this.controller.runJavaScript(this.early).catch(() => {});
          }
        })
        .onPageEnd((e: OnPageEndEvent) => {
          this.loading = false;
          this.injectOnce(e.url);
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

  build() {
    Stack() {
      Column() {
        if (this.url.length === 0) {
          this.setupView()
        } else {
          this.webView()
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
    }
    .width('100%').height('100%')
  }
}
