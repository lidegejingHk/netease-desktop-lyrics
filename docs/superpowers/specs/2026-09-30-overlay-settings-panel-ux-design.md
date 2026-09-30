# 浮层工具与样式面板交互设计

## 工具栏去掉拖动把手

工具栏第一个控件 `OverlayDragHandle`（`✥`，tooltip「拖动歌词位置」）是多余的：解锁时拖动空白背景、图标间隙或歌词文字都能移动整块浮层，锁定后它又不可用，图标本身也读不出用途。直接删除该控件与 `OverlayDragHandle` 类，工具栏只剩锁定、样式、收起三个图标，`OverlayLayout.toolbarSize` 由 160 收窄为 120（仍右上对齐，左上歌名因此多出 40 pt）。拖动保留背景与歌词两条真实入口，`onDrag` 回调不变；锁定只影响歌词与背景的命中，不再牵动任何工具按钮。

## 样式面板关闭

面板由工具栏图标唤起、贴在工具栏下方，语义接近 popover，但现在是 `.titled` 浮动窗口，只有红点能关（本 App 是 accessory，没有菜单栏，⌘W 无效）。按主流做法补齐三种关闭方式：

- **Esc**：面板为 key window 时直接关闭；同时实现 `cancelOperation`，让文本/滑块成为第一响应者时也生效。
- **⌘W**：`performKeyEquivalent` 与 `keyDown` 都处理，因为无菜单栏时系统不会路由。
- **点击面板外**：本地监视器（我们自己的其他窗口，例如浮层本体）与全局监视器（其他 App）都监听鼠标按下；命中样式面板本身或它唤起共享颜色面板时**不**关闭，避免调色时面板消失。监视器在 `show` 时安装、窗口关闭时移除。

不改成 `NSPopover`：`.transient` 的 popover 会在共享颜色面板抢 key 时自行关闭，反而破坏调色。关闭面板时照旧收起共享颜色面板。

## 样式面板不可拖动、无关闭按钮、失焦即关

面板是轻量样式弹窗，不该被拖走，也不需要标题栏红点：`styleMask` 去掉 `.closable`（标题栏保留、红点消失），并设 `panel.isMovable = false`（`setFrameOrigin` 的自动定位不受影响）。关闭方式改为「失去焦点即关」：`windowDidResignKey` 时关闭，但共享颜色面板取得 key 属于同一条调色流程，不算失焦；Esc、⌘W 与点击面板外的现有路径全部保留（点其他 App 的点击同时会触发失焦与外部点击监视器，任一先到即可）。

## 取色面板同样不可拖动、去掉标题栏按钮（待做）

共享 `NSColorPanel` 按同一标准处理：`isMovable = false`，并隐藏 `.closeButton`、`.miniaturizeButton`、`.zoomButton`。它随样式面板一起收起，不需要自己的关闭入口；取色面板取得 key 仍不算样式面板失焦。**本轮未实现**（用户提出后先收工），实现时按下面的定位规则一并配置。

## 颜色面板定位

`NSColorWell` 激活的是全局共享 `NSColorPanel`，位置是它自己的历史位置，于是可能出现在屏幕角落。改为：**弹出前**（`mouseDown` 里、`super` 之前）把它摆到样式面板旁——默认放左侧并让色块中线对齐颜色面板中线，左侧放不下时放右侧，最后按所点色块所在的可见区域夹紧。位置计算写成纯函数 `StyleSettingsPanel.colorPanelOrigin(well:panel:colorPanel:visibleFrames:)` 以便测试；不改变颜色面板本身的取色 UI。

## 验收

Swift 测试覆盖把手图标与 tint、三种关闭路径、颜色面板豁免、颜色面板定位（左/右/上下夹紧）。`./scripts/test-swift.sh`、严格 typecheck、`cargo test`、`cargo fmt --all --check`、`cargo clippy --all-targets -- -D warnings`、`git diff --check` 全绿；独立预览包用 `--stdin` 截图确认列表面板位置与关闭行为。只本地提交，不推送。
