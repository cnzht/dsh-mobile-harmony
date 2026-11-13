import { webview } from '@kit.ArkWeb';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
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

/*
 * Standalone (offline-only) variant of Harness Mobile.
 *
 * There is no server in this build and no account of any kind: the home
 * screen is a static demo page bundled in rawfile (local-demo.html), the
 * app requests no permissions and makes no network requests at all.
 * Privacy policy and user agreement are bundled as local files too
 * (privacy.html / eula.html in rawfile) and shown inside the WebView.
 * The native Sessions drawer, About card and first-launch privacy consent
 * dialog are kept from the online variant; the drawer reads its titles
 * from the demo page itself (window.__dshListSessions /
 * window.__dshClickSession, defined in local-demo.html).
 */
@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  /** Local demo page bundled in rawfile; policy pages replace it temporarily. */
  @State pageSrc: string = $rawfile('local-demo.html');
  /** True while a bundled policy/agreement page is shown instead of the demo. */
  @State onPolicyPage: boolean = false;
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
  private prefs: preferences.Preferences | undefined = undefined;

  aboutToAppear(): void {
    this.readAssets();
    this.loadPrefs();
  }

  private readAssets(): void {
    // Developer name is read in its own try/catch on purpose: the config file
    // is local-only (see developer.json.example), so a missing file must never
    // break the page — the About card then shows a bare label.
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

  /** First-launch privacy consent: record agreement and close the dialog. */
  private acceptPrivacy(): void {
    this.privacyOpen = false;
    this.privacyDeclined = false;
    if (this.prefs !== undefined) {
      this.prefs.putSync('privacyAccepted', true);
      this.prefs.flush();
    }
  }

  /** "不同意": keep the dialog open and show that consent is required to use the app. */
  private declinePrivacy(): void {
    this.privacyDeclined = true;
  }

  /** "暂不使用": close the dialog; the privacy dialog reopens on next launch. */
  private openPrivacyLater(): void {
    this.privacyOpen = false;
  }

  /** Show the bundled privacy policy in the WebView; the top bar offers a way back. */
  private openPrivacyPage(): void {
    this.pageSrc = $rawfile('privacy.html');
    this.onPolicyPage = true;
    this.privacyOpen = false;
  }

  /** Show the bundled user agreement in the WebView; the top bar offers a way back. */
  private openEulaPage(): void {
    this.pageSrc = $rawfile('eula.html');
    this.onPolicyPage = true;
    this.privacyOpen = false;
  }

  /** Return from a policy page to the local demo page. */
  private backToDemo(): void {
    this.pageSrc = $rawfile('local-demo.html');
    this.onPolicyPage = false;
  }

  /** Open the native sessions drawer: pull titles from the demo page, render natively. */
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

  /** About: toggled as an ArkUI overlay (AlertDialog is unreliable on some devices). */
  private showAbout(): void {
    this.aboutOpen = !this.aboutOpen;
  }

  @Builder
  aboutCard() {
    Column({ space: 8 }) {
      Text('About Harness Mobile').fontSize(17).fontWeight(FontWeight.Medium)
      Text('Harness Mobile · 本地单机演示版')
        .fontSize(12).fontColor('#666666').textAlign(TextAlign.Center).maxLines(2)
      Divider().margin({ top: 4, bottom: 4 })
      Text(this.developerName.length > 0 ? 'Developer: ' + this.developerName : 'Developer').fontSize(14)
      // Plain text on purpose: the standalone build must not open any link.
      Text('Repo: github.com/cnzht/dsh-mobile-harmony').fontSize(13).fontColor('#666666')
      Text('License: MIT').fontSize(13).fontColor('#666666')
      Text('演示页内容为本地静态示例，仅作功能演示；本应用不提供 AI 生成服务，也不连接任何服务器。')
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
      Text('本应用完全不联网，不收集任何个人信息，不连接任何服务器；隐私政策与用户协议均在应用本地查看。')
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
  demoView() {
    Column() {
      // Slim opaque bar instead of a floating translucent pill: the pill sat on
      // top of the page and read as a permanent overlay ("蒙层").
      Row() {
        if (this.onPolicyPage) {
          Button('‹ 返回演示')
            .fontSize(11).height(28).padding({ left: 10, right: 10 })
            .backgroundColor('#EBECEF').fontColor('#182431')
            .onClick(() => this.backToDemo())
        } else {
          Button(this.drawerOpen ? 'Close' : 'Sessions')
            .fontSize(11).height(28).padding({ left: 10, right: 10 })
            .backgroundColor('#EBECEF').fontColor('#182431')
            .onClick(() => this.toggleSessions())
        }
        // Explicit AI-generated-content label (AGC review): the demo page shows
        // static sample text, and the label stays so the in-app labelling is
        // identical to the online variant.
        Text('AI 生成内容')
          .fontSize(10).fontColor('#B25E00')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#FFF4E0').borderRadius(4)
        Blank()
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

  build() {
    Stack() {
      Column() {
        this.demoView()
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
