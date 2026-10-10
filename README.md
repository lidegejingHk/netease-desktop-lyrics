<div align="center">

# 网易云桌面歌词

**网易云音乐 macOS 客户端的独立桌面歌词浮层**：可拖动、可锁定、点击穿透；播放器窗口随便放大、随便切桌面，歌词都在。

简体中文 · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/macOS%2013%2B-Apple%20Silicon-lightgrey)
[![Latest release](https://img.shields.io/github/v/release/lidegejingHk/netease-desktop-lyrics?label=release&display_name=tag)](https://github.com/lidegejingHk/netease-desktop-lyrics/releases/latest)

</div>

---

## 1. 项目背景

网易云音乐 macOS 客户端自带桌面歌词，但两个最常用的场景都用不了：

- **不能固定**：自带桌面歌词无法锁定位置、固定在桌面上；
- **窗口一放大就不见**：想用大窗口看网页、同时看歌词，自带桌面歌词会直接消失。

客户端不开源、改不动，这个项目用一条只读旁路补上这两点：一块**独立浮层**浮动在所有普通窗口之上、跟随所有桌面空间，可拖动摆放，**锁定后固定不动、点击穿透**——窗口怎么放大、桌面怎么切换，歌词都在。

安全边界：不注入客户端、不向播放器窗口发送盲目点击、不使用麦克风或系统音频、不保存账号资料。

### 快速开始

1. 到 [Releases](https://github.com/lidegejingHk/netease-desktop-lyrics/releases/latest) 下载最新的 `NeteaseDesktopLyrics-*-macos-arm64.zip`，解压后把「网易云桌面歌词.app」拖进「应用程序」。
2. 首次打开被系统拦下时，在「系统设置 → 隐私与安全性」选择“仍要打开”。
3. 首次启动提示需要辅助功能权限时，在「系统设置 → 隐私与安全性 → 辅助功能」允许“网易云桌面歌词”，然后重启 App。

更新到新版本时 App 会重新签名，macOS 可能不再认可旧的辅助功能授权；若新版不显示歌词，从辅助功能列表中移除旧条目，再重新添加当前路径下的 App。

从源码构建：`./scripts/build-app.sh`（需 Rust/Cargo、Apple Command Line Tools 与联网）。更细的用法见 [docs/usage.md](docs/usage.md)。

## 2. 技术栈

| 层 | 用什么 | 负责什么 |
| --- | --- | --- |
| 歌词引擎 | Rust | 只读解析网易云 Local Storage，交叉验证播放状态，请求并解析逐行歌词，输出有界 JSON 事件流 |
| 桌面宿主 | Swift / AppKit | 菜单栏、无边框浮层与图标命中窗口、样式面板、辅助功能菜单播放控制 |
| 构建 | Cargo + `swiftc` | `scripts/build-app.sh` 组装 .app 并 ad-hoc 签名；`scripts/test-swift.sh` 跑宿主断言 |

- 运行环境：Apple Silicon（arm64）、macOS 13 及以上；在 macOS 26.6.2、网易云音乐 3.1.12 上验证。
- 网易云内部格式、菜单与歌词接口均非公开稳定 API，其他客户端版本需重新验收。

## 3. 项目架构

![运行结构：网易云客户端（只读本地日志与控制菜单）→ Rust 引擎（HTTPS 歌词）→ Swift 宿主（JSON 事件流与 AXPress 播放控制）](docs/architecture.svg)

两个进程、五条通道（更细的实现说明——浮层几何、控件显隐、歌词带测量、样式持久化——见 [docs/architecture.md](docs/architecture.md)）：

1. **数据通道**：宿主把引擎作为子进程启动，逐行读取它的 stdout；每条事件携带歌词、播放标记、估算位置与短状态码，**不含歌曲 ID**，单行上限 64 KiB。
2. **播放状态（Rust）**：只读解析网易云 Local Storage 的 LevelDB 物理日志，再与辅助功能读到的「控制」菜单文案交叉印证；用单调时钟估算位置，暂停时冻结。
3. **歌词与歌名（Rust）**：确认数字歌曲 ID 后经系统 `curl`（仅 HTTPS）请求歌词与歌曲详情接口；不使用账号 Cookie，不落盘，缓存只活在本进程内。
4. **播放控制（Swift）**：用辅助功能在网易云「控制」菜单里匹配唯一、启用且可 AXPress 的菜单项并按下（0.35 s 超时），不在播放器窗口做盲点击。
5. **桌面浮层（Swift/AppKit）**：一组无边框 `NSPanel` 组成圆角背景、歌词带、工具条与播放键、底部声浪；锁定后背景与歌词点击穿透，控件显隐跟随鼠标。

## 4. DEMO 演示

![概念演示：官方桌面歌词被放大的窗口吞掉；替代浮层可拖动、可锁定、点击穿透，窗口随便放大歌词都在](docs/demo/desktop-lyrics-demo.gif)

*概念演示动画（非实机录屏）；源文件与重新渲染方式见 [docs/demo/](docs/demo/)。*

## 5. 如何贡献

- **报问题**：写清 macOS 版本、网易云音乐版本与复现步骤。⚠️ 命令行输出可能包含真实歌曲 ID 与歌词，**不要**直接贴出来。
- **提代码**：从 `main` 拉分支 → 改代码 → 本地跑通测试 → 开 PR；PR 说明动机、改动与验证方式。
- **欢迎的方向**：适配新版网易云客户端、歌词接口与格式变化、交互与可访问性细节、文档与多语言翻译。

## 6. 项目开发规范

- **分支与提交**：不直推 `main`，每个改动走分支 + PR；提交信息用英文祈使句，说明“为什么”而不只是“改了什么”。
- **测试必须全绿**：`cargo test`（引擎）与 `./scripts/test-swift.sh`（宿主几何与交互断言）；`scripts/build-app.sh` 以 `-warnings-as-errors` 编译宿主。
- **行为改动带断言**：新增或修改交互时，在 `tests/OverlayAppearanceTests/` 补对应断言。
- **契约要守住**：引擎事件流是宿主的唯一输入（有界 JSON 行、不含歌曲 ID、单行 64 KiB 上限）；宿主不猜测播放状态，只信已验证的观测。
- **隐私红线**：不注入客户端、不采集与上传数据；真实歌曲 ID 与歌词不得出现在 Issue、日志或提交里。
- **版本与发版**：版本号唯一来源是 `app/Info.plist`，完整步骤见 [docs/release.md](docs/release.md)。

## 7. 项目支持

如果这个工具帮到了你，欢迎请作者喝杯咖啡 ☕️

<!-- 把赞赏码图片放到 docs/support/（如 wechat-reward.png / alipay-reward.png）后，取消下面的注释：
<p align="center">
  <img src="docs/support/wechat-reward.png" width="200" alt="微信赞赏码">
  <img src="docs/support/alipay-reward.png" width="200" alt="支付宝收款码">
</p>
-->

也欢迎点个 ⭐️、提 Issue 或 PR，这些都是很好的支持。

---

许可：[MIT](LICENSE) · 用法细节：[docs/usage.md](docs/usage.md) · 诊断与隐私：[docs/diagnostics.md](docs/diagnostics.md)
