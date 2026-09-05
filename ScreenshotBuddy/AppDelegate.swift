import AppKit
import SwiftUI
import BuddyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        BuddyLaunchAtLogin.enableByDefaultOnFirstInstall()

        let store = ScreenshotStore.shared
        let pause = BuddyPauseController.shared
        pause.restorePersistedPauseIfNeeded()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.action = #selector(togglePopover)
            button.target = self
        }
        statusItem = item
        updateStatusIcon()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarGalleryView()
                .environmentObject(store)
                .environmentObject(pause)
        )
        self.popover = popover

        NotificationCenter.default.addObserver(
            forName: .buddyPauseDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusIcon()
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateStatusIcon() {
        let paused = BuddyPauseController.shared.isPaused
        let name = paused ? "camera.metering.unknown" : "camera.viewfinder"
        let description = paused ? "Screenshot Buddy (paused)" : "Screenshot Buddy"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        statusItem?.button?.appearsDisabled = paused
    }
}
