import SwiftUI
import BuddyFirebase
import BuddyUI
import BuddyCore

@main
struct ScreenshotBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = ScreenshotStore.shared

    init() {
        BuddyFirebase.configure()
        BuddyFirebase.log(event: BuddyFirebase.Event.appLaunch)
    }

    private let brand = BuddyBrand.screenshotBuddy
    private let settingsItems: [BuddySettingsItem] = [
        .appearance,
        .preferences,
        .privacy
    ]

    var body: some Scene {
        WindowGroup("Capture Buddy") {
            GalleryView()
                .environmentObject(store)
                .frame(minWidth: 800, minHeight: 520)
                .background(BuddyMainWindowRegistrar())
                .buddyAppearance(brand: brand)
        }
        Settings {
            BuddySettingsSidebarView(brand: brand, items: settingsItems) { item in
                switch item.id {
                case BuddySettingsItem.appearance.id:
                    BuddyAppearanceSettingsSection(brand: brand)
                case BuddySettingsItem.preferences.id:
                    ScreenshotHistorySettingsSection {
                        store.applyHistoryLimits()
                    }
                    ScreenshotFolderAccessSettingsSection(
                        folderName: store.grantedScreenshotFolderName,
                        needsAccess: store.needsScreenshotFolderAccess,
                        onChooseFolder: { store.chooseScreenshotFolder() },
                        onClearAccess: { store.clearScreenshotFolderAccess() }
                    )
                    BuddyPauseSettingsSection()
                    AutoBlurSettingsSection()
                    BuddyClearHistorySettingsSection(itemNoun: "screenshots") {
                        store.clearAllHistory()
                    }
                    BuddyStartupSettingsSection()
                case BuddySettingsItem.privacy.id:
                    SensitivePrivacySettingsSection()
                    BuddyLegalLinksSection(brand: brand)
                default:
                    EmptyView()
                }
            }
            .accessibilityIdentifier("screenshot-settings")
        }
    }
}
