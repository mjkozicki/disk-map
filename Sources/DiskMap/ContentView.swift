import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DiskMapCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 185, ideal: 215, max: 320)
        } detail: {
            HSplitView {
                Group {
                    if model.hasScan {
                        if model.mode == .cleanup { DevelopmentCleanupView(model: model) }
                        else { ExplorerView(model: model) }
                    }
                    else if model.isScanning {
                        VStack(spacing: 16) { ProgressView(); Text("Reading folder metadata…"); Button("Cancel") { model.cancelScan() } }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else { WelcomeView(model: model) }
                }.frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if model.showInspector && model.hasScan && model.mode != .cleanup {
                    InspectorView(model: model).frame(minWidth: 220, idealWidth: 255, maxWidth: 330)
                }
            }
        }
        .navigationTitle("Disk Map")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.goBack() } label: { Image(systemName: "chevron.left") }.help("Back (⌘[)").disabled(model.history.isEmpty)
                Button { model.goUp() } label: { Image(systemName: "arrow.up") }.help("Enclosing folder (⌘↑)").disabled(model.current?.parent == nil)
            }
            ToolbarItem {
                TextField("Search names and paths", text: $model.query).textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160, idealWidth: 240, maxWidth: 320).focused($searchFocused)
                    .accessibilityLabel("Search names and paths")
            }
            ToolbarItemGroup {
                Picker("Size metric", selection: $model.metric) { ForEach(SizeMetric.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 135)
                Button { model.chooseLocation() } label: { Label("Choose Location", systemImage: "folder.badge.plus") }.help("Choose a folder or volume (⌘O)")
                if model.isScanning { Button("Cancel") { model.cancelScan() } }
                else { Button { model.rescan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }.disabled(!model.hasScan) }
                Button { model.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.help("Toggle inspector")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(model: model) }
        .frame(minWidth: 940, minHeight: 650)
        .overlay { if model.dropTarget { RoundedRectangle(cornerRadius: 10).stroke(.tint, lineWidth: 4).padding(4).allowsHitTesting(false) } }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $model.dropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { model.startScan(url) }
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .diskMapFocusSearch)) { _ in searchFocused = true }
        .alert("Disk Map", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .sheet(isPresented: $model.showIssues) { IssuesView(model: model) }
        .sheet(isPresented: $model.showCleanupReview) { CleanupReviewView(model: model) }
    }
}

struct WelcomeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.split.2x2.fill").font(.system(size: 54)).foregroundStyle(.blue, .purple)
            Text("See where your space goes.").font(.largeTitle.weight(.semibold))
            Text("Choose a folder or volume to explore its files and packages.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Choose a Location…") { model.chooseLocation() }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("Scan Home Folder") { model.startScan(FileManager.default.homeDirectoryForCurrentUser) }
            Text("Or drop a folder here. Scanning reads metadata only; your files stay on your Mac.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }.padding(35).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SidebarView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Explore") {
                    ForEach(ExplorerMode.allCases) { mode in
                        Button { model.mode = mode } label: {
                            Label(mode.rawValue, systemImage: mode.symbol).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 3).foregroundStyle(model.mode == mode ? Color.accentColor : Color.primary).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                if let root = model.root {
                    Section("Scanned location") {
                        Button { model.navigate(0, inspectPackage: true) } label: {
                            Label(root.name, systemImage: "house").lineLimit(1)
                        }.buttonStyle(.plain).help(model.index?.rootURL.path ?? "")
                        ForEach(root.children.filter { model.node($0)?.kind.isContainer == true && model.isVisible($0) }.sorted { (model.node($0)?.bytes(model.metric) ?? 0) > (model.node($1)?.bytes(model.metric) ?? 0) }.prefix(150), id: \.self) { id in
                            FolderRow(model: model, id: id, depth: 0)
                        }
                        if root.children.count > 150 { Text("Open the folder to see all items.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section("Volumes") {
                    ForEach(model.volumes) { volume in
                        Button { model.startScan(volume.url) } label: { Label(volume.name, systemImage: "externaldrive").lineLimit(1) }.buttonStyle(.plain)
                    }
                    Button("Refresh volumes") { model.refreshVolumes() }.font(.caption)
                }
            }.listStyle(.sidebar)
            if let capacity = model.capacity, let available = model.available {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Volume capacity").font(.caption.weight(.medium))
                    ProgressView(value: Double(capacity - available), total: Double(max(1, capacity))).tint(.secondary)
                    Text("\(ByteFormatting.string(available)) available of \(ByteFormatting.string(capacity))").font(.caption).foregroundStyle(.secondary)
                }.padding(14)
            }
        }
    }
}

final class FolderDisclosure: ObservableObject { @Published var expanded = false }

struct FolderRow: View {
    @ObservedObject var model: AppModel
    let id: Int
    let depth: Int
    @StateObject private var disclosure = FolderDisclosure()
    var body: some View {
        if let n = model.node(id) {
            let folders = n.children.filter { model.node($0)?.kind.isContainer == true && model.isVisible($0) }.sorted { (model.node($0)?.bytes(model.metric) ?? 0) > (model.node($1)?.bytes(model.metric) ?? 0) }
            if n.kind == .folder && !folders.isEmpty && depth < 20 {
                DisclosureGroup(isExpanded: $disclosure.expanded) {
                    if disclosure.expanded {
                        ForEach(folders.prefix(100), id: \.self) { child in FolderRow(model: model, id: child, depth: depth + 1) }
                        if folders.count > 100 { Button("Open to see all folders") { model.navigate(id) } }
                    }
                } label: { row(n) }
            } else { row(n) }
        }
    }
    private func row(_ n: DiskNode) -> some View {
        Button { model.navigate(id) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: n.kind == .package ? "shippingbox" : "folder").foregroundStyle(n.kind == .package ? .purple : .blue)
                    Text(n.name).lineLimit(1)
                    Spacer(minLength: 1)
                }
                HStack { Text(n.sizeLabel(model.metric)).font(.caption2).foregroundStyle(.secondary); Spacer() }
                GeometryReader { geometry in
                    Capsule().fill(Color.secondary.opacity(0.35)).frame(width: max(0, geometry.size.width * min(1, Double(n.bytes(model.metric)) / Double(max(1, model.root?.bytes(model.metric) ?? 0)))))
                }.frame(height: 2)
            }.padding(.vertical, 2).foregroundStyle(model.currentID == id ? Color.accentColor : Color.primary).contentShape(Rectangle())
        }.buttonStyle(.plain).help("\(model.url(id)?.path ?? n.name) · size relative to scan root")
            .contextMenu { ItemActions(model: model, id: id) }
    }
}

struct ExplorerView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding([.horizontal, .top], 18)
            filters.padding(.horizontal, 18).padding(.vertical, 10)
            if model.isScanning || model.canceled || (model.root?.issueCount ?? 0) > 0 { scanNotice.padding(.horizontal, 18).padding(.bottom, 8) }
            if model.mode == .map {
                VSplitView {
                    VStack(alignment: .leading, spacing: 7) {
                        MapPanel(model: model).frame(minHeight: 160)
                        HStack {
                            Text(model.filteredMap ? "Matching branches · area includes full branch size" : "Area = \(model.metric.rawValue.lowercased())")
                            Spacer(); Text("Packages stay grouped")
                        }.font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            legend("Folders", .blue); legend("Packages", .purple); legend("Media", .orange); legend("Other files", .teal)
                        }.font(.caption2)
                        HStack { Text("SCAN OVERVIEW").font(.caption2).foregroundStyle(.secondary); Spacer(); Button("Scan root") { model.navigate(0, inspectPackage: true) }.font(.caption) }
                        MapPanel(model: model, overview: true).frame(height: 32)
                    }.padding(.horizontal, 18).padding(.bottom, 10).frame(minHeight: 255, idealHeight: 330)
                    ResultsTable(model: model).frame(minHeight: 150)
                }
            } else { ResultsTable(model: model) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(model.index?.ancestors(of: model.scopeID) ?? [], id: \.self) { id in
                        if id != 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                        Button(model.node(id)?.name ?? "") { model.navigate(id, inspectPackage: true) }.buttonStyle(.plain).font(.caption)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.mode == .map ? (model.current?.name ?? "Disk Map") : model.mode.rawValue).font(.title2.weight(.semibold)).lineLimit(1)
                    Text("\(model.node(model.scopeID)?.sizeLabel(model.metric) ?? "—") measured · \(model.rows.count.formatted()) listed items").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.current?.kind == .package { Label("Inside a package", systemImage: "shippingbox").font(.caption).foregroundStyle(.purple) }
            }
        }
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if model.mode != .packages {
                    Picker("Kind", selection: $model.kindFilter) { ForEach(KindFilter.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(maxWidth: 125)
                }
                Picker("Minimum size", selection: $model.minimumSize) {
                    Text("Any size").tag(Int64(0)); Text("100 MB+").tag(Int64(100_000_000)); Text("1 GB+").tag(Int64(1_000_000_000)); Text("10 GB+").tag(Int64(10_000_000_000))
                }.labelsHidden().frame(maxWidth: 112)
                Picker("Sort", selection: $model.sort) { ForEach(RowSort.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(maxWidth: 170)
                Spacer(minLength: 0)
                Menu {
                    Toggle("Show hidden items", isOn: $model.showHidden)
                    Toggle("Include package descendants in rankings", isOn: $model.includePackageContents)
                    if model.mode == .map { Toggle("Filter map to matching branches", isOn: $model.filteredMap) }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }.menuStyle(.borderlessButton).fixedSize().help("Display options")
            }.controlSize(.small)
            if model.mode != .map {
                Toggle("Search entire scan", isOn: $model.scopeIsRoot).toggleStyle(.checkbox).font(.caption)
            }
            if !model.query.isEmpty {
                HStack {
                    Text(model.isFiltering ? "Searching…" : "\(model.rows.count.formatted()) matches").foregroundStyle(.secondary)
                    Button { model.nextMatch(-1) } label: { Image(systemName: "arrow.up") }.help("Previous match")
                    Button { model.nextMatch(1) } label: { Image(systemName: "arrow.down") }.help("Next match")
                    Button("Show in Map") { if let id = model.selectedID { model.showInMap(id) } }.disabled(model.selectedID == nil)
                    Button("Clear") { model.query = "" }
                }.font(.caption).controlSize(.small)
            }
            if model.groupIDs != nil {
                HStack { Text("Smaller items in this folder").font(.caption); Button("Show all") { model.groupIDs = nil; model.refreshRows() }.font(.caption) }
            }
        }
    }
    private var scanNotice: some View {
        HStack(spacing: 10) {
            if model.isScanning { ProgressView().controlSize(.small) }
            else { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.stateLabel).font(.caption.weight(.medium))
                Text(model.isScanning ? "Results are available while sizes are still changing." : "Measured totals exclude unreadable or unvisited contents.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if (model.root?.issueCount ?? 0) > 0 { Button("\(model.root?.issueCount ?? 0) skipped") { model.showIssues = true }.controlSize(.small) }
        }.padding(9).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.6)).frame(width: 7, height: 7); Text(text).foregroundStyle(.secondary) }
    }
}

struct ResultsTable: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Group {
            if model.rows.isEmpty {
                ContentUnavailableView(model.isFiltering ? "Updating results…" : "No matching items", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try changing the size, kind, or search filters. Unknown-size items are included when no minimum size is set."))
            } else {
                Table(model.rows, selection: $model.selectedID) {
                    TableColumn("Item") { row in
                        HStack(spacing: 7) {
                            Image(systemName: row.kind == .package ? "shippingbox" : row.kind == .folder ? "folder" : row.kind == .symbolicLink ? "link" : "doc")
                                .foregroundStyle(Color(nsColor: colorForKind(row.kind, name: row.name)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).lineLimit(1)
                                if model.mode != .map || !model.query.isEmpty { Text(model.url(row.id)?.deletingLastPathComponent().path ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                            }
                            if row.partial { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).help("Partial or unknown size") }
                        }.help(model.url(row.id)?.path ?? row.name)
                    }.width(min: 170, ideal: 250)
                    TableColumn("Size") { row in Text(row.sizeText).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing) }.width(min: 75, ideal: 95, max: 125)
                    TableColumn("Relative size") { row in
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(model.denominator > 0 ? String(format: "%.1f%%", Double(row.bytes) / Double(model.denominator) * 100) : "—").font(.caption).monospacedDigit()
                            GeometryReader { proxy in
                                Capsule().fill(Color.secondary.opacity(0.4)).frame(width: proxy.size.width * min(1, Double(row.bytes) / Double(max(1, model.denominator))))
                            }.frame(height: 3)
                        }.help(model.mode == .map || !model.scopeIsRoot ? "Percentage of current folder" : "Percentage of scan root")
                    }.width(min: 70, ideal: 85, max: 110)
                    TableColumn("Kind") { row in Text(row.kind.rawValue).foregroundStyle(.secondary) }.width(min: 60, ideal: 80, max: 110)
                    TableColumn("Modified") { row in
                        if let date = row.modified { Text(date, style: .date).foregroundStyle(.secondary) } else { Text("—") }
                    }.width(min: 85, ideal: 100, max: 140)
                }
                .contextMenu(forSelectionType: Int.self) { ids in
                    if let id = ids.first { ItemActions(model: model, id: id) }
                } primaryAction: { ids in
                    if let id = ids.first { model.navigate(id) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text(model.mode == .map ? "Percentages use the current folder total." : "Folder rows may overlap; do not add ancestor and descendant sizes.")
                Spacer()
                if model.isFiltering { ProgressView().controlSize(.mini) }
            }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6)
        }
    }
}

struct ItemActions: View {
    @ObservedObject var model: AppModel
    let id: Int
    var body: some View {
        if let n = model.node(id) {
            if n.kind.isContainer { Button(n.kind == .package ? "Inspect Package Contents" : "Open Folder") { model.inspect(id) } }
            Button("Show in Map") { model.showInMap(id) }
            Divider()
            Button("Reveal in Finder") { model.reveal(id) }
            Button("Copy Path") { model.copyPath(id) }
        }
    }
}

struct InspectorView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            if let n = model.selected {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SELECTED ITEM").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    Image(systemName: n.kind == .package ? "shippingbox.fill" : n.kind == .folder ? "folder.fill" : "doc.fill")
                        .font(.system(size: 36)).foregroundStyle(Color(nsColor: colorForKind(n.kind, name: n.name))).padding(.top, 6)
                    Text(n.name).font(.headline).textSelection(.enabled)
                    Text(n.kind.rawValue + (n.cloud ? " · cloud metadata" : "")).font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.sizeLabel(model.metric)).font(.system(size: 28, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                        Text(model.metric == .allocated ? "Reported size on disk" : "Logical size").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        info("Logical", n.sizeLabel(.logical))
                        info("Allocated", n.sizeLabel(.allocated))
                        info("Items inside", n.descendantCount.formatted())
                        info("Status", model.staleIDs.contains(n.id) ? "Stale" : n.isPartial ? "Partial" : n.unknown(model.metric) > 0 ? "Unknown size" : "Complete")
                        if let modified = n.modified { info("Modified", modified.formatted(date: .abbreviated, time: .omitted)) }
                    }.font(.caption)
                    Divider()
                    Text("LOCATION").font(.caption2).foregroundStyle(.secondary)
                    Text(model.url(n.id)?.path ?? "").font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) {
                        if n.kind.isContainer { Button(n.kind == .package ? "Inspect Package Contents" : "Open Folder") { model.inspect(n.id) }.buttonStyle(.borderedProminent) }
                        Button("Show in Map") { model.showInMap(n.id) }
                        Button("Reveal in Finder") { model.reveal(n.id) }
                        Button("Copy Path") { model.copyPath(n.id) }
                    }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    if let issue = n.issue { Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    if let shared = n.sharedWith {
                        Text("Hard link: allocated bytes are attributed to \(model.url(shared)?.path ?? "another path") in this scan. This path contributes zero additional allocated bytes.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let allocated = n.reportedAllocated {
                        Text("Reported allocation: \(allocated.formatted()) bytes").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Text("Logical total: \(n.logicalBytes.formatted()) bytes").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    if n.kind == .package { Text("Package totals include scanned contents. Related application data elsewhere is excluded.").font(.caption).foregroundStyle(.secondary) }
                    if n.kind == .symbolicLink || n.kind == .other { Text("Link targets and special-file contents are not traversed or included in file-size totals.").font(.caption).foregroundStyle(.secondary) }
                    Text("Reported allocation is not guaranteed reclaimable space. Shared APFS blocks, snapshots, and filesystem overhead can make volume usage differ.").font(.caption).foregroundStyle(.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView("Select an item", systemImage: "cursorarrow.click", description: Text("Choose a tile or list row to inspect its size and location.")).padding(.top, 35)
            }
        }.frame(maxHeight: .infinity, alignment: .top).background(.background)
    }
    private func info(_ key: String, _ value: String) -> some View {
        GridRow { Text(key).foregroundStyle(.secondary); Text(value).frame(maxWidth: .infinity, alignment: .trailing) }
    }
}

struct StatusBar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            if model.isScanning { ProgressView().controlSize(.mini) }
            Text(model.stateLabel)
            if model.hasScan {
                Text("\(model.itemCount.formatted()) items")
                Text("\(model.root?.sizeLabel(model.metric) ?? "—") measured")
                Text(String(format: "%.1f s", model.elapsed)).monospacedDigit()
            }
            Spacer(minLength: 5)
            if model.isScanning { Text(model.currentPath).lineLimit(1).truncationMode(.middle).frame(maxWidth: 330).help(model.currentPath) }
            else if let finished = model.finishedAt { Text(finished, style: .time) }
            Text("Local scan").foregroundStyle(.secondary)
        }.font(.caption).padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }
}

struct IssuesView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Skipped locations").font(.title2.bold())
            Text("Unreadable contents have unknown sizes. Grant access where appropriate, then rescan. Full Disk Access does not bypass all filesystem permissions.").foregroundStyle(.secondary)
            List(model.issues) { node in
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.url(node.id)?.path ?? node.name).font(.callout).textSelection(.enabled)
                    Text(node.issue ?? "").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            HStack {
                Button("Full Disk Access Settings") { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) } }
                Spacer()
                Button("Rescan") { dismiss(); model.rescan() }.disabled(model.isScanning)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 650, height: 450)
    }
}

extension Notification.Name { static let diskMapFocusSearch = Notification.Name("diskMapFocusSearch") }
