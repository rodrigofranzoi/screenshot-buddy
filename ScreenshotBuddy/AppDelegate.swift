import AppKit
import SwiftUI
import BuddyCore
import BuddyUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    var store: ScreenshotStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        BuddyLaunchAtLogin.enableByDefaultOnFirstInstall()
        BuddyAppearanceSettings.applyAppKitAppearance()

        let store = ScreenshotStore.shared
        self.store = store
        let pause = BuddyPauseController.shared

        pause.onPauseChanged = { [weak self] isPaused in
            if isPaused {
                self?.store?.stopMonitoring()
            } else {
                self?.store?.startMonitoring()
            }
            self?.updateStatusIcon()
        }
        pause.restorePersistedPauseIfNeeded()
        if !pause.isPaused {
            store.startMonitoring()
        }

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
                .buddyAppearance(brand: .screenshotBuddy)
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

        if BuddyMarketingCapture.isEnabled {
            NSApp.setActivationPolicy(.regular)
            ScreenshotMarketingCaptureRunner.startIfNeeded(store: store) { [weak self] in
                self?.showPopoverForCapture()
            }
        } else {
            BuddyMainWindow.hideOnLaunchIfNeeded()
        }
    }

    @discardableResult
    private func showPopoverForCapture() -> NSWindow? {
        guard let button = statusItem?.button, let popover else { return nil }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
        return popover.contentViewController?.view.window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
