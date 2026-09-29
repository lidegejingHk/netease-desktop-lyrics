/// The App bundle and terminal pipeline have different Accessibility identities.
enum DesktopLaunchMode {
    case app
    case stdin

    init(arguments: [String]) {
        self = arguments.contains("--stdin") ? .stdin : .app
    }

    var accessibilityPermissionStatus: String {
        switch self {
        case .app:
            return "请在辅助功能中允许“网易云桌面歌词”，然后重启 App"
        case .stdin:
            return "请在辅助功能中允许运行命令的终端，然后重新运行脚本"
        }
    }
}
