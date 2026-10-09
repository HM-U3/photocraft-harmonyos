import { util } from '@kit.ArkTS';
import { common, Want } from '@kit.AbilityKit';
import { picker, fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConstants } from './Constants';

/**
 * ResourceBridge
 *
 * 通过 javaScriptProxy 注入到 Web 页面（window.pcBridge），承担四件事：
 * 1. 向页面下发宿主配置（渲染后端等）；
 * 2. 接收页面状态回调（loading / ready / error），同步到 AppStorage 驱动原生 UI；
 * 3. 兜底资源通道：当 resource:// 下的 fetch / XHR 都不可用时，
 *    页面可以分块读取 rawfile 中的 wasm（避免因协议限制导致引擎无法启动）；
 * 4. 接管「保存 / 导出」与外部链接 —— Web 组件不会处理 `<a download>`，
 *    页面会拦截那次点击并把字节分块送过来，由原生用系统文件选择器落盘。
 */
export class ResourceBridge {
  private context: common.UIAbilityContext;
  private helper: util.Base64Helper = new util.Base64Helper();
  private cache: Map<string, Uint8Array> = new Map();

  // 正在接收的一次保存：文件名、MIME、已收到的分块
  private saveName: string = '';
  private saveMime: string = '';
  private saveChunks: Uint8Array[] = [];
  private saveBytes: number = 0;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  // ---------------- 下发宿主配置 ----------------

  /** 渲染后端：auto / webgpu / webgl / cpu */
  renderMode(): string {
    const mode = AppStorage.get<string>(AppConstants.KEY_RENDER_MODE);
    return mode ? mode : AppConstants.MODE_AUTO;
  }

  /** 设备类型：phone / tablet / 2in1 */
  deviceType(): string {
    const type = AppStorage.get<string>(AppConstants.KEY_DEVICE_TYPE);
    return type ? type : 'phone';
  }

  /** 布局宽度（vp），供页面做自适应 */
  viewportWidth(): number {
    const w = AppStorage.get<number>(AppConstants.KEY_WIN_W);
    return w ? w : 0;
  }

  // ---------------- 页面状态回调 ----------------

  reportState(state: string, message: string): void {
    const s: string = state ? state : AppConstants.STATE_IDLE;
    AppStorage.setOrCreate(AppConstants.KEY_ENGINE_STATE, s);
    AppStorage.setOrCreate(AppConstants.KEY_ENGINE_MESSAGE, message ? message : '');
    console.info('[PhotoCraft] engine state=' + s + ' message=' + (message ? message : ''));
  }

  /** 页面日志，便于 DevEco 中排查 */
  log(message: string): void {
    console.info('[PhotoCraft/web] ' + (message ? message : ''));
  }

  // ---------------- 保存 / 导出 ----------------
  //
  // 引擎的「保存 .pcraft」和「导出 PNG/JPG」最终都是同一个动作：把字节打成 Blob，
  // 造一个隐藏的 <a download> 再 click()。桌面浏览器会弹下载；鸿蒙的 Web 组件不会，
  // 于是点了没反应、也不知道存到了哪里。index.html 会拦下这次 click，
  // 通过下面四个方法把字节交给原生，由系统文件选择器写到用户选的目录。

  /** 开始一次保存。total 为 0 表示长度未知。 */
  beginSave(name: string, mime: string, total: number): boolean {
    this.saveName = name ? name : 'photocraft-export';
    this.saveMime = mime ? mime : '';
    this.saveChunks = [];
    this.saveBytes = 0;
    console.info('[PhotoCraft] beginSave name=' + this.saveName + ' mime=' + this.saveMime + ' total=' + total);
    this.setStatus('正在导出 ' + this.saveName + ' …');
    return true;
  }

  /** 追加一块 base64 数据 */
  saveChunk(base64: string): boolean {
    if (!base64) {
      return false;
    }
    try {
      const bytes: Uint8Array = this.helper.decodeSync(base64);
      this.saveChunks.push(bytes);
      this.saveBytes += bytes.length;
      return true;
    } catch (err) {
      console.error('[PhotoCraft] 保存分块解码失败: ' + JSON.stringify(err));
      return false;
    }
  }

  /**
   * 结束一次保存并落盘。totalBytes < 0 表示页面侧读取失败。
   * 立刻返回，真正的写文件在异步流程里，结果通过 AppStorage 的 saveStatus 回传。
   */
  finishSave(totalBytes: number): boolean {
    const name = this.saveName;
    const chunks = this.saveChunks;
    this.saveChunks = [];
    if (totalBytes < 0 || chunks.length === 0) {
      console.error('[PhotoCraft] 导出数据不完整 bytes=' + this.saveBytes);
      this.setStatus('导出失败：没有收到图像数据');
      return false;
    }
    const data: Uint8Array = this.join(chunks, this.saveBytes);
    console.info('[PhotoCraft] finishSave ' + name + ' -> ' + data.length + ' 字节');
    this.saveWithPicker(name, data);
    return true;
  }

  // ---------------- 外部链接 ----------------

  /**
   * 用系统浏览器打开链接。
   * 引擎里的「在 GitHub 上查看」等外链在 Web 里是 window.open / <a target=_blank>，
   * 在 Web 组件内会直接把编辑器页面顶掉，而且没有返回键 —— 所以交给系统浏览器。
   */
  openUrl(url: string): boolean {
    if (!url) {
      return false;
    }
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      };
      this.context.startAbility(want).then(() => {
        console.info('[PhotoCraft] 已在浏览器中打开: ' + url);
      }).catch((err: BusinessError) => {
        console.error('[PhotoCraft] 打开链接失败: ' + JSON.stringify(err));
        this.setStatus('无法打开链接，请检查是否安装了浏览器');
      });
      return true;
    } catch (err) {
      console.error('[PhotoCraft] openUrl 异常: ' + JSON.stringify(err));
      return false;
    }
  }

  // ---------------- 兜底资源通道 ----------------

  /** 返回资源字节数，0 表示不存在 */
  assetSize(url: string): number {
    const data = this.read(url);
    return data ? data.length : 0;
  }

  /** 返回指定区间数据的 base64 字符串（每块建议 1 MiB 以内） */
  assetChunk(url: string, offset: number, length: number): string {
    const data = this.read(url);
    if (!data) {
      return '';
    }
    const start: number = Math.max(0, Math.floor(offset));
    const size: number = Math.max(0, Math.floor(length));
    const end: number = Math.min(data.length, start + size);
    if (end <= start) {
      return '';
    }
    try {
      return this.helper.encodeToStringSync(data.subarray(start, end));
    } catch (err) {
      console.error('[PhotoCraft] base64 编码失败: ' + JSON.stringify(err));
      return '';
    }
  }

  /** 清理缓存（释放 wasm 占用的内存） */
  releaseCache(): void {
    this.cache.clear();
  }

  // ---------------- 落盘 ----------------

  private join(chunks: Uint8Array[], total: number): Uint8Array {
    const out = new Uint8Array(total);
    let off = 0;
    for (let i = 0; i < chunks.length; i++) {
      out.set(chunks[i], off);
      off += chunks[i].length;
    }
    return out;
  }

  /** 让用户选目录保存；选择器不可用时退回应用沙箱目录，文件至少不会丢 */
  private saveWithPicker(name: string, data: Uint8Array): void {
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [name];
      const ext = this.extOf(name);
      if (ext.length > 0) {
        options.fileSuffixChoices = [ext];
      }
      const view = new picker.DocumentViewPicker(this.context);
      view.save(options).then((uris: Array<string>) => {
        if (!uris || uris.length === 0) {
          this.setStatus('已取消保存');
          return;
        }
        this.writeTo(uris[0], data, name);
      }).catch((err: BusinessError) => {
        console.error('[PhotoCraft] 文件选择器失败: ' + JSON.stringify(err));
        this.saveFallback(name, data);
      });
    } catch (err) {
      console.error('[PhotoCraft] 启动文件选择器异常: ' + JSON.stringify(err));
      this.saveFallback(name, data);
    }
  }

  private writeTo(uri: string, data: Uint8Array, name: string): void {
    try {
      const file = fs.openSync(uri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, this.toBuffer(data));
      fs.closeSync(file);
      let path: string = uri;
      try {
        path = new fileUri.FileUri(uri).path;
      } catch (err) {
        console.info('[PhotoCraft] 解析保存路径失败，显示原始 URI');
      }
      console.info('[PhotoCraft] 已保存 ' + path);
      this.setStatus('已保存到：' + path);
    } catch (err) {
      console.error('[PhotoCraft] 写入失败: ' + JSON.stringify(err));
      this.saveFallback(name, data);
    }
  }

  /** 选择器走不通时的兜底：写到应用自己的 filesDir/exports 下 */
  private saveFallback(name: string, data: Uint8Array): void {
    try {
      const dir = this.context.filesDir + '/exports';
      try {
        fs.mkdirSync(dir, true);
      } catch (err) {
        console.info('[PhotoCraft] 导出目录已存在');
      }
      const path = dir + '/' + name;
      const file = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, this.toBuffer(data));
      fs.closeSync(file);
      console.info('[PhotoCraft] 兜底保存 ' + path);
      this.setStatus('已保存到应用目录：' + path);
    } catch (err) {
      console.error('[PhotoCraft] 兜底保存失败: ' + JSON.stringify(err));
      this.setStatus('保存失败：' + JSON.stringify(err));
    }
  }

  private toBuffer(data: Uint8Array): ArrayBuffer {
    return data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) as ArrayBuffer;
  }

  private extOf(name: string): string {
    const dot = name.lastIndexOf('.');
    if (dot < 0 || dot === name.length - 1) {
      return '';
    }
    return name.substring(dot);
  }

  private setStatus(text: string): void {
    AppStorage.setOrCreate(AppConstants.KEY_SAVE_STATUS, text);
    console.info('[PhotoCraft] ' + text);
  }

  private read(url: string): Uint8Array | undefined {
    const path: string = ResourceBridge.normalize(url);
    if (!path.length) {
      return undefined;
    }
    const cached: Uint8Array | undefined = this.cache.get(path);
    if (cached) {
      return cached;
    }
    try {
      const bytes: Uint8Array = this.context.resourceManager.getRawFileContentSync(path);
      this.cache.set(path, bytes);
      return bytes;
    } catch (err) {
      console.error('[PhotoCraft] 读取 rawfile 失败: ' + path + ' ' + JSON.stringify(err));
      return undefined;
    }
  }

  /** 把页面里的相对/绝对 URL 映射为 rawfile 路径 */
  static normalize(url: string): string {
    let path: string = url ? url : '';
    const hashIndex: number = path.indexOf('#');
    if (hashIndex >= 0) {
      path = path.substring(0, hashIndex);
    }
    const queryIndex: number = path.indexOf('?');
    if (queryIndex >= 0) {
      path = path.substring(0, queryIndex);
    }
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('data:')) {
      return '';
    }
    if (path.startsWith(AppConstants.RAW_PREFIX)) {
      path = path.substring(AppConstants.RAW_PREFIX.length);
    }
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    if (!path.startsWith(AppConstants.RAW_ROOT)) {
      path = AppConstants.RAW_ROOT + path;
    }
    return path;
  }
}
