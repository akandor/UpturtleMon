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
            Image(nsImage: .menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("UpturtleMon Settings", id: WindowID.settings) {
            SettingsView()
                .environment(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
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
    static let menuBarIcon: NSImage = {
        let size = NSSize(width: 20, height: 20)
        let source = NSImage(named: "upturtle-mon") ?? NSImage(
            systemSymbolName: "tortoise.fill",
            accessibilityDescription: nil
        )!
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }()
}
