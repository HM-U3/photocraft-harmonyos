import { AppConstants, RenderModes } from '../common/Constants';

/**
 * 使用说明
 *
 * 原生帮助页，讲清外壳上的每一项操作、引擎能做什么/不能做什么，
 * 以及真机上常见问题的排查步骤。内容与本工程实际实现严格对应，不含推测性描述。
 */
@Entry
@Component
struct Help {
  @StorageProp('deviceType') deviceType: string = 'phone';
  @StorageProp('renderMode') renderMode: string = AppConstants.MODE_AUTO;
  @StorageProp('engineState') engineState: string = AppConstants.STATE_IDLE;

  private platformLabel(): string {
    if (this.deviceType === '2in1') {
      return '鸿蒙电脑 / 二合一';
    }
    if (this.deviceType === 'tablet') {
      return '鸿蒙平板';
    }
    return '鸿蒙手机';
  }

  build() {
    Column() {
      this.TitleBar()

      Scroll() {
        Column() {
          this.Section('这是什么', [
            '本应用是开源图像编辑器 PhotoCraft（WebAssembly 版）的鸿蒙客户端，' +
              '并已做界面汉化：编辑引擎内嵌在安装包里，鸿蒙侧另外提供一层原生外壳。',
            '界面文案全部为简体中文 —— 外壳（侧栏 / 顶栏 / 底栏、状态提示、本说明）由本工程编写；' +
              '编辑器内部的菜单、工具与面板名称来自上游官方中文语言包，' +
              '并内嵌了中文字体子集（Noto Sans SC），因此无需系统安装中文字体也能正常显示。',
            '产品名与技术名（PhotoCraft、RGB、CMYK、Lab 等）按上游约定保留原文。'
          ])

          this.Section('第一次启动', [
            '首次启动需要把约 24.5 MB 的引擎读入内存并编译，通常需要几秒到十几秒，' +
              '期间会显示进度条，属正常现象，之后再次启动会快很多。',
            '引擎就绪后，状态指示灯变蓝并显示「引擎就绪」。',
            '如果卡在加载页超过 1 分钟，见下方「启动失败怎么办」。'
          ])

          this.Section('保存与导出', [
            '「保存 / 另存为 / 导出」都会弹出系统「保存到」选择器：选好目录后点保存，' +
              '文件就写到那里，完成后会提示完整的保存路径。',
            '如果选择器不可用（少数设备或分屏状态），会自动改存到应用自己的目录，' +
              '提示里会给出完整路径；该目录属于应用沙箱，普通文件管理器看不到，' +
              '所以尽量使用选择器保存到「下载」或「文档」。',
            '导出大图时会先编码再传送，十几 MB 的图片通常需要几秒，期间不要退出应用。'
          ])

          this.Section('外壳上的操作', [
            '返回编辑器：重新加载内置首页。引擎内的「在 GitHub 上查看」等外链会交给系统浏览器' +
              '打开，编辑器页面不会被顶掉；万一页面真的跑偏了，点这里就能回来，不需要退出应用。',
            '渲染后端：切换引擎绘制图形的方式，切换后引擎会重新加载。',
            '重新加载引擎：不退出应用，直接重启编辑引擎。',
            '全屏显示：隐藏状态栏与导航栏，获得更大的画布（电脑上同时隐藏窗口标题栏）。',
            '关于：查看版本、引擎版本、许可协议与运行形态。',
            '使用说明：即本页。'
          ])

          this.Section('三种形态的界面', [
            '鸿蒙电脑 / 二合一：左侧竖向侧边栏，可展开为 216vp 或收起为 64vp 图标条。',
            '鸿蒙平板：顶部工具栏，左侧显示名称与引擎状态，右侧是操作按钮。',
            '鸿蒙手机 / 小窗：底部悬浮胶囊按钮组。',
            '拖拽窗口改变宽度时，界面会在三种形态之间实时切换；当前识别为：' + this.platformLabel() + '。'
          ])

          this.Section('渲染后端怎么选', [
            '自动：引擎自行选择，优先 WebGPU，不可用时回落 WebGL2。',
            'WebGL2：兼容性最好。若启动后画布全黑或无法绘制，请优先选这一项。',
            'WebGPU：性能最佳，但需要系统与 Web 内核支持，不是所有设备都可用。',
            'CPU 软件渲染：最慢，仅用于排查图形相关问题，日常使用不建议选。',
            '当前设置：' + RenderModes.label(this.renderMode) + '（引擎状态：' + this.stateLabel() + '）'
          ])

          this.Section('启动失败怎么办', [
            '错误面板里有「重新加载」和「改用 WebGL2」两个按钮，先点后者。',
            '「改用 WebGL2」会屏蔽浏览器的 WebGPU 接口，强制引擎走兼容性更好的 WebGL2 路径。',
            '仍然失败时，在 DevEco 的 Log 面板搜索 [PhotoCraft]，' +
              '可以看到引擎走的是哪条加载通道、卡在哪一步。',
            '安装时报「no signature file」：工程需要签名，请在 ' +
              'File → Project Structure → Signing Configs 中开启自动签名。'
          ])

          this.Section('已知限制', [
            '内嵌的中文字体是子集（覆盖全部界面用字），若在文字图层里输入生僻字，' +
              '可能显示为空白；系统安装了中文字体时会自动回退到系统字体。',
            '界面语言可在编辑器的「首选项 › 界面 › 语言」中改回 English 或其它语言。' +
              '英文正常（用的是内嵌 Inter 字体）；日文假名、韩文等不在内嵌子集内，需要系统字体支持。',
            '引擎完全在本地运行，不联网、无服务端，所有处理都在设备内存与 GPU 中完成。',
            '编辑大图时内存占用较高，建议在平板上处理超大尺寸图片时分批进行。'
          ])

          this.Section('版本与许可', [
            '客户端版本：1.0.0',
            '编辑引擎：PhotoCraft 0.3.0（上游 main 分支源码重新编译，WebAssembly，MIT / Apache-2.0 双许可）',
            '引擎改动：默认加载官方简体中文语言包；内嵌 Noto Sans SC 子集字体（OFL 1.1）；' +
              '并修复了 WebGL2 下缩小画面变透明的缺陷',
            '上游项目：storytold/photocraft',
            '本客户端仅做本地适配，引擎相对上游只做了四处最小改动（默认语言、字体注册、' +
              '字族回退链、WebGL2 的 mip 链生成方式）；应用图标与本页内容由本工程原创。'
          ])

          Blank().height(24)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 4, bottom: 24 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.shell_bg'))
  }

  private stateLabel(): string {
    if (this.engineState === AppConstants.STATE_READY) {
      return '就绪';
    }
    if (this.engineState === AppConstants.STATE_ERROR) {
      return '报错';
    }
    if (this.engineState === AppConstants.STATE_LOADING) {
      return '加载中';
    }
    return '未启动';
  }

  @Builder
  TitleBar() {
    Row() {
      Image($r('app.media.ic_help'))
        .width(22)
        .height(22)
        .draggable(false)
      Text('使用说明')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 10 })
      Blank()
      Text('返回')
        .fontSize(13)
        .fontColor($r('app.color.accent'))
        .padding({ left: 12, right: 4, top: 8, bottom: 8 })
        .onClick(() => {
          try {
            this.getUIContext().getRouter().back();
          } catch (err) {
            console.error('[PhotoCraft] 返回失败: ' + JSON.stringify(err));
          }
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 20, right: 14 })
    .backgroundColor($r('app.color.panel_bg'))
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  Section(title: string, lines: string[]) {
    Column() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 10 })
      ForEach(lines, (line: string) => {
        Row() {
          Circle()
            .width(4)
            .height(4)
            .fill($r('app.color.accent'))
            .margin({ top: 8 })
          Text(line)
            .fontSize(13)
            .lineHeight(21)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 10 })
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ bottom: 8 })
      }, (line: string) => line)
    }
    .width('100%')
    .padding(16)
    .margin({ bottom: 14 })
    .backgroundColor($r('app.color.panel_bg'))
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
  }
}
