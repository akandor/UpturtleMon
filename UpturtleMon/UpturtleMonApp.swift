import SwiftUI
import AppKit

@main
struct UpturtleMonApp: App {
    @State private var store = MonitorStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(store)
                .task { store.start() }
        } label: {
            Image(nsImage: hasDownMonitors ? .menuBarIconAlert : .menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("UpturtleMon Settings", id: WindowID.settings) {
            SettingsView()
                .environment(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    private var hasDownMonitors: Bool {
        store.visibleGroups.contains { group in
            group.monitors.contains { $0.status == .down }
        }
    }
}

enum WindowID {
    static let settings = "settings"
}

private extension NSImage {
    /// Pre-sized template NSImage for the menu bar. MenuBarExtra reads the
    /// image's intrinsic size for layout and ignores SwiftUI .frame()
    /// modifiers, so a raw SVG asset would render at its full viewBox size
    /// and overflow the menu bar.
    static let menuBarIcon: NSImage = makeMenuBarIcon(tint: nil)

    /// Solid red variant used when any visible monitor is down.
    static let menuBarIconAlert: NSImage = makeMenuBarIcon(tint: .systemRed)

    private static func makeMenuBarIcon(tint: NSColor?) -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let source = NSImage(named: "upturtle-mon") ?? NSImage(
            systemSymbolName: "tortoise.fill",
            accessibilityDescription: nil
        )!
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            if let tint {
                tint.set()
                rect.fill(using: .sourceAtop)
            }
            return true
        }
        // Template = system tints with menu bar foreground color.
        // For the red alert variant we set the color explicitly and opt out.
        image.isTemplate = tint == nil
        return image
    }
}
