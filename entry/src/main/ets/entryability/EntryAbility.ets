import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * EntryAbility —— PhotoCraft 应用入口
 *
 * 2.0 起界面由引擎自己绘制，这里只保留两件事：
 * 1. 把沙箱目录交给渲染页（偏好、导出文件都写在里面）；
 * 2. 加载唯一的原生渲染页。
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
