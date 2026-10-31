import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * EntryAbility —— PhotoCraft 应用入口
 *
 * 2.0 起界面由引擎自己绘制，这里只保留三件事：
 * 1. 把沙箱目录交给渲染页（偏好、导出文件都写在里面）；
 * 2. 打开即全屏（电脑 / 平板电脑模式）；
 * 3. 加载唯一的原生渲染页。
 *
 * 旧版放在 AppStorage 里的渲染后端选择、窗口尺寸、设备类型，原生路径都用不到了 ——
 * 尺寸由 XComponent 自己的 surface 回调给出，设备形态由引擎按窗口宽度自行断点。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('[PhotoCraft] onCreate');
    // 原生渲染页需要沙箱目录（偏好、导出都写在里面）。
    try {
      AppStorage.setOrCreate('pc_files_dir', this.context.filesDir);
      console.info('[PhotoCraft] filesDir=' + this.context.filesDir);
    } catch (err) {
      console.error('[PhotoCraft] 读取 filesDir 失败: ' + JSON.stringify(err));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    console.info('[PhotoCraft] onWindowStageCreate');
    // 先切全屏、再 loadContent：顺序不能反。
    // XComponent 的 surface 尺寸只在创建那一刻定下来，之后不会自己跟着窗口长；
    // 若先按默认窗口加载内容，surface 就建在小尺寸上，用户点全屏之后只能靠 resize 补救，
    // 中间那一帧还会缩在中间、四周一圈黑。
    this.prepareFullScreen(windowStage).then(() => {
      this.loadPage(windowStage);
    });
  }

  /**
   * 打开即全屏。
   *
   * 电脑（2in1）上走 `maximize(ENTER_IMMERSIVE)`：窗口铺满整屏、隐藏标题栏与 Dock，
   * 光标移到屏幕顶边时标题栏才浮出来（保留一个能关闭/还原的出口）。
   * 手机 / 平板上系统本身就是全屏，这个调用会报 801（能力不支持），忽略即可。
   */
  private async prepareFullScreen(windowStage: window.WindowStage): Promise<void> {
    let win: window.Window;
    try {
      win = windowStage.getMainWindowSync();
    } catch (err) {
      console.error('[PhotoCraft] 取主窗口失败: ' + JSON.stringify(err));
      return;
    }
    // 超时兜底：真机上万一某个形态迟迟不回 Promise，也不能让页面一直不加载。
    const timeout: Promise<void> = new Promise<void>((resolve: (value: void) => void) => {
      setTimeout(() => {
        resolve();
      }, 1500);
    });
    try {
      await Promise.race([win.maximize(window.MaximizePresentation.ENTER_IMMERSIVE), timeout]);
      const rect: window.Rect = win.getWindowProperties().windowRect;
      console.info('[PhotoCraft] 全屏就绪 ' + rect.width + 'x' + rect.height +
        ' @' + rect.left + ',' + rect.top);
    } catch (err) {
      const e = err as BusinessError;
      console.warn('[PhotoCraft] 全屏失败(忽略) code=' + e.code + ' ' + e.message);
    }
  }

  private loadPage(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/NativeRender', (err: BusinessError) => {
      if (err && err.code !== 0) {
        console.error('[PhotoCraft] 加载页面失败: ' + JSON.stringify(err));
        return;
      }
      console.info('[PhotoCraft] 页面加载完成');
    });
  }

  onWindowStageDestroy(): void {
    console.info('[PhotoCraft] onWindowStageDestroy');
  }

  onDestroy(): void {
    console.info('[PhotoCraft] onDestroy');
  }

  onForeground(): void {
    console.info('[PhotoCraft] onForeground');
  }

  onBackground(): void {
    console.info('[PhotoCraft] onBackground');
  }
}
