/**
 * `libphotocraft_native.so` 的类型声明。
 *
 * 这个库是 Rust 侧 `apps/photocraft-ohos` 用 napi-rs 导出的，函数名在 ArkTS 里是驼峰
 * （Rust 的 snake_case 自动转换）。这里的签名与 `apps/photocraft-ohos/src/lib.rs` 的
 * `#[napi]` 函数一一对应，改 Rust 侧时记得同步，否则编译期就会报错。
 */

/** 取走引擎排队等待 ArkTS 处理的平台请求（打开/保存/外链等），返回命令串。 */
export const takeRequests: () => Array<string>;

/** 告诉原生侧沙箱目录（偏好、自动保存、导出都写在这里）。 */
export const setDataDir: (dir: string) => void;

/** 把系统语言（BCP 47，如 `zh-Hans-CN`）交给引擎，用于 `interface.language = auto`。 */
export const setLocale: (tag: string) => void;

/** 把系统选择器读到的文件交给编辑器。 */
export const openFile: (name: string, data: ArrayBuffer) => boolean;

/** 把当前文档编码成 PNG 交给 ArkTS 另存。 */
export const exportPng: () => ArrayBuffer | undefined;

/** 在 XComponent 的 surface 上启动（或重启）渲染线程。 */
export const start: (surfaceId: number, width: number, height: number, dpi: number) => boolean;

/** 停掉渲染线程。 */
export const stop: () => void;

/** surface 尺寸/像素密度变化（surface 本身没换）。 */
export const resize: (width: number, height: number, dpi: number) => void;

/** 渲染线程是否在跑。 */
export const isRunning: () => boolean;

/** 单指触摸：phase 0 按下 / 1 抬起 / 2 移动 / 3 取消。 */
export const touch: (phase: number, x: number, y: number) => void;

/** 双指捏合：scale 为本次缩放比，x/y 是两指中点。 */
export const pinch: (scale: number, x: number, y: number) => void;

/** 键盘：phase 0 按下 / 1 抬起，code 为 HarmonyOS KeyCode。 */
export const key: (phase: number, code: number, ctrl: boolean, shift: boolean, alt: boolean, text: string) => void;

/** 输入法上屏的文字。 */
export const imeText: (text: string) => void;

/** 输入法退格 count 个字符。 */
export const imeBackspace: (count: number) => void;

/** 编辑器现在是否在等文字输入（决定要不要拉起输入法）。 */
export const wantsTextInput: () => boolean;

/** 鼠标：phase 0 按下 / 1 抬起 / 2 移动，button 0 左 / 1 右 / 2 中。 */
export const mouse: (phase: number, button: number, x: number, y: number) => void;

/** 滚轮/触控板两轴增量，单位为角度近似值。 */
export const wheel: (dx: number, dy: number, ctrl: boolean, shift: boolean, alt: boolean) => void;
