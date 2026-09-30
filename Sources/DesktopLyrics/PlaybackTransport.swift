import AppKit
import ApplicationServices

/// Strict menu matching keeps transport actions scoped to the NetEase player.
/// All AX calls must run off the main thread; only the returned availability
/// and result may be used to update AppKit controls on the main thread.
enum PlaybackTransport {
    enum Action: CaseIterable {
        case previous
        case play
        case pause
        case next

        var titles: Set<String> {
            switch self {
            case .previous: return ["上一个", "上一首", "上一曲", "Previous"]
            case .play: return ["播放", "Play"]
            case .pause: return ["暂停", "Pause"]
            case .next: return ["下一个", "下一首", "下一曲", "Next"]
            }
        }
    }

    struct Item {
        let role: String
        let title: String
        let enabled: Bool
    }

    struct Availability {
        let previous: Bool
        let toggle: OverlayControls.PlaybackToggle
        let next: Bool

        static let unavailable = Self(previous: false, toggle: .unavailable, next: false)

        func allows(_ action: Action) -> Bool {
            switch action {
            case .previous: return previous
            case .play: return toggle == .play
            case .pause: return toggle == .pause
            case .next: return next
            }
        }
    }

    static func uniqueIndex(for action: Action, in items: [Item]) -> Int? {
        let matches = items.indices.filter { action.titles.contains(items[$0].title) }
        guard matches.count == 1, items[matches[0]].role == "AXMenuItem",
              items[matches[0]].enabled else { return nil }
        return matches[0]
    }

    static func availability(_ items: [Item]) -> Availability {
        let play = uniqueIndex(for: .play, in: items) != nil
        let pause = uniqueIndex(for: .pause, in: items) != nil
        let toggle: OverlayControls.PlaybackToggle = play == pause
            ? .unavailable : (pause ? .pause : .play)
        return Availability(previous: uniqueIndex(for: .previous, in: items) != nil,
                            toggle: toggle,
                            next: uniqueIndex(for: .next, in: items) != nil)
    }

    static func currentAvailability() -> Availability {
        guard let menu = readMenu() else { return .unavailable }
        let actionable = menu.map { entry in
            Item(role: entry.item.role, title: entry.item.title,
                 enabled: entry.item.enabled && supportsPress(entry.element))
        }
        return availability(actionable)
    }

    /// Freshly resolve both the current menu and the intended action before pressing.
    @discardableResult
    static func perform(_ action: Action) -> Bool {
        guard let menu = readMenu(),
              let index = uniqueIndex(for: action, in: menu.map(\.item)),
              (action != .play && action != .pause) ||
                  availability(menu.map(\.item)).toggle == (action == .play ? .play : .pause)
        else { return false }
        let element = menu[index].element
        guard supportsPress(element) else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private static func supportsPress(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let actions = names as? [String] else { return false }
        return actions.contains(kAXPressAction as String)
    }

    private struct Entry {
        let item: Item
        let element: AXUIElement
    }

    private static func readMenu() -> [Entry]? {
        guard AXIsProcessTrusted() else { return nil }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.netease.163music")
        guard apps.count == 1, !apps[0].isTerminated else { return nil }
        let application = AXUIElementCreateApplication(apps[0].processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.35)
        guard let bar = element(application, kAXMenuBarAttribute as CFString),
              role(bar) == "AXMenuBar",
              let barItems = children(bar, max: 16) else { return nil }
        let controlItems = barItems.filter {
            role($0) == "AXMenuBarItem" &&
            ["控制", "Controls"].contains(title($0) ?? "")
        }
        guard controlItems.count == 1,
              let controlChildren = children(controlItems[0], max: 2) else { return nil }
        let menus = controlChildren.filter { role($0) == "AXMenu" }
        guard menus.count == 1, let menuItems = children(menus[0], max: 32) else { return nil }
        return menuItems.map { element in
            Entry(item: Item(role: role(element) ?? "",
                             title: title(element) ?? "",
                             enabled: bool(element, kAXEnabledAttribute as CFString)),
                  element: element)
        }
    }

    private static func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.35)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &result) == .success else { return nil }
        return result
    }

    private static func element(_ parent: AXUIElement, _ key: CFString) -> AXUIElement? {
        attribute(parent, key) as! AXUIElement?
    }

    private static func children(_ element: AXUIElement, max: Int) -> [AXUIElement]? {
        guard let values = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement],
              !values.isEmpty, values.count <= max else { return nil }
        return values
    }

    private static func role(_ element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute as CFString) as? String
    }

    private static func title(_ element: AXUIElement) -> String? {
        attribute(element, kAXTitleAttribute as CFString) as? String
    }

    private static func bool(_ element: AXUIElement, _ key: CFString) -> Bool {
        (attribute(element, key) as? Bool) == true
    }
}
