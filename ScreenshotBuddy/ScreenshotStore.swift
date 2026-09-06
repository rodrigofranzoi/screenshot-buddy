import Darwin
import AppKit
import Foundation
import SwiftUI
import BuddyCore
import BuddyFirebase
import Combine
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
final class ScreenshotStore: ObservableObject {
    static let shared = ScreenshotStore()

    @Published var items: [ScreenshotItem] = []
    @Published var selectedId: UUID?
    @Published var draftNotes: String = ""
    @Published var query: String = ""

    let unlockSession = SensitiveUnlockSession.shared

    private let itemsKey = "screenshot.items"
    private let ciContext = CIContext(options: nil)
    private var undoStacks: [UUID: [EditSnapshot]] = [:]
    private var redoStacks: [UUID: [EditSnapshot]] = [:]
    private let maxUndoDepth = 50

    private struct EditSnapshot: Equatable {
        var imageData: Data
        var redactionRects: [RedactionRect]
        var drawStrokes: [DrawStroke]
        var annotations: [ImageAnnotation]
    }

    // MARK: - Auto-detect new screenshots
    private var metadataQuery: NSMetadataQuery?
    private var queryObservers: [NSObjectProtocol] = []
    private var knownScreenshotPaths: Set<String> = []
    private var hasSeededKnownScreenshots = false
    private var pasteboardTimer: Timer?
    private var lastPasteboardChangeCount: Int = -1
    private var importTasks: [String: Task<Void, Never>] = [:]
    private var folderWatchSources: [DispatchSourceFileSystemObject] = []
    private var folderPollTimer: Timer?
    private var watchedDirectories: [URL] = []
    private var knownFilesInWatchedDirs: Set<String> = []
    private var monitoringStartedAt = Date()
    private var burstTimer: Timer?
    private var burstDeadline: Date?
    private var hotkeyMonitor: Any?

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]

    var selected: ScreenshotItem? {
        items.first { $0.id == selectedId }
    }

    var filtered: [ScreenshotItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(q)
                || $0.notes.lowercased().contains(q)
                || $0.ocrText.lowercased().contains(q)
                || $0.tags.contains { $0.rawValue.contains(q) }
                || $0.annotations.contains { $0.text.lowercased().contains(q) }
        }
    }

    init() {
        load()
    }

    func startMonitoring() {
        monitoringStartedAt = Date()
        startMetadataQuery()
        startFolderWatch()
        startPasteboardWatch()
        startScreenshotHotkeyMonitor()
    }

    func stopMonitoring() {
        stopMetadataQueryOnly()
        stopFolderWatch()
        stopBurstScan()
        stopScreenshotHotkeyMonitor()
        hasSeededKnownScreenshots = false
        knownScreenshotPaths = []
        pasteboardTimer?.invalidate()
        pasteboardTimer = nil
        for (_, task) in importTasks { task.cancel() }
        importTasks = [:]
    }

    private func startMetadataQuery() {
        stopMetadataQueryOnly()

        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]

        let finish = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.seedKnownScreenshots(from: query)
            }
        }
        let update = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleMetadataUpdate(note)
            }
        }
        queryObservers = [finish, update]
        metadataQuery = query
        query.start()
    }

    private func stopMetadataQueryOnly() {
        for observer in queryObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        queryObservers = []
        metadataQuery?.disableUpdates()
        metadataQuery?.stop()
        metadataQuery = nil
    }

    private func seedKnownScreenshots(from query: NSMetadataQuery) {
        query.disableUpdates()
        defer { query.enableUpdates() }
        for case let item as NSMetadataItem in query.results {
            if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                knownScreenshotPaths.insert(path)
            }
        }
        hasSeededKnownScreenshots = true
    }

    private func handleMetadataUpdate(_ note: Notification) {
        guard hasSeededKnownScreenshots else { return }
        let added = (note.userInfo?["kMDQueryUpdateAddedItems"] as? [NSMetadataItem]) ?? []
        for item in added {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            enqueueDiskScreenshot(path: path)
        }
    }

    // MARK: Folder watch (Cmd+Shift+3/4 → disk)

    private func startFolderWatch() {
        stopFolderWatch()
        watchedDirectories = Self.screenshotDirectories()
        knownFilesInWatchedDirs = Self.listImagePaths(in: watchedDirectories)
        knownScreenshotPaths.formUnion(knownFilesInWatchedDirs)

        for dir in watchedDirectories {
            let path = dir.path
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .link, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor in
                    // Directory changed — scan aggressively for a few seconds.
                    self?.startBurstScan(duration: 4)
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            folderWatchSources.append(source)
        }

        folderPollTimer?.invalidate()
        folderPollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanWatchedDirectoriesForNewScreenshots()
            }
        }
    }

    private func stopFolderWatch() {
        folderPollTimer?.invalidate()
        folderPollTimer = nil
        for source in folderWatchSources {
            source.cancel()
        }
        folderWatchSources = []
        watchedDirectories = []
        knownFilesInWatchedDirs = []
    }

    /// Starts the moment ⌘⇧3/4 is pressed so we catch the file as soon as it lands (not after Spotlight/folder UI updates).
    private func startScreenshotHotkeyMonitor() {
        stopScreenshotHotkeyMonitor()
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isDiskScreenshotHotkey(event) else { return }
            Task { @MainActor in
                // Region capture (4) can take a while; full-screen (3) is quick — cover both.
                self?.startBurstScan(duration: 25)
            }
        }
    }

    private func stopScreenshotHotkeyMonitor() {
        if let hotkeyMonitor {
            NSEvent.removeMonitor(hotkeyMonitor)
        }
        hotkeyMonitor = nil
    }

    private static func isDiskScreenshotHotkey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), flags.contains(.shift) else { return false }
        // ⌃⌘⇧3/4 goes to the clipboard — pasteboard watcher handles those.
        if flags.contains(.control) { return false }
        let key = event.charactersIgnoringModifiers
        return key == "3" || key == "4"
    }

    private func startBurstScan(duration: TimeInterval) {
        burstDeadline = Date().addingTimeInterval(duration)
        scanWatchedDirectoriesForNewScreenshots()
        guard burstTimer == nil else { return }
        burstTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.scanWatchedDirectoriesForNewScreenshots()
                if let deadline = self.burstDeadline, Date() >= deadline {
                    self.stopBurstScan()
                }
            }
        }
    }

    private func stopBurstScan() {
        burstTimer?.invalidate()
        burstTimer = nil
        burstDeadline = nil
    }

    private func scanWatchedDirectoriesForNewScreenshots() {
        let current = Self.listImagePaths(in: watchedDirectories)
        let newcomers = current.subtracting(knownFilesInWatchedDirs)
        knownFilesInWatchedDirs = current
        for path in newcomers {
            guard Self.shouldImportDiskImage(at: path, monitoringStartedAt: monitoringStartedAt) else {
                knownScreenshotPaths.insert(path)
                continue
            }
            enqueueDiskScreenshot(path: path)
        }
    }

    private func enqueueDiskScreenshot(path: String) {
        guard !knownScreenshotPaths.contains(path) else { return }
        knownScreenshotPaths.insert(path)
        scheduleImport(path: path, title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
    }

    private static func screenshotDirectories() -> [URL] {
        var dirs: [URL] = []
        if let custom = readScreencaptureLocation() {
            dirs.append(custom)
        }
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            dirs.append(desktop)
        }
        if let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            let screenshots = pictures.appendingPathComponent("Screenshots", isDirectory: true)
            if FileManager.default.fileExists(atPath: screenshots.path) {
                dirs.append(screenshots)
            }
        }
        var seen = Set<String>()
        return dirs.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func readScreencaptureLocation() -> URL? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.screencapture", "location"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private static func listImagePaths(in directories: [URL]) -> Set<String> {
        var paths = Set<String>()
        let fm = FileManager.default
        for dir in directories {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in contents {
                let ext = url.pathExtension.lowercased()
                guard imageExtensions.contains(ext) else { continue }
                paths.insert(url.standardizedFileURL.path)
            }
        }
        return paths
    }

    private static func shouldImportDiskImage(at path: String, monitoringStartedAt: Date) -> Bool {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent.lowercased()
        let looksNamed =
            name.contains("screenshot")
            || name.contains("screen shot")
            || name.contains("captura")
            || name.contains("bildschirm")
            || name.contains("capture d")
            || name.contains("capture de")
            || name.hasPrefix("scherm")

        guard looksNamed else { return false }

        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let created = values?.creationDate ?? values?.contentModificationDate
        guard let created else { return true }
        // Ignore old files that appear after a folder refresh.
        return created >= monitoringStartedAt.addingTimeInterval(-5)
    }

    private func startPasteboardWatch() {
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        pasteboardTimer?.invalidate()
        pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboardForScreenshot()
            }
        }
    }

    /// Captures screenshots that go to the clipboard (⌃⌘⇧3 / 4, or Save to Clipboard).
    private func pollPasteboardForScreenshot() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = pb.changeCount
        guard Self.looksLikeClipboardScreenshot(pb) else { return }
        guard let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation else { return }
        if let first = items.first, first.imageData == tiff { return }
        addImageData(tiff, title: "Clipboard screenshot")
    }

    /// Heuristic: image flavors only (no file URLs / rich text) — typical of macOS screenshot→clipboard.
    private static func looksLikeClipboardScreenshot(_ pb: NSPasteboard) -> Bool {
        guard let types = pb.types, !types.isEmpty else { return false }
        let raw = types.map(\.rawValue)
        if raw.contains(where: {
            $0 == NSPasteboard.PasteboardType.fileURL.rawValue
                || $0 == "public.file-url"
                || $0.lowercased().contains("rtf")
                || $0.lowercased().contains("html")
        }) {
            return false
        }
        let hasImage = raw.contains(where: {
            let t = $0.lowercased()
            return t.contains("image") || t.contains("tiff") || t.contains("png") || t.contains("jpeg")
        })
        guard hasImage, NSImage(pasteboard: pb) != nil else { return false }
        if let str = pb.string(forType: .string), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    private func scheduleImport(path: String, title: String) {
        importTasks[path]?.cancel()
        importTasks[path] = Task { @MainActor in
            defer { importTasks[path] = nil }
            // Read as soon as the file is valid — no fixed delay.
            for _ in 0..<40 {
                guard !Task.isCancelled else { return }
                if importScreenshotFile(at: path, title: title) { return }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    @discardableResult
    private func importScreenshotFile(at path: String, title: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url), data.count > 64,
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation else { return false }
        if let first = items.first, first.imageData == tiff { return true }
        // Avoid double-import if the same capture also landed on the pasteboard.
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        addImageData(tiff, title: title)
        // File landed — no need to keep bursting.
        stopBurstScan()
        return true
    }

    func isHidden(_ item: ScreenshotItem) -> Bool {
        unlockSession.shouldHide(isSensitive: item.isSensitive)
    }

    func reveal(item: ScreenshotItem, completion: @escaping (Bool) -> Void) {
        unlockSession.unlock(reason: String(localized: "Reveal sensitive screenshot")) { success in
            if success {
                BuddyFirebase.log(event: BuddyFirebase.Event.sensitiveRevealed)
            }
            completion(success)
        }
    }

    func importFromPasteboard() {
        let pb = NSPasteboard.general
        if let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation {
            if ContentSafety.evaluate(imageData: tiff).isBlocked {
                handleBlockedContent()
                return
            }
            addImageDataUnchecked(tiff, title: "Pasted screenshot")
        }
    }

    func addImageData(_ data: Data, title: String) {
        if ContentSafety.evaluate(imageData: data).isBlocked {
            handleBlockedContent()
            return
        }
        if ContentSafety.evaluate(text: draftNotes).isBlocked {
            handleBlockedContent()
            return
        }
        addImageDataUnchecked(data, title: title)
    }

    private func addImageDataUnchecked(_ data: Data, title: String) {
        if let first = items.first, first.imageData == data { return }

        var tags: [ContentTag] = [.image]
        let notes = draftNotes
        let tagged = ContentTagger.tag(text: draftNotes)
        let embedded = ContentTagger.embeddedSensitiveTags(in: draftNotes)
        if tagged.isSensitive || !embedded.isEmpty {
            tags.append(contentsOf: tagged.tags.filter { $0 != .text })
            tags.append(contentsOf: embedded)
        }
        // OCR image for sensitive tags (passwords, IBANs, etc.)
        let ocrRegions = SensitiveRegionFinder.findRegions(in: data)
        for region in ocrRegions {
            tags.append(contentsOf: region.tags)
        }
        let item = ScreenshotItem(
            imageData: data,
            title: title,
            notes: notes,
            tags: Array(Set(tags)),
            autoBlurTagValues: [],
            ocrText: ""
        )
        items.insert(item, at: 0)
        selectedId = item.id
        prune()
        save()
        refreshOCRText(for: item.id)
    }

    private func handleBlockedContent() {
        BuddyFirebase.log(event: BuddyFirebase.Event.contentBlocked)
        ContentSafety.notifyBlocked()
    }

    func updateTitle(_ title: String, for id: UUID) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if ContentSafety.evaluate(text: trimmed).isBlocked {
            handleBlockedContent()
            return
        }
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].title = trimmed
        save()
    }

    func updateNotes(_ notes: String, for id: UUID) {
        if ContentSafety.evaluate(text: notes).isBlocked {
            handleBlockedContent()
            return
        }
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
        pushUndo(for: id)
        items[idx].redactionRects.append(rect)
        save()
    }

    func addStroke(_ stroke: DrawStroke, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        guard stroke.points.count > 1 else { return }
        pushUndo(for: id)
        items[idx].drawStrokes.append(stroke)
        save()
    }

    func addAnnotation(_ annotation: ImageAnnotation, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        pushUndo(for: id)
        items[idx].annotations.append(annotation)
        save()
    }

    func updateAnnotation(_ annotation: ImageAnnotation, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              let aIdx = items[idx].annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        pushUndo(for: id)
        items[idx].annotations[aIdx] = annotation
        save()
    }

    func removeAnnotation(_ annotationID: UUID, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              items[idx].annotations.contains(where: { $0.id == annotationID }) else { return }
        pushUndo(for: id)
        items[idx].annotations.removeAll { $0.id == annotationID }
        save()
    }

    /// Crops the base image to a normalized top-left rect and clears overlays. Undoable.
    @discardableResult
    func crop(toNormalized rect: CGRect, for id: UUID) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return false }
        let item = items[idx]
        guard let base = NSImage(data: item.imageData),
              base.size.width > 0, base.size.height > 0 else { return false }

        let nx = min(max(rect.minX, 0), 1)
        let ny = min(max(rect.minY, 0), 1)
        let nw = min(max(rect.width, 0), 1 - nx)
        let nh = min(max(rect.height, 0), 1 - ny)
        guard nw > 0.01, nh > 0.01 else { return false }

        let pixelRect = NSRect(
            x: nx * base.size.width,
            y: (1.0 - ny - nh) * base.size.height,
            width: nw * base.size.width,
            height: nh * base.size.height
        )
        guard let cropped = cropImage(base, to: pixelRect),
              let tiff = cropped.tiffRepresentation else { return false }

        pushUndo(for: id)
        items[idx].imageData = tiff
        items[idx].redactionRects = []
        items[idx].drawStrokes = []
        items[idx].annotations = []
        items[idx].ocrText = ""
        save()
        objectWillChange.send()
        refreshOCRText(for: id)
        return true
    }

    func detectQRCodes(for id: UUID) -> [QRCodePayload] {
        guard let item = items.first(where: { $0.id == id }) else { return [] }
        return ScreenshotSmartTools.detectQRCodes(in: item.imageData)
    }

    func sampleColorHex(atNormalized point: CGPoint, for id: UUID) -> String? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        return ScreenshotSmartTools.sampleColorHex(in: item.imageData, atNormalized: point)
    }

    var canUndoSelected: Bool {
        guard let id = selectedId else { return false }
        return !(undoStacks[id] ?? []).isEmpty
    }

    var canRedoSelected: Bool {
        guard let id = selectedId else { return false }
        return !(redoStacks[id] ?? []).isEmpty
    }

    func undo(for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              var stack = undoStacks[id],
              let previous = stack.popLast() else { return }
        redoStacks[id, default: []].append(snapshot(of: items[idx]))
        apply(previous, to: idx)
        undoStacks[id] = stack
        objectWillChange.send()
        save()
    }

    func redo(for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              var stack = redoStacks[id],
              let next = stack.popLast() else { return }
        undoStacks[id, default: []].append(snapshot(of: items[idx]))
        apply(next, to: idx)
        redoStacks[id] = stack
        objectWillChange.send()
        save()
    }

    private func pushUndo(for id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        var stack = undoStacks[id] ?? []
        stack.append(snapshot(of: item))
        if stack.count > maxUndoDepth {
            stack.removeFirst(stack.count - maxUndoDepth)
        }
        undoStacks[id] = stack
        redoStacks[id] = []
    }

    private func snapshot(of item: ScreenshotItem) -> EditSnapshot {
        EditSnapshot(
            imageData: item.imageData,
            redactionRects: item.redactionRects,
            drawStrokes: item.drawStrokes,
            annotations: item.annotations
        )
    }

    private func apply(_ snapshot: EditSnapshot, to idx: Int) {
        let previousData = items[idx].imageData
        items[idx].imageData = snapshot.imageData
        items[idx].redactionRects = snapshot.redactionRects
        items[idx].drawStrokes = snapshot.drawStrokes
        items[idx].annotations = snapshot.annotations
        if previousData != snapshot.imageData {
            items[idx].ocrText = ""
            let id = items[idx].id
            refreshOCRText(for: id)
        }
    }

    func duplicate(_ item: ScreenshotItem) {
        var copy = item
        copy.id = UUID()
        copy.createdAt = Date()
        if !copy.title.lowercased().hasSuffix(" copy") {
            copy.title = "\(item.title) copy"
        }
        items.insert(copy, at: 0)
        selectedId = copy.id
        prune()
        save()
    }

    /// Manually applies blur for the given detected matches. Undoable.
    @discardableResult
    func applyAutoBlur(matches: [AutoBlurMatch], for id: UUID) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }), !matches.isEmpty else { return false }
        let existing = items[idx].redactionRects
        var additions: [RedactionRect] = []
        for match in matches {
            let rect = match.region.asBlurRedaction()
            if !existing.contains(where: { SensitiveRegionFinder.roughlyCovers($0, rect) })
                && !additions.contains(where: { SensitiveRegionFinder.roughlyCovers($0, rect) }) {
                additions.append(rect)
            }
        }
        guard !additions.isEmpty else { return false }
        pushUndo(for: id)
        items[idx].redactionRects.append(contentsOf: additions)
        save()
        objectWillChange.send()
        return true
    }

    /// Detected sensitive regions still awaiting blur (excludes areas already covered by redactions).
    func autoBlurPreview(for id: UUID) -> [AutoBlurMatch] {
        guard let item = items.first(where: { $0.id == id }) else { return [] }
        let matches = SensitiveRegionFinder.autoBlurMatches(
            imageData: item.imageData,
            notes: item.notes,
            enabledTags: SensitivePrivacySettings.autoBlurTags
        )
        let existing = item.redactionRects
        return matches.filter { match in
            let rect = match.region.asBlurRedaction()
            return !existing.contains(where: { SensitiveRegionFinder.roughlyCovers($0, rect) })
        }
    }

    /// Legacy: blurs every detected sensitive match.
    @discardableResult
    func applyAutoBlur(for id: UUID) -> Bool {
        applyAutoBlur(matches: autoBlurPreview(for: id), for: id)
    }

    /// Legacy name — prefer ``applyAutoBlur(for:)``.
    @discardableResult
    func ensureAutoBlur(for id: UUID) -> Bool {
        applyAutoBlur(for: id)
    }

    func quickRedactSensitive(for id: UUID) {
        guard applyAutoBlur(for: id) else {
            guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
            let tagged = ContentTagger.tag(text: items[idx].notes)
            guard tagged.isSensitive else { return }
            pushUndo(for: id)
            items[idx].redactionRects.append(
                RedactionRect(
                    x: 0.05,
                    y: 0.05,
                    width: 0.9,
                    height: 0.12,
                    style: .blur,
                    blurRadius: EditorRedactionSettings.blurRadius
                )
            )
            save()
            return
        }
    }

    func renderedImage(for item: ScreenshotItem, excludingAnnotationIDs: Set<UUID> = []) -> NSImage? {
        guard let base = NSImage(data: item.imageData) else { return nil }
        let size = base.size
        guard size.width > 0, size.height > 0 else { return base }

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
                if r.fillEnabled {
                    let fill = EditorRedactionSettings.nsColor(fromHex: r.fillColorHex)
                        .withAlphaComponent(min(max(r.fillOpacity, 0.05), 1))
                    fill.setFill()
                    rect.fill()
                }
            } else if let blurred = blurredPatch(from: base, rect: rect, radius: r.blurRadius) {
                blurred.draw(in: rect)
            } else if r.fillEnabled {
                let fill = EditorRedactionSettings.nsColor(fromHex: r.fillColorHex)
                    .withAlphaComponent(0.55)
                fill.setFill()
                rect.fill()
            }
            if r.borderEnabled {
                let border = EditorRedactionSettings.nsColor(fromHex: r.borderColorHex)
                border.setStroke()
                let path = NSBezierPath(rect: rect.insetBy(dx: r.borderWidth / 2, dy: r.borderWidth / 2))
                path.lineWidth = CGFloat(max(r.borderWidth, 1))
                path.stroke()
            }
        }

        for stroke in item.drawStrokes {
            drawStroke(stroke, in: size)
        }

        for annotation in item.annotations where !excludingAnnotationIDs.contains(annotation.id) {
            drawAnnotation(annotation, in: size)
        }

        image.unlockFocus()
        return image
    }

    private func cropImage(_ image: NSImage, to rect: NSRect) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cgImage = rep.cgImage else { return nil }
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let pixel = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: max(rect.width * scaleX, 1),
            height: max(rect.height * scaleY, 1)
        ).integral
        guard let cropped = cgImage.cropping(to: pixel) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: pixel.width / scaleX, height: pixel.height / scaleY))
    }

    private func drawAnnotation(_ annotation: ImageAnnotation, in size: CGSize) {
        let color = EditorRedactionSettings.nsColor(fromHex: annotation.colorHex)
        switch annotation.kind {
        case .arrow:
            let start = CGPoint(x: annotation.x * size.width, y: (1.0 - annotation.y) * size.height)
            let end = CGPoint(x: annotation.x2 * size.width, y: (1.0 - annotation.y2) * size.height)
            drawArrow(from: start, to: end, color: color, lineWidth: CGFloat(max(annotation.lineWidth, 1)))
        case .ellipse:
            let rect = NSRect(
                x: min(annotation.x, annotation.x2) * size.width,
                y: (1.0 - max(annotation.y, annotation.y2)) * size.height,
                width: abs(annotation.x2 - annotation.x) * size.width,
                height: abs(annotation.y2 - annotation.y) * size.height
            )
            if annotation.fillEnabled {
                color.withAlphaComponent(min(max(annotation.fillOpacity, 0.05), 1)).setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
            color.setStroke()
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: annotation.lineWidth / 2, dy: annotation.lineWidth / 2))
            path.lineWidth = CGFloat(max(annotation.lineWidth, 1))
            path.stroke()
        case .text:
            let origin = CGPoint(
                x: annotation.x * size.width,
                y: (1.0 - annotation.y) * size.height
            )
            let text = annotation.text.isEmpty ? "Text" : annotation.text
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: CGFloat(max(annotation.fontSize, 10)), weight: .semibold),
                .foregroundColor: color
            ]
            let drawn = (text as NSString).size(withAttributes: attrs)
            // NSString draws with y as baseline from bottom-left of image coords.
            (text as NSString).draw(
                at: NSPoint(x: origin.x, y: origin.y - drawn.height),
                withAttributes: attrs
            )
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = lineWidth
        path.move(to: start)
        path.line(to: end)

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 1)
        let ux = dx / length
        let uy = dy / length
        let head = max(lineWidth * 3.5, 10)
        let left = CGPoint(x: end.x - ux * head - uy * head * 0.55, y: end.y - uy * head + ux * head * 0.55)
        let right = CGPoint(x: end.x - ux * head + uy * head * 0.55, y: end.y - uy * head - ux * head * 0.55)
        path.move(to: left)
        path.line(to: end)
        path.line(to: right)

        color.setStroke()
        path.stroke()
    }

    private func drawStroke(_ stroke: DrawStroke, in size: CGSize) {
        guard stroke.points.count > 1 else { return }
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = CGFloat(max(stroke.lineWidth, 1))

        for (index, point) in stroke.points.enumerated() {
            let p = CGPoint(
                x: point.x * size.width,
                y: (1.0 - point.y) * size.height
            )
            if index == 0 {
                path.move(to: p)
            } else {
                path.line(to: p)
            }
        }
        EditorRedactionSettings.nsColor(fromHex: stroke.colorHex).setStroke()
        path.stroke()
    }

    private func blurredPatch(from image: NSImage, rect: NSRect, radius: Double) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cgImage = rep.cgImage else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        // NSImage bottom-left coords match CI after we convert from our draw rect.
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        let crop = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: max(rect.width * scaleX, 1),
            height: max(rect.height * scaleY, 1)
        )

        // Soft Gaussian only — same look as SwiftUI `.blur` used in SensitiveBlurView.
        // Scale so a preview-like radius (~10) stays soft on high-res screenshots.
        let viewLikeRadius = min(max(radius, 2), 40)
        let displayScale = max(CGFloat(cgImage.width) / 900, 1)
        let effectiveRadius = viewLikeRadius * displayScale
        let pad = max(effectiveRadius * 3, 24)
        let padded = crop.insetBy(dx: -pad, dy: -pad).intersection(ciImage.extent)
        let cropped = ciImage.cropped(to: padded).clampedToExtent()

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = cropped
        blur.radius = Float(effectiveRadius)

        guard let output = blur.outputImage?.cropped(to: crop),
              let cgOut = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgOut, size: rect.size)
    }

    func copyToClipboard(_ item: ScreenshotItem) {
        let current = items.first(where: { $0.id == item.id }) ?? item
        guard let image = renderedImage(for: current) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        // Avoid re-importing our own copy as a new "Clipboard screenshot".
        lastPasteboardChangeCount = pb.changeCount
        BuddyFirebase.log(event: BuddyFirebase.Event.screenshotExported, parameters: ["action": "copy"])
    }

    func copyTextToClipboard(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(trimmed, forType: .string)
        lastPasteboardChangeCount = pb.changeCount
    }

    func saveAs(_ item: ScreenshotItem, url: URL) {
        let current = items.first(where: { $0.id == item.id }) ?? item
        guard let image = renderedImage(for: current),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        BuddyFirebase.log(event: BuddyFirebase.Event.screenshotExported, parameters: ["action": "saveAs"])
    }

    func overwrite(_ item: ScreenshotItem) {
        guard let current = items.first(where: { $0.id == item.id }),
              let image = renderedImage(for: current),
              let tiff = image.tiffRepresentation,
              let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        pushUndo(for: item.id)
        items[idx].imageData = tiff
        items[idx].redactionRects = []
        items[idx].drawStrokes = []
        items[idx].annotations = []
        save()
        BuddyFirebase.log(event: BuddyFirebase.Event.screenshotExported, parameters: ["action": "overwrite"])
    }

    func delete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: idx)
        undoStacks[id] = nil
        redoStacks[id] = nil
        if selectedId == id {
            if items.indices.contains(idx) {
                selectedId = items[idx].id
            } else {
                selectedId = items.last?.id
            }
        }
        save()
    }

    func deleteItems(at offsets: IndexSet) {
        let ids = offsets.compactMap { items.indices.contains($0) ? items[$0].id : nil }
        for id in ids {
            delete(id)
        }
    }

    func prune() {
        let limit = max(ClipboardIgnoreSettings.screenshotMaxHistoryCount, 1)
        guard items.count > limit else { return }
        let removed = Array(items.suffix(from: limit))
        items = Array(items.prefix(limit))
        for item in removed {
            undoStacks[item.id] = nil
            redoStacks[item.id] = nil
        }
        if let selectedId, !items.contains(where: { $0.id == selectedId }) {
            self.selectedId = items.first?.id
        }
    }

    func applyHistoryLimits() {
        let before = items.count
        prune()
        if items.count != before {
            save()
        }
    }

    func clearAllHistory() {
        let ids = items.map(\.id)
        items.removeAll()
        selectedId = nil
        for id in ids {
            undoStacks[id] = nil
            redoStacks[id] = nil
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: itemsKey)
        }
    }

    /// Replaces gallery contents for App Store marketing captures.
    func installMarketingSeed() {
        UserDefaults.standard.set(true, forKey: BuddySettingsKey.requireAuthSensitiveContent)
        UserDefaults.standard.set(
            "password,iban,creditCard,apiKey,bearerToken,otp,email,phone,amount",
            forKey: BuddySettingsKey.protectedContentTags
        )
        UserDefaults.standard.set(
            "password,iban,creditCard,apiKey,bearerToken,otp,email,phone,amount",
            forKey: BuddySettingsKey.autoBlurContentTags
        )
        SensitiveUnlockSession.shared.lock()

        let now = Date()
        let login = ScreenshotItem(
            id: MarketingShotID.login,
            imageData: BuddyMarketingFixtures.loginForm(),
            title: "Login form",
            notes: "password SecretPass123! IBAN NL91 ABNA 0417 1643 00",
            tags: [.image, .password, .iban],
            createdAt: now.addingTimeInterval(-360),
            autoBlurTagValues: ["password", "iban"],
            ocrText: "Sign in Email you@company.com Password SecretPass123! IBAN NL91 ABNA 0417 1643 00 Continue"
        )
        // Gallery hero: charts stay visible (notes avoid sensitive tokens) with a few blur patches.
        let dashboard = ScreenshotItem(
            id: MarketingShotID.dashboard,
            imageData: BuddyMarketingFixtures.dashboard(),
            title: "Dashboard chart",
            notes: "Nexora HR payroll overview",
            tags: [.image, .text],
            createdAt: now.addingTimeInterval(-300),
            redactionRects: [
                // Net salary amount (not the icon)
                RedactionRect(x: 0.118, y: 0.205, width: 0.13, height: 0.05, style: .blur, blurRadius: 16),
                // Gross salary amount
                RedactionRect(x: 0.325, y: 0.205, width: 0.13, height: 0.05, style: .blur, blurRadius: 16),
                // Email in “Your information”
                RedactionRect(x: 0.74, y: 0.875, width: 0.20, height: 0.028, style: .blur, blurRadius: 12),
                // IBAN in “Your information”
                RedactionRect(x: 0.74, y: 0.910, width: 0.21, height: 0.028, style: .blur, blurRadius: 12),
                // Salary overview tooltip amounts
                RedactionRect(x: 0.40, y: 0.40, width: 0.13, height: 0.075, style: .blur, blurRadius: 11)
            ],
            ocrText: "Welcome back Alex Net salary 3,269.48 Gross salary 4,888.00 Days worked 22 Remaining leave 18 Salary overview Earnings vs deductions"
        )
        // Editor hero: payslip PDF with highlight callouts (notes stay non-sensitive so Reveal stays off).
        let payslip = ScreenshotItem(
            id: MarketingShotID.payslip,
            imageData: BuddyMarketingFixtures.payslip(),
            title: "Demo payslip",
            notes: "Nexora demo payslip — May payroll",
            tags: [.image, .text],
            createdAt: now.addingTimeInterval(-240),
            annotations: [
                ImageAnnotation(
                    kind: .ellipse,
                    x: 0.04, y: 0.600, x2: 0.96, y2: 0.655,
                    colorHex: "#E85D22",
                    lineWidth: 3.5,
                    fillEnabled: true,
                    fillOpacity: 0.22
                ),
                ImageAnnotation(
                    kind: .arrow,
                    x: 0.22, y: 0.52, x2: 0.48, y2: 0.615,
                    colorHex: "#E85D22",
                    lineWidth: 4
                ),
                ImageAnnotation(
                    kind: .text,
                    x: 0.06, y: 0.46, x2: 0.55, y2: 0.54,
                    text: "Net pay highlighted",
                    colorHex: "#E85D22",
                    fontSize: 22
                )
            ],
            ocrText: "DEMO PAYSLIP Nexora Solutions Alex Martin Net salary 3,269.48 IBAN LU28 0019 4006 4475 0000 you@email.com"
        )
        let invoice = ScreenshotItem(
            id: MarketingShotID.invoice,
            imageData: BuddyMarketingFixtures.invoice(),
            title: "Invoice PDF",
            notes: "amount IBAN card",
            tags: [.image, .amount, .iban, .creditCard],
            createdAt: now.addingTimeInterval(-180),
            autoBlurTagValues: ["amount", "iban", "creditCard"],
            ocrText: "Invoice #4821 Amount due: EUR 1,240.00 IBAN: DE89 3704 0044 0532 0130 00 Card: 4111 1111 1111 1111"
        )
        let invite = ScreenshotItem(
            id: MarketingShotID.invite,
            imageData: BuddyMarketingFixtures.inviteWithQR(),
            title: "Invite poster",
            notes: "QR invite",
            tags: [.image, .url],
            createdAt: now.addingTimeInterval(-120),
            ocrText: "Join Buddy Office Scan to open invite https://buddy.app/invite"
        )
        let palette = ScreenshotItem(
            id: MarketingShotID.palette,
            imageData: BuddyMarketingFixtures.brandPalette(),
            title: "Brand palette",
            notes: "#E85D22 #10B981 #3B82F6",
            tags: [.image, .colorHex],
            createdAt: now.addingTimeInterval(-60),
            ocrText: "Brand palette #E85D22 #10B981 #3B82F6"
        )
        let notes = ScreenshotItem(
            id: MarketingShotID.notes,
            imageData: BuddyMarketingFixtures.meetingNotes(),
            title: "Meeting notes",
            notes: "",
            tags: [.image, .text],
            createdAt: now,
            ocrText: "Meeting notes Ship gallery blur unlock Polish OCR copy flow Prep App Store screenshots"
        )

        items = [login, dashboard, payslip, invoice, invite, palette, notes]
        selectedId = MarketingShotID.dashboard
        save()
    }

    enum MarketingShotID {
        static let login = UUID(uuidString: "AAAAAAAA-0001-4000-8000-000000000001")!
        static let dashboard = UUID(uuidString: "AAAAAAAA-0001-4000-8000-000000000002")!
        static let payslip = UUID(uuidString: "AAAAAAAA-0001-4000-8000-000000000007")!
        static let invoice = UUID(uuidString: "AAAAAAAA-0001-4000-8000-000000000003")!
        static let invite = UUID(uuidString: "AAAAAAAA-0001-4000-8000-000000000004")!
        static let palette = UUID(uuidString: "AAAAAAAA-0001-4000-8000-000000000005")!
        static let notes = UUID(uuidString: "AAAAAAAA-0001-4000-8000-000000000006")!
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: itemsKey),
           let decoded = try? JSONDecoder().decode([ScreenshotItem].self, from: data) {
            items = decoded
        }
        let before = items.count
        prune()
        if items.count != before {
            save()
        }
        backfillMissingOCR()
    }

    /// Re-runs OCR for search indexing when image bytes change.
    private func refreshOCRText(for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let data = items[idx].imageData
        Task { @MainActor in
            let text = await Task.detached(priority: .utility) {
                ScreenshotOCR.recognizedText(in: data)
            }.value
            guard let i = items.firstIndex(where: { $0.id == id }),
                  items[i].imageData == data else { return }
            items[i].ocrText = text
            save()
        }
    }

    /// Fills OCR search text for older gallery items that predate `ocrText`.
    private func backfillMissingOCR() {
        // Avoid long Vision work while unit tests construct stores against real defaults.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        let pending = items.compactMap { item -> (UUID, Data)? in
            guard item.ocrText.isEmpty else { return nil }
            return (item.id, item.imageData)
        }
        guard !pending.isEmpty else { return }
        Task { @MainActor in
            var didChange = false
            for (id, data) in pending {
                let text = await Task.detached(priority: .utility) {
                    ScreenshotOCR.recognizedText(in: data)
                }.value
                guard let idx = items.firstIndex(where: { $0.id == id }),
                      items[idx].imageData == data,
                      items[idx].ocrText.isEmpty else { continue }
                items[idx].ocrText = text
                didChange = true
            }
            if didChange { save() }
        }
    }
}
