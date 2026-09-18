import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        discardSettingsWindowState()
        setupStatusItem()
        FloatingPanelController.shared.show()
    }

    /// Clears the frame AppKit saved for the SwiftUI settings window.
    ///
    /// The app used to declare a `Settings { EmptyView() }` scene to satisfy the
    /// `App` protocol, and that scene opened itself — empty — on a first run.
    /// The scene is gone, but anyone who ran an earlier build still has its
    /// saved frame sitting in their preferences, describing a window nothing
    /// will ever open again.
    ///
    /// Unconditional because removing an absent key costs one call and needs no
    /// second key to remember that the first one was already dealt with.
    private func discardSettingsWindowState() {
        UserDefaults.standard.removeObject(
            forKey: "NSWindow Frame com_apple_SwiftUI_Settings_window"
        )
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Glancie")
            button.action = #selector(toggleStatusMenu)
            button.target = self
        }
    }
    
    @objc private func toggleStatusMenu() {
        guard let button = statusItem?.button else { return }
        MenuBarPanelController.shared.toggle(relativeTo: button)
    }
}
