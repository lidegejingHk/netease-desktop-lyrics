# 概念演示动画

`desktop-lyrics-demo.html` 是 README 顶部演示动画的源文件：纯静态 HTML、无外部依赖，
按 23 秒时间轴讲述「官方桌面歌词被放大的窗口吞掉 → 本项目的浮层可以拖动、锁定、点击穿透 →
窗口随便放大歌词都在」的完整故事，末尾给出一条小表演。

- 浏览器直接打开即可预览（循环播放）；`window.__hold(t)` 可把画面定格在第 t 秒
- 导出视频：用 Playwright 的 recordVideo（或任意录屏工具）抓 1920x1080 的 MP4，再用 ffmpeg 转 GIF；
  命令示例见 HTML 文件顶部的注释
- README 使用的是 15 秒精选剪辑版 GIF（800px、12fps）
