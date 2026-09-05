import AppKit
import Foundation
import SwiftUI
import BuddyCore
import BuddyFirebase
import Combine
import UniformTypeIdentifiers

@MainActor
final class ScreenshotStore: ObservableObject {
    static let shared = ScreenshotStore()

    @Published var items: [ScreenshotItem] = []
    @Published var selectedId: UUID?
    @Published var draftNotes: String = ""

    private let key = "screenshot.items"

    var selected: ScreenshotItem? {
        items.first { $0.id == selectedId }
    }

    init() { load() }

    func importFromPasteboard() {
        let pb = NSPasteboard.general
        if let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation {
            addImageData(tiff, title: "Pasted screenshot")
        }
    }

    func addImageData(_ data: Data, title: String) {
        var tags: [ContentTag] = [.image]
        var notes = draftNotes
        let tagged = ContentTagger.tag(text: draftNotes)
        let embedded = ContentTagger.embeddedSensitiveTags(in: draftNotes)
        if tagged.isSensitive || !embedded.isEmpty {
            tags.append(contentsOf: tagged.tags.filter { $0 != .text })
            tags.append(contentsOf: embedded)
        }
        let item = ScreenshotItem(imageData: data, title: title, notes: notes, tags: Array(Set(tags)))
        items.insert(item, at: 0)
        selectedId = item.id
        save()
    }

    func updateNotes(_ notes: String, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].notes = notes
        let tagged = ContentTagger.tag(text: notes)
        let embedded = ContentTagger.embeddedSensitiveTags(in: notes)
        var tags = Set(items[idx].tags)
        tags.insert(.image)
        tags.formUnion(tagged.tags)
        tags.formUnion(embedded)
        items[idx].tags = Array(tags)
        save()
    }

    func addRedaction(_ rect: RedactionRect, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].redactionRects.append(rect)
        save()
    }

    func quickRedactSensitive(for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        // Placeholder band across top area when sensitive notes detected
        let tagged = ContentTagger.tag(text: items[idx].notes)
        guard tagged.isSensitive else { return }
        items[idx].redactionRects.append(RedactionRect(x: 0.05, y: 0.05, width: 0.9, height: 0.12, style: .blackBox))
        save()
    }

    func renderedImage(for item: ScreenshotItem) -> NSImage? {
        guard let base = NSImage(data: item.imageData) else { return nil }
        let size = base.size
        let image = NSImage(size: size)
        image.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))
        for r in item.redactionRects {
            let rect = NSRect(
                x: r.x * size.width,
                y: (1.0 - r.y - r.height) * size.height,
                width: r.width * size.width,
                height: r.height * size.height
            )
            if r.style == .blackBox {
                NSColor.black.setFill()
                rect.fill()
            } else {
                NSColor.black.withAlphaComponent(0.55).setFill()
                rect.fill()
            }
        }
        image.unlockFocus()
        return image
    }

    func copyToClipboard(_ item: ScreenshotItem) {
        guard let image = renderedImage(for: item) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        BuddyFirebase.log(event: BuddyFirebase.Event.screenshotExported, parameters: ["action": "copy"])
    }

    func saveAs(_ item: ScreenshotItem, url: URL) {
        guard let image = renderedImage(for: item),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        BuddyFirebase.log(event: BuddyFirebase.Event.screenshotExported, parameters: ["action": "saveAs"])
    }

    func overwrite(_ item: ScreenshotItem) {
        guard let image = renderedImage(for: item), let tiff = image.tiffRepresentation,
              let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].imageData = tiff
        items[idx].redactionRects = []
        save()
        BuddyFirebase.log(event: BuddyFirebase.Event.screenshotExported, parameters: ["action": "overwrite"])
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ScreenshotItem].self, from: data) {
            items = decoded
        }
    }
}
