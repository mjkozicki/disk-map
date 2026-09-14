import AppKit
import SwiftUI
import DiskMapCore

enum ExplorerMode: String, CaseIterable, Identifiable {
    case map = "Treemap", largest = "Largest Items", packages = "Bundles & Packages", cleanup = "Development Cleanup"
    var id: String { rawValue }
    var symbol: String { self == .map ? "rectangle.split.2x2" : self == .largest ? "chart.bar.xaxis" : self == .cleanup ? "trash" : "shippingbox" }
}
enum KindFilter: String, CaseIterable, Identifiable {
    case all = "All kinds", files = "Files", folders = "Folders", packages = "Packages"
    var id: String { rawValue }
}
enum RowSort: String, CaseIterable, Identifiable {
    case size = "Size, largest first", name = "Name", modified = "Recently modified"
    var id: String { rawValue }
}
struct ItemRow: Identifiable, Sendable {
    let id: Int
    let name: String
    let kind: ItemKind
    let bytes: Int64
    let sizeText: String
    let modified: Date?
    let partial: Bool
}
struct NavigationState { let folder: Int; let selection: Int?; let mode: ExplorerMode; let query: String }
struct VolumeItem: Identifiable { var id: String { url.path }; let url: URL; let name: String }

@MainActor
final class AppModel: ObservableObject {
    @Published var cleanupCandidates: [CleanupCandidate] = []
    @Published var cleanupSelection: Set<Int> = []
    @Published var cleanupReview: [CleanupCandidate] = []
    @Published var showCleanupReview = false
    @Published var isCleaning = false
    @Published var isFindingCleanup = false
    @Published var cleanupReport: CleanupResult?
    @Published var revision = 0
    @Published var dropTarget = false
    @Published var mode: ExplorerMode = .map { didSet { groupIDs = nil; refreshRows() } }
    @Published var metric: SizeMetric = .allocated { didSet { refreshRows() } }
    @Published var query = "" { didSet { scheduleSearch() } }
    @Published var kindFilter: KindFilter = .all { didSet { refreshRows() } }
    @Published var minimumSize: Int64 = 0 { didSet { refreshRows() } }
    @Published var showHidden = true { didSet { refreshRows() } }
    @Published var includePackageContents = false { didSet { refreshRows() } }
    @Published var scopeIsRoot = true { didSet { refreshRows() } }
    @Published var sort: RowSort = .size { didSet { refreshRows() } }
    @Published var filteredMap = false { didSet { refreshRows() } }
    @Published var rows: [ItemRow] = []
    @Published var selectedID: Int?
    @Published var currentID = 0
    @Published var isScanning = false
    @Published var isFiltering = false
    @Published var canceled = false
    @Published var elapsed: TimeInterval = 0
    @Published var startedAt: Date?
    @Published var finishedAt: Date?
    @Published var currentPath = ""
    @Published var message: String?
    @Published var showIssues = false
    @Published var showInspector = true
    @Published var history: [NavigationState] = []
    @Published var groupIDs: Set<Int>?
    @Published var volumes: [VolumeItem] = []
    @Published var capacity: Int64?
    @Published var available: Int64?
    @Published var staleIDs: Set<Int> = []
    private(set) var index: ScanIndex?
    private var cancellation: ScanCancellation?
    private var generation = UUID()
    private var rowGeneration = UUID()
    private var searchTask: Task<Void, Never>?
    private var lastPresentation = Date.distantPast

    init() { refreshVolumes() }
    var hasScan: Bool { index?.nodes.isEmpty == false }
    var root: DiskNode? { index?.nodes.first }
    var current: DiskNode? { node(currentID) }
    var selected: DiskNode? { selectedID.flatMap(node) }
    var itemCount: Int { max(0, (index?.nodes.count ?? 0) - 1) }
    var scopeID: Int { mode == .map || !scopeIsRoot ? currentID : 0 }
    var issues: [DiskNode] { index?.nodes.filter { $0.issue != nil } ?? [] }
    var denominator: Int64 {
        let id = (mode != .map && scopeIsRoot) ? 0 : currentID
        return node(id)?.bytes(metric) ?? 0
    }
    var stateLabel: String {
        if isCleaning { return "Moving folders to Trash…" }
        if isScanning { return "Scanning" }
        if canceled { return "Canceled · partial results" }
        if !staleIDs.isEmpty { return "Results may be stale" }
        if root?.issueCount ?? 0 > 0 { return "Completed with skipped items" }
        return hasScan ? "Scan complete" : "Ready to scan"
    }
    func node(_ id: Int) -> DiskNode? { guard let index, index.contains(id) else { return nil }; return index[id] }
    func url(_ id: Int) -> URL? { guard let index, index.contains(id) else { return nil }; return index.url(for: id) }
    func isVisible(_ id: Int) -> Bool {
        guard let index else { return false }
        if showHidden { return true }
        return !index.ancestors(of: id).dropFirst().contains { index[$0].hidden }
    }
    func refreshVolumes() {
        volumes = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsLocalKey, .volumeNameKey], options: [.skipHiddenVolumes]) ?? []).compactMap {
            let values = try? $0.resourceValues(forKeys: [.volumeIsLocalKey, .volumeNameKey])
            guard values?.volumeIsLocal == true else { return nil }
            return VolumeItem(url: $0, name: values?.volumeName ?? $0.lastPathComponent)
        }
    }
    func chooseLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder or volume to scan"
        panel.prompt = "Scan"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { startScan(url) }
    }
    func startScan(_ requestedURL: URL) {
        guard !isCleaning else { return }
        cleanupCandidates = []; cleanupSelection = []; cleanupReview = []; showCleanupReview = false
        isFindingCleanup = false
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: requestedURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            message = "Choose an existing folder or mounted volume."; return
        }
        cancellation?.cancel()
        let rootURL = requestedURL.standardizedFileURL.resolvingSymlinksInPath()
        let token = UUID(), flag = ScanCancellation()
        generation = token; cancellation = flag
        index = ScanIndex(rootURL: rootURL)
        rows = []; currentID = 0; selectedID = nil; history = []; groupIDs = nil
        query = ""; mode = .map; staleIDs = []; canceled = false; isScanning = true
        elapsed = 0; startedAt = Date(); finishedAt = nil; currentPath = rootURL.path
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: rootURL.path)
        capacity = (attrs?[.systemSize] as? NSNumber)?.int64Value
        available = (attrs?[.systemFreeSize] as? NSNumber)?.int64Value
        revision += 1
        let scoped = rootURL.startAccessingSecurityScopedResource()
        // Backpressure limits queued UI batches to two, even when traversal is very fast.
        let permits = DispatchSemaphore(value: 2)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = FileScanner.scan(root: rootURL, cancellation: flag) { batch in
                permits.wait()
                DispatchQueue.main.async { [weak self] in
                    defer { permits.signal() }
                    guard let self, self.generation == token else { return }
                    self.index?.apply(batch)
                    self.currentPath = batch.currentPath
                    self.elapsed = Date().timeIntervalSince(self.startedAt ?? Date())
                    self.revision += 1
                    if Date().timeIntervalSince(self.lastPresentation) >= 0.6 {
                        self.lastPresentation = Date(); self.refreshRows()
                    }
                }
            }
            if scoped { rootURL.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.isScanning = false; self.canceled = result.canceled
                self.elapsed = result.elapsed; self.finishedAt = Date()
                if self.selectedID == nil { self.selectedID = self.current?.children.max { (self.node($0)?.bytes(self.metric) ?? 0) < (self.node($1)?.bytes(self.metric) ?? 0) } ?? 0 }
                self.revision += 1; self.refreshRows(); self.findCleanupCandidates()
            }
        }
    }
    var selectedCleanup: [CleanupCandidate] { cleanupCandidates.filter { cleanupSelection.contains($0.id) } }
    var canReviewCleanup: Bool { !isScanning && !canceled && !isCleaning && !isFindingCleanup && !selectedCleanup.isEmpty }
    func findCleanupCandidates() {
        guard let index, !isScanning, !canceled else { return }
        let token = generation
        isFindingCleanup = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let candidates = DevelopmentCleanup.candidates(in: index)
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.cleanupCandidates = candidates; self.isFindingCleanup = false
            }
        }
    }
    func reviewCleanup() {
        guard canReviewCleanup else { return }
        cleanupReview = selectedCleanup
        showCleanupReview = true
    }
    func confirmCleanup() {
        guard !isScanning, !canceled, !isCleaning, !cleanupReview.isEmpty, let index else { return }
        let ids = Set(cleanupReview.map(\.id))
        isCleaning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scoped = index.rootURL.startAccessingSecurityScopedResource()
            let result = DevelopmentCleanup.moveToTrash(ids: ids, in: index)
            if scoped { index.rootURL.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCleaning = false; self.showCleanupReview = false
                self.cleanupReport = result
                self.startScan(index.rootURL)
                self.mode = .cleanup
            }
        }
    }
    func cancelScan() { cancellation?.cancel(); canceled = true }
    func rescan() { if let index { startScan(index.rootURL) } else { chooseLocation() } }
    func navigate(_ id: Int, inspectPackage: Bool = false) {
        guard let n = node(id), n.kind.isContainer else { selectedID = id; return }
        if n.kind == .package && !inspectPackage { selectedID = id; showInspector = true; return }
        history.append(NavigationState(folder: currentID, selection: selectedID, mode: mode, query: query))
        currentID = id; selectedID = id; groupIDs = nil; query = ""; mode = .map
        refreshRows()
    }
    func goBack() {
        guard let previous = history.popLast() else { return }
        currentID = previous.folder; selectedID = previous.selection; mode = previous.mode; query = previous.query
        groupIDs = nil; refreshRows()
    }
    func goUp() { if let parent = current?.parent { navigate(parent, inspectPackage: true) } }
    func showInMap(_ id: Int) {
        guard let index else { return }
        let target = index.enclosingPackage(of: id) ?? id
        let parent = index[target].parent ?? 0
        navigate(parent, inspectPackage: true); selectedID = target
        if target != id { message = "This item is inside \(index[target].name). Use Inspect Package Contents to open the package." }
    }
    func inspect(_ id: Int) { navigate(id, inspectPackage: true) }
    func reveal(_ id: Int) {
        guard let node = node(id), let url = url(id) else { return }
        guard let identity = FileScanner.identity(at: url), identity == node.identity else {
            staleIDs.insert(id); message = "This item moved, changed identity, or is no longer accessible. Rescan its location to update the results."; return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    func copyPath(_ id: Int) {
        guard let url = url(id) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string)
    }
    func nextMatch(_ offset: Int) {
        guard !rows.isEmpty else { return }
        let old = rows.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : 0)
        selectedID = rows[(old + offset + rows.count) % rows.count].id
        showInspector = true
    }
    func showGroup(_ ids: [Int]) { groupIDs = Set(ids); refreshRows() }
    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            self?.refreshRows()
        }
    }
    func refreshRows() {
        let ticket = UUID(); rowGeneration = ticket
        guard mode != .cleanup, let index, !index.nodes.isEmpty, index.contains(currentID) else { rows = []; isFiltering = false; return }
        isFiltering = true
        let scope = mode == .map || !scopeIsRoot ? currentID : 0
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mode = mode, metric = metric, kind = kindFilter, minimum = minimumSize
        let hidden = showHidden, includeContents = includePackageContents, order = sort, group = groupIDs
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var candidates: [Int] = []
            if let group, query.isEmpty { candidates = Array(group) }
            else if mode == .map && query.isEmpty { candidates = index[scope].children }
            else {
                var stack = Array(index[scope].children.reversed())
                while let id = stack.popLast() {
                    let n = index[id]
                    if !hidden && n.hidden { continue }
                    candidates.append(id)
                    if n.kind != .package || includeContents || !query.isEmpty {
                        stack.append(contentsOf: n.children.reversed())
                    }
                }
            }
            let result = candidates.compactMap { id -> ItemRow? in
                let n = index[id]
                guard hidden || !n.hidden else { return nil }
                guard mode != .packages || n.kind == .package else { return nil }
                guard minimum == 0 || n.bytes(metric) >= minimum else { return nil }
                if mode != .packages {
                    switch kind {
                    case .all: break
                    case .files: guard n.kind == .file || n.kind == .alias else { return nil }
                    case .folders: guard n.kind == .folder else { return nil }
                    case .packages: guard n.kind == .package else { return nil }
                    }
                }
                if !query.isEmpty && !n.name.lowercased().contains(query) && !index.url(for: id).path.lowercased().contains(query) { return nil }
                return ItemRow(id: id, name: n.name, kind: n.kind, bytes: n.bytes(metric), sizeText: n.sizeLabel(metric), modified: n.modified, partial: n.isPartial || n.unknown(metric) > 0)
            }.sorted { a, b in
                switch order {
                case .size: return a.bytes == b.bytes ? a.id < b.id : a.bytes > b.bytes
                case .name: return a.name == b.name ? a.id < b.id : a.name.localizedStandardCompare(b.name) == .orderedAscending
                case .modified: return a.modified == b.modified ? a.id < b.id : (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
                }
            }
            DispatchQueue.main.async {
                guard let self, self.rowGeneration == ticket else { return }
                self.rows = result; self.isFiltering = false
            }
        }
    }
}
