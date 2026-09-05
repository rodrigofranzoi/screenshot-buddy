import SwiftUI
import BuddyFirebase
import BuddyUI

@main
struct ScreenshotBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = ScreenshotStore.shared

    init() {
        BuddyFirebase.configure()
        BuddyFirebase.log(event: BuddyFirebase.Event.appLaunch)
    }

    var body: some Scene {
        WindowGroup("Screenshot Buddy") {
            GalleryView()
                .environmentObject(store)
                .frame(minWidth: 800, minHeight: 520)
        }
        Settings {
            Form {
                Section("Startup") {
                    BuddyLaunchAtLoginToggle()
                }
            }
            .formStyle(.grouped)
            .frame(width: 420, height: 160)
            .accessibilityIdentifier("screenshot-settings")
        }
    }
}
