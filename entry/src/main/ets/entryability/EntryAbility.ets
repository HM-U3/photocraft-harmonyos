import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window, display } from '@kit.ArkUI';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { AppConstants } from '../common/Constants';

/**
 * EntryAbility —— PhotoCraft 应用入口
 *
 * 职责：
 * 1. 初始化 AppStorage / PersistentStorage（渲染后端、窗口尺寸、设备类型）
 * 2. 加载主页面并跟踪窗口尺寸变化，供 ArkUI 侧做平板 / PC 自适应
 */
export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined = undefined;
  private sizeListener: ((size: window.Size) => void) | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('[PhotoCraft] onCreate');
    // 渲染后端需要跨启动保持
    PersistentStorage.persistProp(AppConstants.KEY_RENDER_MODE, AppConstants.MODE_AUTO);
    AppStorage.setOrCreate(AppConstants.KEY_ENGINE_STATE, AppConstants.STATE_IDLE);
    AppStorage.setOrCreate(AppConstants.KEY_ENGINE_MESSAGE, '');
    AppStorage.setOrCreate(AppConstants.KEY_WIN_W, 0);
    AppStorage.setOrCreate(AppConstants.KEY_WIN_H, 0);

    let type: string = 'phone';
    try {
      type = deviceInfo.deviceType ? deviceInfo.deviceType : 'phone';
    } catch (err) {
      console.error('[PhotoCraft] 获取设备类型失败: ' + JSON.stringify(err));
    }
    AppStorage.setOrCreate(AppConstants.KEY_DEVICE_TYPE, type);
    console.info('[PhotoCraft] deviceType=' + type);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    console.info('[PhotoCraft] onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err && err.code !== 0) {
        console.error('[PhotoCraft] 加载页面失败: ' + JSON.stringify(err));
        return;
      }
      console.info('[PhotoCraft] 页面加载完成');
    });

    try {
      this.mainWindow = windowStage.getMainWindowSync();
      AppStorage.setOrCreate(AppConstants.KEY_MAIN_WINDOW, this.mainWindow);
      this.trackWindowSize(this.mainWindow);
    } catch (err) {
      console.error('[PhotoCraft] 获取主窗口失败: ' + JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    if (this.mainWindow && this.sizeListener) {
      try {
        this.mainWindow.off('windowSizeChange', this.sizeListener);
      } catch (err) {
        console.error('[PhotoCraft] 注销窗口监听失败: ' + JSON.stringify(err));
      }
    }
    this.sizeListener = undefined;
    this.mainWindow = undefined;
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

  /**
   * 跟踪窗口尺寸，转换成 vp 后写入 AppStorage。
   * 平板/PC 上窗口可自由缩放，ArkUI 侧据此切换侧边栏 / 顶栏 / 底栏形态。
   */
  private trackWindowSize(win: window.Window): void {
    const applyRect = (widthPx: number, heightPx: number): void => {
      if (widthPx <= 0 || heightPx <= 0) {
        return;
      }
      let density: number = 1;
      try {
        density = display.getDefaultDisplaySync().densityPixels;
      } catch (err) {
        density = 1;
      }
      if (density <= 0) {
        density = 1;
      }
      AppStorage.setOrCreate(AppConstants.KEY_WIN_W, widthPx / density);
      AppStorage.setOrCreate(AppConstants.KEY_WIN_H, heightPx / density);
    };

    try {
      const rect: window.Rect = win.getWindowProperties().windowRect;
      applyRect(rect.width, rect.height);
    } catch (err) {
      console.error('[PhotoCraft] 读取窗口尺寸失败: ' + JSON.stringify(err));
    }

    this.sizeListener = (size: window.Size) => {
      applyRect(size.width, size.height);
    };
    try {
      win.on('windowSizeChange', this.sizeListener);
    } catch (err) {
      console.error('[PhotoCraft] 监听窗口尺寸失败: ' + JSON.stringify(err));
    }
  }
}
