/**
 * 全局常量与配置
 */

export class AppConstants {
  /** 内置 Web 应用入口（打包在 resources/rawfile/photocraft 下） */
  static readonly WEB_ENTRY: string = 'resource://rawfile/photocraft/index.html';

  /** rawfile 协议前缀 */
  static readonly RAW_PREFIX: string = 'resource://rawfile/';

  /** rawfile 中 Web 应用的根目录 */
  static readonly RAW_ROOT: string = 'photocraft/';

  /** 资源探测用的相对路径（与 index.html 中的引用保持一致） */
  static readonly WASM_FILE: string = 'photocraft-web-b33881c18c5db349_bg.wasm';
  static readonly JS_FILE: string = 'photocraft-web-b33881c18c5db349.js';

  /** 布局断点（vp） */
  static readonly BREAKPOINT_MEDIUM: number = 600;
  static readonly BREAKPOINT_WIDE: number = 840;

  /** 渲染后端取值 */
  static readonly MODE_AUTO: string = 'auto';
  static readonly MODE_WEBGPU: string = 'webgpu';
  static readonly MODE_WEBGL: string = 'webgl';
  static readonly MODE_CPU: string = 'cpu';

  /** AppStorage 键名 */
  static readonly KEY_ENGINE_STATE: string = 'engineState';
  static readonly KEY_ENGINE_MESSAGE: string = 'engineMessage';
  static readonly KEY_RENDER_MODE: string = 'renderMode';
  static readonly KEY_WIN_W: string = 'winWidthVp';
  static readonly KEY_WIN_H: string = 'winHeightVp';
  static readonly KEY_DEVICE_TYPE: string = 'deviceType';
  static readonly KEY_MAIN_WINDOW: string = 'mainWindow';

  /** 保存/导出结果提示（由原生桥写入，Index 弹 toast 展示） */
  static readonly KEY_SAVE_STATUS: string = 'saveStatus';
  /** 保存块大小上限（字节），JS 侧按此切片后逐块交给原生 */
  static readonly SAVE_CHUNK_MAX: number = 512 * 1024;

  /** 引擎状态 */
  static readonly STATE_IDLE: string = 'idle';
  static readonly STATE_LOADING: string = 'loading';
  static readonly STATE_READY: string = 'ready';
  static readonly STATE_ERROR: string = 'error';
}

export interface RenderOption {
  value: string;
  label: string;
  desc: string;
}

export class RenderModes {
  static all(): RenderOption[] {
    return [
      { value: AppConstants.MODE_AUTO, label: '自动', desc: '优先 WebGPU，不可用时回落 WebGL2' },
      { value: AppConstants.MODE_WEBGL, label: 'WebGL2', desc: '兼容性最好，平板/手机推荐' },
      { value: AppConstants.MODE_WEBGPU, label: 'WebGPU', desc: '性能最佳，需要系统与驱动支持' },
      { value: AppConstants.MODE_CPU, label: 'CPU 软件渲染', desc: '最慢但兼容性最高，用于排查问题' }
    ];
  }

  static label(value: string): string {
    const list = RenderModes.all();
    for (let i = 0; i < list.length; i++) {
      if (list[i].value === value) {
        return list[i].label;
      }
    }
    return '自动';
  }
}
