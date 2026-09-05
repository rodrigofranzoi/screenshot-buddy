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

    enum DrawMode { case none, blackBox, blur, text }

    var body: some View {
        NavigationSplitView {
            List(store.items, selection: $store.selectedId) { item in
                HStack {
                    if let img = NSImage(data: item.imageData) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 36)
                            .clipped()
                            .cornerRadius(4)
                    }
                    VStack(alignment: .leading) {
                        Text(item.title).lineLimit(1)
                        Text(item.tags.map(\.rawValue).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(item.id)
                .accessibilityIdentifier("gallery-row")
            }
            .accessibilityIdentifier("gallery-list")
            .toolbar {
                ToolbarItem {
                    Button("Paste") { store.importFromPasteboard() }
                        .accessibilityIdentifier("paste-screenshot")
                }
            }
            .navigationTitle("Gallery")
        } detail: {
            if let item = store.selected {
                EditorPane(item: item, drawMode: $drawMode, dragStart: $dragStart, dragCurrent: $dragCurrent)
            } else {
                Text("Select or paste a screenshot")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct EditorPane: View {
    @EnvironmentObject private var store: ScreenshotStore
    let item: ScreenshotItem
    @Binding var drawMode: GalleryView.DrawMode
    @Binding var dragStart: CGPoint?
    @Binding var dragCurrent: CGPoint?
    @State private var notes: String = ""
    @State private var annotationText: String = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Tool", selection: $drawMode) {
                    Text("Select").tag(GalleryView.DrawMode.none)
                    Text("Black box").tag(GalleryView.DrawMode.blackBox)
                    Text("Blur").tag(GalleryView.DrawMode.blur)
                    Text("Text").tag(GalleryView.DrawMode.text)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Edit tools")

                Button("Redact sensitive") { store.quickRedactSensitive(for: item.id) }
                Button("Copy") { store.copyToClipboard(item) }
                Button("Save As…") { saveAs() }
                Button("Overwrite") { store.overwrite(item) }
            }
            .padding(.horizontal)

            GeometryReader { geo in
                ZStack {
                    if let image = store.renderedImage(for: item) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel("Screenshot editor canvas")
                    }
                    if drawMode == .text {
                        TextField("Annotation", text: $annotationText)
                            .textFieldStyle(.roundedBorder)
                            .padding()
                    }
                }
                .gesture(dragGesture(in: geo.size))
            }

            TextField("Notes (used for sensitive detection)", text: $notes)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .onAppear { notes = item.notes }
                .onChange(of: notes) { newValue in
                    store.updateNotes(newValue, for: item.id)
                }

            HStack {
                ForEach(item.tags, id: \.self) { TagChip(tag: $0) }
            }
            .padding(.bottom)
        }
        .accessibilityIdentifier("editor-pane")
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard drawMode == .blackBox || drawMode == .blur else { return }
                if dragStart == nil { dragStart = value.startLocation }
                dragCurrent = value.location
            }
            .onEnded { value in
                guard drawMode == .blackBox || drawMode == .blur, let start = dragStart else {
                    dragStart = nil
                    dragCurrent = nil
                    return
                }
                let end = value.location
                let x = min(start.x, end.x) / max(size.width, 1)
                let y = min(start.y, end.y) / max(size.height, 1)
                let w = abs(end.x - start.x) / max(size.width, 1)
                let h = abs(end.y - start.y) / max(size.height, 1)
                let style: RedactionStyle = drawMode == .blur ? .blur : .blackBox
                store.addRedaction(RedactionRect(x: x, y: y, width: w, height: h, style: style), for: item.id)
                dragStart = nil
                dragCurrent = nil
            }
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

struct MenuBarGalleryView: View {
    @EnvironmentObject private var store: ScreenshotStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent shots")
                .font(.headline)
                .padding([.horizontal, .top])
            ForEach(store.items.prefix(8)) { item in
                MenuBarRow(title: item.title, subtitle: item.createdAt.formatted()) {
                    store.selectedId = item.id
                    store.copyToClipboard(item)
                }
                .padding(.horizontal)
            }
            Spacer()
        }
        .accessibilityIdentifier("menu-bar-gallery")
    }
}
