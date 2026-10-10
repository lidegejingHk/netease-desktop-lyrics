<div align="center">

# 网易云桌面歌词（Netease Desktop Lyrics）

**NetEase Cloud Music（网易云音乐）macOS クライアント用の独立デスクトップ歌詞オーバーレイ**。ドラッグ・固定・クリック透過に対応し、プレイヤーウィンドウをいくら拡大しても、Space を切り替えても歌詞は表示されたままです。

[简体中文](README.md) · [English](README.en.md) · 日本語 · [한국어](README.ko.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/macOS%2013%2B-Apple%20Silicon-lightgrey)
[![Latest release](https://img.shields.io/github/v/release/lidegejingHk/netease-desktop-lyrics?label=release&display_name=tag)](https://github.com/lidegejingHk/netease-desktop-lyrics/releases/latest)

</div>

---

## 1. プロジェクト背景

网易云音乐（NetEase Cloud Music）の macOS クライアントにはデスクトップ歌詞が付属していますが、よくある 2 つの使い方には対応していません。

- **固定できない**：付属の歌詞は位置をロックしてデスクトップに貼り付けておけません。
- **ウィンドウを拡大すると消える**：大きなウィンドウで作業しながら歌詞を見ようとすると、付属の歌詞は表示されなくなります。

クライアントは非公開で手を入れられないため、本プロジェクトは読み取り専用のサイドカーでこの 2 点を補います。通常のウィンドウより上の**独立したオーバーレイ**で、すべての Space に追従し、ドラッグで移動でき、**ロックすると固定され、クリックは透過**します。ウィンドウを拡大しても Space を切り替えても歌詞は残ります。

安全面の方針：クライアントへの注入、プレイヤーウィンドウへの盲クリック、マイクやシステム音声の利用、アカウント情報の保存は行いません。

### クイックスタート

1. [Releases](https://github.com/lidegejingHk/netease-desktop-lyrics/releases/latest) から最新の `NeteaseDesktopLyrics-*-macos-arm64.zip` をダウンロードし、解凍して「网易云桌面歌词.app」をアプリケーションへ。
2. 初回起動を macOS がブロックしたら、「システム設定 → プライバシーとセキュリティ」で「このまま開く」を選択。
3. アクセシビリティ権限を求められたら、「システム設定 → プライバシーとセキュリティ → アクセシビリティ」で「网易云桌面歌词」を許可し、アプリを再起動。

新しいバージョンへ更新するとアプリは再署名され、macOS が以前のアクセシビリティ許可を無効とみなすことがあります。歌詞が表示されない場合は、アクセシビリティ一覧から古い項目を削除し、現在のパスのアプリを追加し直してください。

ソースからビルド：`./scripts/build-app.sh`（Rust/Cargo、Apple Command Line Tools、ネット接続が必要）。詳しい使い方は [docs/usage.md](docs/usage.md)（中国語）。

## 2. 技術スタック

| 層 | 使用技術 | 役割 |
| --- | --- | --- |
| 歌詞エンジン | Rust | 网易云の Local Storage を読み取り専用で解析し、再生状態を照合、時間付き歌詞を取得・解析して有界な JSON イベント列を出力 |
| デスクトップホスト | Swift / AppKit | メニューバー、枠なしオーバーレイとアイコンのヒットウィンドウ、スタイルパネル、アクセシビリティメニュー経由の再生操作 |
| ビルド | Cargo + `swiftc` | `scripts/build-app.sh` が .app を組み立てて ad-hoc 署名。`scripts/test-swift.sh` がホストのアサーションを実行 |

- 動作環境：Apple Silicon（arm64）、macOS 13 以上。macOS 26.6.2 と 网易云音乐 3.1.12 で検証済み。
- 网易云の内部フォーマット・メニュー・歌詞 API は公開された安定 API ではありません。他のクライアント版では再検証が必要です。

## 3. アーキテクチャ

![実行構造：网易云クライアント（読み取り専用のローカルログとコントロールメニュー）→ Rust エンジン（HTTPS 歌詞）→ Swift ホスト（JSON イベント列と AXPress による再生操作）](docs/architecture.svg)

2 プロセス・5 つのチャネル（オーバーレイの幾何、コントロール表示、歌詞帯の計測、スタイル保存などの詳細は [docs/architecture.md](docs/architecture.md)、中国語）：

1. **データチャネル**：ホストはエンジンを子プロセスとして起動し、stdout を 1 行ずつ読み取ります。各イベントは歌詞・再生フラグ・推定位置・短い状態コードを持ち、**曲 ID を含みません**（1 行 64 KiB 上限）。
2. **再生状態（Rust）**：网易云の Local Storage（LevelDB ログ）を読み取り専用で解析し、アクセシビリティ経由で読んだ「コントロール」メニューの文言と照合。単調時計で位置を推定し、一時停止中は凍結します。
3. **歌詞と曲名（Rust）**：数字の曲 ID を確認した後、システムの `curl`（HTTPS のみ）で歌詞と曲詳細を取得。アカウント Cookie は使わず、ディスクにも書かず、キャッシュはプロセス内のみ。
4. **再生操作（Swift）**：网易云のコントロールメニューから一意で有効、AXPress 可能な項目を選んで押します（0.35 秒タイムアウト）。プレイヤーウィンドウへの盲クリックはしません。
5. **デスクトップオーバーレイ（Swift/AppKit）**：枠なし `NSPanel` 群で、角丸背景・歌詞帯・ツールバーと再生キー・下部の波形を構成。ロック後は背景と歌詞がクリック透過になり、コントロールだけが操作可能。コントロールの表示はポインタに追従します。

## 4. デモ

![コンセプトデモ：付属のデスクトップ歌詞は拡大したウィンドウに飲み込まれる。置き換えたオーバーレイはドラッグ・ロック・クリック透過ができ、ウィンドウをいくら拡大しても表示され続ける](docs/demo/desktop-lyrics-demo.gif)

*コンセプトアニメーション（実機録画ではありません）。ソースと再レンダリング手順は [docs/demo/](docs/demo/)。*

## 5. コントリビュート

- **問題報告**：macOS のバージョン、网易云音乐のバージョン、再現手順を書いてください。⚠️ コマンドライン出力には実際の曲 ID と歌詞が含まれることがあります。**貼り付けないでください**。
- **コード**：`main` からブランチ → 変更 → ローカルでテスト → PR。PR には動機・変更内容・検証方法を書いてください。
- **歓迎する領域**：新しいクライアント版への対応、歌詞 API とフォーマットの変化、インタラクションとアクセシビリティの細部、ドキュメントと翻訳。

## 6. 開発規約

- **ブランチとコミット**：`main` へ直接 push しない。すべての変更はブランチ + PR で。コミットメッセージは英語の命令形で「何を」より「なぜ」を書く。
- **テストは必ず通す**：`cargo test`（エンジン）と `./scripts/test-swift.sh`（ホストの幾何・インタラクションのアサーション）。`scripts/build-app.sh` は `-warnings-as-errors` でホストをコンパイルします。
- **振る舞いの変更にはアサーション**：インタラクションを追加・変更したら `tests/OverlayAppearanceTests/` に対応するアサーションを追加。
- **契約を守る**：エンジンのイベント列はホストの唯一の入力（有界な JSON 行、曲 ID なし、1 行 64 KiB 上限）。ホストは再生状態を推測せず、検証済みの観測だけを信頼します。
- **プライバシー**：クライアントへの注入やデータの収集・送信はしません。実際の曲 ID と歌詞を Issue・ログ・コミットに出さないでください。
- **バージョンとリリース**：バージョンの唯一の出所は `app/Info.plist`。手順は [docs/release.md](docs/release.md)（中国語）。

## 7. サポート

このツールが役に立ったら、作者にコーヒーを一杯おごっていただけると嬉しいです ☕️

<!-- 投げ銭用の QR 画像を docs/support/ に置いて（例：wechat-reward.png / alipay-reward.png）コメントを外してください：
<p align="center">
  <img src="docs/support/wechat-reward.png" width="200" alt="WeChat 投げ銭コード">
  <img src="docs/support/alipay-reward.png" width="200" alt="Alipay 投げ銭コード">
</p>
-->

⭐️ や Issue、PR も立派なサポートです。

---

ライセンス：[MIT](LICENSE) · 使い方：[docs/usage.md](docs/usage.md) · 診断とプライバシー：[docs/diagnostics.md](docs/diagnostics.md)
