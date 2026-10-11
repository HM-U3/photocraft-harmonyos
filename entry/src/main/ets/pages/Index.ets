import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { ResourceBridge } from '../common/ResourceBridge';
import { AppConstants, RenderModes, RenderOption } from '../common/Constants';

/**
 * PhotoCraft 主页面
 *
 * 结构：一个全屏 Stack，底层是承载 WebAssembly 编辑引擎的 Web 组件，
 * 上层是根据窗口宽度自适应的原生外壳（PC 侧栏 / 平板顶栏 / 手机底栏）。
 */
@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: ResourceBridge | undefined = undefined;
  private mainWindow: window.Window | undefined = undefined;

  @StorageProp('engineState') engineState: string = AppConstants.STATE_IDLE;
  @StorageProp('engineMessage') engineMessage: string = '';
  @StorageProp('winWidthVp') winWidthVp: number = 0;
  @StorageProp('deviceType') deviceType: string = 'phone';
  @StorageLink('renderMode') renderMode: string = AppConstants.MODE_AUTO;
  // 原生桥写回的「保存 / 导出」结果，弹 toast 让用户知道文件去了哪
  @StorageProp('saveStatus') @Watch('onSaveStatus') saveStatus: string = '';

  @State pageLoaded: boolean = false;
  @State fatalError: string = '';
  @State sidebarExpanded: boolean = false;
  @State showAbout: boolean = false;
  @State showModePanel: boolean = false;
  @State fullScreen: boolean = false;
  @State statusText: string = '正在准备…';

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.bridge = new ResourceBridge(ctx);
    this.mainWindow = AppStorage.get<window.Window>('mainWindow');
    console.info('[PhotoCraft] Index aboutToAppear, renderMode=' + this.renderMode);
    // 兜底：即使页面事件未回调，也避免原生遮罩长期挡住网页自身的启动进度
    setTimeout(() => {
      if (!this.pageLoaded) {
        this.pageLoaded = true;
      }
    }, 3500);
  }

  aboutToDisappear(): void {
    if (this.bridge) {
      this.bridge.releaseCache();
    }
  }

  // ------------------------------------------------------------------
  // 布局尺寸
  // ------------------------------------------------------------------

  private effectiveWidth(): number {
    if (this.winWidthVp > 0) {
      return this.winWidthVp;
    }
    // 首帧兜底：按设备形态估算
    if (this.deviceType === '2in1') {
      return 1280;
    }
    if (this.deviceType === 'tablet') {
      return 900;
    }
    return 400;
  }

  private isWide(): boolean {
    return this.effectiveWidth() >= AppConstants.BREAKPOINT_WIDE;
  }

  private isMedium(): boolean {
    return this.effectiveWidth() >= AppConstants.BREAKPOINT_MEDIUM && !this.isWide();
  }

  private sidebarWidth(): number {
    if (!this.isWide()) {
      return 0;
    }
    return this.sidebarExpanded ? 216 : 64;
  }

  private topBarHeight(): number {
    return this.isMedium() ? 48 : 0;
  }

  private bottomBarHeight(): number {
    return (!this.isWide() && !this.isMedium()) ? 62 : 0;
  }

  // ------------------------------------------------------------------
  // 交互
  // ------------------------------------------------------------------

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 });
    } catch (err) {
      console.error('[PhotoCraft] toast 失败: ' + JSON.stringify(err));
    }
  }

  onSaveStatus(): void {
    if (this.saveStatus.length > 0) {
      this.toast(this.saveStatus);
    }
  }

  private reloadEngine(): void {
    this.fatalError = '';
    this.pageLoaded = false;
    this.statusText = '正在重新加载…';
    try {
      this.controller.refresh();
    } catch (err) {
      console.error('[PhotoCraft] 刷新失败: ' + JSON.stringify(err));
      this.toast('刷新失败，请重试');
    }
  }

  /**
   * 回到编辑器首页。
   *
   * 引擎内的「在 GitHub 上查看」这类外链如果真把页面顶掉了（宿主没接住、或用了
   * 其它跳转方式），引擎自己没有返回键，就只能杀掉应用重开。这里提供一个常驻出口：
   * 重新加载内置首页即可，正常情况下等价于一次刷新。
   */
  private backToEditor(): void {
    console.info('[PhotoCraft] backToEditor');
    this.fatalError = '';
    this.pageLoaded = false;
    this.statusText = '正在返回编辑器…';
    try {
      this.controller.loadUrl(AppConstants.WEB_ENTRY);
    } catch (err) {
      console.error('[PhotoCraft] 返回编辑器失败: ' + JSON.stringify(err));
      this.reloadEngine();
    }
  }

  private switchRenderMode(mode: string): void {
    this.showModePanel = false;
    if (mode === this.renderMode) {
      return;
    }
    this.renderMode = mode;
    this.fatalError = '';
    this.pageLoaded = false;
    this.statusText = '正在切换到 ' + RenderModes.label(mode) + '…';
    this.toast('渲染后端已切换为「' + RenderModes.label(mode) + '」，正在重启引擎');
    // 刷新页面，index.html 会重新向宿主查询渲染后端
    setTimeout(() => {
      try {
        this.controller.refresh();
      } catch (err) {
        console.error('[PhotoCraft] 切换后端失败: ' + JSON.stringify(err));
      }
    }, 120);
  }

  private openHelp(): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/Help' });
    } catch (err) {
      console.error('[PhotoCraft] 打开使用说明失败: ' + JSON.stringify(err));
      this.toast('无法打开使用说明');
    }
  }

  private toggleFullScreen(): void {
    const win = this.mainWindow;
    if (!win) {
      this.toast('当前环境不支持全屏切换');
      return;
    }
    this.fullScreen = !this.fullScreen;
    win.setWindowLayoutFullScreen(this.fullScreen).catch((err: BusinessError) => {
      console.error('[PhotoCraft] 全屏切换失败: ' + JSON.stringify(err));
    });
    // 2in1（PC）上同时切换窗口装饰栏
    try {
      if (this.deviceType === '2in1') {
        win.setWindowDecorVisible(!this.fullScreen);
      }
    } catch (err) {
      console.info('[PhotoCraft] setWindowDecorVisible 不可用: ' + JSON.stringify(err));
    }
    // 系统栏显隐
    try {
      win.setSpecificSystemBarEnabled('status', !this.fullScreen);
      win.setSpecificSystemBarEnabled('navigationIndicator', !this.fullScreen);
    } catch (err) {
      console.info('[PhotoCraft] 系统栏控制不可用: ' + JSON.stringify(err));
    }
  }

  private stateColor(): Resource {
    if (this.fatalError.length > 0 || this.engineState === AppConstants.STATE_ERROR) {
      return $r('app.color.danger');
    }
    if (this.engineState === AppConstants.STATE_READY) {
      return $r('app.color.accent');
    }
    return $r('app.color.text_secondary');
  }

  private engineStateLabel(): string {
    if (this.fatalError.length > 0) {
      return '启动失败';
    }
    if (this.engineState === AppConstants.STATE_READY) {
      return '引擎就绪 · ' + RenderModes.label(this.renderMode);
    }
    if (this.engineState === AppConstants.STATE_ERROR) {
      return '引擎报错';
    }
    if (this.engineState === AppConstants.STATE_LOADING) {
      return '正在加载引擎';
    }
    return '正在准备…';
  }

  // ------------------------------------------------------------------
  // 视图
  // ------------------------------------------------------------------

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. 编辑引擎承载区
      Column() {
        this.WebHost()
      }
      .width('100%')
      .height('100%')
      .padding({
        left: this.sidebarWidth(),
        top: this.topBarHeight(),
        bottom: this.bottomBarHeight()
      })
      .backgroundColor($r('app.color.shell_bg'))

      // 2. 自适应原生外壳
      if (this.isWide()) {
        this.SideBar()
      } else if (this.isMedium()) {
        this.TopBar()
      } else {
        this.BottomBar()
      }

      // 3. 页面首帧之前的原生过渡遮罩
      if (!this.pageLoaded && this.fatalError.length === 0 && this.engineState !== AppConstants.STATE_ERROR) {
        this.SplashOverlay()
      }

      // 4. 渲染后端选择面板
      if (this.showModePanel) {
        this.ModeOverlay()
      }

      // 5. 关于面板
      if (this.showAbout) {
        this.AboutOverlay()
      }

      // 6. 致命错误面板
      if (this.fatalError.length > 0 || this.engineState === AppConstants.STATE_ERROR) {
        this.ErrorOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.shell_bg'))
  }

  @Builder
  WebHost() {
    Web({ src: $rawfile('photocraft/index.html'), controller: this.controller })
      .width('100%')
      .height('100%')
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .imageAccess(true)
      .onlineImageAccess(true)
      .mixedMode(MixedMode.All)
      .cacheMode(CacheMode.Default)
      .zoomAccess(false)
      .horizontalScrollBarAccess(false)
      .verticalScrollBarAccess(false)
      .javaScriptProxy({
        object: this.bridge!,
        name: 'pcBridge',
        methodList: ['renderMode', 'deviceType', 'viewportWidth', 'reportState', 'assetSize', 'assetChunk', 'log',
          'beginSave', 'saveChunk', 'finishSave', 'openUrl'],
        controller: this.controller
      })
      .onPageBegin(() => {
        console.info('[PhotoCraft] onPageBegin');
      })
      .onPageEnd(() => {
        console.info('[PhotoCraft] onPageEnd');
        this.pageLoaded = true;
      })
      .onConsole((event) => {
        if (event) {
          console.info('[PhotoCraft][web] ' + event.message.getMessage());
        }
        return false;
      })
      .onErrorReceive((event) => {
        if (!event) {
          return;
        }
        try {
          const isMain: boolean = event.request.isMainFrame();
          const info: string = event.error.getErrorInfo();
          const code: number = event.error.getErrorCode();
          console.error('[PhotoCraft] 资源加载失败 main=' + isMain + ' code=' + code + ' info=' + info);
          if (isMain) {
            this.fatalError = '无法加载内置页面（code ' + code + '）：' + info;
          }
        } catch (err) {
          console.error('[PhotoCraft] 处理加载错误失败: ' + JSON.stringify(err));
        }
      })
  }

  // ---------------- 宽屏：左侧栏 ----------------

  @Builder
  SideBar() {
    Column() {
      // 品牌区
      Row() {
        Image($r('app.media.app_icon'))
          .width(38)
          .height(38)
          .borderRadius(10)
        if (this.sidebarExpanded) {
          Column() {
            Text('照片工坊')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text('PhotoCraft 引擎 · 鸿蒙版')
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 10 })
        }
      }
      .width('100%')
      .padding({ left: 13, right: 13, top: 16, bottom: 16 })

      Divider().color($r('app.color.divider')).strokeWidth(1)

      // 引擎状态灯 + 状态文字
      //
      // 收起态（64vp 图标条）里没有文字，只剩这颗 7vp 的圆点，必须显式水平居中：
      // Row 默认 justifyContent 是 FlexAlign.Start，圆点会贴到侧栏最左边（也就是屏幕
      // 左边缘）上，看上去就像一个没有来由的孤立小蓝点。
      // 顺手把整行做成可点的：收起时点一下提示当前状态，别让这个点"没有说明"。
      Column() {
        Row() {
          Circle()
            .width(7)
            .height(7)
            .fill(this.stateColor())
          if (this.sidebarExpanded) {
            Text(this.engineStateLabel())
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 8 })
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(this.sidebarExpanded ? FlexAlign.Start : FlexAlign.Center)
        // 展开态留左边距与文字对齐；收起态左右都留 0，居中才是真的居中
        .padding({ left: this.sidebarExpanded ? 16 : 0, right: this.sidebarExpanded ? 8 : 0 })
        .onClick(() => {
          if (!this.sidebarExpanded) {
            this.toast(this.engineStateLabel());
          }
        })
      }
      .width('100%')
      .height(34)
      .justifyContent(FlexAlign.Center)
      .alignItems(this.sidebarExpanded ? HorizontalAlign.Start : HorizontalAlign.Center)

      // 功能列表
      Column() {
        this.NavItem($r('app.media.ic_home'), '返回编辑器', '回到首页并重新加载', false, () => {
          this.backToEditor();
        })
        this.NavItem($r('app.media.ic_render'), '渲染后端', RenderModes.label(this.renderMode), true, () => {
          this.showModePanel = true;
        })
        this.NavItem($r('app.media.ic_reload'), '重新加载引擎', this.renderMode === AppConstants.MODE_CPU ? 'CPU 模式较慢' : '',
          false, () => {
            this.reloadEngine();
          })
        this.NavItem($r('app.media.ic_fullscreen'), this.fullScreen ? '退出全屏' : '全屏显示', '', false, () => {
          this.toggleFullScreen();
        })
      }
      .width('100%')
      .margin({ top: 6 })

      Blank()

      // 底部
      Column() {
        this.NavItem($r('app.media.ic_help'), '使用说明', '', false, () => {
          this.openHelp();
        })
        this.NavItem($r('app.media.ic_info'), '关于本应用', '', false, () => {
          this.showAbout = true;
        })
        this.NavItem(this.sidebarExpanded ? $r('app.media.ic_collapse') : $r('app.media.ic_expand'),
          this.sidebarExpanded ? '收起侧边栏' : '展开', '', false, () => {
            this.sidebarExpanded = !this.sidebarExpanded;
          })
        if (this.sidebarExpanded) {
          Text('v1.0.1 · 引擎 0.3.0')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 16, top: 4, bottom: 12 })
        } else {
          Blank().height(12)
        }
      }
      .width('100%')
    }
    .width(this.sidebarWidth())
    .height('100%')
    .backgroundColor($r('app.color.panel_bg'))
    .border({ width: { right: 1 }, color: $r('app.color.divider') })
    .alignItems(HorizontalAlign.Start)
  }

  // ---------------- 中屏：顶部栏 ----------------

  @Builder
  TopBar() {
    Row() {
      Image($r('app.media.app_icon'))
        .width(26)
        .height(26)
        .borderRadius(7)
      Text('照片工坊')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 9 })

      Row() {
        Circle().width(6).height(6).fill(this.stateColor())
        Text(this.engineStateLabel())
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 6 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .margin({ left: 12 })
      .layoutWeight(1)

      this.IconButton($r('app.media.ic_home'), () => {
        this.backToEditor();
      })
      this.IconButton($r('app.media.ic_render'), () => {
        this.showModePanel = true;
      })
      this.IconButton($r('app.media.ic_help'), () => {
        this.openHelp();
      })
      this.IconButton($r('app.media.ic_info'), () => {
        this.showAbout = true;
      })
    }
    .width('100%')
    .height(this.topBarHeight())
    .padding({ left: 14, right: 10 })
    .backgroundColor($r('app.color.panel_bg'))
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  // ---------------- 窄屏：底部栏 ----------------

  @Builder
  BottomBar() {
    Column() {
      Row() {
        this.PillButton($r('app.media.ic_home'), '返回编辑器', () => {
          this.backToEditor();
        })
        this.PillButton($r('app.media.ic_render'), RenderModes.label(this.renderMode), () => {
          this.showModePanel = true;
        })
        this.PillButton($r('app.media.ic_help'), '说明', () => {
          this.openHelp();
        })
        this.PillButton($r('app.media.ic_info'), '关于', () => {
          this.showAbout = true;
        })
      }
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.panel_bg'))
      .borderRadius(24)
      .border({ width: 1, color: $r('app.color.divider') })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.bottomBarHeight())
    .justifyContent(FlexAlign.Center)
    .align(Alignment.Bottom)
    .backgroundColor($r('app.color.shell_bg'))
  }

  // ---------------- 复用小部件 ----------------

  @Builder
  NavItem(icon: Resource, label: string, value: string, highlight: boolean, action: () => void) {
    Row() {
      Image(icon)
        .width(20)
        .height(20)
        .draggable(false)
      if (this.sidebarExpanded) {
        Column() {
          Text(label)
            .fontSize(13)
            .fontColor(highlight ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (value.length > 0) {
            Text(value)
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 1 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: this.sidebarExpanded ? 16 : 14, right: 10 })
    .justifyContent(this.sidebarExpanded ? FlexAlign.Start : FlexAlign.Center)
    .borderRadius(10)
    .stateStyles({
      pressed: {
        .backgroundColor($r('app.color.panel_bg_hover'))
      }
    })
    .onClick(() => {
      action();
    })
  }

  @Builder
  IconButton(icon: Resource, action: () => void) {
    Image(icon)
      .width(34)
      .height(34)
      .padding(7)
      .borderRadius(9)
      .stateStyles({
        pressed: {
          .backgroundColor($r('app.color.panel_bg_hover'))
        }
      })
      .onClick(() => {
        action();
      })
  }

  @Builder
  PillButton(icon: Resource, label: string, action: () => void) {
    Row() {
      Image(icon)
        .width(16)
        .height(16)
        .draggable(false)
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 6 })
        .maxLines(1)
    }
    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
    .margin({ left: 4, right: 4 })
    .borderRadius(18)
    .backgroundColor($r('app.color.panel_bg_hover'))
    .onClick(() => {
      action();
    })
  }

  // ---------------- 覆盖层 ----------------

  @Builder
  SplashOverlay() {
    Column() {
      Image($r('app.media.app_icon'))
        .width(72)
        .height(72)
        .borderRadius(18)
      Text('正在启动照片工坊')
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 20 })
      Text(this.engineStateLabel())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
      LoadingProgress()
        .width(44)
        .height(44)
        .color($r('app.color.accent'))
        .margin({ top: 18 })
      Text('首次启动需要编译约 24.5 MB 图像引擎，请稍候')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 14 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.shell_bg'))
  }

  @Builder
  ModeOverlay() {
    Column() {
      Column() {
        Text('渲染后端')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text('切换后编辑引擎会重新加载。若画面异常或无法启动，请选择 WebGL2 或 CPU。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })
          .textAlign(TextAlign.Start)
        this.ModeRow(AppConstants.MODE_AUTO)
        this.ModeRow(AppConstants.MODE_WEBGL)
        this.ModeRow(AppConstants.MODE_WEBGPU)
        this.ModeRow(AppConstants.MODE_CPU)
        Button('取消')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .margin({ top: 8 })
          .onClick(() => {
            this.showModePanel = false;
          })
      }
      .width(this.isWide() ? 380 : '86%')
      .padding(22)
      .backgroundColor($r('app.color.panel_bg'))
      .borderRadius(18)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(0,0,0,0.55)')
    .onClick(() => {
      this.showModePanel = false;
    })
  }

  @Builder
  ModeRow(value: string) {
    Row() {
      Column() {
        Text(RenderModes.label(value))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        Text(this.modeDesc(value))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.renderMode === value) {
        Text('已启用')
          .fontSize(11)
          .fontColor($r('app.color.accent'))
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .margin({ top: 10 })
    .borderRadius(12)
    .backgroundColor(this.renderMode === value ? $r('app.color.accent_soft') : $r('app.color.panel_bg_hover'))
    .onClick(() => {
      this.switchRenderMode(value);
    })
  }

  private modeDesc(value: string): string {
    const list: RenderOption[] = RenderModes.all();
    for (let i = 0; i < list.length; i++) {
      if (list[i].value === value) {
        return list[i].desc;
      }
    }
    return '';
  }

  @Builder
  AboutOverlay() {
    Column() {
      Column() {
        Image($r('app.media.app_icon'))
          .width(64)
          .height(64)
          .borderRadius(16)
        Text('照片工坊 · 鸿蒙版')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 14 })
        Text('v1.0.1 · PhotoCraft 0.3.0 引擎')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })

        Divider().color($r('app.color.divider')).strokeWidth(1).margin({ top: 16, bottom: 16 })

        this.AboutLine('编辑引擎', 'PhotoCraft 0.3.0（WebAssembly）')
        this.AboutLine('上游项目', 'storytold/photocraft')
        this.AboutLine('界面语言', '简体中文（可在引擎内切换）')
        this.AboutLine('许可协议', 'MIT / Apache-2.0')
        this.AboutLine('渲染后端', RenderModes.label(this.renderMode))
        this.AboutLine('运行形态', this.platformLabel())

        Row() {
          Button('使用说明')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.panel_bg_hover'))
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .onClick(() => {
              this.showAbout = false;
              this.openHelp();
            })
          Button('关闭')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.accent'))
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .margin({ left: 10 })
            .onClick(() => {
              this.showAbout = false;
            })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width(this.isWide() ? 400 : '88%')
      .padding(24)
      .backgroundColor($r('app.color.panel_bg'))
      .borderRadius(18)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(0,0,0,0.55)')
    .onClick(() => {
      this.showAbout = false;
    })
  }

  @Builder
  AboutLine(key: string, value: string) {
    Row() {
      Text(key)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .margin({ bottom: 10 })
  }

  private platformLabel(): string {
    if (this.deviceType === '2in1') {
      return '鸿蒙电脑 / 二合一';
    }
    if (this.deviceType === 'tablet') {
      return '鸿蒙平板';
    }
    return '鸿蒙手机';
  }

  @Builder
  ErrorOverlay() {
    Column() {
      Column() {
        Image($r('app.media.ic_warning'))
          .width(44)
          .height(44)
        Text('图像引擎启动失败')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 12 })
        Text(this.fatalError.length > 0 ? this.fatalError : this.engineMessage)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 10 })
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Button('重新加载')
            .fontSize(13)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .layoutWeight(1)
            .height(38)
            .borderRadius(19)
            .onClick(() => {
              this.reloadEngine();
            })
          Button('改用 WebGL2')
            .fontSize(13)
            .backgroundColor($r('app.color.panel_bg_hover'))
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .height(38)
            .borderRadius(19)
            .margin({ left: 10 })
            .onClick(() => {
              this.switchRenderMode(AppConstants.MODE_WEBGL);
            })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width(this.isWide() ? 420 : '88%')
      .padding(24)
      .backgroundColor($r('app.color.panel_bg'))
      .borderRadius(18)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.shell_bg'))
  }
}
