# 浮层工具与样式面板交互设计

## 拖动把手

工具栏第一个控件是 `OverlayDragHandle`，画的是 `✥`，tooltip 与无障碍标签为「拖动歌词位置」：解锁时可拖动整块浮层，锁定后变暗并点击穿透。它不是唯一入口（空白背景、歌词文字同样可拖），但当前字形含义不清。改用系统符号 `arrow.up.and.down.and.arrow.left.and.right`（app 内已有的 `NSImage(systemSymbolName:)` 模式），保留尺寸、tint 跟随歌词文字色、锁定降到 42% 透明度与穿透行为；符号不可用时回退到同样的四向箭头字形。

## 样式面板关闭

面板由工具栏图标唤起、贴在工具栏下方，语义接近 popover，但现在是 `.titled` 浮动窗口，只有红点能关（本 App 是 accessory，没有菜单栏，⌘W 无效）。按主流做法补齐三种关闭方式：

- **Esc**：面板为 key window 时直接关闭；同时实现 `cancelOperation`，让文本/滑块成为第一响应者时也生效。
- **⌘W**：`performKeyEquivalent` 与 `keyDown` 都处理，因为无菜单栏时系统不会路由。
- **点击面板外**：本地监视器（我们自己的其他窗口，例如浮层本体）与全局监视器（其他 App）都监听鼠标按下；命中样式面板本身或它唤起共享颜色面板时**不**关闭，避免调色时面板消失。监视器在 `show` 时安装、窗口关闭时移除。

不改成 `NSPopover`：`.transient` 的 popover 会在共享颜色面板抢 key 时自行关闭，反而破坏调色。关闭面板时照旧收起共享颜色面板。

## 颜色面板定位

`NSColorWell` 激活的是全局共享 `NSColorPanel`，位置是它自己的历史位置，于是可能出现在屏幕角落。改为：**弹出前**（`mouseDown` 里、`super` 之前）把它摆到样式面板旁——默认放左侧并让色块中线对齐颜色面板中线，左侧放不下时放右侧，最后按所点色块所在的可见区域夹紧。位置计算写成纯函数 `StyleSettingsPanel.colorPanelOrigin(well:panel:colorPanel:visibleFrames:)` 以便测试；不改变颜色面板本身的取色 UI。

## 验收

Swift 测试覆盖把手图标与 tint、三种关闭路径、颜色面板豁免、颜色面板定位（左/右/上下夹紧）。`./scripts/test-swift.sh`、严格 typecheck、`cargo test`、`cargo fmt --all --check`、`cargo clippy --all-targets -- -D warnings`、`git diff --check` 全绿；独立预览包用 `--stdin` 截图确认列表面板位置与关闭行为。只本地提交，不推送。
