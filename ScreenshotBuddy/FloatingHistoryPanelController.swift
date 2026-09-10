import AppKit
import SwiftUI
import BuddyCore
import BuddyUI

extension Notification.Name {
    static let screenshotToggleFloatingPanel = Notification.Name("screenshot.buddy.toggleFloatingPanel")
}

@MainActor
final class FloatingScreenshotPanelController {
    private var panel: NSPanel?
    private weak var store: ScreenshotStore?

    func attach(store: ScreenshotStore) {
        self.store = store
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        guard let store else { return }
        if panel == nil {
            panel = makePanel(store: store)
        }
        guard let panel else { return }
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    var panelWindow: NSWindow? {
        panel?.isVisible == true ? panel : nil
    }

    private func makePanel(store: ScreenshotStore) -> NSPanel {
        let hosting = NSHostingController(
            rootView: FloatingScreenshotHistoryView()
                .environmentObject(store)
                .buddyAppearance(brand: .screenshotBuddy)
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 440),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "Capture Buddy")
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 240, height: 280)
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 320, y: frame.midY - 220))
        }
        return panel
    }
}

struct FloatingScreenshotHistoryView: View {
    @EnvironmentObject private var store: ScreenshotStore
    @AppStorage(BuddySettingsKey.screenshotMenuBarRecentCount) private var recentCount = 8
    @State private var copiedItemId: UUID?

    private var visibleItems: [ScreenshotItem] {
        Array(store.items.prefix(max(recentCount * 2, 20)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if visibleItems.isEmpty {
                Text("New screenshots appear here automatically.")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(selection: $store.selectedId) {
                        ForEach(visibleItems) { item in
                            FloatingScreenshotHistoryRow(
                                item: item,
                                isCopied: copiedItemId == item.id,
                                onCopy: { copyItem(item) },
                                onAutoBlur: { applyAutoBlur(item) }
                            )
                            .tag(item.id)
                            .id(item.id)
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(copiedItemId == item.id ? BuddyTheme.BuddyColor.success.opacity(0.22) : Color.clear)
                                    .padding(.vertical, 1)
                            )
                        }
                    }
                    .listStyle(.inset)
                    .onChange(of: store.selectedId) { id in
                        scrollTo(id, proxy: proxy, anchor: .center)
                    }
                    .onChange(of: visibleItems.first?.id) { id in
                        scrollTo(id, proxy: proxy, anchor: .top)
                    }
                    .onAppear {
                        scrollTo(store.selectedId ?? visibleItems.first?.id, proxy: proxy, anchor: .top)
                    }
                }
            }
        }
        .frame(minWidth: 240, minHeight: 280)
        .accessibilityIdentifier("floating-screenshot-history")
    }

    private var header: some View {
        HStack(spacing: BuddyTheme.Spacing.xs) {
            Text("History")
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                BuddyMainWindow.show()
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.borderless)
            .help("Open gallery")
            .accessibilityLabel("Open gallery")
        }
        .padding(.horizontal, BuddyTheme.Spacing.sm)
        .padding(.vertical, BuddyTheme.Spacing.xs)
    }

    private func copyItem(_ item: ScreenshotItem) {
        store.selectedId = item.id
        let performCopy = {
            store.copyToClipboard(item)
            copiedItemId = item.id
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if copiedItemId == item.id {
                    copiedItemId = nil
                }
            }
        }
        if store.isHidden(item) {
            store.reveal(item: item) { ok in
                if ok { performCopy() }
            }
        } else {
            performCopy()
        }
    }

    private func applyAutoBlur(_ item: ScreenshotItem) {
        store.selectedId = item.id
        _ = store.applyAutoBlur(for: item.id)
    }

    private func scrollTo(_ id: UUID?, proxy: ScrollViewProxy, anchor: UnitPoint) {
        guard let id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        }
    }
}

private struct FloatingScreenshotHistoryRow: View {
    @EnvironmentObject private var store: ScreenshotStore
    @ObservedObject private var unlock = SensitiveUnlockSession.shared
    @AppStorage(BuddySettingsKey.autoBlurContentTags) private var protectedTagsRaw: String = ""
    @AppStorage(BuddySettingsKey.requireAuthSensitiveContent) private var requireAuth = false

    let item: ScreenshotItem
    let isCopied: Bool
    let onCopy: () -> Void
    let onAutoBlur: () -> Void

    private var isHidden: Bool {
        _ = protectedTagsRaw
        _ = requireAuth
        _ = unlock.unlockedUntil
        return store.isHidden(item)
    }

    var body: some View {
        HStack(spacing: BuddyTheme.Spacing.sm) {
            Button(action: onCopy) {
                HStack(spacing: BuddyTheme.Spacing.sm) {
                    ZStack(alignment: .bottomTrailing) {
                        if let img = NSImage(data: item.imageData) {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 40)
                                .clipped()
                                .cornerRadius(4)
                                .blur(radius: isHidden ? 8 : 0)
                        } else {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 52, height: 40)
                        }

                        if isCopied {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, BuddyTheme.BuddyColor.success)
                                .font(.system(size: 14, weight: .bold))
                                .offset(x: 4, y: 4)
                        }
                    }
                    .accessibilityLabel(isCopied ? "Copied" : (isHidden ? "Hidden sensitive screenshot" : "Screenshot thumbnail"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isHidden ? "•••• Sensitive" : item.title)
                            .lineLimit(1)
                            .foregroundStyle(isCopied ? BuddyTheme.BuddyColor.success : Color.primary)
                        Text(isCopied ? "Copied" : item.createdAt.formatted())
                            .font(.caption)
                            .foregroundStyle(isCopied ? BuddyTheme.BuddyColor.success.opacity(0.9) : Color.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCopied ? "Copied" : "Copy to clipboard")
            .accessibilityLabel(isCopied ? "Copied screenshot" : "Copy screenshot")

            Button(action: onAutoBlur) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
            }
            .buttonStyle(.borderless)
            // Do not call autoBlurPreview here — that runs Vision OCR synchronously and
            // hitchs the panel (and trips priority-inversion when invoked from MainActor).
            .help("Auto-blur secrets, then click to copy")
            .accessibilityLabel("Auto-blur")
            .accessibilityIdentifier("floating-autoblur")
        }
        .padding(.vertical, 2)
    }
}
