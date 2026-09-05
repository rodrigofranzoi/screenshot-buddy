import SwiftUI
import BuddyFirebase

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
    }
}
