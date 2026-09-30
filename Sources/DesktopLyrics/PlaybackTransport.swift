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
        let pressable: Bool

        init(role: String, title: String, enabled: Bool, pressable: Bool = true) {
            self.role = role
            self.title = title
            self.enabled = enabled
            self.pressable = pressable
        }
    }

    struct Availability: Equatable {
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

        func suppressing(_ action: Action) -> Self {
            switch action {
            case .previous: return Self(previous: false, toggle: toggle, next: next)
            case .play, .pause: return Self(previous: previous, toggle: .unavailable, next: next)
            case .next: return Self(previous: previous, toggle: toggle, next: false)
            }
        }
    }

    /// Keep a failed menu action disabled while the player still reports the
    /// same menu state. A real menu-state change clears the failure latch.
    struct FailureLatch {
        private(set) var failed: (action: Action, state: Availability)?
        private var interrupted = false

        var hasFailure: Bool { failed != nil }

        mutating func record(_ action: Action, in state: Availability) {
            failed = (action, state)
            interrupted = false
        }

        mutating func visibleState(for current: Availability) -> Availability {
            guard let failed else { return current }
            if failed.state == current { return current.suppressing(failed.action) }
            if current == .unavailable {
                // A temporary AX timeout is not evidence that the player
                // actually changed its menu; keep the failure until it returns.
                interrupted = true
                return current
            }
            if interrupted && current.allows(failed.action) {
                interrupted = false
                return current.suppressing(failed.action)
            }
            self.failed = nil
            interrupted = false
            return current
        }
    }

    static func uniqueIndex(for action: Action, in items: [Item]) -> Int? {
        let matches = items.indices.filter { action.titles.contains(items[$0].title) }
        guard matches.count == 1, items[matches[0]].role == "AXMenuItem",
              items[matches[0]].enabled, items[matches[0]].pressable else { return nil }
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
        return availability(menu.map(\.item))
    }

    /// Freshly resolve both the current menu and the intended action before pressing.
    @discardableResult
    static func perform(_ action: Action) -> Bool {
        guard let menu = readMenu(),
              let index = uniqueIndex(for: action, in: menu.map(\.item)),
              availability(menu.map(\.item)).allows(action) else { return false }
        let element = menu[index].element
        // AX menu state can change after the snapshot; fail closed on a stale element.
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
                             enabled: bool(element, kAXEnabledAttribute as CFString),
                             pressable: supportsPress(element)),
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
