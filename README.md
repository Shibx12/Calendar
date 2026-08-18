# CalendarBar

CalendarBar 是一个只驻留在 macOS 菜单栏的轻量日历倒计时。它使用系统的 EventKit 读取本机日历，不依赖网络服务或第三方库。

菜单栏会显示：

- 下一项：`出门去遛狗 in 87 min`
- 正在进行 + 下一项：`吃饭 1 h 38 mins left · 出门去遛狗 in 87 min`
- 指定时间范围内无日程：`Free`

每个事件都会在开始前 10 分钟和 5 分钟通过摄像头区域的纯黑提醒岛提示；事件在 Apple 日历中已有的绝对或相对提醒时间也会保留。相同时间的提醒会自动去重，不使用普通通知中心横幅。

提醒岛会自动收起；需要手动关闭时，把指针放在提醒岛上并用触控板向上推，它会跟随手势缩回摄像头区域。

设置顶部提供“测试提醒岛”按钮，优先预览最近的真实事件；没有未来事件时会显示临时测试内容，不会写入日历或影响正式提醒记录。

点开菜单栏项目可查看从今天开始的 7 天日程。全天事件默认显示在周视图中，但不会占用菜单栏；设置中可以选择日历和菜单栏时间范围（默认 24 小时，可直接输入 1–72 小时）。

## 系统要求

- Apple Silicon 或 Intel Mac
- macOS 13 或更高版本
- Xcode 15 或更高版本（支持并优先自动使用 `/Applications/Xcode-beta.app`）

如果尚未安装开发工具，请先从 App Store 安装 Xcode，打开一次完成组件安装，然后执行：

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

使用 Xcode Beta 时不需要执行上面的切换命令，`make` 会自动找到它。

## 构建

```bash
make app
open dist/CalendarBar.app
```

第一次打开时，请允许 CalendarBar 读取日历。生成的应用位于 `dist/CalendarBar.app`，采用本机临时签名，可以直接在当前 Mac 上使用。

运行测试：

```bash
make test
```

## 设计与体积

- AppKit `NSStatusItem` 提供真正的原生菜单栏体验。
- SwiftUI + 系统材质构成半透明、分层的系统风格界面。
- 仅链接 AppKit、SwiftUI、Combine 与 EventKit；没有数据库、网络 SDK、图片资源或第三方包。
- `LSUIElement` 隐藏 Dock 图标，应用只驻留菜单栏。
