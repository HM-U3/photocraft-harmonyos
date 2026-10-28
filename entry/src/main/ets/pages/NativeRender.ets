import native from 'libphotocraft_native.so';
import display from '@ohos.display';
import { common } from '@kit.AbilityKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 原生渲染页：不加载 WebView，Rust 通过 wgpu(GLES/EGL) 直接渲染到 XComponent。
 *
 * 这一层只做「系统能力代理」：
 * - 编辑器菜单里的「打开 / 存储为 / 外链」会在 Rust 侧排成请求，
 *   这里定时 takeRequests() 取走并弹系统 picker / 打开浏览器；
 * - 触摸和键盘事件转发给 Rust（native.touch / native.key）。
 */
@Entry
@Component
struct NativeRender {
  private controller: XComponentController = new XComponentController();
  @State private status: string = '正在启动原生渲染…';
  @State private startFailed: boolean = false;
  private busy: boolean = false;
  private pollTimer: number = -1;
  /** 文件名 → 用户上次选定的保存位置，第二次保存不再弹框。 */
  private savedTo: Map<string, string> = new Map();
  private dataDir: string = '';
  /** 修饰键按下状态（getModifierKeyState 在某些场景返回 undefined，自己跟踪更可靠）。 */
  private ctrlDown: boolean = false;
  private shiftDown: boolean = false;
  private altDown: boolean = false;
  /** 隐藏 TextInput 的内容，用来和 IME 的新值做差。 */
  @State private imeValue: string = '';
  private imeActive: boolean = false;
  @State private showIme: boolean = false;
  /** 上一个已处理的轴事件指纹（父子容器双挂 onAxisEvent 时去重）。时间戳 + 动作 + 数值全同
   *  才算重复：只比时间戳会把同一毫秒里真实发生的不同事件（例如慢速滚动时的 END）也吞掉。 */
  private lastAxisKey: string = '';
  /** 当前这次滚动（BEGIN 到 END）里是不是已经报过数值了：END 只在没报过时才顶上。 */
  private gestureHadValue: boolean = false;
  /** 一次触摸按下已经转发给引擎、还没抬起：第二根手指落下时要把它收回（Cancel）。 */
  private touchDown: boolean = false;
  /** 正在双指操作：从第二根手指落下起，到所有手指离开屏幕为止，单指事件一律不转发。 */
  private pinching: boolean = false;
  /** 屏上手指的 id 表。不能直接用 event.touches.length 判断还剩几根手指：抬起的那个在部分
   *  版本里仍留在 touches 里，于是「全部离开」永远等不到，pinching 卡死、之后单指画不了。 */
  private fingerIds: number[] = [];
  /** 上次两指的间距（vp，锚点即两指中点），-1 表示这一轮捏合还没有基准。 */
  private pinchDist: number = -1;

  aboutToAppear(): void {
    this.ensureDataDir();
  }

  /** 页面显示后把焦点交给渲染区，否则键盘事件收不到。 */
  onPageShow(): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus('pc_root');
      } catch (err) {
        console.error('[PhotoCraft] requestFocus 失败: ' + JSON.stringify(err));
      }
    }, 200);
  }

  aboutToDisappear(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
    try {
      native.stop();
    } catch (err) {
      console.error('[PhotoCraft] native.stop 异常: ' + JSON.stringify(err));
    }
  }

  private ensureDataDir(): void {
    try {
      let dir: string = AppStorage.get<string>('pc_files_dir') ?? '';
      if (dir.length === 0) {
        const host = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
        if (host && host.filesDir) {
          dir = host.filesDir;
        }
      }
      if (dir.length === 0) {
        console.error('[PhotoCraft] 拿不到沙箱目录');
        return;
      }
      this.dataDir = dir;
      native.setDataDir(dir);
    } catch (err) {
      console.error('[PhotoCraft] 设置沙箱目录失败: ' + JSON.stringify(err));
    }
  }

  private startRender(): void {
    try {
      this.ensureDataDir();
      const surfaceId: string = this.controller.getXComponentSurfaceId();
      const rect = this.controller.getXComponentSurfaceRect();
      let width: number = rect.surfaceWidth;
      let height: number = rect.surfaceHeight;
      let dpi: number = 1.0;
      try {
        const d = display.getDefaultDisplaySync();
        if (width <= 0 || height <= 0) {
          width = d.width;
          height = d.height;
        }
        dpi = d.densityDPI / 160;
      } catch (err) {
        dpi = 1.0;
      }
      const ok: boolean = native.start(Number(surfaceId), width, height, dpi);
      this.startFailed = !ok;
      this.status = ok ? '' : '原生渲染启动失败，请查看 hilog（photocraft-ohos）';
      console.info('[PhotoCraft] native.start surface=' + surfaceId +
        ' size=' + width + 'x' + height + ' dpi=' + dpi + ' -> ' + ok);
      this.startPolling();
    } catch (err) {
      this.startFailed = true;
      this.status = '原生渲染启动异常：' + JSON.stringify(err);
      console.error('[PhotoCraft] native.start 异常: ' + JSON.stringify(err));
    }
  }

  /** 轮询 Rust 侧的系统能力请求（菜单里的打开/存储为/外链）。 */
  private startPolling(): void {
    if (this.pollTimer >= 0) {
      return;
    }
    this.pollTimer = setInterval(() => {
      let reqs: string[] = [];
      try {
        reqs = native.takeRequests();
      } catch (err) {
        return;
      }
      for (const req of reqs) {
        if (req === 'pickOpen') {
          this.pickOpen();
        } else if (req.startsWith('saveAs:')) {
          this.saveAs(req.substring('saveAs:'.length));
        } else if (req.startsWith('openUrl:')) {
          this.openUrl(req.substring('openUrl:'.length));
        }
      }
      this.syncImeFocus();
    }, 80);
  }

  /** 鼠标滚轮 / 触控板轴事件 → egui 的滚轮事件（Ctrl+滚轮=缩放，Alt+滚轮=微调，普通=平移）。 */
  /** 双指捏合 → 引擎的缩放事件。用的是相邻两次事件的间距比（增量），不是手势的累计 scale：
   *  egui 的 Zoom 事件本身就是倍数因子，逐帧相乘即可，ArkTS 这边不必记手势起点。
   *  中点一起送过去 —— 引擎以指针为锚点缩放，双指的中点就该是那个锚点。 */
  private pinch(event: TouchEvent): void {
    // 只有 touches 里确实有两根手指时才量间距；拿不到就跳过这一帧（捏合本身继续）。
    if (event.touches.length < 2) {
      return;
    }
    const a: TouchObject = event.touches[0];
    const b: TouchObject = event.touches[1];
    const dx: number = a.x - b.x;
    const dy: number = a.y - b.y;
    const dist: number = Math.sqrt(dx * dx + dy * dy);
    const cx: number = (a.x + b.x) / 2;
    const cy: number = (a.y + b.y) / 2;
    const last: number = this.pinchDist;
    this.pinchDist = dist;
    if (last <= 0 || dist <= 0) {
      return;
    }
    const scale: number = dist / last;
    if (scale === 1) {
      return;
    }
    try {
      native.pinch(scale, cx, cy);
    } catch (err) {
      console.error('[PhotoCraft] native.pinch 异常: ' + JSON.stringify(err));
    }
  }

  private onWheel(event: AxisEvent): void {
    if (this.status.length > 0) {
      return;
    }
    // CANCEL 不带数值；END 带：慢速滚动时系统常常只在 END 上报这一段的增量，
    // 早先直接丢掉 END，结果「滚一格」完全没反应，只有快速连滚（UPDATE 连续上报）才动。
    if (event.action === AxisAction.CANCEL) {
      return;
    }
    let dx: number = 0;
    let dy: number = 0;
    try {
      dy = event.getVerticalAxisValue();
      dx = event.getHorizontalAxisValue();
    } catch (err) {
      dy = 0;
      dx = 0;
    }
    // 一次滚动 = BEGIN … UPDATE … END。数值可能只出现在 UPDATE 上，也可能只在 END 上
    // （慢速滚动时系统就只在段尾报一次）。已经报过数值的段里，END 若重复同一个数值就跳过，
    // 免得一格算两次；整段没有任何数值时，END 的那一下就是全部。
    if (event.action === AxisAction.BEGIN) {
      this.gestureHadValue = false;
    }
    const hasValue: boolean = dx !== 0 || dy !== 0;
    if (hasValue && event.action === AxisAction.UPDATE) {
      this.gestureHadValue = true;
    }
    if (hasValue && event.action === AxisAction.END && this.gestureHadValue) {
      return;
    }
    if (!hasValue) {
      return;
    }
    // 同一个轴事件可能被 XComponent 和外层 Stack 各派发一次：时间戳、动作、数值全同才算重复。
    const key: string = event.timestamp + '|' + event.action + '|' + dx + '|' + dy;
    if (this.lastAxisKey === key) {
      return;
    }
    this.lastAxisKey = key;
    // 滚轮上报的是角度（向前为负），egui 期望点：约 40pt/notch、1 notch ≈ 15°
    try {
      native.wheel(dx * 2.6, dy * 2.6, this.ctrlDown, this.shiftDown, this.altDown);
    } catch (err) {
      console.error('[PhotoCraft] native.wheel 异常: ' + JSON.stringify(err));
    }
  }

  /** IME 上屏的文本：拿新值和旧值做差，增量送给 egui（否则会重复插入）。 */
  private onImeChange(value: string): void {
    if (value === this.imeValue) {
      return;
    }
    const prev: string = this.imeValue;
    try {
      // 找公共前缀：先删掉差异部分再插入，这样「全选后输入」也能正确替换
      let p: number = 0;
      const n: number = Math.min(prev.length, value.length);
      while (p < n && prev.charCodeAt(p) === value.charCodeAt(p)) {
        p++;
      }
      const removed: number = prev.length - p;
      if (removed > 0) {
        native.imeBackspace(removed);
      }
      if (value.length > p) {
        native.imeText(value.substring(p));
      }
    } catch (err) {
      console.error('[PhotoCraft] IME 转发失败: ' + JSON.stringify(err));
    }
    this.imeValue = value;
  }

  /** 编辑器需要文字输入时把焦点交给隐藏输入框（系统才会弹输入法）。 */
  private syncImeFocus(): void {
    let wants: boolean = false;
    try {
      wants = native.wantsTextInput();
    } catch (err) {
      return;
    }
    if (wants === this.imeActive) {
      return;
    }
    this.imeActive = wants;
    this.showIme = wants;
    if (!wants) {
      this.imeValue = '';
    }
    try {
      if (wants) {
        // 组件这帧才进树，等它挂载再要焦点
        setTimeout(() => {
          try {
            this.getUIContext().getFocusController().requestFocus('pc_ime');
          } catch (e) {
            console.error('[PhotoCraft] IME 焦点失败: ' + JSON.stringify(e));
          }
        }, 50);
      } else {
        this.getUIContext().getFocusController().requestFocus('pc_root');
      }
    } catch (err) {
      console.error('[PhotoCraft] 切换 IME 焦点失败: ' + JSON.stringify(err));
    }
  }

  /** 菜单「文件 → 打开」：系统选择器 → 读字节 → 交给编辑器。 */
  private async pickOpen(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const viewPicker = new picker.DocumentViewPicker(getContext(this));
      const uris: string[] = await viewPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.png', '.jpg', '.jpeg', '.webp', '.psd', '.tif', '.tiff', '.gif', '.bmp']
      });
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      const name: string = uri.split('/').pop() ?? 'image';
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(file.fd).size;
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      const ok: boolean = native.openFile(name, buffer);
      console.info('[PhotoCraft] openFile ' + name + ' ' + size + 'B -> ' + ok);
    } catch (err) {
      const e = err as BusinessError;
      console.error('[PhotoCraft] 打开文件失败: ' + JSON.stringify(e));
    } finally {
      this.busy = false;
    }
  }

  /** 菜单「存储为」：把沙箱里的导出复制到用户选定的位置（同一个名字只问一次）。 */
  private async saveAs(name: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const src = this.dataDir + '/exports/' + name;
      const file = fs.openSync(src, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(file.fd).size;
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);

      let uri: string = this.savedTo.get(name) ?? '';
      if (uri.length === 0) {
        const viewPicker = new picker.DocumentViewPicker(getContext(this));
        const uris: string[] = await viewPicker.save({ newFileNames: [name] });
        if (uris.length === 0) {
          return;
        }
        uri = uris[0];
        this.savedTo.set(name, uri);
      }
      const out = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(out.fd, buffer);
      fs.closeSync(out);
      console.info('[PhotoCraft] saved ' + name + ' -> ' + uri + ' (' + buffer.byteLength + 'B)');
    } catch (err) {
      const e = err as BusinessError;
      console.error('[PhotoCraft] 保存失败: ' + JSON.stringify(e));
    } finally {
      this.busy = false;
    }
  }

  /** 帮助 / 关于页里的链接：用系统浏览器打开。 */
  private openUrl(url: string): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.openLink(url).catch((err: BusinessError) => {
        console.error('[PhotoCraft] 打开链接失败: ' + JSON.stringify(err));
      });
    } catch (err) {
      console.error('[PhotoCraft] openLink 异常: ' + JSON.stringify(err));
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      XComponent({ id: 'pc_native', type: XComponentType.SURFACE, controller: this.controller })
        .width('100%')
        .height('100%')
        .onLoad(() => {
          this.startRender();
        })
        .onTouch((event: TouchEvent) => {
          if (this.status.length > 0) {
            return;
          }
          const t: TouchObject | undefined =
            event.touches.length > 0 ? event.touches[0] : event.changedTouches[0];
          if (!t) {
            return;
          }
          // 屏上还有几根手指：以 changedTouches 的增删为准，不看 touches.length ——
          // 抬起的那个在部分版本里仍留在 touches 里，「所有手指都走了」就永远等不到，
          // pinching 卡住之后单指再也画不了线。
          if (event.type === TouchType.Down) {
            for (const c of event.changedTouches) {
              if (this.fingerIds.indexOf(c.id) < 0) {
                this.fingerIds.push(c.id);
              }
            }
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            for (const c of event.changedTouches) {
              const i: number = this.fingerIds.indexOf(c.id);
              if (i >= 0) {
                this.fingerIds.splice(i, 1);
              }
            }
          }
          if (event.touches.length === 0) {
            // 兜底：系统说屏上没有手指了，就以它为准。
            this.fingerIds.length = 0;
          }
          // 两指（及以上）是捏合缩放。第一根手指按下时已经当作落笔转发出去了，这里要把它收回
          // （Cancel），否则整个捏合过程中笔刷会一直跟着第一根手指画。之后的单指事件一律不转发，
          // 一直到所有手指离屏 —— 捏合途中抬起一根手指不能变成新的一笔。
          if (this.fingerIds.length >= 2) {
            if (!this.pinching) {
              this.pinching = true;
              this.pinchDist = -1;
              if (this.touchDown) {
                this.touchDown = false;
                try {
                  native.touch(3, t.x, t.y);
                } catch (err) {
                  console.error('[PhotoCraft] native.touch(cancel) 异常: ' + JSON.stringify(err));
                }
              }
            }
            this.pinch(event);
            return;
          }
          if (this.pinching) {
            if (this.fingerIds.length === 0) {
              this.pinching = false;
              this.pinchDist = -1;
            }
            return;
          }
          let phase: number = 1;
          if (event.type === TouchType.Down) {
            phase = 0;
          } else if (event.type === TouchType.Up) {
            phase = 2;
          } else if (event.type === TouchType.Cancel) {
            phase = 3;
          }
          if (phase === 0) {
            this.touchDown = true;
          } else if (phase === 2 || phase === 3) {
            this.touchDown = false;
          }
          try {
            native.touch(phase, t.x, t.y);
          } catch (err) {
            console.error('[PhotoCraft] native.touch 异常: ' + JSON.stringify(err));
          }
        })
        .onMouse((event: MouseEvent) => {
          if (this.status.length > 0) {
            return;
          }
          let phase: number = 1;
          if (event.action === MouseAction.Press) {
            phase = 0;
          } else if (event.action === MouseAction.Release) {
            phase = 2;
          } else if (event.action !== MouseAction.Move) {
            return;
          }
          let button: number = 0;
          if (event.button === MouseButton.Right) {
            button = 1;
          } else if (event.button === MouseButton.Middle) {
            button = 2;
          }
          try {
            native.mouse(phase, button, event.x, event.y);
          } catch (err) {
            console.error('[PhotoCraft] native.mouse 异常: ' + JSON.stringify(err));
          }
        })
        // 滚轮/触控板轴事件必须挂在 XComponent 上：指针整屏都在它上面，
        // 轴事件不会冒泡到外层 Stack（onTouch/onMouse 同理，所以也挂在这）。
        .onAxisEvent((event: AxisEvent) => {
          this.onWheel(event);
        })
        .onDestroy(() => {
          native.stop();
        })

      // IME 代理：只在编辑器需要文字输入时才进组件树，否则会自己抢焦点弹出输入法。
      if (this.showIme) {
        TextInput({ text: this.imeValue })
          .id('pc_ime')
          .width(2)
          .height(2)
          .opacity(0.01)
          .backgroundColor(Color.Transparent)
          .caretColor(Color.Transparent)
          .enablePreviewText(false)
          .onChange((value: string) => {
            this.onImeChange(value);
          })
      }

      if (this.status.length > 0) {
        Column() {
          Text(this.status)
            .fontSize(14)
            .fontColor(this.startFailed ? '#F09595' : '#9FE1CB')
            .textAlign(TextAlign.Center)
            .padding(12)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .id('pc_root')
    .focusable(true)
    .defaultFocus(true)
    .onAxisEvent((event: AxisEvent) => {
      this.onWheel(event);
    })
    .onKeyEvent((event: KeyEvent) => {
      if (this.status.length > 0) {
        return;
      }
      const down: boolean = event.type === KeyType.Down;
      // 修饰键自己跟踪：2072/2073 = Ctrl，2047/2048 = Shift，2045/2046 = Alt
      if (event.keyCode === 2072 || event.keyCode === 2073) {
        this.ctrlDown = down;
      } else if (event.keyCode === 2047 || event.keyCode === 2048) {
        this.shiftDown = down;
      } else if (event.keyCode === 2045 || event.keyCode === 2046) {
        this.altDown = down;
      }
      let ctrl: boolean = this.ctrlDown;
      let shift: boolean = this.shiftDown;
      let alt: boolean = this.altDown;
      const modState = event.getModifierKeyState;
      if (modState) {
        try {
          // 系统能给就以系统为准（自己跟踪的只在拿不到状态时兜底，
          // 否则一次丢失的 key-up 会让 Ctrl 永远卡住）。
          const c: boolean | undefined = modState(['ctrl']);
          const s: boolean | undefined = modState(['shift']);
          const a: boolean | undefined = modState(['alt']);
          if (c !== undefined) {
            ctrl = c === true;
          }
          if (s !== undefined) {
            shift = s === true;
          }
          if (a !== undefined) {
            alt = a === true;
          }
        } catch (err) {
          ctrl = this.ctrlDown;
          shift = this.shiftDown;
          alt = this.altDown;
        }
      }
      this.ctrlDown = ctrl;
      this.shiftDown = shift;
      this.altDown = alt;
      const phase: number = down ? 0 : 1;
      let text: string = '';
      if (phase === 0 && event.keyText !== undefined) {
        const kt: string = event.keyText;
        if (kt.length === 1 && kt.charCodeAt(0) >= 32) {
          text = kt;
        }
      }
      try {
        native.key(phase, event.keyCode, ctrl, shift, alt, text);
      } catch (err) {
        console.error('[PhotoCraft] native.key 异常: ' + JSON.stringify(err));
      }
    })
    .backgroundColor('#0E1016')
  }
}
