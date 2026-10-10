# 版本与打包发布

版本号只有一个来源：`app/Info.plist` 的 `CFBundleShortVersionString`。发版时把它与 `Cargo.toml` 的 `version` 一起改，构建出的 App 就是新版本（`scripts/build-app.sh` 直接把该 plist 复制进包内）。

```bash
# 1) 改版本号（Info.plist: 短版本 + 构造号；Cargo.toml: version）
# 2) 从 main 构建并打标签
git tag -a v0.3.0 -m "网易云桌面歌词 v0.3.0" && git push origin v0.3.0
./scripts/build-app.sh
# 3) 打包：-X 去掉扩展属性，避免 zip 里混入 __MACOSX 垃圾
cd dist && zip -q -r -X ~/Desktop/NeteaseDesktopLyrics-v0.3.0-macos-arm64.zip "网易云桌面歌词.app" && cd ..
# 4) 校验后再发布：解包验签 + 记录 SHA-256，附到 GitHub Release
unzip -q ~/Desktop/NeteaseDesktopLyrics-v0.3.0-macos-arm64.zip -d /tmp/pkgcheck
codesign --verify --deep --strict "/tmp/pkgcheck/网易云桌面歌词.app" && shasum -a 256 ~/Desktop/NeteaseDesktopLyrics-v0.3.0-macos-arm64.zip
gh release create v0.3.0 --title "网易云桌面歌词 v0.3.0" --notes-file notes.md ~/Desktop/NeteaseDesktopLyrics-v0.3.0-macos-arm64.zip
```

发布说明里附上 SHA-256，与上传的 zip 一致；不要用系统「压缩」生成 zip（会带上 `__MACOSX` 冗余条目）。

Release 页面上的 `Source code (zip / tar.gz)` 由 GitHub 依 tag 自动生成，无法关闭或移除；能控制的只有我们自己附加的资产，通常只附一个构建好的 App 包。
