import SwiftUI
import AppKit
import BuddyCore
import BuddyUI
import UniformTypeIdentifiers

struct GalleryView: View {
    @EnvironmentObject private var store: ScreenshotStore
    @State private var drawMode: DrawMode = .none
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var pendingDeleteId: UUID?

    enum DrawMode {
        case none
        case rectangle
        case blur
        case draw
        case arrow
        case ellipse
        case text
        case crop
        case colorPicker

        var systemImage: String {
            switch self {
            case .none: return "cursorarrow"
            case .arrow: return "arrow.up.right"
            case .ellipse: return "oval"
            case .rectangle: return "rectangle"
            case .draw: return "scribble.variable"
            case .text: return "textformat"
            case .blur: return "drop"
            case .crop: return "crop"
            case .colorPicker: return "eyedropper"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if store.needsScreenshotFolderAccess {
                    HStack(alignment: .center, spacing: BuddyTheme.Spacing.sm) {
                        Image(systemName: "folder.badge.questionmark")
                            .foregroundStyle(.orange)
                        Text("Allow Desktop (or your screenshot folder) so ⌘⇧3 / ⌘⇧4 shots appear here.")
                            .font(BuddyTheme.Typography.caption)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Allow…") {
                            store.chooseScreenshotFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier("gallery-allow-screenshot-folder")
                    }
                    .padding(.horizontal, BuddyTheme.Spacing.md)
                    .padding(.vertical, BuddyTheme.Spacing.sm)
                    .background(Color.orange.opacity(0.12))
                }

                ScrollViewReader { proxy in
                    List(selection: $store.selectedId) {
                        ForEach(store.filtered) { item in
                            GalleryRow(item: item)
                                .tag(item.id)
                                .id(item.id)
                                .listRowSeparator(.visible)
                                .listRowSeparatorTint(BuddyTheme.BuddyColor.border.opacity(0.4))
                                .accessibilityIdentifier("gallery-row")
                                .contextMenu {
                                    Button {
                                        store.duplicate(item)
                                    } label: {
                                        Label("Duplicate", systemImage: "plus.square.on.square")
                                    }
                                    Button {
                                        store.copyToClipboard(item)
                                    } label: {
                                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                                    }
                                    Button(role: .destructive) {
                                        pendingDeleteId = item.id
                                    } label: {
                                        Label("Delete…", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeleteId = item.id
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete { offsets in
                            if let idx = offsets.first, store.filtered.indices.contains(idx) {
                                pendingDeleteId = store.filtered[idx].id
                            }
                        }
                    }
                    .listStyle(.inset)
                    .accessibilityIdentifier("gallery-list")
                    .onDeleteCommand {
                        pendingDeleteId = store.selectedId
                    }
                    .onChange(of: store.selectedId) { id in
                        focusGalleryList(on: id, proxy: proxy)
                    }
                    .onChange(of: store.items.first?.id) { _ in
                        focusGalleryList(on: store.selectedId, proxy: proxy)
                    }
                }
            }
            .searchable(text: $store.query, placement: .sidebar, prompt: "Search")
            .navigationTitle("Gallery")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 420)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    BuddySettingsGearButton(accessibilityIdentifier: "open-settings")
                }
            }
        } detail: {
            if let item = store.selected {
                EditorPane(item: item, drawMode: $drawMode, dragStart: $dragStart, dragCurrent: $dragCurrent)
            } else {
                Text("New screenshots appear here automatically.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Delete Screenshot?", isPresented: Binding(
            get: { pendingDeleteId != nil },
            set: { if !$0 { pendingDeleteId = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeleteId = nil }
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteId {
                    store.delete(id)
                }
                pendingDeleteId = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .buddyMarketingStageScene)) { note in
            guard let scene = note.userInfo?[BuddyMarketingCapture.sceneKey] as? String else { return }
            switch scene {
            case "editor":
                drawMode = .arrow
            case "smart":
                drawMode = .colorPicker
            case "redact", "qr", "gallery":
                drawMode = .none
            default:
                break
            }
        }
    }

    private func focusGalleryList(on id: UUID?, proxy: ScrollViewProxy) {
        guard let id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}

struct GalleryRow: View {
    @EnvironmentObject private var store: ScreenshotStore
    @ObservedObject private var unlock = SensitiveUnlockSession.shared
    @AppStorage(BuddySettingsKey.autoBlurContentTags) private var protectedTagsRaw: String = ""
    @AppStorage(BuddySettingsKey.requireAuthSensitiveContent) private var requireAuth = false
    let item: ScreenshotItem

    private var isHidden: Bool {
        _ = protectedTagsRaw
        _ = requireAuth
        _ = unlock.unlockedUntil
        return store.isHidden(item)
    }

    var body: some View {
        HStack {
            if let img = NSImage(data: item.imageData) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 36)
                    .clipped()
                    .cornerRadius(4)
                    .blur(radius: isHidden ? 8 : 0)
                    .accessibilityLabel(isHidden ? "Hidden sensitive screenshot" : "Screenshot thumbnail")
            }
            VStack(alignment: .leading) {
                Text(isHidden ? "•••• Sensitive" : item.title).lineLimit(1)
                Text(item.tags.map(\.rawValue).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isHidden {
                Button {
                    store.reveal(item: item) { _ in }
                } label: {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reveal sensitive screenshot")
            }
        }
        .padding(.vertical, BuddyTheme.Spacing.sm)
    }
}

struct EditorPane: View {
    @EnvironmentObject private var store: ScreenshotStore
    @ObservedObject private var unlock = SensitiveUnlockSession.shared
    @AppStorage(BuddySettingsKey.autoBlurContentTags) private var protectedTagsRaw: String = ""
    @AppStorage(BuddySettingsKey.requireAuthSensitiveContent) private var requireAuth = false
    @AppStorage(BuddySettingsKey.editorBlurRadius) private var blurRadius: Double = 10
    @AppStorage(BuddySettingsKey.editorBlackBoxOpacity) private var blackBoxOpacity: Double = 1
    @AppStorage(BuddySettingsKey.editorBlackBoxColor) private var blackBoxColorHex: String = "#000000"
    @AppStorage(BuddySettingsKey.editorFillEnabled) private var fillEnabled = true
    @AppStorage(BuddySettingsKey.editorBorderEnabled) private var borderEnabled = false
    @AppStorage(BuddySettingsKey.editorBorderColor) private var borderColorHex: String = "#FFFFFF"
    @AppStorage(BuddySettingsKey.editorBorderWidth) private var borderWidth: Double = 3
    @AppStorage(BuddySettingsKey.editorDrawColor) private var drawColorHex: String = "#FF3B30"
    @AppStorage(BuddySettingsKey.editorDrawSize) private var drawSize: Double = 4
    @AppStorage(BuddySettingsKey.editorToolsCollapsed) private var toolsCollapsed = false
    let item: ScreenshotItem
    @Binding var drawMode: GalleryView.DrawMode
    @Binding var dragStart: CGPoint?
    @Binding var dragCurrent: CGPoint?
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var isSyncingMetadata = false
    @State private var confirmDelete = false
    @State private var isHoveringCanvas = false
    @State private var autoBlurExpanded = true
    @State private var autoBlurMatches: [AutoBlurMatch] = []
    @State private var isLoadingAutoBlurPreview = false
    @State private var autoBlurPreviewGeneration = 0
    @State private var liveStrokePoints: [CGPoint] = []
    @State private var fittedImageFrame: CGRect = .zero
    @State private var selectedText = ""
    @State private var annotationLineWidth: Double = 3
    @State private var annotationFontSize: Double = 18
    @State private var annotationFontName: String = "System"
    @State private var annotationTextAlignment: String = "left"
    @State private var textPlacementStart: CGPoint?
    @State private var textPlacementCurrent: CGPoint?
    @State private var ellipseFillEnabled = false
    @State private var qrPayloads: [QRCodePayload] = []
    @State private var qrScanGeneration = 0
    @State private var isScanningQR = false
    /// Skips the imageData-driven QR refresh that follows an item selection change.
    @State private var suppressImageDataQRRefresh = false
    @State private var ocrText = ""
    @State private var pickedColorHex = ""
    @State private var smartExpanded = true
    @State private var qrScanExpanded = true
    @State private var annotateExpanded = true
    @State private var textDraft: TextAnnotationDraft?
    /// Holds typed text without publishing SwiftUI state on every keystroke.
    @State private var textEditBuffer = AnnotateTextBuffer()
    /// Bumped to focus the text view after placing/selecting a box (drives a SwiftUI refresh).
    @State private var textFocusGeneration = 0
    /// Baked image with the draft annotation excluded; stable while the draft is open.
    @State private var textDraftCanvasImage: NSImage?
    @State private var cropInsetLeft: Double = 0
    @State private var cropInsetRight: Double = 0
    @State private var cropInsetTop: Double = 0
    @State private var cropInsetBottom: Double = 0
    @State private var cropHandleDragStart: (left: Double, right: Double, top: Double, bottom: Double)?
    @State private var canvasZoom: CGFloat = 1
    @State private var canvasZoomGestureBase: CGFloat = 1

    private static let minCanvasZoom: CGFloat = 1
    private static let maxCanvasZoom: CGFloat = 8
    private static let minCropKeep = 0.01
    /// Extra canvas margin so crop handles stay visible outside the image edge.
    private static let cropCanvasPadding: CGFloat = 14

    private enum CropHandle: CaseIterable, Hashable {
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight
        case move
    }

    private var isHidden: Bool {
        _ = protectedTagsRaw
        _ = requireAuth
        _ = unlock.unlockedUntil
        return store.isHidden(item)
    }

    private var usesCrosshair: Bool {
        switch drawMode {
        case .rectangle, .blur, .arrow, .ellipse, .crop, .colorPicker, .text:
            return true
        default:
            return false
        }
    }

    private var usesDrawCursor: Bool {
        drawMode == .draw
    }

    private var usesLiveText: Bool {
        drawMode == .none && !isHidden
    }

    private var usesDragShape: Bool {
        switch drawMode {
        case .rectangle, .blur, .ellipse, .arrow:
            return true
        default:
            return false
        }
    }

    private var isCropping: Bool {
        drawMode == .crop
    }

    private var showToolsPanel: Bool { !toolsCollapsed }

    private var blackBoxSwiftUIColor: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: EditorRedactionSettings.nsColor(fromHex: blackBoxColorHex))
            },
            set: { newColor in
                blackBoxColorHex = EditorRedactionSettings.hex(from: NSColor(newColor))
            }
        )
    }

    private var borderSwiftUIColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: EditorRedactionSettings.nsColor(fromHex: borderColorHex)) },
            set: { borderColorHex = EditorRedactionSettings.hex(from: NSColor($0)) }
        )
    }

    private var drawSwiftUIColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: EditorRedactionSettings.nsColor(fromHex: drawColorHex)) },
            set: { drawColorHex = EditorRedactionSettings.hex(from: NSColor($0)) }
        )
    }

    private var selectionPreviewFill: Color {
        switch drawMode {
        case .none:
            return Color.accentColor.opacity(0.18)
        case .blur, .crop:
            return Color.primary.opacity(0.06)
        case .ellipse:
            return ellipseFillEnabled
                ? Color(nsColor: EditorRedactionSettings.nsColor(fromHex: drawColorHex)).opacity(0.2)
                : Color.clear
        case .rectangle:
            if fillEnabled {
                return Color(nsColor: EditorRedactionSettings.nsColor(fromHex: blackBoxColorHex))
                    .opacity(min(max(blackBoxOpacity * 0.35, 0.08), 0.45))
            }
            return Color.clear
        default:
            return Color.clear
        }
    }

    private var selectionPreviewStroke: Color {
        switch drawMode {
        case .none:
            return Color.accentColor
        case .rectangle where borderEnabled:
            return Color(nsColor: EditorRedactionSettings.nsColor(fromHex: borderColorHex))
        case .blur:
            return Color.secondary
        case .crop:
            return Color.accentColor
        case .arrow, .ellipse, .text:
            return Color(nsColor: EditorRedactionSettings.nsColor(fromHex: drawColorHex))
        default:
            return Color.primary
        }
    }

    private var selectionPreviewLineWidth: CGFloat {
        if drawMode == .rectangle, borderEnabled {
            return CGFloat(max(borderWidth, 1))
        }
        return 1.5
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                GeometryReader { geo in
                    let excluding = textDraft.map { Set([$0.annotationID]) } ?? []
                    let rendered = textDraftCanvasImage
                        ?? store.renderedImage(for: item, excludingAnnotationIDs: excluding)
                    let _ = blurRadius
                    let _ = blackBoxOpacity
                    let _ = blackBoxColorHex
                    let _ = fillEnabled
                    let _ = borderEnabled
                    let _ = borderColorHex
                    let _ = borderWidth
                    let _ = drawColorHex
                    let _ = drawSize
                    let fitted = fittedImageRect(imageSize: rendered?.size ?? .zero, in: geo.size)

                    SensitiveBlurView(isHidden: isHidden) {
                        store.reveal(item: item) { _ in }
                    } content: {
                        let zoom = min(max(canvasZoom, Self.minCanvasZoom), Self.maxCanvasZoom)
                        let zoomedSize = CGSize(
                            width: fitted.width * zoom,
                            height: fitted.height * zoom
                        )
                        let cropPad = isCropping ? Self.cropCanvasPadding : 0
                        let canvasContentSize = CGSize(
                            width: zoomedSize.width + cropPad * 2,
                            height: zoomedSize.height + cropPad * 2
                        )
                        // Image stays inset when cropping; crop math never uses the padding.
                        let imageBounds = CGRect(
                            x: cropPad,
                            y: cropPad,
                            width: zoomedSize.width,
                            height: zoomedSize.height
                        )
                        let hostSize = CGSize(
                            width: max(geo.size.width, canvasContentSize.width),
                            height: max(geo.size.height, canvasContentSize.height)
                        )
                        // Canvas is centered inside the scroll host.
                        let canvasOriginInHost = CGPoint(
                            x: (hostSize.width - canvasContentSize.width) / 2,
                            y: (hostSize.height - canvasContentSize.height) / 2
                        )
                        let imageBoundsInHost = imageBounds.offsetBy(
                            dx: canvasOriginInHost.x,
                            dy: canvasOriginInHost.y
                        )

                        ScrollView([.horizontal, .vertical], showsIndicators: zoom > 1.01 || isCropping) {
                            ZStack {
                                // Expand the scroll content so the image stays centered when
                                // it is smaller than the viewport (fit / light zoom).
                                Color.clear
                                    .frame(width: hostSize.width, height: hostSize.height)

                                if usesLiveText, let image = rendered {
                                    // Same host sizing as the annotation canvas so Select does not
                                    // jump/zoom relative to other tools. Live Text fills the
                                    // aspect-fit frame only (no letterbox hit targets).
                                    ZStack {
                                        LiveTextImageView(
                                            image: image,
                                            selectedText: $selectedText,
                                            isInteractionEnabled: true
                                        )
                                        .frame(width: zoomedSize.width, height: zoomedSize.height)
                                        .position(x: imageBounds.midX, y: imageBounds.midY)
                                    }
                                    .frame(width: canvasContentSize.width, height: canvasContentSize.height)
                                    .clipped()
                                    .contentShape(Rectangle())
                                    .accessibilityLabel("Screenshot text selection canvas")
                                } else {
                                    // Keep image + annotation hit-testing inside the image frame
                                    // so letterbox margins cannot receive arrows/shapes.
                                    ZStack {
                                        if let image = rendered {
                                            Image(nsImage: image)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: zoomedSize.width, height: zoomedSize.height)
                                                .position(x: imageBounds.midX, y: imageBounds.midY)
                                                .accessibilityLabel("Screenshot editor canvas")
                                        }

                                        if let start = dragStart, let current = dragCurrent, usesDragShape, !isHidden {
                                            dragPreview(from: start, to: current, fitted: imageBounds)
                                                .allowsHitTesting(false)
                                        }

                                        if isCropping, !isHidden, zoomedSize.width > 0 {
                                            edgeCropPreview(in: imageBounds)
                                        }

                                        if !liveStrokePoints.isEmpty, !isHidden {
                                            Path { path in
                                                for (index, point) in liveStrokePoints.enumerated() {
                                                    if index == 0 {
                                                        path.move(to: point)
                                                    } else {
                                                        path.addLine(to: point)
                                                    }
                                                }
                                            }
                                            .stroke(
                                                Color(nsColor: EditorRedactionSettings.nsColor(fromHex: drawColorHex)),
                                                style: StrokeStyle(
                                                    lineWidth: canvasStrokeWidth(for: imageBounds),
                                                    lineCap: .round,
                                                    lineJoin: .round
                                                )
                                            )
                                            .allowsHitTesting(false)
                                        }

                                        if drawMode == .text, !isHidden {
                                            textCanvasInteractionLayer(
                                                fitted: imageBounds,
                                                imageSize: rendered?.size ?? .zero,
                                                showsEditorChrome: false
                                            )
                                        }
                                    }
                                    .frame(width: canvasContentSize.width, height: canvasContentSize.height)
                                    .clipped()
                                    .contentShape(Rectangle())
                                    .gesture(
                                        dragGesture(fittedImageRect: imageBounds),
                                        including: drawMode == .text ? .subviews : .all
                                    )

                                    // Host-sized chrome so the format bar stays tappable in letterbox
                                    // / outside the image without resizing (zooming) the picture.
                                    if drawMode == .text, !isHidden, textDraft != nil {
                                        TextDraftEditorOverlay(
                                            draft: $textDraft,
                                            textBuffer: textEditBuffer,
                                            focusGeneration: textFocusGeneration,
                                            fitted: imageBoundsInHost,
                                            hostSize: hostSize,
                                            imageSize: rendered?.size ?? .zero,
                                            onDone: { commitTextDraftIfNeeded() }
                                        )
                                        .frame(width: hostSize.width, height: hostSize.height)
                                    }
                                }
                            }
                            .frame(width: hostSize.width, height: hostSize.height)
                        }
                        .modifier(ScrollDisabledWhenFitModifier(disabled: zoom <= 1.01))
                        .simultaneousGesture(canvasZoomGesture)
                        .onAppear { fittedImageFrame = fitted }
                        .onChange(of: geo.size) { _ in
                            fittedImageFrame = fittedImageRect(imageSize: rendered?.size ?? .zero, in: geo.size)
                        }
                        .onHover { hovering in
                            isHoveringCanvas = hovering
                            updateCursor()
                        }
                    }
                }
                .onChange(of: drawMode) { mode in
                    updateCursor()
                    if mode != .none {
                        clearTextSelection()
                    }
                    if mode != .text {
                        commitTextDraftIfNeeded()
                        textPlacementStart = nil
                        textPlacementCurrent = nil
                    }
                    if mode == .crop {
                        resetCropSelection()
                        toolsCollapsed = false
                    }
                }

                metadataSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            toolsRail
        }
        .accessibilityIdentifier("editor-pane")
        .animation(.easeInOut(duration: 0.18), value: showToolsPanel)
        .animation(.easeInOut(duration: 0.18), value: toolsCollapsed)
        .onAppear {
            syncMetadataFromItem()
            if blurRadius > 40 { blurRadius = 10 }
            refreshQRPayloads(for: item.id)
            refreshOCRText()
        }
        .onReceive(NotificationCenter.default.publisher(for: .buddyMarketingStageScene)) { note in
            guard let scene = note.userInfo?[BuddyMarketingCapture.sceneKey] as? String else { return }
            toolsCollapsed = false
            switch scene {
            case "gallery":
                toolsCollapsed = true
                annotateExpanded = false
                autoBlurExpanded = false
                smartExpanded = false
                qrScanExpanded = false
            case "editor":
                toolsCollapsed = false
                annotateExpanded = true
                autoBlurExpanded = false
                smartExpanded = false
                qrScanExpanded = false
            case "redact":
                toolsCollapsed = false
                annotateExpanded = false
                autoBlurExpanded = true
                smartExpanded = false
                qrScanExpanded = false
                refreshAutoBlurPreview()
            case "smart":
                toolsCollapsed = false
                annotateExpanded = false
                autoBlurExpanded = false
                smartExpanded = true
                qrScanExpanded = false
                refreshOCRText()
            case "qr":
                toolsCollapsed = false
                annotateExpanded = false
                autoBlurExpanded = false
                smartExpanded = false
                qrScanExpanded = true
                refreshQRPayloads(for: item.id)
            default:
                break
            }
        }
        .onChange(of: item.id) { newId in
            isSyncingMetadata = true
            if let current = store.items.first(where: { $0.id == newId }) {
                title = current.title
                notes = current.notes
            }
            DispatchQueue.main.async { isSyncingMetadata = false }
            // Leaving an image exits crop/draw/etc. so the next one starts on Select.
            drawMode = .none
            dragStart = nil
            dragCurrent = nil
            liveStrokePoints = []
            textDraftCanvasImage = nil
            resetCropSelection()
            clearTextSelection()
            textDraft = nil
            textEditBuffer.text = ""
            textPlacementStart = nil
            textPlacementCurrent = nil
            autoBlurMatches = []
            autoBlurPreviewGeneration += 1
            isLoadingAutoBlurPreview = false
            canvasZoom = 1
            canvasZoomGestureBase = 1
            ocrText = ""
            pickedColorHex = ""
            // Drop previous image's QR immediately; scan the newly selected id from the store.
            qrPayloads = []
            updateCursor()
            suppressImageDataQRRefresh = true
            refreshQRPayloads(for: newId)
            refreshOCRText()
            DispatchQueue.main.async { suppressImageDataQRRefresh = false }
        }
        .onChange(of: item.imageData) { _ in
            // Edits to the current image (crop/draw). Selection changes are handled above.
            guard !suppressImageDataQRRefresh else { return }
            refreshQRPayloads(for: item.id)
            refreshOCRText()
        }
        .onChange(of: item.ocrText) { newValue in
            if !newValue.isEmpty {
                ocrText = newValue
                smartExpanded = true
            }
        }
        .alert("Delete Screenshot?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.delete(item.id)
            }
        } message: {
            Text("This cannot be undone.")
        }
        .background(shortcutButtons)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                exportToolbarButtons
            }
        }
        .onDisappear {
            NSCursor.arrow.set()
        }
    }

    private var metadataSection: some View {
        VStack(spacing: 8) {
            TextField("Name", text: $title)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .disabled(isHidden)
                .accessibilityIdentifier("screenshot-name-field")
                .onChange(of: title) { newValue in
                    guard !isSyncingMetadata else { return }
                    guard let current = store.items.first(where: { $0.id == item.id }),
                          newValue != current.title else { return }
                    store.updateTitle(newValue, for: item.id)
                }

            TextField("Notes (used for sensitive detection)", text: $notes)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .disabled(isHidden)
                .onChange(of: notes) { newValue in
                    guard !isSyncingMetadata else { return }
                    guard let current = store.items.first(where: { $0.id == item.id }),
                          newValue != current.notes else { return }
                    store.updateNotes(newValue, for: item.id)
                }

            HStack {
                ForEach(item.tags, id: \.self) { TagChip(tag: $0) }
            }
            .padding(.bottom)
        }
    }

    private var toolsRail: some View {
        HStack(spacing: 0) {
            if showToolsPanel {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Group {
                                if isCropping {
                                    Text("Crop")
                                } else {
                                    Text("Tools")
                                }
                            }
                            .font(.headline)
                            Spacer()
                            if !isCropping {
                                Button {
                                    toolsCollapsed = true
                                } label: {
                                    Image(systemName: "sidebar.trailing")
                                }
                                .buttonStyle(.borderless)
                                .help("Collapse tools")
                                .accessibilityLabel("Collapse tools")
                            }
                        }

                        if isCropping {
                            cropOptions
                                .disabled(isHidden)
                        } else {
                            annotateSection
                                .disabled(isHidden)

                            autoBlurSection
                                .disabled(isHidden)

                            qrScanSection
                                .disabled(isHidden)

                            smartSection
                                .disabled(isHidden)

                            toolButton("Crop", mode: .crop)
                                .disabled(isHidden)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 260)
                .background(.bar)
            }

            collapsedToolsStrip
        }
    }

    private var collapsedToolsStrip: some View {
        VStack(spacing: 10) {
            Button {
                guard !isCropping else { return }
                toolsCollapsed.toggle()
            } label: {
                Image(systemName: toolsCollapsed ? "chevron.left" : "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(isCropping)
            .help(toolsCollapsed ? LocalizedStringKey("Expand tools") : LocalizedStringKey("Collapse tools"))
            .accessibilityLabel(toolsCollapsed ? Text("Expand tools") : Text("Collapse tools"))

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(width: 36)
        .background(.bar)
    }

    private var annotateSection: some View {
        DisclosureGroup(isExpanded: $annotateExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                toolButton("Select", mode: .none, shortcut: "⌘A")
                if drawMode == .none {
                    selectOptions.toolOptionChrome()
                }

                toolButton("Arrow", mode: .arrow)
                if drawMode == .arrow {
                    annotationStrokeOptions.toolOptionChrome()
                }

                toolButton("Ellipse", mode: .ellipse)
                if drawMode == .ellipse {
                    ellipseOptions.toolOptionChrome()
                }

                toolButton("Rectangle", mode: .rectangle, shortcut: "⌘R")
                if drawMode == .rectangle {
                    rectangleOptions.toolOptionChrome()
                }

                toolButton("Free draw", mode: .draw, shortcut: "⌘E")
                if drawMode == .draw {
                    drawOptions.toolOptionChrome()
                }

                toolButton("Text", mode: .text)
                if drawMode == .text {
                    textAnnotationOptions.toolOptionChrome()
                }

                toolButton("Blur", mode: .blur, shortcut: "⌘B")
                if drawMode == .blur {
                    blurOptions.toolOptionChrome()
                }
            }
            .padding(.top, 4)
            .animation(.easeInOut(duration: 0.15), value: drawMode)
        } label: {
            Label("Annotate", systemImage: "pencil.tip.crop.circle")
        }
        .accessibilityLabel("Annotate tools")
    }

    private var qrScanSection: some View {
        DisclosureGroup(isExpanded: $qrScanExpanded) {
            qrScanContent
                .padding(.top, 4)
                .onChange(of: qrScanExpanded) { open in
                    // Manual re-scan when the user opens the section; avoid looping when we auto-expand.
                    if open, qrPayloads.isEmpty, !isScanningQR {
                        refreshQRPayloads(for: item.id)
                    }
                }
        } label: {
            Label("QR scan", systemImage: "qrcode.viewfinder")
        }
        .accessibilityIdentifier("editor-qr-scan-menu")
    }

    @ViewBuilder
    private var qrScanContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isScanningQR && qrPayloads.isEmpty {
                ProgressView("Scanning…")
                    .controlSize(.small)
                    .accessibilityIdentifier("editor-qr-scanning")
            } else if qrPayloads.isEmpty {
                Text("No readable QR code found. Try a sharper crop with more white margin around the code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("editor-qr-empty")
            } else {
                Group {
                    if qrPayloads.count == 1 {
                        Text("QR code found")
                    } else {
                        Text("\(qrPayloads.count) QR codes found")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(Array(qrPayloads.enumerated()), id: \.element.id) { index, payload in
                    qrPayloadRow(payload)
                    if index < qrPayloads.count - 1 {
                        BuddyDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func qrPayloadRow(_ payload: QRCodePayload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Group {
                    if payload.kind == .link {
                        Text("Link")
                    } else {
                        Text("Text")
                    }
                }
                .font(.caption.weight(.medium))
            } icon: {
                Image(systemName: payload.kind == .link ? "link" : "text.alignleft")
            }
            .foregroundStyle(.secondary)

            if let colorToken = payload.colorToken {
                DetectedContentTokenRow(token: colorToken) { text in
                    store.copyTextToClipboard(text)
                }
            } else {
                Text(payload.content)
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    if payload.isLink, let url = payload.openableURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Open", systemImage: "safari")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Open link")
                    }

                    Button {
                        store.copyTextToClipboard(payload.content)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy to clipboard")
                }
            }
        }
        .toolOptionChrome()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(payload.kind == .link ? "QR link" : "QR text")
        .accessibilityValue(payload.content)
    }

    private var smartSection: some View {
        DisclosureGroup(isExpanded: $smartExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if !ocrText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OCR")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            store.copyTextToClipboard(ocrText)
                        } label: {
                            Label("Copy all text", systemImage: "text.viewfinder")
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)

                        let ocrTokens = DetectedContentExtractor.extractTokens(from: ocrText)
                        if !ocrTokens.isEmpty {
                            Text("Detected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(Array(ocrTokens.enumerated()), id: \.element.id) { index, token in
                                DetectedContentTokenRow(
                                    token: token,
                                    showsSeparator: index < ocrTokens.count - 1
                                ) { text in
                                    store.copyTextToClipboard(text)
                                }
                            }
                        }

                        Text(ocrText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                    }
                }

                toolButton("Color picker", mode: .colorPicker)
                if drawMode == .colorPicker {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Click a pixel to copy its hex color.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !pickedColorHex.isEmpty {
                            HStack {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(nsColor: EditorRedactionSettings.nsColor(fromHex: pickedColorHex)))
                                    .frame(width: 18, height: 18)
                                Text(pickedColorHex)
                                    .font(.caption.monospaced())
                                Spacer()
                                Button {
                                    store.copyTextToClipboard(pickedColorHex)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .toolOptionChrome()
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Smart", systemImage: "sparkles")
        }
        .accessibilityIdentifier("editor-smart-menu")
    }

    private var cropOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drag handles to resize, drag inside the box to move, or drag on the image to select an area. Then confirm.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                confirmCrop()
            } label: {
                Label("Confirm crop", systemImage: "checkmark.circle.fill")
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!canConfirmCrop)
            .accessibilityIdentifier("editor-confirm-crop")

            Button {
                cancelCrop()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityIdentifier("editor-cancel-crop")
        }
    }

    private var canConfirmCrop: Bool {
        let width = 1 - cropInsetLeft - cropInsetRight
        let height = 1 - cropInsetTop - cropInsetBottom
        return width > Self.minCropKeep && height > Self.minCropKeep
            && (cropInsetLeft > 0.0001 || cropInsetRight > 0.0001
                || cropInsetTop > 0.0001 || cropInsetBottom > 0.0001)
    }

    private func resetCropSelection() {
        cropInsetLeft = 0
        cropInsetRight = 0
        cropInsetTop = 0
        cropInsetBottom = 0
        cropHandleDragStart = nil
    }

    private func confirmCrop() {
        guard canConfirmCrop else { return }
        let rect = CGRect(
            x: cropInsetLeft,
            y: cropInsetTop,
            width: 1 - cropInsetLeft - cropInsetRight,
            height: 1 - cropInsetTop - cropInsetBottom
        )
        _ = store.crop(toNormalized: rect, for: item.id)
        resetCropSelection()
        drawMode = .none
    }

    private func cancelCrop() {
        resetCropSelection()
        drawMode = .none
    }

    private func setCropInsets(fromNormalized rect: CGRect) {
        let x = min(max(rect.origin.x, 0), 1)
        let y = min(max(rect.origin.y, 0), 1)
        let w = min(max(rect.width, Self.minCropKeep), 1 - x)
        let h = min(max(rect.height, Self.minCropKeep), 1 - y)
        cropInsetLeft = x
        cropInsetTop = y
        cropInsetRight = max(0, 1 - x - w)
        cropInsetBottom = max(0, 1 - y - h)
    }

    private func edgeKeepRect(in fitted: CGRect) -> CGRect {
        CGRect(
            x: fitted.minX + fitted.width * cropInsetLeft,
            y: fitted.minY + fitted.height * cropInsetTop,
            width: fitted.width * max(1 - cropInsetLeft - cropInsetRight, Self.minCropKeep),
            height: fitted.height * max(1 - cropInsetTop - cropInsetBottom, Self.minCropKeep)
        )
    }

    private func edgeCropPreview(in fitted: CGRect) -> some View {
        let keep = edgeKeepRect(in: fitted)
        let resizeHandles = CropHandle.allCases.filter { $0 != .move }
        let canMoveBox = cropInsetLeft > 0.0001 || cropInsetRight > 0.0001
            || cropInsetTop > 0.0001 || cropInsetBottom > 0.0001
        return ZStack {
            Path { path in
                path.addRect(fitted)
                path.addRect(keep)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .frame(width: keep.width, height: keep.height)
                .position(x: keep.midX, y: keep.midY)
                .allowsHitTesting(false)

            if canMoveBox {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: max(keep.width - 16, 8), height: max(keep.height - 16, 8))
                    .position(x: keep.midX, y: keep.midY)
                    .highPriorityGesture(cropHandleGesture(.move, fitted: fitted))
                    .onHover { hovering in
                        if hovering { NSCursor.openHand.set() }
                        else { updateCursor() }
                    }
            }

            ForEach(resizeHandles, id: \.self) { handle in
                cropHandleView(handle, at: cropHandlePoint(handle, in: keep), fitted: fitted)
            }
        }
    }

    private func cropHandleView(_ handle: CropHandle, at point: CGPoint, fitted: CGRect) -> some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 9, height: 9)
            .overlay(
                Circle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
            )
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .position(point)
            .highPriorityGesture(cropHandleGesture(handle, fitted: fitted))
            .accessibilityLabel(cropHandleAccessibilityLabel(handle))
    }

    private func cropHandleAccessibilityLabel(_ handle: CropHandle) -> String {
        switch handle {
        case .topLeft: return "Crop top-left handle"
        case .top: return "Crop top handle"
        case .topRight: return "Crop top-right handle"
        case .left: return "Crop left handle"
        case .right: return "Crop right handle"
        case .bottomLeft: return "Crop bottom-left handle"
        case .bottom: return "Crop bottom handle"
        case .bottomRight: return "Crop bottom-right handle"
        case .move: return "Move crop box"
        }
    }

    private func cropHandlePoint(_ handle: CropHandle, in keep: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: keep.minX, y: keep.minY)
        case .top: return CGPoint(x: keep.midX, y: keep.minY)
        case .topRight: return CGPoint(x: keep.maxX, y: keep.minY)
        case .left: return CGPoint(x: keep.minX, y: keep.midY)
        case .right: return CGPoint(x: keep.maxX, y: keep.midY)
        case .bottomLeft: return CGPoint(x: keep.minX, y: keep.maxY)
        case .bottom: return CGPoint(x: keep.midX, y: keep.maxY)
        case .bottomRight: return CGPoint(x: keep.maxX, y: keep.maxY)
        case .move: return CGPoint(x: keep.midX, y: keep.midY)
        }
    }

    private func cropHandleGesture(_ handle: CropHandle, fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if cropHandleDragStart == nil {
                    cropHandleDragStart = (
                        left: cropInsetLeft,
                        right: cropInsetRight,
                        top: cropInsetTop,
                        bottom: cropInsetBottom
                    )
                }
                guard let start = cropHandleDragStart else { return }
                applyCropHandleDrag(
                    handle,
                    translation: value.translation,
                    start: start,
                    fitted: fitted
                )
            }
            .onEnded { _ in
                cropHandleDragStart = nil
            }
    }

    private func applyCropHandleDrag(
        _ handle: CropHandle,
        translation: CGSize,
        start: (left: Double, right: Double, top: Double, bottom: Double),
        fitted: CGRect
    ) {
        guard fitted.width > 0, fitted.height > 0 else { return }

        let dx = Double(translation.width / fitted.width)
        let dy = Double(translation.height / fitted.height)

        if handle == .move {
            let width = 1 - start.left - start.right
            let height = 1 - start.top - start.bottom
            let left = min(max(start.left + dx, 0), 1 - width)
            let top = min(max(start.top + dy, 0), 1 - height)
            cropInsetLeft = left
            cropInsetRight = 1 - width - left
            cropInsetTop = top
            cropInsetBottom = 1 - height - top
            return
        }

        var left = start.left
        var right = start.right
        var top = start.top
        var bottom = start.bottom

        switch handle {
        case .left, .topLeft, .bottomLeft:
            left = min(max(start.left + dx, 0), 1 - start.right - Self.minCropKeep)
        case .right, .topRight, .bottomRight:
            right = min(max(start.right - dx, 0), 1 - start.left - Self.minCropKeep)
        default:
            break
        }

        switch handle {
        case .top, .topLeft, .topRight:
            top = min(max(start.top + dy, 0), 1 - start.bottom - Self.minCropKeep)
        case .bottom, .bottomLeft, .bottomRight:
            bottom = min(max(start.bottom - dy, 0), 1 - start.top - Self.minCropKeep)
        default:
            break
        }

        cropInsetLeft = left
        cropInsetRight = right
        cropInsetTop = top
        cropInsetBottom = bottom
    }

    private func toolButton(_ title: LocalizedStringKey, mode: GalleryView.DrawMode, shortcut: String? = nil) -> some View {
        let selected = drawMode == mode
        return Button {
            drawMode = mode
            if mode != .colorPicker { pickedColorHex = "" }
            if mode != .none { clearTextSelection() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.systemImage)
                    .frame(width: 14, alignment: .center)
                Text(title)
                if let shortcut {
                    Spacer(minLength: 4)
                    Text(shortcut)
                        .font(.caption2)
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.06))
            )
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func dragPreview(from start: CGPoint, to current: CGPoint, fitted: CGRect) -> some View {
        switch drawMode {
        case .arrow:
            let lineWidth = canvasAnnotationLineWidth(for: fitted)
            let scale = lineWidth / CGFloat(max(annotationLineWidth, 1))
            Path { path in
                path.move(to: start)
                path.addLine(to: current)
                let dx = current.x - start.x
                let dy = current.y - start.y
                let length = max(hypot(dx, dy), 1)
                let ux = dx / length
                let uy = dy / length
                // Same formula as ScreenshotStore.drawArrow, mapped into canvas points.
                let head = max(lineWidth * 3.5, 10 * scale)
                path.move(to: CGPoint(x: current.x - ux * head - uy * head * 0.55, y: current.y - uy * head + ux * head * 0.55))
                path.addLine(to: current)
                path.addLine(to: CGPoint(x: current.x - ux * head + uy * head * 0.55, y: current.y - uy * head - ux * head * 0.55))
            }
            .stroke(selectionPreviewStroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        case .ellipse:
            let rect = selectionRect(from: start, to: current)
            let lineWidth = canvasAnnotationLineWidth(for: fitted)
            Ellipse()
                .fill(selectionPreviewFill)
                .overlay(
                    Ellipse()
                        .strokeBorder(selectionPreviewStroke, lineWidth: lineWidth)
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        default:
            let rect = selectionRect(from: start, to: current)
            Rectangle()
                .fill(selectionPreviewFill)
                .overlay(
                    Rectangle()
                        .strokeBorder(
                            selectionPreviewStroke,
                            style: StrokeStyle(
                                lineWidth: selectionPreviewLineWidth,
                                dash: (drawMode == .rectangle && borderEnabled) ? [] : [5, 3]
                            )
                        )
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    private var selectOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select text in the image like Preview. Use ⌘C or Copy Text.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if selectedText.isEmpty {
                Text("No text selected.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(selectedText)
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )

                let selectedTokens = DetectedContentExtractor.extractTokens(from: selectedText)
                if !selectedTokens.isEmpty {
                    Text("Detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(selectedTokens.enumerated()), id: \.element.id) { index, token in
                        DetectedContentTokenRow(
                            token: token,
                            showsSeparator: index < selectedTokens.count - 1
                        ) { text in
                            store.copyTextToClipboard(text)
                        }
                    }
                }

                Button {
                    store.copyTextToClipboard(selectedText)
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
            }
        }
    }

    private var annotationStrokeOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            ColorPicker("Color", selection: drawSwiftUIColor, supportsOpacity: false)
            VStack(alignment: .leading, spacing: 4) {
                Text("Thickness")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $annotationLineWidth, in: 1...16, step: 1)
                Text("\(Int(annotationLineWidth)) pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var ellipseOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            annotationStrokeOptions
            Toggle("Fill", isOn: $ellipseFillEnabled)
                .toggleStyle(.checkbox)
        }
    }

    private var textAnnotationOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if textDraft != nil {
                ColorPicker("Color", selection: draftTextColorBinding, supportsOpacity: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { textDraft?.fontSize ?? annotationFontSize },
                            set: { newValue in
                                textDraft?.fontSize = newValue
                                annotationFontSize = newValue
                            }
                        ),
                        in: 10...72,
                        step: 1
                    )
                    Text("\(Int(textDraft?.fontSize ?? annotationFontSize)) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Picker("Font", selection: draftFontNameBinding) {
                    ForEach(TextAnnotationDraft.fontChoices, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                Picker("Align", selection: draftTextAlignmentBinding) {
                    Image(systemName: "text.alignleft").tag("left")
                    Image(systemName: "text.aligncenter").tag("center")
                    Image(systemName: "text.alignright").tag("right")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Drag the top bar to move, corner to resize. Press Done when finished.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    commitTextDraftIfNeeded()
                } label: {
                    Label("Done", systemImage: "checkmark.circle")
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            } else {
                Text("Drag on the image to draw a text box, or click existing text to edit it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var draftFontNameBinding: Binding<String> {
        Binding(
            get: { textDraft?.fontName ?? annotationFontName },
            set: { newValue in
                textDraft?.fontName = newValue
                annotationFontName = newValue
            }
        )
    }

    private var draftTextAlignmentBinding: Binding<String> {
        Binding(
            get: { textDraft?.textAlignment ?? annotationTextAlignment },
            set: { newValue in
                textDraft?.textAlignment = newValue
                annotationTextAlignment = newValue
            }
        )
    }

    private var draftTextColorBinding: Binding<Color> {
        Binding(
            get: {
                let hex = textDraft?.colorHex ?? drawColorHex
                return Color(nsColor: EditorRedactionSettings.nsColor(fromHex: hex))
            },
            set: { newColor in
                let hex = EditorRedactionSettings.hex(from: NSColor(newColor))
                textDraft?.colorHex = hex
                drawColorHex = hex
            }
        )
    }

    private var rectangleOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Fill", isOn: $fillEnabled)
                .toggleStyle(.checkbox)
            if fillEnabled {
                ColorPicker("Fill color", selection: blackBoxSwiftUIColor, supportsOpacity: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opacity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $blackBoxOpacity, in: 0.05...1, step: 0.05)
                    Text("\(Int(blackBoxOpacity * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Toggle("Border", isOn: $borderEnabled)
                .toggleStyle(.checkbox)
            if borderEnabled {
                ColorPicker("Border color", selection: borderSwiftUIColor, supportsOpacity: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Border width")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $borderWidth, in: 1...24, step: 1)
                    Text("\(Int(borderWidth)) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var blurOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Blur amount")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $blurRadius, in: 2...40, step: 1)
            Text("\(Int(blurRadius))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("Same soft blur as the sensitive preview.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var drawOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            ColorPicker("Ink color", selection: drawSwiftUIColor, supportsOpacity: false)
            VStack(alignment: .leading, spacing: 4) {
                Text("Stroke size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $drawSize, in: 1...48, step: 1)
                Text("\(Int(drawSize)) pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var autoBlurSection: some View {
        DisclosureGroup(isExpanded: $autoBlurExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Uses the sensitive types from Settings → General.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isLoadingAutoBlurPreview {
                    ProgressView("Scanning…")
                        .controlSize(.small)
                } else if autoBlurMatches.isEmpty {
                    Text("No matching sensitive data found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("editor-auto-blur-empty")
                } else {
                    Group {
                        if autoBlurMatches.count == 1 {
                            Text("1 item ready to blur.")
                        } else {
                            Text("\(autoBlurMatches.count) items ready to blur.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor-auto-blur-preview")

                    Button {
                        _ = store.applyAutoBlur(matches: autoBlurMatches, for: item.id)
                        refreshAutoBlurPreview()
                    } label: {
                        Label("Blur all", systemImage: "eye.trianglebadge.exclamationmark")
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .accessibilityIdentifier("editor-apply-auto-blur-all")
                    .help("Applies blur to every matching item. Undo with ⌘Z.")
                }

                autoBlurOpenSettingsRow
            }
            .padding(.top, 4)
            .onAppear { refreshAutoBlurPreview() }
            .onChange(of: item.id) { _ in
                refreshAutoBlurPreview()
                pickedColorHex = ""
            }
            .onChange(of: item.notes) { _ in refreshAutoBlurPreview() }
            .onChange(of: item.imageData) { _ in refreshAutoBlurPreview() }
            .onChange(of: item.redactionRects) { _ in refreshAutoBlurPreview() }
            .onChange(of: protectedTagsRaw) { _ in refreshAutoBlurPreview() }
            .onChange(of: autoBlurExpanded) { open in
                if open { refreshAutoBlurPreview() }
            }
        } label: {
            Label("Auto-blur", systemImage: "eye.trianglebadge.exclamationmark")
        }
        .accessibilityIdentifier("editor-auto-blur-menu")
    }

    @ViewBuilder
    private var autoBlurOpenSettingsRow: some View {
        if #available(macOS 14.0, *) {
            BuddyDeferredOpenSettingsButton(title: "Choose types in Settings…")
                .buttonStyle(.link)
        } else {
            Button("Choose types in Settings…") {
                buddyOpenAppSettings()
            }
            .buttonStyle(.link)
        }
    }

    private func refreshAutoBlurPreview() {
        let id = item.id
        guard let imageData = store.items.first(where: { $0.id == id })?.imageData else {
            autoBlurMatches = []
            isLoadingAutoBlurPreview = false
            return
        }
        let notes = store.items.first(where: { $0.id == id })?.notes ?? ""
        let existing = store.items.first(where: { $0.id == id })?.redactionRects ?? []
        let enabledTags = SensitivePrivacySettings.autoBlurTags
        autoBlurPreviewGeneration += 1
        let generation = autoBlurPreviewGeneration
        isLoadingAutoBlurPreview = true
        // Vision OCR must not run on MainActor — same priority-inversion / hitch class as QR.
        Task.detached(priority: .utility) {
            let matches = SensitiveRegionFinder.autoBlurMatches(
                imageData: imageData,
                notes: notes,
                enabledTags: enabledTags
            ).filter { match in
                let rect = match.region.asBlurRedaction()
                return !existing.contains(where: { SensitiveRegionFinder.roughlyCovers($0, rect) })
            }
            await MainActor.run {
                // item is captured at task start; use generation + live selection to drop stale OCR.
                guard generation == autoBlurPreviewGeneration, store.selectedId == id else { return }
                autoBlurMatches = matches
                isLoadingAutoBlurPreview = false
            }
        }
    }

    private func refreshQRPayloads(for id: UUID) {
        guard let imageData = store.items.first(where: { $0.id == id })?.imageData else {
            qrPayloads = []
            isScanningQR = false
            return
        }
        qrScanGeneration += 1
        let generation = qrScanGeneration
        isScanningQR = true
        // Utility QoS: VNImageRequestHandler.perform waits on Vision’s utility threads;
        // userInitiated/userInteractive callers produce priority-inversion warnings + hitching.
        Task.detached(priority: .utility) {
            let payloads = ScreenshotSmartTools.detectQRCodes(in: imageData)
            await MainActor.run {
                guard generation == qrScanGeneration, store.selectedId == id else { return }
                qrPayloads = payloads
                isScanningQR = false
                if !payloads.isEmpty, !qrScanExpanded {
                    qrScanExpanded = true
                }
            }
        }
    }

    private func refreshOCRText() {
        let id = item.id
        guard let current = store.items.first(where: { $0.id == id }) else {
            ocrText = ""
            return
        }
        if !current.ocrText.isEmpty {
            ocrText = current.ocrText
            smartExpanded = true
            return
        }
        let imageData = current.imageData
        ocrText = ""
        Task.detached(priority: .utility) {
            let text = ScreenshotOCR.recognizedText(in: imageData)
            await MainActor.run {
                guard store.selectedId == id else { return }
                ocrText = text
                if !text.isEmpty {
                    smartExpanded = true
                }
            }
        }
    }

    @ViewBuilder
    private var exportToolbarButtons: some View {
        toolbarIconButton("Copy to Clipboard", systemImage: "doc.on.doc") {
            if isHidden {
                store.reveal(item: item) { ok in if ok { store.copyToClipboard(item) } }
            } else {
                store.copyToClipboard(item)
            }
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])

        toolbarIconButton("Duplicate", systemImage: "plus.square.on.square") {
            if isHidden {
                store.reveal(item: item) { ok in if ok { store.duplicate(item) } }
            } else {
                store.duplicate(item)
            }
        }
        .keyboardShortcut("d", modifiers: [.command])

        toolbarIconButton("Save As…", systemImage: "square.and.arrow.down") {
            if isHidden {
                store.reveal(item: item) { ok in if ok { saveAs() } }
            } else {
                saveAs()
            }
        }
        .keyboardShortcut("s", modifiers: [.command])

        toolbarIconButton("Overwrite", systemImage: "arrow.triangle.2.circlepath") {
            if isHidden {
                store.reveal(item: item) { ok in if ok { store.overwrite(item) } }
            } else {
                store.overwrite(item)
            }
        }

        toolbarIconButton("Undo", systemImage: "arrow.uturn.backward") {
            store.undo(for: item.id)
        }
        .disabled(!store.canUndoSelected)

        toolbarIconButton("Redo", systemImage: "arrow.uturn.forward") {
            store.redo(for: item.id)
        }
        .disabled(!store.canRedoSelected)

        toolbarIconButton("Delete", systemImage: "trash", role: .destructive) {
            confirmDelete = true
        }
        .keyboardShortcut(.delete, modifiers: [.command])
        .accessibilityIdentifier("delete-screenshot")
    }

    private func toolbarIconButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
        .labelStyle(.iconOnly)
        .help(title)
        .accessibilityLabel(title)
    }

    private var shortcutButtons: some View {
        ZStack {
            Button("Blur tool") { drawMode = .blur }
                .keyboardShortcut("b", modifiers: [.command])
            Button("Rectangle tool") { drawMode = .rectangle }
                .keyboardShortcut("r", modifiers: [.command])
            Button("Free draw tool") { drawMode = .draw }
                .keyboardShortcut("e", modifiers: [.command])
            Button("Select tool") { drawMode = .none }
                .keyboardShortcut("a", modifiers: [.command])
            Button("Copy selected text") {
                store.copyTextToClipboard(selectedText)
            }
            .keyboardShortcut("c", modifiers: [.command])
            .disabled(selectedText.isEmpty)
            Button("Undo edit") { store.undo(for: item.id) }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!store.canUndoSelected)
            Button("Redo edit") { store.redo(for: item.id) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!store.canRedoSelected)
            Button("Save As") {
                if !isHidden { saveAs() }
            }
            .keyboardShortcut("s", modifiers: [.command])
        }
        .opacity(0.01)
        .frame(width: 1, height: 1)
        .accessibilityHidden(true)
        .disabled(isHidden)
    }

    private func syncMetadataFromItem() {
        isSyncingMetadata = true
        if let current = store.items.first(where: { $0.id == item.id }) {
            title = current.title
            notes = current.notes
        } else {
            title = item.title
            notes = item.notes
        }
        DispatchQueue.main.async {
            isSyncingMetadata = false
        }
    }

    private var canvasZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let next = canvasZoomGestureBase * value
                canvasZoom = min(max(next, Self.minCanvasZoom), Self.maxCanvasZoom)
            }
            .onEnded { _ in
                canvasZoomGestureBase = canvasZoom
            }
    }

    private func updateCursor() {
        if isHoveringCanvas && !isHidden {
            if usesCrosshair {
                NSCursor.crosshair.set()
                return
            }
            if usesDrawCursor {
                NSCursor.crosshair.set()
                return
            }
        }
        NSCursor.arrow.set()
    }

    private func canvasStrokeWidth(for fitted: CGRect) -> CGFloat {
        guard fitted.width > 0, let rendered = store.renderedImage(for: item), rendered.size.width > 0 else {
            return CGFloat(drawSize)
        }
        return CGFloat(drawSize) * (fitted.width / rendered.size.width)
    }

    /// Line width in canvas points so drag previews match baked annotations.
    private func canvasAnnotationLineWidth(for fitted: CGRect) -> CGFloat {
        guard fitted.width > 0, let rendered = store.renderedImage(for: item), rendered.size.width > 0 else {
            return CGFloat(max(annotationLineWidth, 1))
        }
        return CGFloat(max(annotationLineWidth, 1)) * (fitted.width / rendered.size.width)
    }

    private func normalizedPoint(from canvasPoint: CGPoint, fitted: CGRect) -> DrawPoint? {
        guard fitted.width > 0, fitted.height > 0 else { return nil }
        let x = (canvasPoint.x - fitted.minX) / fitted.width
        let y = (canvasPoint.y - fitted.minY) / fitted.height
        // Clamp so a drag that exits the image still lands on the edge, never past it.
        return DrawPoint(
            x: min(max(Double(x), 0), 1),
            y: min(max(Double(y), 0), 1)
        )
    }

    private func clampPointToFitted(_ point: CGPoint, fitted: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, fitted.minX), fitted.maxX),
            y: min(max(point.y, fitted.minY), fitted.maxY)
        )
    }

    private func clearTextSelection() {
        selectedText = ""
    }

    private func selectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// Aspect-fit frame of the image inside the canvas (same as `.scaledToFit()`).
    private func fittedImageRect(imageSize: CGSize, in canvas: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, canvas.width > 0, canvas.height > 0 else {
            return CGRect(origin: .zero, size: canvas)
        }
        let scale = min(canvas.width / imageSize.width, canvas.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (canvas.width - width) / 2,
            y: (canvas.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func dragGesture(fittedImageRect fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isHidden else { return }
                fittedImageFrame = fitted
                // Ignore presses that begin outside the image (letterbox / empty canvas).
                guard fitted.contains(value.startLocation) else { return }
                let location = clampPointToFitted(value.location, fitted: fitted)

                if drawMode == .draw {
                    NSCursor.crosshair.set()
                    if liveStrokePoints.isEmpty {
                        liveStrokePoints = [clampPointToFitted(value.startLocation, fitted: fitted)]
                    }
                    if let last = liveStrokePoints.last {
                        let dx = location.x - last.x
                        let dy = location.y - last.y
                        if (dx * dx + dy * dy) >= 1 {
                            liveStrokePoints.append(location)
                        }
                    }
                    return
                }

                if drawMode == .crop {
                    guard cropHandleDragStart == nil else { return }
                    if usesCrosshair { NSCursor.crosshair.set() }
                    let start = clampPointToFitted(value.startLocation, fitted: fitted)
                    let rect = selectionRect(from: start, to: location)
                    guard rect.width > 2, rect.height > 2, fitted.width > 0, fitted.height > 0 else { return }
                    let x = (rect.minX - fitted.minX) / fitted.width
                    let y = (rect.minY - fitted.minY) / fitted.height
                    let w = rect.width / fitted.width
                    let h = rect.height / fitted.height
                    setCropInsets(
                        fromNormalized: CGRect(
                            x: min(max(Double(x), 0), 1),
                            y: min(max(Double(y), 0), 1),
                            width: min(max(Double(w), 0), 1),
                            height: min(max(Double(h), 0), 1)
                        )
                    )
                    return
                }

                if usesDragShape {
                    if usesCrosshair { NSCursor.crosshair.set() }
                    if dragStart == nil {
                        dragStart = clampPointToFitted(value.startLocation, fitted: fitted)
                    }
                    dragCurrent = location
                }
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    dragCurrent = nil
                    liveStrokePoints = []
                }
                guard !isHidden else { return }
                guard fitted.contains(value.startLocation) else { return }
                let endLocation = clampPointToFitted(value.location, fitted: fitted)
                let startLocation = clampPointToFitted(value.startLocation, fitted: fitted)

                if drawMode == .draw {
                    var points = liveStrokePoints
                    if points.isEmpty {
                        points = [startLocation, endLocation]
                    } else if points.last != endLocation {
                        points.append(endLocation)
                    }
                    let normalized = points.compactMap { normalizedPoint(from: $0, fitted: fitted) }
                    guard normalized.count >= 2 else { return }
                    store.addStroke(
                        DrawStroke(points: normalized, colorHex: drawColorHex, lineWidth: drawSize),
                        for: item.id
                    )
                    return
                }

                if drawMode == .colorPicker {
                    guard let point = normalizedPoint(from: endLocation, fitted: fitted),
                          let hex = store.sampleColorHex(
                            atNormalized: CGPoint(x: point.x, y: point.y),
                            for: item.id
                          ) else { return }
                    pickedColorHex = hex
                    store.copyTextToClipboard(hex)
                    return
                }

                guard usesDragShape, let start = dragStart else { return }
                let end = endLocation
                let rect = selectionRect(from: start, to: end)

                if drawMode == .arrow {
                    guard hypot(end.x - start.x, end.y - start.y) > 4,
                          let from = normalizedPoint(from: start, fitted: fitted),
                          let to = normalizedPoint(from: end, fitted: fitted) else { return }
                    store.addAnnotation(
                        ImageAnnotation(
                            kind: .arrow,
                            x: from.x,
                            y: from.y,
                            x2: to.x,
                            y2: to.y,
                            colorHex: drawColorHex,
                            lineWidth: annotationLineWidth
                        ),
                        for: item.id
                    )
                    return
                }

                guard rect.width > 2, rect.height > 2, fitted.width > 0, fitted.height > 0 else { return }

                let x = (rect.minX - fitted.minX) / fitted.width
                let y = (rect.minY - fitted.minY) / fitted.height
                let w = rect.width / fitted.width
                let h = rect.height / fitted.height
                let nx = min(max(Double(x), 0), 1)
                let ny = min(max(Double(y), 0), 1)
                let nw = min(max(Double(w), 0), 1 - nx)
                let nh = min(max(Double(h), 0), 1 - ny)

                if drawMode == .ellipse {
                    guard nw > 0.002, nh > 0.002 else { return }
                    store.addAnnotation(
                        ImageAnnotation(
                            kind: .ellipse,
                            x: nx,
                            y: ny,
                            x2: nx + nw,
                            y2: ny + nh,
                            colorHex: drawColorHex,
                            lineWidth: annotationLineWidth,
                            fillEnabled: ellipseFillEnabled,
                            fillOpacity: 0.25
                        ),
                        for: item.id
                    )
                    return
                }

                guard drawMode == .rectangle || drawMode == .blur else { return }
                let isBlur = drawMode == .blur
                let clamped = RedactionRect(
                    x: nx,
                    y: ny,
                    width: nw,
                    height: nh,
                    style: isBlur ? .blur : .blackBox,
                    borderEnabled: isBlur ? false : borderEnabled,
                    borderColorHex: borderColorHex,
                    borderWidth: borderWidth,
                    fillColorHex: blackBoxColorHex,
                    fillOpacity: blackBoxOpacity,
                    fillEnabled: isBlur ? false : fillEnabled,
                    blurRadius: blurRadius
                )
                guard clamped.width > 0.002, clamped.height > 0.002 else { return }
                store.addRedaction(clamped, for: item.id)
            }
    }

    @ViewBuilder
    private func textCanvasInteractionLayer(
        fitted: CGRect,
        imageSize: CGSize,
        showsEditorChrome: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(textPlacementGesture(fitted: fitted, imageSize: imageSize))

            if let start = textPlacementStart, let current = textPlacementCurrent, textDraft == nil {
                let rect = selectionRect(from: start, to: current)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }

            if showsEditorChrome, textDraft != nil {
                TextDraftEditorOverlay(
                    draft: $textDraft,
                    textBuffer: textEditBuffer,
                    focusGeneration: textFocusGeneration,
                    fitted: fitted,
                    hostSize: CGSize(width: fitted.width, height: fitted.height),
                    imageSize: imageSize,
                    onDone: { commitTextDraftIfNeeded() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func textPlacementGesture(fitted: CGRect, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard textDraft == nil else { return }
                guard fitted.contains(value.startLocation) else { return }
                NSCursor.crosshair.set()
                if textPlacementStart == nil {
                    textPlacementStart = clampPointToFitted(value.startLocation, fitted: fitted)
                }
                textPlacementCurrent = clampPointToFitted(value.location, fitted: fitted)
            }
            .onEnded { value in
                defer {
                    textPlacementStart = nil
                    textPlacementCurrent = nil
                }

                // While editing, only Done (or leaving Text mode) commits — ignore outside clicks.
                guard textDraft == nil else { return }

                guard fitted.contains(value.startLocation) else { return }
                let start = clampPointToFitted(value.startLocation, fitted: fitted)
                let end = clampPointToFitted(value.location, fitted: fitted)
                let distance = hypot(end.x - start.x, end.y - start.y)

                if distance < 6 {
                    guard let point = normalizedPoint(from: start, fitted: fitted) else { return }
                    if let existing = hitTestTextAnnotation(at: point, fitted: fitted, imageSize: imageSize) {
                        beginEditingTextAnnotation(existing, imageSize: imageSize)
                    } else {
                        beginNewTextDraft(at: point)
                    }
                    return
                }

                let rect = selectionRect(from: start, to: end)
                guard rect.width > 8, rect.height > 8,
                      let origin = normalizedPoint(from: CGPoint(x: rect.minX, y: rect.minY), fitted: fitted),
                      fitted.width > 0, fitted.height > 0 else { return }
                beginNewTextDraft(
                    x: origin.x,
                    y: origin.y,
                    width: min(max(Double(rect.width / fitted.width), 0.06), 1 - origin.x),
                    height: min(max(Double(rect.height / fitted.height), 0.04), 1 - origin.y)
                )
            }
    }

    private func hitTestTextAnnotation(
        at point: DrawPoint,
        fitted: CGRect,
        imageSize: CGSize
    ) -> ImageAnnotation? {
        let current = store.items.first(where: { $0.id == item.id }) ?? item
        for annotation in current.annotations.reversed() where annotation.kind == .text {
            let box = Self.normalizedTextBox(for: annotation, imageSize: imageSize)
            if point.x >= box.x,
               point.x <= box.x + box.width,
               point.y >= box.y,
               point.y <= box.y + box.height {
                return annotation
            }
        }
        return nil
    }

    private static func normalizedTextBox(
        for annotation: ImageAnnotation,
        imageSize: CGSize
    ) -> (x: Double, y: Double, width: Double, height: Double) {
        let x = min(annotation.x, annotation.x2)
        let y = min(annotation.y, annotation.y2)
        var width = abs(annotation.x2 - annotation.x)
        var height = abs(annotation.y2 - annotation.y)
        if width >= 0.02, height >= 0.02 {
            return (x, y, width, height)
        }
        let text = annotation.text.isEmpty ? "Text" : annotation.text
        let font = ScreenshotStore.annotationFont(
            name: annotation.fontName,
            size: CGFloat(max(annotation.fontSize, 10))
        )
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let measured = (text as NSString).boundingRect(
            with: NSSize(
                width: max(imageSize.width * 0.5, 120),
                height: .greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        ).size
        let iw = max(imageSize.width, 1)
        let ih = max(imageSize.height, 1)
        width = max(Double(measured.width / iw) + 0.02, 0.12)
        height = max(Double(measured.height / ih) + 0.015, 0.05)
        return (x, y, min(width, 0.9), min(height, 0.5))
    }

    private func beginNewTextDraft(at point: DrawPoint) {
        let width = 0.28
        let height = 0.1
        let x = min(max(point.x, 0), 1 - width)
        let y = min(max(point.y, 0), 1 - height)
        beginNewTextDraft(x: x, y: y, width: width, height: height)
    }

    private func beginNewTextDraft(x: Double, y: Double, width: Double, height: Double) {
        textEditBuffer.text = ""
        textDraft = TextAnnotationDraft(
            annotationID: UUID(),
            isNew: true,
            x: x,
            y: y,
            width: width,
            height: height,
            text: "",
            fontSize: annotationFontSize,
            fontName: annotationFontName,
            textAlignment: annotationTextAlignment,
            colorHex: drawColorHex,
            isEditing: true
        )
        // Defer bake + focus past the drag gesture / current view update to avoid
        // "Publishing changes from within view updates" and to focus after mouse-up.
        DispatchQueue.main.async {
            bakeTextDraftCanvasImage()
            textFocusGeneration &+= 1
        }
    }

    private func beginEditingTextAnnotation(_ annotation: ImageAnnotation, imageSize: CGSize) {
        let box = Self.normalizedTextBox(for: annotation, imageSize: imageSize)
        textEditBuffer.text = annotation.text
        let fontName = annotation.fontName.isEmpty ? "System" : annotation.fontName
        let alignment = annotation.textAlignment.isEmpty ? "left" : annotation.textAlignment
        textDraft = TextAnnotationDraft(
            annotationID: annotation.id,
            isNew: false,
            x: box.x,
            y: box.y,
            width: box.width,
            height: box.height,
            text: annotation.text,
            fontSize: annotation.fontSize,
            fontName: fontName,
            textAlignment: alignment,
            colorHex: annotation.colorHex,
            isEditing: true
        )
        DispatchQueue.main.async {
            annotationFontSize = annotation.fontSize
            annotationFontName = fontName
            annotationTextAlignment = alignment
            drawColorHex = annotation.colorHex
            bakeTextDraftCanvasImage()
            textFocusGeneration &+= 1
        }
    }

    private func bakeTextDraftCanvasImage() {
        guard let draft = textDraft else {
            textDraftCanvasImage = nil
            return
        }
        textDraftCanvasImage = store.renderedImage(
            for: item,
            excludingAnnotationIDs: [draft.annotationID]
        )
    }

    private func commitTextDraftIfNeeded() {
        guard var draft = textDraft else { return }
        // Prefer live editor buffer so keystrokes aren't mirrored into @State while typing.
        draft.text = textEditBuffer.text
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let x2 = min(max(draft.x + draft.width, 0), 1)
        let y2 = min(max(draft.y + draft.height, 0), 1)
        if draft.isNew {
            if !trimmed.isEmpty {
                store.addAnnotation(
                    ImageAnnotation(
                        id: draft.annotationID,
                        kind: .text,
                        x: draft.x,
                        y: draft.y,
                        x2: x2,
                        y2: y2,
                        text: trimmed,
                        colorHex: draft.colorHex,
                        fontSize: draft.fontSize,
                        fontName: draft.fontName,
                        textAlignment: draft.textAlignment
                    ),
                    for: item.id
                )
            }
        } else if trimmed.isEmpty {
            store.removeAnnotation(draft.annotationID, for: item.id)
        } else {
            store.updateAnnotation(
                ImageAnnotation(
                    id: draft.annotationID,
                    kind: .text,
                    x: draft.x,
                    y: draft.y,
                    x2: x2,
                    y2: y2,
                    text: trimmed,
                    colorHex: draft.colorHex,
                    fontSize: draft.fontSize,
                    fontName: draft.fontName,
                    textAlignment: draft.textAlignment
                ),
                for: item.id
            )
        }
        textDraft = nil
        textEditBuffer.text = ""
        textDraftCanvasImage = nil
        textPlacementStart = nil
        textPlacementCurrent = nil
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(item.title).png"
        if panel.runModal() == .OK, let url = panel.url {
            store.saveAs(item, url: url)
        }
    }
}

private struct TextDraftEditorOverlay: View {
    @Binding var draft: TextAnnotationDraft?
    let textBuffer: AnnotateTextBuffer
    var focusGeneration: Int
    let fitted: CGRect
    /// Full scroll-host size; format bar is clamped inside so it stays tappable.
    let hostSize: CGSize
    let imageSize: CGSize
    var onDone: () -> Void

    /// Local-only so dragging/resizing does not thrash the parent canvas.
    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero

    private let minBoxSide: CGFloat = 36
    private let handleSize: CGFloat = 12
    private let moveBarHeight: CGFloat = 18
    private let formatBarHeight: CGFloat = 36
    private static let canvasSpace = "textDraftCanvas"
    private static let minFontSize: Double = 10
    private static let maxFontSize: Double = 72

    var body: some View {
        if let draft {
            let scale = imageSize.width > 0 ? fitted.width / imageSize.width : 1
            // Match on-image bake size: annotation points scaled to the fitted canvas.
            let fontSize = max(10, CGFloat(draft.fontSize) * scale)
            let baseWidth = max(CGFloat(draft.width) * fitted.width, minBoxSide)
            let baseHeight = max(CGFloat(draft.height) * fitted.height, minBoxSide)
            let width = max(baseWidth + resizeDelta.width, minBoxSide)
            let height = max(baseHeight + resizeDelta.height, minBoxSide)
            let origin = CGPoint(
                x: fitted.minX + CGFloat(draft.x) * fitted.width + dragOffset.width,
                y: fitted.minY + CGFloat(draft.y) * fitted.height + dragOffset.height
            )
            // Prefer above the move strip / outside the picture; keep inside the host so hits work.
            let barOrigin = CGPoint(
                x: min(max(origin.x, 4), max(hostSize.width - 320, 4)),
                y: min(
                    max(origin.y - moveBarHeight - formatBarHeight - 6, 4),
                    max(hostSize.height - formatBarHeight - 4, 4)
                )
            )

            ZStack(alignment: .topLeading) {
                formattingBar(draft: draft)
                    .offset(x: barOrigin.x, y: barOrigin.y)

                ZStack(alignment: .topLeading) {
                    // Move strip sits *above* the text box so stored coords match bake layout.
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: width, height: moveBarHeight)
                        .contentShape(Rectangle())
                        .overlay(
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .offset(y: -moveBarHeight)
                        .gesture(moveGesture())
                        .help("Drag to move")

                    // Text area = annotation rect (no chrome insets — must match ScreenshotStore bake).
                    boxChrome(draft: draft, fontSize: fontSize, width: width, height: height)
                        .frame(width: width, height: height)

                    // Corner resize — available while editing.
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: handleSize, height: handleSize)
                        .contentShape(Rectangle())
                        .overlay(
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .offset(x: width - handleSize / 2, y: height - handleSize / 2)
                        .gesture(resizeGesture(baseWidth: baseWidth, baseHeight: baseHeight))
                        .help("Drag to resize")
                }
                .offset(x: origin.x, y: origin.y)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Stable space so drag deltas track the cursor while the box moves.
            .coordinateSpace(name: Self.canvasSpace)
            .onAppear {
                dragOffset = .zero
                resizeDelta = .zero
                textBuffer.text = draft.text
            }
        }
    }

    @ViewBuilder
    private func formattingBar(draft: TextAnnotationDraft) -> some View {
        HStack(spacing: 6) {
            Button {
                adjustFontSize(by: -2)
            } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .buttonStyle(.borderless)
            .help("Smaller")

            Text("\(Int(draft.fontSize))")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 24)
                .help("Font size in image points")

            Button {
                adjustFontSize(by: 2)
            } label: {
                Image(systemName: "textformat.size.larger")
            }
            .buttonStyle(.borderless)
            .help("Larger")

            Divider().frame(height: 14)

            Picker("", selection: fontNameBinding) {
                ForEach(TextAnnotationDraft.fontChoices, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 120)
            .controlSize(.small)

            Picker("", selection: alignmentBinding) {
                Image(systemName: "text.alignleft").tag("left")
                Image(systemName: "text.aligncenter").tag("center")
                Image(systemName: "text.alignright").tag("right")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 90)
            .controlSize(.small)

            Divider().frame(height: 14)

            Button("Done") {
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Place text on the image")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        )
    }

    private func adjustFontSize(by delta: Double) {
        guard let current = draft?.fontSize else { return }
        draft?.fontSize = min(Self.maxFontSize, max(Self.minFontSize, current + delta))
    }

    private var fontNameBinding: Binding<String> {
        Binding(
            get: { draft?.fontName ?? "System" },
            set: { draft?.fontName = $0 }
        )
    }

    private var alignmentBinding: Binding<String> {
        Binding(
            get: { draft?.textAlignment ?? "left" },
            set: { draft?.textAlignment = $0 }
        )
    }

    private func boxChrome(
        draft: TextAnnotationDraft,
        fontSize: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let nsFont = ScreenshotStore.annotationFont(name: draft.fontName, size: fontSize)
        let nsColor = EditorRedactionSettings.nsColor(fromHex: draft.colorHex)
        let alignment = ScreenshotStore.nsTextAlignment(draft.textAlignment)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.94))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)

            // Fill the annotation box edge-to-edge so Done bake matches live typing.
            AnnotateTextEditor(
                textBuffer: textBuffer,
                focusGeneration: focusGeneration,
                font: nsFont,
                textColor: nsColor,
                alignment: alignment
            )
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }

    private func moveGesture() -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                // Prefer cursor delta in a fixed parent space — local `.translation`
                // drifts once this view moves under the pointer.
                dragOffset = CGSize(
                    width: value.location.x - value.startLocation.x,
                    height: value.location.y - value.startLocation.y
                )
            }
            .onEnded { value in
                let delta = CGSize(
                    width: value.location.x - value.startLocation.x,
                    height: value.location.y - value.startLocation.y
                )
                defer { dragOffset = .zero }
                guard fitted.width > 0, fitted.height > 0 else { return }
                guard hypot(delta.width, delta.height) > 1, let draft else { return }
                let nx = draft.x + Double(delta.width / fitted.width)
                let ny = draft.y + Double(delta.height / fitted.height)
                let maxX = max(1 - draft.width, 0)
                let maxY = max(1 - draft.height, 0)
                self.draft?.x = min(max(nx, 0), maxX)
                self.draft?.y = min(max(ny, 0), maxY)
            }
    }

    private func resizeGesture(
        baseWidth: CGFloat,
        baseHeight: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                resizeDelta = CGSize(
                    width: value.location.x - value.startLocation.x,
                    height: value.location.y - value.startLocation.y
                )
            }
            .onEnded { value in
                let delta = CGSize(
                    width: value.location.x - value.startLocation.x,
                    height: value.location.y - value.startLocation.y
                )
                defer { resizeDelta = .zero }
                guard fitted.width > 0, fitted.height > 0, let draft else { return }
                let newWidth = max(baseWidth + delta.width, minBoxSide)
                let newHeight = max(baseHeight + delta.height, minBoxSide)
                var width = Double(newWidth / fitted.width)
                var height = Double(newHeight / fitted.height)
                width = min(max(width, 0.05), max(1 - draft.x, 0.05))
                height = min(max(height, 0.04), max(1 - draft.y, 0.04))
                self.draft?.width = width
                self.draft?.height = height
            }
    }
}

/// Plain buffer so typing does not publish SwiftUI `@State` on every keystroke.
private final class AnnotateTextBuffer {
    var text: String = ""
}

/// AppKit text view so font family and paragraph alignment apply while typing.
private struct AnnotateTextEditor: NSViewRepresentable {
    let textBuffer: AnnotateTextBuffer
    var focusGeneration: Int
    var font: NSFont
    var textColor: NSColor
    var alignment: NSTextAlignment

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        context.coordinator.textView = textView
        applyStyle(to: textView, string: textBuffer.text, coordinator: context.coordinator)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        let styleChanged =
            abs(context.coordinator.appliedFontSize - font.pointSize) > 0.05
            || context.coordinator.appliedFontName != font.fontName
            || context.coordinator.appliedColorHex != colorKey
            || context.coordinator.appliedAlignment != alignment.rawValue

        // Keep whatever the user typed in the text view; only restyle when formatting changes.
        if styleChanged {
            let selected = textView.selectedRanges
            let live = textView.string
            textBuffer.text = live
            applyStyle(to: textView, string: live, coordinator: context.coordinator)
            textView.selectedRanges = selected
        }

        if focusGeneration != context.coordinator.lastFocusGeneration {
            context.coordinator.lastFocusGeneration = focusGeneration
            // After place-drag, wait a beat so mouse-up doesn't steal first responder.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak textView] in
                guard let textView, let window = textView.window else { return }
                window.makeFirstResponder(textView)
            }
        }
    }

    private var colorKey: String {
        textColor.usingColorSpace(.sRGB)?.hexString ?? textColor.description
    }

    /// Rebuilds the whole attributed string so already-typed characters pick up size/font/color.
    private func applyStyle(to textView: NSTextView, string: String, coordinator: Coordinator) {
        coordinator.isApplyingStyle = true
        defer { coordinator.isApplyingStyle = false }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        textView.textStorage?.beginEditing()
        textView.textStorage?.setAttributedString(NSAttributedString(string: string, attributes: attrs))
        textView.textStorage?.endEditing()
        textView.typingAttributes = attrs
        textView.font = font
        textView.textColor = textColor
        textView.alignment = alignment
        coordinator.appliedFontSize = font.pointSize
        coordinator.appliedFontName = font.fontName
        coordinator.appliedColorHex = colorKey
        coordinator.appliedAlignment = alignment.rawValue
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AnnotateTextEditor
        weak var textView: NSTextView?
        var appliedFontSize: CGFloat = -1
        var appliedFontName: String = ""
        var appliedColorHex: String = ""
        var appliedAlignment: Int = .min
        var isApplyingStyle = false
        var lastFocusGeneration: Int = 0

        init(_ parent: AnnotateTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingStyle else { return }
            guard let textView = notification.object as? NSTextView else { return }
            // Write to the plain buffer only — never publish SwiftUI state from AppKit callbacks.
            parent.textBuffer.text = textView.string
        }
    }
}

private extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return description }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

private struct TextAnnotationDraft: Equatable {
    var annotationID: UUID
    var isNew: Bool
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var text: String
    var fontSize: Double
    var fontName: String
    var textAlignment: String
    var colorHex: String
    var isEditing: Bool

    static let fontChoices = ["System", "Helvetica Neue", "Arial", "Times New Roman", "Menlo"]
}

private extension View {
    func toolOptionChrome() -> some View {
        self
            .padding(8)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct MenuBarGalleryView: View {
    @EnvironmentObject private var store: ScreenshotStore
    @EnvironmentObject private var pause: BuddyPauseController
    @ObservedObject private var unlock = SensitiveUnlockSession.shared
    @AppStorage(BuddySettingsKey.autoBlurContentTags) private var protectedTagsRaw: String = ""
    @AppStorage(BuddySettingsKey.requireAuthSensitiveContent) private var requireAuth = false
    @AppStorage(BuddySettingsKey.screenshotMenuBarRecentCount) private var menuBarRecentCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if pause.isPaused {
                Text(pause.statusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .top])
            }

            Text("Recent shots")
                .font(.headline)
                .padding([.horizontal, .top])
            let recent = Array(store.items.prefix(max(menuBarRecentCount, 1)))
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, item in
                let _ = protectedTagsRaw
                let _ = requireAuth
                let _ = unlock.unlockedUntil
                let isHidden = store.isHidden(item)
                MenuBarRow(
                    title: isHidden ? "•••• Sensitive" : item.title,
                    subtitle: item.createdAt.formatted(),
                    thumbnail: NSImage(data: item.imageData).map { Image(nsImage: $0) },
                    thumbnailBlur: isHidden ? 8 : 0,
                    copyAction: {
                        guard !pause.isPaused else { return }
                        if isHidden {
                            store.reveal(item: item) { ok in
                                if ok { store.copyToClipboard(item) }
                            }
                        } else {
                            store.copyToClipboard(item)
                        }
                    },
                    showsSeparator: index < recent.count - 1
                ) {
                    guard !pause.isPaused else { return }
                    store.selectedId = item.id
                    BuddyMainWindow.show()
                }
                .contextMenu {
                    Button(role: .destructive) {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "Delete Screenshot?")
                        alert.informativeText = String(localized: "This cannot be undone.")
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: String(localized: "Delete"))
                        alert.addButton(withTitle: String(localized: "Cancel"))
                        if alert.runModal() == .alertFirstButtonReturn {
                            store.delete(item.id)
                        }
                    } label: {
                        Label("Delete…", systemImage: "trash")
                    }
                    .disabled(pause.isPaused)
                }
                .padding(.horizontal)
                .opacity(pause.isPaused ? 0.45 : 1)
                .disabled(pause.isPaused)
            }
            Spacer(minLength: 0)
            BuddyPauseControls(pause: pause)
            BuddyClearHistoryButton(itemNoun: "screenshots") {
                store.clearAllHistory()
            }
            BuddyMenuBarAppControls(appName: "Capture Buddy", brand: .screenshotBuddy)
        }
        .accessibilityIdentifier("menu-bar-gallery")
    }
}

private struct ScrollDisabledWhenFitModifier: ViewModifier {
    let disabled: Bool

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.scrollDisabled(disabled)
        } else {
            content
        }
    }
}
