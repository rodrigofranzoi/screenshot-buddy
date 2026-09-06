import XCTest
@testable import ScreenshotBuddy
import BuddyCore
import AppKit

final class ScreenshotStoreTests: XCTestCase {
    @MainActor
    func testSearchMatchesNotesAndOCR() {
        let store = ScreenshotStore()
        let previousData = UserDefaults.standard.data(forKey: "screenshot.items")
        let previousSelected = store.selectedId
        defer {
            if let previousData {
                UserDefaults.standard.set(previousData, forKey: "screenshot.items")
            } else {
                UserDefaults.standard.removeObject(forKey: "screenshot.items")
            }
            if let data = previousData,
               let decoded = try? JSONDecoder().decode([ScreenshotItem].self, from: data) {
                store.items = decoded
            } else {
                store.items = []
            }
            store.selectedId = previousSelected
            store.query = ""
        }

        store.items = [
            ScreenshotItem(
                imageData: makeTestImageData(color: .cyan),
                title: "Dashboard",
                notes: "Q3 planning board",
                ocrText: "Revenue up 12%"
            ),
            ScreenshotItem(
                imageData: makeTestImageData(color: .magenta),
                title: "Login",
                notes: "",
                ocrText: "Enter password"
            )
        ]
        store.query = "planning"
        XCTAssertEqual(store.filtered.map(\.title), ["Dashboard"])

        store.query = "password"
        XCTAssertEqual(store.filtered.map(\.title), ["Login"])

        store.query = "login"
        XCTAssertEqual(store.filtered.map(\.title), ["Login"])

        store.query = ""
        XCTAssertEqual(store.filtered.count, 2)
    }

    @MainActor
    func testAddAndTagFromNotes() {
        let store = ScreenshotStore()
        store.draftNotes = "IBAN DE89370400440532013000"
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        let data = image.tiffRepresentation!
        store.addImageData(data, title: "Test")
        XCTAssertFalse(store.items.isEmpty)
        XCTAssertTrue(store.items.first?.tags.contains(.iban) ?? false)
    }

    @MainActor
    func testBlocksSexualNotesOnImport() {
        let store = ScreenshotStore()
        store.draftNotes = "free porn video"
        let before = store.items.count
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        store.addImageData(image.tiffRepresentation!, title: "Blocked")
        XCTAssertEqual(store.items.count, before)
    }

    @MainActor
    func testAutoBlurIsManual() {
        let blurKey = BuddySettingsKey.blurSensitiveContent
        let previous = UserDefaults.standard.object(forKey: blurKey)
        UserDefaults.standard.set(true, forKey: blurKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: blurKey)
            } else {
                UserDefaults.standard.removeObject(forKey: blurKey)
            }
        }

        let store = ScreenshotStore()
        store.draftNotes = "IBAN DE89370400440532013000"
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        store.addImageData(image.tiffRepresentation!, title: "Sensitive")
        XCTAssertTrue(store.items.first?.isSensitive ?? false)
        // Import must not auto-redact; apply is manual.
        XCTAssertTrue(store.items.first?.redactionRects.isEmpty ?? false)
        guard let id = store.items.first?.id else {
            return XCTFail("missing item")
        }
        _ = store.applyAutoBlur(for: id)
        XCTAssertFalse(store.items.first?.redactionRects.isEmpty ?? true)
        // Applied blurs are no longer suggested until undo restores the redaction.
        XCTAssertTrue(store.autoBlurPreview(for: id).isEmpty)
        store.undo(for: id)
        XCTAssertFalse(store.autoBlurPreview(for: id).isEmpty)
    }

    @MainActor
    func testDoesNotDuplicateIdenticalImage() {
        let store = ScreenshotStore()
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        let data = image.tiffRepresentation!
        let before = store.items.filter { $0.imageData == data }.count
        store.addImageData(data, title: "One")
        store.addImageData(data, title: "Two")
        XCTAssertEqual(store.items.filter { $0.imageData == data }.count, before + 1)
    }

    @MainActor
    func testUpdateTitleRenamesItem() {
        let store = ScreenshotStore()
        let previousData = UserDefaults.standard.data(forKey: "screenshot.items")
        let previousSelected = store.selectedId
        defer {
            if let previousData {
                UserDefaults.standard.set(previousData, forKey: "screenshot.items")
            } else {
                UserDefaults.standard.removeObject(forKey: "screenshot.items")
            }
            if let data = previousData,
               let decoded = try? JSONDecoder().decode([ScreenshotItem].self, from: data) {
                store.items = decoded
            } else {
                store.items = []
            }
            store.selectedId = previousSelected
        }

        store.items = []
        store.selectedId = nil
        store.addImageData(makeTestImageData(color: .orange), title: "Original")
        let id = store.items[0].id

        store.updateTitle("  Renamed shot  ", for: id)
        XCTAssertEqual(store.items[0].title, "Renamed shot")

        store.updateTitle("   ", for: id)
        XCTAssertEqual(store.items[0].title, "Renamed shot")
    }

    @MainActor
    func testDeleteRemovesItemAndUpdatesSelection() {
        let store = ScreenshotStore()
        let previousData = UserDefaults.standard.data(forKey: "screenshot.items")
        let previousSelected = store.selectedId
        defer {
            if let previousData {
                UserDefaults.standard.set(previousData, forKey: "screenshot.items")
            } else {
                UserDefaults.standard.removeObject(forKey: "screenshot.items")
            }
            if let data = previousData,
               let decoded = try? JSONDecoder().decode([ScreenshotItem].self, from: data) {
                store.items = decoded
            } else {
                store.items = []
            }
            store.selectedId = previousSelected
        }

        store.items = []
        store.selectedId = nil

        let first = makeTestImageData(color: .red)
        let second = makeTestImageData(color: .blue)
        store.addImageData(first, title: "First")
        store.addImageData(second, title: "Second")
        XCTAssertEqual(store.items.count, 2)

        let selected = store.selectedId
        XCTAssertEqual(selected, store.items.first?.id)

        store.delete(selected!)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.selectedId, store.items.first?.id)
        XCTAssertNotEqual(store.selectedId, selected)

        store.delete(store.items[0].id)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.selectedId)
    }

    @MainActor
    private func makeTestImageData(color: NSColor) -> Data {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        return image.tiffRepresentation!
    }
}
