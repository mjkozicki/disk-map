import AppKit
import SwiftUI
import DiskMapCore

struct MapDisplayItem: Equatable {
    let id: Int
    let name: String
    let path: String
    let bytes: Int64
    let kind: ItemKind
    let sizeText: String
    let group: [Int]
    let partial: Bool
}

func colorForKind(_ kind: ItemKind, name: String = "") -> NSColor {
    if kind == .package { return .systemPurple }
    if kind == .folder { return .systemBlue }
    if kind == .symbolicLink || kind == .alias { return .systemGray }
    switch (name as NSString).pathExtension.lowercased() {
    case "mov", "mp4", "mkv", "avi", "mp3", "wav", "m4a": return .systemOrange
    case "jpg", "jpeg", "png", "heic", "gif", "tiff", "raw": return .systemGreen
    case "zip", "dmg", "tar", "gz", "iso": return .systemPink
    default: return .systemTeal
    }
}

struct NativeTreemap: NSViewRepresentable {
    let items: [MapDisplayItem]
    let selected: Int?
    let highlights: Set<Int>
    var overview = false
    var choose: (Int) -> Void
    var open: (Int) -> Void
    var inspect: (Int) -> Void
    var reveal: (Int) -> Void
    var copy: (Int) -> Void
    var group: ([Int]) -> Void

    func makeNSView(context: Context) -> TreemapNSView { TreemapNSView() }
    func updateNSView(_ view: TreemapNSView, context: Context) {
        view.choose = choose; view.open = open; view.inspect = inspect
        view.reveal = reveal; view.copyPath = copy; view.chooseGroup = group
        view.selected = selected; view.highlights = highlights; view.overview = overview
        if view.items != items { view.items = items; view.rebuild() }
        view.needsDisplay = true
    }
}

final class TreemapNSView: NSView, NSViewToolTipOwner {
    var items: [MapDisplayItem] = []
    var selected: Int?
    var highlights: Set<Int> = []
    var overview = false
    var choose: (Int) -> Void = { _ in }
    var open: (Int) -> Void = { _ in }
    var inspect: (Int) -> Void = { _ in }
    var reveal: (Int) -> Void = { _ in }
    var copyPath: (Int) -> Void = { _ in }
    var chooseGroup: ([Int]) -> Void = { _ in }
    private var tiles: [MapTile] = []
    private var lookup: [Int: MapDisplayItem] = [:]
    private var contextID: Int?
    private var tips: [NSView.ToolTipTag: String] = [:]
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("File size treemap. Use the file table to select and inspect every item with VoiceOver.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); rebuild() }
    func rebuild() {
        lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        tiles = TreemapLayout.layout(items.map { MapItem(id: $0.id, weight: Double($0.bytes)) }, in: bounds.insetBy(dx: 1, dy: 1))
        removeAllToolTips()
        tips.removeAll(keepingCapacity: true)
        let total = items.reduce(Int64(0)) { $0 + $1.bytes }
        for tile in tiles {
            guard let item = lookup[tile.id] else { continue }
            let tag = addToolTip(tile.rect, owner: self, userData: nil)
            let percent = String(format: "%.1f%%", Double(item.bytes) / Double(max(1, total)) * 100)
            tips[tag] = "\(item.name)\n\(item.sizeText) · \(item.kind.rawValue) · \(percent) of displayed bytes\n\(item.path)"
        }
        needsDisplay = true
    }
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData: UnsafeMutableRawPointer?) -> String { tips[tag] ?? "" }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        for tile in tiles {
            guard let item = lookup[tile.id], tile.rect.intersects(dirtyRect) else { continue }
            let rect = tile.rect.insetBy(dx: 1.5, dy: 1.5)
            guard rect.width > 0 && rect.height > 0 else { continue }
            let isSelected = selected == item.id
            let color = colorForKind(item.kind, name: item.name)
            let fill = color.withAlphaComponent(isSelected ? 0.43 : highlights.contains(item.id) ? 0.32 : 0.16)
            fill.setFill(); NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            if isSelected || highlights.contains(item.id) {
                (isSelected ? NSColor.controlAccentColor : NSColor.systemYellow).setStroke()
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
                path.lineWidth = isSelected ? 2.5 : 2; path.stroke()
            }
            if overview || rect.width < 45 || rect.height < 22 { continue }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()
            let textRect = rect.insetBy(dx: 9, dy: 6)
            drawText(item.name, rect: NSRect(x: textRect.minX, y: textRect.minY, width: textRect.width, height: 20), font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor)
            if rect.height >= 52 {
                drawText(item.sizeText, rect: NSRect(x: textRect.minX, y: textRect.minY + 23, width: textRect.width, height: 23), font: .systemFont(ofSize: rect.width > 115 ? 18 : 13, weight: .medium), color: .labelColor)
            }
            if rect.height > 95 && rect.width > 90 {
                let detail = item.group.isEmpty ? (item.kind == .package ? "Package · grouped contents" : item.kind.rawValue) : "\(item.group.count) smaller items"
                drawText(detail + (item.partial ? " · partial" : ""), rect: NSRect(x: textRect.minX, y: rect.maxY - 24, width: textRect.width, height: 18), font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let tile = tiles.first(where: { $0.rect.contains(point) }), let item = lookup[tile.id] else { return }
        if !item.group.isEmpty { chooseGroup(item.group); return }
        choose(item.id)
        if event.clickCount == 2 || overview { open(item.id) }
    }
    override func keyDown(with event: NSEvent) {
        let ids = tiles.map(\.id).filter { $0 >= 0 }
        guard !ids.isEmpty else { return }
        let position = ids.firstIndex(of: selected ?? -1) ?? 0
        switch event.keyCode {
        case 123, 126: choose(ids[(position - 1 + ids.count) % ids.count])
        case 124, 125: choose(ids[(position + 1) % ids.count])
        case 36: if let selected { open(selected) }
        default: super.keyDown(with: event)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let tile = tiles.first(where: { $0.rect.contains(point) }), let item = lookup[tile.id], item.id >= 0 else { return nil }
        contextID = item.id; choose(item.id)
        let menu = NSMenu()
        if item.kind.isContainer {
            let action = NSMenuItem(title: item.kind == .package ? "Inspect Package Contents" : "Open Folder", action: #selector(contextInspect), keyEquivalent: "")
            action.target = self; menu.addItem(action)
        }
        let finder = NSMenuItem(title: "Reveal in Finder", action: #selector(contextReveal), keyEquivalent: "")
        finder.target = self; menu.addItem(finder)
        let copy = NSMenuItem(title: "Copy Path", action: #selector(contextCopy), keyEquivalent: "")
        copy.target = self; menu.addItem(copy)
        return menu
    }
    @objc private func contextInspect() { if let contextID { inspect(contextID) } }
    @objc private func contextReveal() { if let contextID { reveal(contextID) } }
    @objc private func contextCopy() { if let contextID { copyPath(contextID) } }
}

struct MapPanel: View {
    @ObservedObject var model: AppModel
    var overview = false

    private var displayItems: [MapDisplayItem] {
        guard let index = model.index, let parent = model.node(overview ? 0 : model.currentID) else { return [] }
        var ids = parent.children.filter { model.isVisible($0) && index[$0].bytes(model.metric) > 0 }
        if !overview && model.filteredMap {
            let allowed = Set(model.rows.compactMap { row -> Int? in
                let path = index.ancestors(of: row.id)
                guard let offset = path.firstIndex(of: model.currentID), offset + 1 < path.count else { return nil }
                return path[offset + 1]
            })
            ids = ids.filter { allowed.contains($0) }
        }
        ids.sort { index[$0].bytes(model.metric) == index[$1].bytes(model.metric) ? $0 < $1 : index[$0].bytes(model.metric) > index[$1].bytes(model.metric) }
        let total = ids.reduce(Int64(0)) { $0 + index[$1].bytes(model.metric) }
        var group: [Int] = [], result: [MapDisplayItem] = []
        for (position, id) in ids.enumerated() {
            let n = index[id]
            if position >= (overview ? 60 : 300) || (position > 12 && Double(n.bytes(model.metric)) / Double(max(1, total)) < 0.001) { group.append(id); continue }
            result.append(MapDisplayItem(id: id, name: n.name, path: index.url(for: id).path, bytes: n.bytes(model.metric), kind: n.kind, sizeText: n.sizeLabel(model.metric), group: [], partial: n.isPartial))
        }
        if !group.isEmpty {
            let bytes = group.reduce(Int64(0)) { $0 + index[$1].bytes(model.metric) }
            result.append(MapDisplayItem(id: -1, name: "Smaller items", path: "Select to list all \(group.count) items", bytes: bytes, kind: .other, sizeText: ByteFormatting.string(bytes), group: group, partial: false))
        }
        return result
    }
    private var highlights: Set<Int> {
        guard let index = model.index else { return [] }
        let parent = overview ? 0 : model.currentID
        let targets = overview ? [model.currentID] : (!model.query.isEmpty ? model.rows.map(\.id) : [])
        return Set(targets.compactMap { id in
            let ancestors = index.ancestors(of: id)
            guard let offset = ancestors.firstIndex(of: parent), offset + 1 < ancestors.count else { return nil }
            return ancestors[offset + 1]
        })
    }
    var body: some View {
        let items = displayItems
        let visibleSelection: Int? = {
            guard let selected = model.selectedID, let index = model.index else { return nil }
            let parent = overview ? 0 : model.currentID
            let path = index.ancestors(of: selected)
            guard let offset = path.firstIndex(of: parent), offset + 1 < path.count else { return selected }
            return path[offset + 1]
        }()
        ZStack {
            if items.isEmpty {
                ContentUnavailableView("No measured file sizes", systemImage: "rectangle.dashed", description: Text("Zero-byte, unknown-size, and filtered items remain available in the list."))
            } else {
                NativeTreemap(items: items, selected: overview ? highlights.first : visibleSelection, highlights: highlights, overview: overview,
                              choose: { model.selectedID = $0; model.showInspector = true }, open: { model.navigate($0) },
                              inspect: { model.inspect($0) }, reveal: { model.reveal($0) }, copy: { model.copyPath($0) }, group: { ids in
                    if overview { model.navigate(0, inspectPackage: true) }
                    model.showGroup(ids)
                })
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5))
    }
}
