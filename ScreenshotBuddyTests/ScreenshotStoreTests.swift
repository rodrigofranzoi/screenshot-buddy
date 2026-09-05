import XCTest
@testable import ScreenshotBuddy
import BuddyCore

final class ScreenshotStoreTests: XCTestCase {
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
}

import AppKit
