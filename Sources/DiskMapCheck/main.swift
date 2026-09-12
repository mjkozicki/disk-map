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

do {
    let args = CommandLine.arguments
    if args.count == 3 && args[1] == "--scan" {
        let (index, result) = scan(URL(fileURLWithPath: args[2]))
        guard let root = index.nodes.first else { throw CheckFailure("No scan results") }
        print("\(result.itemCount) items in \(String(format: "%.3f", result.elapsed))s")
        print("Logical: \(root.logicalBytes) bytes; allocated: \(root.allocatedBytes) bytes; unknown allocation: \(root.unknownAllocated); issues: \(root.issueCount)")
    } else {
        try verifyCore()
        print("All core checks passed.")
    }
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
