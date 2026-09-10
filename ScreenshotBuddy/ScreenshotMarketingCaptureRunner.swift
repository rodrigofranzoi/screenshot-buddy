import AppKit
import Foundation
import SwiftUI
import BuddyCore
import BuddyUI

@MainActor
enum ScreenshotMarketingCaptureRunner {
    private static var hostedWindow: NSWindow?

    static func startIfNeeded(store: ScreenshotStore, showPopover: @escaping () -> NSWindow?) {
        guard BuddyMarketingCapture.isEnabled else { return }

        store.stopMonitoring()
        store.installMarketingSeed()

        Task { @MainActor in
            do {
                let out = try BuddyMarketingCapture.ensureOutputDirectory()
                await BuddyMarketingCapture.sleep(0.4)
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let window = makeHostedWindow(store: store)
                window.makeKeyAndOrderFront(nil)
                await BuddyMarketingCapture.sleep(0.8)

                try await captureMainScenes(store: store, window: window, out: out)
                try await captureMenubar(showPopover: showPopover, out: out)

                print("[BuddyMarketing] Capture Buddy captures written to \(out.path)")
                NSApp.terminate(nil)
            } catch {
                fputs("[BuddyMarketing] ERROR: \(error)\n", stderr)
                NSApp.terminate(nil)
            }
        }
    }

    private static func makeHostedWindow(store: ScreenshotStore) -> NSWindow {
        if let hostedWindow {
            return hostedWindow
        }
        let root = GalleryView()
            .environmentObject(store)
            .frame(minWidth: 800, minHeight: 520)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Capture Buddy"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1080, height: 700))
        window.center()
        window.isReleasedWhenClosed = false
        hostedWindow = window
        BuddyMainWindow.register(window)
        return window
    }

    private static func captureMainScenes(store: ScreenshotStore, window: NSWindow, out: URL) async throws {
        let scenes: [(String, UUID, TimeInterval, Bool)] = [
            // scene, id, wait, requireAuth
            // Gallery keeps auth on so Sensitive sidebar rows stay locked; dashboard itself is not protected.
            ("gallery", ScreenshotStore.MarketingShotID.dashboard, 1.2, true),
            // Editor shows annotated payslip clearly (auth off for this scene).
            ("editor", ScreenshotStore.MarketingShotID.payslip, 1.4, false),
            ("redact", ScreenshotStore.MarketingShotID.login, 2.8, false),
            ("smart", ScreenshotStore.MarketingShotID.palette, 1.4, false),
            ("qr", ScreenshotStore.MarketingShotID.invite, 2.4, false)
        ]
        for (scene, id, wait, requireAuth) in scenes {
            UserDefaults.standard.set(requireAuth, forKey: BuddySettingsKey.requireAuthSensitiveContent)
            if requireAuth {
                SensitiveUnlockSession.shared.lock()
            } else {
                // Ensure Quick edit / redact scenes aren't left behind a Reveal overlay.
                SensitiveUnlockSession.shared.lock()
            }
            store.selectedId = id
            store.objectWillChange.send()
            BuddyMarketingCapture.stage(scene)
            await BuddyMarketingCapture.sleep(wait)
            try BuddyMarketingCapture.captureWindow(window, to: out.appendingPathComponent("\(scene).png"))
        }
        UserDefaults.standard.set(true, forKey: BuddySettingsKey.requireAuthSensitiveContent)
        SensitiveUnlockSession.shared.lock()
    }

    private static func captureMenubar(showPopover: @escaping () -> NSWindow?, out: URL) async throws {
        hostedWindow?.orderOut(nil)
        await BuddyMarketingCapture.sleep(0.3)
        guard let popoverWindow = showPopover() else {
            throw BuddyMarketingCapture.CaptureError.missingPopoverWindow
        }
        await BuddyMarketingCapture.sleep(0.8)
        try BuddyMarketingCapture.captureWindow(popoverWindow, to: out.appendingPathComponent("menubar.png"))
    }
}
