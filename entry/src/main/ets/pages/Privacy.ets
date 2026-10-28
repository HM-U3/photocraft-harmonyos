/**
 * 隐私政策
 *
 * 原生页面，内容与本工程的实际行为严格对应：不申请任何权限、不联网、
 * 不采集任何数据。上架应用市场要求应用内可查阅隐私政策，故此页随包内嵌，
 * 离线也能打开，不依赖任何在线链接。
 */
@Entry
@Component
struct Privacy {
  build() {
    Column() {
      this.TitleBar()

      Scroll() {
        Column() {
          Text('最近更新：2026 年 10 月 11 日 · 适用于 1.0.1 及后续版本')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ bottom: 14 })

          this.Section('一句话说明', [
            '当前版本下，本应用不申请任何系统权限，不联网，不采集、不上传任何个人信息，' +
              '也不存在任何服务端或数据接收方。你导入的每一张图片都只在设备本地处理，' +
              '不会离开这台设备。'
          ])

          this.Section('我们不收集的信息', [
            '不收集姓名、手机号、邮箱、通讯录、位置、照片元数据等任何个人信息。',
            '不设账号、不要求登录，也没有手机号或第三方账号绑定。',
            '没有埋点、没有崩溃上报、没有第三方统计或广告 SDK。',
            '不读取设备标识符，也不向任何服务器发送数据。'
          ])

          this.Section('权限使用', [
            '本应用未在配置文件中申请任何权限，包括网络访问、位置、相机、麦克风、' +
              '通讯录、日历、相册读写等，一项都没有。',
            '读取和保存图片均通过系统提供的文件选择器完成，由你主动选择文件与保存位置，' +
              '应用不会在后台访问你的存储空间。'
          ])

          this.Section('数据存在哪里', [
            '编辑器内的偏好设置、面板布局等保存在应用私有目录，随卸载一并清除，不备份到云端。',
            '保存与导出会写入你在系统文件选择器中指定的目录；若选择器不可用，' +
              '会改存到应用私有目录，并在提示中给出完整路径。',
            '所有图像数据仅存在于设备内存与 GPU 显存中，退出应用即释放。'
          ])

          this.Section('联网说明', [
            '本应用完全离线可用：编辑引擎、界面语言包与字体全部随安装包内嵌，' +
              '不需要下载任何在线资源。',
            '编辑引擎界面中的外部链接（例如项目主页）会调用系统浏览器打开，' +
              '该访问由浏览器发起并受浏览器自身的隐私设置约束，本应用不参与、不记录。'
          ])

          this.Section('第三方组件', [
            '编辑引擎 PhotoCraft：MIT / Apache-2.0 双许可。',
            '中文字体 Noto Sans SC：SIL Open Font License 1.1（以子集形式内嵌）。',
            '界面字体 Inter：MIT License。',
            '本应用不含任何付费、广告、推送或数据统计类第三方服务。',
            '完整的许可与署名声明见开源仓库中的 LICENSE-MIT、LICENSE-APACHE 与 NOTICE。'
          ])

          this.Section('你的权利（访问、更正、删除、注销）', [
            '本应用没有账号体系，不提供注册与登录，因此不存在账号注销、' +
              '注销后数据处理等问题。',
            '本应用不向你以外的任何一方提供数据，因此不存在向第三方转移、共享或公开披露的情形。',
            '本应用不在服务端保存你的任何信息，因此没有可供查询、更正、导出的服务端数据；' +
              '设备上由本应用写入的内容，你可通过系统文件管理自行查看与删除，' +
              '卸载应用会一并清除其私有目录下的全部数据。'
          ])

          this.Section('儿童隐私', [
            '本应用为通用图像编辑工具，不专门面向不满十四周岁的儿童，' +
              '也不会有意收集儿童个人信息。',
            '本应用不存在任何形式的自动化个人信息收集，' +
              '因此不会在儿童使用过程中获取其个人信息。'
          ])

          this.Section('第三方 SDK 与数据接收方', [
            '本应用未集成任何第三方 SDK，也未委托任何第三方处理数据。',
            '无账号、登录、云同步服务；无推送、无消息通知服务。',
            '无统计分析、无埋点、无崩溃上报服务；无广告与营销服务。',
            '无支付、无客服、无在线客服工单服务。',
            '无数据接收方清单——因为不存在任何对外传输的数据。'
          ])

          this.Section('政策更新与联系', [
            '若本政策发生变更，会在新版本的应用内本页同步更新，并通过版本说明告知。',
            '对隐私政策有疑问，可通过开源仓库的 Issues 提交，开发者会在仓库中公开答复。'
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

  @Builder
  TitleBar() {
    Row() {
      Image($r('app.media.ic_privacy'))
        .width(22)
        .height(22)
        .draggable(false)
      Text('隐私政策')
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
