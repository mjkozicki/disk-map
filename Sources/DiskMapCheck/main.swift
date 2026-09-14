import Foundation
import CoreGraphics
import DiskMapCore
import Darwin

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(message) }
}
func scan(_ root: URL, cancelAfterFirstBatch: Bool = false) -> (ScanIndex, ScanResult) {
    var index = ScanIndex(rootURL: root)
    let cancellation = ScanCancellation()
    let result = FileScanner.scan(root: root, cancellation: cancellation) { batch in
        index.apply(batch)
        if cancelAfterFirstBatch { cancellation.cancel() }
    }
    return (index, result)
}

func verifyCore() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("disk-map-check-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    func dir(_ path: String) throws { try fm.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
    func file(_ path: String, _ bytes: Int) throws { try Data(repeating: 7, count: bytes).write(to: root.appendingPathComponent(path)) }
    try dir("Example.app/Contents/Frameworks/Example.framework")
    try file("Example.app/Contents/payload", 100_000)
    try file("Example.app/Contents/Frameworks/Example.framework/code", 20_000)
    try dir("Empty")
    try file("a.bin", 10_000)
    try file(".hidden", 123)
    try fm.linkItem(at: root.appendingPathComponent("a.bin"), to: root.appendingPathComponent("z-link.bin"))
    try fm.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
    let (index, result) = scan(root)
    try require(!result.canceled, "Unexpected cancellation")
    try require(index[0].logicalBytes == 140_123, "Logical total must include every file path, including the hard link")
    try require(index[0].pendingDirectories == 0, "Completed traversal left directories pending")
    try require(index[0].issueCount == 0, "Unexpected scan errors")
    let app = index.nodes.first { $0.name == "Example.app" }!
    try require(app.kind == .package && app.logicalBytes == 120_000, "Package descendants must be counted exactly once")
    let nested = index.nodes.first { $0.name == "Example.framework" }!
    try require(nested.kind == .package && nested.logicalBytes == 20_000, "Nested packages need correct totals")
    let link = index.nodes.first { $0.name == "z-link.bin" }!
    try require(link.sharedWith != nil && link.allocatedBytes == 0, "Hard links must not duplicate allocated bytes")
    let source = index.nodes.first { $0.name == "a.bin" }!
    try require(link.sharedWith == source.id, "Hard-link attribution must follow deterministic traversal order")
    let leaves = index.nodes.filter { !$0.kind.isContainer }
    try require(leaves.reduce(Int64(0)) { $0 + $1.allocatedBytes } == index[0].allocatedBytes, "Allocated total disagrees with attributed leaf sizes")
    try require(index.nodes.first { $0.name == "loop" }?.kind == .symbolicLink, "Symlink must not be traversed")
    try require(index.nodes.first { $0.name == ".hidden" }?.hidden == true, "Hidden files must be scanned and marked")
    try require(index.url(for: nested.id).path == root.appendingPathComponent("Example.app/Contents/Frameworks/Example.framework").path, "Path reconstruction failed")
    try require(index.enclosingPackage(of: nested.id) == app.id, "Show in Map must respect outer package boundaries")
    print("PASS: real filesystem totals, packages, hard links, symlink loop, hidden files, paths")

    var synthetic = ScanIndex(rootURL: root)
    var folder = DiskNode(id: 0, parent: nil, name: "root", kind: .folder); folder.pendingDirectories = 1
    var unknown = DiskNode(id: 1, parent: 0, name: "unknown", kind: .file); unknown.logicalBytes = 900; unknown.unknownAllocated = 1
    synthetic.apply(ScanBatch(events: [.discovered(folder), .discovered(unknown), .closed(0)], currentPath: ""))
    try require(synthetic[0].allocatedBytes == 0 && synthetic[0].unknownAllocated == 1, "Unknown allocation must not become logical bytes")
    try require(synthetic[1].sizeLabel(.allocated) == "Unknown", "Unknown file must not display as zero")
    print("PASS: unavailable allocation remains unknown")

    try dir("Denied")
    try file("Denied/secret", 999)
    let denied = root.appendingPathComponent("Denied")
    try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
    let (partial, _) = scan(root)
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
    if geteuid() != 0 {
        try require(partial[0].issueCount > 0 && partial[0].logicalBytes == 140_123, "Denied directories must produce partial totals without stopping siblings")
        print("PASS: denied access produces partial results")
    } else { print("SKIP: permission denial cannot be verified as root") }

    try dir("Cancel")
    for i in 0..<2500 { try file("Cancel/f\(i)", 0) }
    let (canceled, canceledResult) = scan(root, cancelAfterFirstBatch: true)
    try require(canceledResult.canceled && !canceled.nodes.isEmpty, "Cancellation must retain discovered results")
    try require(canceled.nodes.count < 2520 && canceled[0].pendingDirectories > 0, "Canceled scan must remain incomplete")
    print("PASS: cancellation retains a partial tree")

    for count in [0, 1, 2, 9, 300] {
        let items = (0..<count).map { MapItem(id: $0, weight: Double(($0 + 1) * ($0 + 1))) }
        let bounds = CGRect(x: 5, y: 8, width: 900, height: 430)
        let tiles = TreemapLayout.layout(items, in: bounds)
        try require(tiles.count == count, "Layout lost positive-size entries")
        let sum = tiles.reduce(0.0) { $0 + $1.rect.width * $1.rect.height }
        if count > 0 { try require(abs(sum - bounds.width * bounds.height) < 0.001, "Treemap area not conserved") }
        for (i, tile) in tiles.enumerated() {
            try require(tile.rect.minX >= bounds.minX - 0.001 && tile.rect.maxX <= bounds.maxX + 0.001 && tile.rect.minY >= bounds.minY - 0.001 && tile.rect.maxY <= bounds.maxY + 0.001, "Tile outside bounds")
            let expected = count == 0 ? 0 : items[tile.id].weight / items.reduce(0) { $0 + $1.weight }
            try require(abs(tile.rect.width * tile.rect.height / (bounds.width * bounds.height) - expected) < 0.00001, "Tile area is not proportional")
            for other in tiles.dropFirst(i + 1) {
                let overlap = tile.rect.intersection(other.rect)
                try require(overlap.isNull || overlap.width * overlap.height < 0.001, "Tiles overlap")
            }
        }
        let again = TreemapLayout.layout(items.reversed(), in: bounds)
        try require(zip(tiles, again).allSatisfy { $0.id == $1.id && $0.rect == $1.rect }, "Layout must be deterministic")
    }
    let special = TreemapLayout.layout([MapItem(id: 1, weight: 0), MapItem(id: 2, weight: .nan), MapItem(id: 3, weight: 8)], in: CGRect(x: 0, y: 0, width: 100, height: 100))
    try require(special.count == 1 && special[0].id == 3, "Invalid or zero-size items must not generate rectangles")
    print("PASS: treemap proportionality, containment, non-overlap, determinism, empty/invalid input")
}

func verifyCleanup() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("disk-map-cleanup-\(UUID().uuidString)").resolvingSymlinksInPath()
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    func dir(_ path: String) throws { try fm.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
    func file(_ path: String) throws { try Data("fixture".utf8).write(to: root.appendingPathComponent(path)) }
    try dir("web/node_modules/dependency/node_modules/nested")
    try file("web/node_modules/local-edit.txt")
    try file("web/package.json")
    for path in ["web/dist", "web/build", "web/.next", "web/.nuxt", "web/.svelte-kit", "web/.parcel-cache", "web/.turbo", "python/__pycache__", "python/.pytest_cache", "python/.mypy_cache", "python/.ruff_cache", "python/.venv", "rust/target", "swift/.build", "unrelated/build", "unrelated/dist", "unrelated/target", "unrelated/.next", "unrelated/.nuxt", "unrelated/.svelte-kit", "unrelated/.parcel-cache", "unrelated/venv", "Sample.app/Contents/node_modules", ".git/node_modules", ".Trash/node_modules"] { try dir(path) }
    try file("python/.venv/pyvenv.cfg")
    try file("rust/Cargo.toml")
    try file("swift/Package.swift")
    for path in ["dotnet/bin", "dotnet/obj", "java/target", "gradle/build", "gradle/.gradle", "unrelated/bin", "unrelated/obj", "unrelated/.gradle"] { try dir(path) }
    try file("dotnet/Example.csproj")
    try file("java/pom.xml")
    try file("gradle/build.gradle.kts")
    try dir("linked")
    try fm.createSymbolicLink(at: root.appendingPathComponent("linked/node_modules"), withDestinationURL: root.appendingPathComponent("web/node_modules"))
    let (index, _) = scan(root)
    let candidates = DevelopmentCleanup.candidates(in: index)
    let paths = Set(candidates.map { $0.url.path.replacingOccurrences(of: root.path + "/", with: "") })
    try require(paths == Set(["web/node_modules", "web/dist", "web/build", "web/.next", "web/.nuxt", "web/.svelte-kit", "web/.parcel-cache", "web/.turbo", "python/__pycache__", "python/.pytest_cache", "python/.mypy_cache", "python/.ruff_cache", "python/.venv", "rust/target", "swift/.build", "dotnet/bin", "dotnet/obj", "java/target", "gradle/build", "gradle/.gradle"]), "Cleanup classification or exclusion failed: \(paths)")
    let target = candidates.first { $0.url.lastPathComponent == "node_modules" }!
    try DevelopmentCleanup.validate(target, in: index)
    for path in ["web/node_modules", "web/node_modules/dependency", "Sample.app/Contents", ".git"] {
        let (nested, _) = scan(root.appendingPathComponent(path))
        try require(DevelopmentCleanup.candidates(in: nested).isEmpty, "Cleanup must exclude generated roots and package interiors")
    }
    var partial = index
    partial.apply(ScanBatch(events: [.problem(target.id, "Fixture unreadable directory")], currentPath: ""))
    try require(!DevelopmentCleanup.candidates(in: partial).contains { $0.id == target.id }, "Partial candidate must be excluded")
    print("PASS: cleanup classification, project evidence, nested deduplication, packages, symlinks, partial folders")

    // A replaced target and a redirected ancestor must both be rejected before the mover is called.
    let original = root.appendingPathComponent("saved-dependencies")
    try fm.moveItem(at: target.url, to: original)
    try dir("web/node_modules")
    var moveCount = 0
    let replaced = DevelopmentCleanup.moveToTrash(ids: [target.id], in: index) { _ in moveCount += 1 }
    try require(replaced.failures.count == 1 && moveCount == 0, "Changed target reached the mover")
    try fm.removeItem(at: target.url)
    try fm.moveItem(at: original, to: target.url)
    let web = root.appendingPathComponent("web"), saved = root.appendingPathComponent("saved-web")
    try fm.moveItem(at: web, to: saved)
    try fm.createSymbolicLink(at: web, withDestinationURL: saved)
    let redirected = DevelopmentCleanup.moveToTrash(ids: [target.id], in: index) { _ in moveCount += 1 }
    try require(redirected.failures.count == 1 && moveCount == 0, "Symlink ancestor reached the mover")
    try fm.removeItem(at: web)
    try fm.moveItem(at: saved, to: web)
    let nestedID = index.nodes.first { $0.name == "nested" }!.id
    let rejected = DevelopmentCleanup.moveToTrash(ids: [0, nestedID], in: index) { _ in moveCount += 1 }
    try require(rejected.failures.count == 2 && moveCount == 0, "Root or nested selection reached the mover")
    print("PASS: cleanup rejects replaced targets, redirected ancestors, root and nested selections")

    let other = candidates.first { $0.url == root.appendingPathComponent("rust/target") }!
    let simulated = DevelopmentCleanup.moveToTrash(ids: [target.id, other.id], in: index) { url in
        if url == target.url { throw CocoaError(.fileWriteNoPermission) }
        try fm.moveItem(at: url, to: root.appendingPathComponent("simulated-trash"))
    }
    try require(simulated.failures.count == 1 && simulated.moved == [other.url], "One failure must not stop other selected folders")
    try require(fm.fileExists(atPath: target.url.appendingPathComponent("local-edit.txt").path), "Failed move altered original contents")
    let unavailable = DevelopmentCleanup.moveToTrash(ids: [target.id], in: index) { _ in throw CocoaError(.featureUnsupported) }
    try require(unavailable.failures.count == 1 && fm.fileExists(atPath: target.url.path), "Unavailable Trash must not fall back to deleting")
    print("PASS: cleanup reports individual failures, continues other moves, never falls back to deletion")

    // Exercise the native Trash API only on the fixture; restore it immediately for teardown.
    var trashedURL: NSURL?
    let actual = DevelopmentCleanup.moveToTrash(ids: [target.id], in: index) { url in
        try fm.trashItem(at: url, resultingItemURL: &trashedURL)
    }
    guard let trashedURL else { throw CheckFailure("Native Trash fixture failed: \(actual.failures.map(\.message))") }
    let trashPath = trashedURL as URL
    defer { try? fm.removeItem(at: trashPath) }
    try require(actual.moved == [target.url] && !fm.fileExists(atPath: target.url.path), "Native Trash did not move the selected fixture")
    try require(fm.fileExists(atPath: trashPath.appendingPathComponent("local-edit.txt").path), "Trash lost fixture contents")
    try fm.moveItem(at: trashPath, to: target.url)
    let (refreshed, _) = scan(root)
    try require(!DevelopmentCleanup.candidates(in: refreshed).contains { $0.url == other.url }, "Rescan retained moved folder")
    print("PASS: native Trash move, recoverable contents, restore, refreshed cleanup results")
}

do {
    let args = CommandLine.arguments
    if args.count == 3 && args[1] == "--scan" {
        let (index, result) = scan(URL(fileURLWithPath: args[2]))
        guard let root = index.nodes.first else { throw CheckFailure("No scan results") }
        print("\(result.itemCount) items in \(String(format: "%.3f", result.elapsed))s")
        print("Logical: \(root.logicalBytes) bytes; allocated: \(root.allocatedBytes) bytes; unknown allocation: \(root.unknownAllocated); issues: \(root.issueCount)")
    } else {
        try verifyCore()
        try verifyCleanup()
        print("All core checks passed.")
    }
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
