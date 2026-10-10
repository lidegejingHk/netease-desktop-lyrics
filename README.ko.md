<div align="center">

# 网易云桌面歌词 (Netease Desktop Lyrics)

**NetEase Cloud Music(网易云音乐) macOS 클라이언트용 독립 데스크톱 가사 오버레이**: 드래그·잠금·클릭 통과를 지원하며, 플레이어 창을 아무리 키우거나 Space를 바꿔도 가사는 계속 표시됩니다.

[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · 한국어

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/macOS%2013%2B-Apple%20Silicon-lightgrey)
[![Latest release](https://img.shields.io/github/v/release/lidegejingHk/netease-desktop-lyrics?label=release&display_name=tag)](https://github.com/lidegejingHk/netease-desktop-lyrics/releases/latest)

</div>

---

## 1. 프로젝트 배경

NetEase Cloud Music의 macOS 클라이언트에는 데스크톱 가사가 내장되어 있지만, 가장 흔한 두 가지 사용 방식은 지원하지 않습니다.

- **고정할 수 없음**: 내장 가사는 위치를 잠그고 데스크톱에 붙여 둘 수 없습니다.
- **창을 키우면 사라짐**: 큰 창으로 작업하면서 가사를 보려 하면 내장 가사는 표시되지 않습니다.

클라이언트는 소스가 공개되지 않아 손댈 수 없으므로, 이 프로젝트는 읽기 전용 사이드카로 이 두 가지를 보완합니다. 일반 창 위에 떠 있는 **독립 오버레이**로, 모든 Space를 따라가고 드래그로 옮길 수 있으며, **잠그면 고정되고 클릭은 통과**됩니다. 창을 키우든 Space를 바꾸든 가사는 그대로 남습니다.

안전 원칙: 클라이언트에 주입하지 않고, 플레이어 창에 무작위 클릭을 보내지 않으며, 마이크나 시스템 오디오를 사용하지 않고, 계정 정보를 저장하지 않습니다.

### 빠른 시작

1. [Releases](https://github.com/lidegejingHk/netease-desktop-lyrics/releases/latest)에서 최신 `NeteaseDesktopLyrics-*-macos-arm64.zip`을 내려받아 압축을 풀고 「网易云桌面歌词.app」을 응용 프로그램 폴더로 옮깁니다.
2. 첫 실행이 macOS에 의해 차단되면 시스템 설정 → 개인정보 보호 및 보안에서 "확인 없이 열기"를 선택합니다.
3. 손쉬운 사용 권한을 요청하면 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 "网易云桌面歌词"를 허용한 뒤 앱을 다시 실행합니다.

새 버전으로 업데이트하면 앱이 다시 서명되어 macOS가 이전 손쉬운 사용 권한을 인정하지 않을 수 있습니다. 새 버전에서 가사가 보이지 않으면 손쉬운 사용 목록에서 예전 항목을 지우고 현재 경로의 앱을 다시 추가하세요.

소스에서 빌드: `./scripts/build-app.sh`(Rust/Cargo, Apple Command Line Tools, 네트워크 필요). 자세한 사용법은 [docs/usage.md](docs/usage.md)(중국어).

## 2. 기술 스택

| 계층 | 사용 기술 | 역할 |
| --- | --- | --- |
| 가사 엔진 | Rust | NetEase의 Local Storage를 읽기 전용으로 파싱하고 재생 상태를 교차 확인, 시간별 가사를 가져와 파싱해 유계 JSON 이벤트 스트림을 출력 |
| 데스크톱 호스트 | Swift / AppKit | 메뉴 막대, 테두리 없는 오버레이와 아이콘 히트 윈도, 스타일 패널, 손쉬운 사용 메뉴를 통한 재생 제어 |
| 빌드 | Cargo + `swiftc` | `scripts/build-app.sh`가 .app을 구성하고 ad-hoc 서명, `scripts/test-swift.sh`가 호스트 단언 실행 |

- 실행 환경: Apple Silicon(arm64), macOS 13 이상; macOS 26.6.2와 NetEase Cloud Music 3.1.12에서 검증.
- NetEase의 내부 형식, 메뉴, 가사 API는 공개된 안정 API가 아니므로 다른 클라이언트 버전에서는 재검증이 필요합니다.

## 3. 아키텍처

![실행 구조: NetEase 클라이언트(읽기 전용 로컬 로그와 컨트롤 메뉴) → Rust 엔진(HTTPS 가사) → Swift 호스트(JSON 이벤트 스트림과 AXPress 재생 제어)](docs/architecture.svg)

두 개의 프로세스, 다섯 개의 채널(오버레이 기하, 컨트롤 표시, 가사 밴드 측정, 스타일 저장 등 자세한 내용은 [docs/architecture.md](docs/architecture.md), 중국어):

1. **데이터 채널**: 호스트가 엔진을 자식 프로세스로 실행하고 stdout을 한 줄씩 읽습니다. 각 이벤트는 가사, 재생 플래그, 추정 위치, 짧은 상태 코드를 담고 **곡 ID는 포함하지 않습니다**(줄당 64 KiB 상한).
2. **재생 상태(Rust)**: NetEase Local Storage의 LevelDB 로그를 읽기 전용으로 파싱하고, 손쉬운 사용으로 읽은 「컨트롤」 메뉴 문구와 교차 확인합니다. 단조 시계로 위치를 추정하고 일시정지 중에는 동결합니다.
3. **가사와 곡명(Rust)**: 숫자 곡 ID를 확인한 뒤 시스템 `curl`(HTTPS 전용)로 가사와 곡 상세를 요청합니다. 계정 쿠키를 쓰지 않고 디스크에 쓰지 않으며, 캐시는 프로세스 안에서만 유지됩니다.
4. **재생 제어(Swift)**: NetEase 「컨트롤」 메뉴에서 유일하고 활성화되어 있으며 AXPress가 가능한 항목을 찾아 누릅니다(0.35초 타임아웃). 플레이어 창에 무작위 클릭을 하지 않습니다.
5. **데스크톱 오버레이(Swift/AppKit)**: 테두리 없는 `NSPanel` 묶음으로 둥근 배경, 가사 밴드, 툴바와 재생 키, 하단 파형을 구성합니다. 잠그면 배경과 가사는 클릭을 통과하고 컨트롤만 동작하며, 컨트롤 표시는 포인터를 따라갑니다.

## 4. 데모

![개념 데모: 내장 데스크톱 가사는 커진 창에 가려 사라지고, 대체 오버레이는 드래그·잠금·클릭 통과가 되며 창을 아무리 키워도 계속 보인다](docs/demo/desktop-lyrics-demo.gif)

*개념 애니메이션(실기 녹화 아님). 소스와 재렌더링 방법은 [docs/demo/](docs/demo/).*

## 5. 기여하기

- **문제 제보**: macOS 버전, NetEase Cloud Music 버전, 재현 절차를 적어 주세요. ⚠️ 명령줄 출력에 실제 곡 ID와 가사가 포함될 수 있으니 **붙여 넣지 마세요**.
- **코드 기여**: `main`에서 브랜치 생성 → 수정 → 로컬 테스트 통과 → PR 생성. PR에는 동기, 변경 내용, 검증 방법을 적어 주세요.
- **특히 환영하는 방향**: 새 클라이언트 버전 대응, 가사 API와 형식 변화 대응, 인터랙션과 접근성 세부, 문서와 번역.

## 6. 개발 규칙

- **브랜치와 커밋**: `main`에 직접 push하지 않고 모든 변경은 브랜치 + PR로 진행합니다. 커밋 메시지는 영어 명령형으로, "무엇"보다 "왜"를 설명합니다.
- **테스트는 항상 통과**: `cargo test`(엔진)와 `./scripts/test-swift.sh`(호스트 기하·인터랙션 단언). `scripts/build-app.sh`는 `-warnings-as-errors`로 호스트를 컴파일합니다.
- **동작 변경에는 단언**: 인터랙션을 추가·수정하면 `tests/OverlayAppearanceTests/`에 해당 단언을 함께 추가합니다.
- **계약 유지**: 엔진 이벤트 스트림은 호스트의 유일한 입력입니다(유계 JSON 줄, 곡 ID 없음, 줄당 64 KiB 상한). 호스트는 재생 상태를 추측하지 않고 검증된 관측만 신뢰합니다.
- **프라이버시 원칙**: 클라이언트에 주입하거나 데이터를 수집·전송하지 않습니다. 실제 곡 ID와 가사는 이슈·로그·커밋에 남기지 마세요.
- **버전과 릴리스**: 버전의 유일한 출처는 `app/Info.plist`이며, 전체 절차는 [docs/release.md](docs/release.md)(중국어)에 있습니다.

## 7. 후원

이 도구가 도움이 되셨다면 작가에게 커피 한 잔을 사 주세요 ☕️

<!-- 후원 QR 이미지를 docs/support/에 넣고(예: wechat-reward.png / alipay-reward.png) 아래 주석을 해제하세요:
<p align="center">
  <img src="docs/support/wechat-reward.png" width="200" alt="위챗 후원 코드">
  <img src="docs/support/alipay-reward.png" width="200" alt="알리페이 후원 코드">
</p>
-->

⭐️, 이슈, PR도 좋은 후원입니다.

---

라이선스: [MIT](LICENSE) · 사용법: [docs/usage.md](docs/usage.md) · 진단과 프라이버시: [docs/diagnostics.md](docs/diagnostics.md)
