import AppKit

// Entry point is AppKit's rather than SwiftUI's `App`.
//
// Every window Glancie puts on screen is an `NSPanel` it owns — the bar, the
// menu, the cat — so the `App` protocol had no scene to describe. Satisfying its
// "declare at least one scene" requirement with `Settings { EmptyView() }` was
// not free: that scene is a real window, it is the only one the app has, and on
// a first run there is no saved state to keep it shut. It opened by itself,
// empty, in front of the user.
//
// `NSApplication` asks for no scene, so there is none to leak.

// Top-level code is not main-actor isolated, but it is the main thread, which is
// what `AppDelegate` and `NSApplication` actually require.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate

    // What `LSUIElement` in the bundle's Info.plist says, said again for the
    // times the binary runs outside a bundle: `swift run` otherwise puts a Dock
    // icon up for a menu bar app.
    application.setActivationPolicy(.accessory)

    // Holds the main thread for the life of the process.
    application.run()
}
