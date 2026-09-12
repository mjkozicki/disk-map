import Foundation

public typealias NodeID = Int

public enum SizeMetric: String, CaseIterable, Identifiable, Sendable {
    case allocated = "Size on disk"
    case logical = "Logical size"
    public var id: String { rawValue }
}

public enum ItemKind: String, CaseIterable, Sendable {
    case folder = "Folder", package = "Package", file = "File"
    case symbolicLink = "Symbolic link", alias = "Finder alias", other = "Other"
    public var isContainer: Bool { self == .folder || self == .package }
}

public struct FileIdentity: Hashable, Sendable {
    public let device: Int64
    public let inode: UInt64
    public init(device: Int64, inode: UInt64) { self.device = device; self.inode = inode }
}

public struct DiskNode: Identifiable, Sendable {
    public var id: NodeID
    public var parent: NodeID?
    public var name: String
    public var kind: ItemKind
    public var children: [NodeID] = []
    public var identity: FileIdentity?
    public var modified: Date?
    public var hidden = false
    public var cloud = false
    public var reportedAllocated: Int64?
    public var sharedWith: NodeID?
    public var logicalBytes: Int64 = 0
    public var allocatedBytes: Int64 = 0
    public var unknownLogical = 0
    public var unknownAllocated = 0
    public var pendingDirectories = 0
    public var issueCount = 0
    public var descendantCount = 0
    public var issue: String?

    public init(id: NodeID, parent: NodeID?, name: String, kind: ItemKind) {
        self.id = id; self.parent = parent; self.name = name; self.kind = kind
    }
    public func bytes(_ metric: SizeMetric) -> Int64 {
        metric == .allocated ? allocatedBytes : logicalBytes
    }
    public func unknown(_ metric: SizeMetric) -> Int {
        metric == .allocated ? unknownAllocated : unknownLogical
    }
    public var isPartial: Bool { pendingDirectories > 0 || issueCount > 0 }
    public func sizeLabel(_ metric: SizeMetric) -> String {
        if bytes(metric) == 0 && (unknown(metric) > 0 || isPartial) { return "Unknown" }
        return ByteFormatting.string(bytes(metric)) + ((isPartial || unknown(metric) > 0) ? "+" : "")
    }
}

public enum ScanEvent: Sendable {
    case discovered(DiskNode)
    case closed(NodeID)
    case problem(NodeID, String)
}

public struct ScanBatch: Sendable {
    public var events: [ScanEvent]
    public var currentPath: String
    public init(events: [ScanEvent], currentPath: String) { self.events = events; self.currentPath = currentPath }
}

public struct ScanResult: Sendable {
    public let canceled: Bool
    public let elapsed: TimeInterval
    public let itemCount: Int
}

/// Single-owner accumulator: scanner batches contain deltas, not whole-tree copies.
public struct ScanIndex: Sendable {
    public private(set) var nodes: [DiskNode] = []
    public let rootURL: URL
    public init(rootURL: URL) { self.rootURL = rootURL }
    public subscript(_ id: NodeID) -> DiskNode { nodes[id] }
    public func contains(_ id: NodeID) -> Bool { nodes.indices.contains(id) }
    public func url(for id: NodeID) -> URL {
        var names: [String] = [], cursor: NodeID? = id
        while let i = cursor, nodes[i].parent != nil { names.append(nodes[i].name); cursor = nodes[i].parent }
        return names.reversed().reduce(rootURL) { $0.appendingPathComponent($1) }
    }
    public func ancestors(of id: NodeID) -> [NodeID] {
        var result: [NodeID] = [], cursor: NodeID? = id
        while let i = cursor { result.append(i); cursor = nodes[i].parent }
        return result.reversed()
    }
    public func enclosingPackage(of id: NodeID, below scope: NodeID = 0) -> NodeID? {
        let lineage = ancestors(of: id)
        guard let start = lineage.firstIndex(of: scope) else { return nil }
        return lineage.dropFirst(start + 1).dropLast().first { nodes[$0].kind == .package }
    }
    public mutating func apply(_ batch: ScanBatch) {
        for event in batch.events {
            switch event {
            case .discovered(let node):
                precondition(node.id == nodes.count, "Scan batches must stay ordered")
                nodes.append(node)
                if let p = node.parent { nodes[p].children.append(node.id) }
                var cursor = node.parent
                while let p = cursor {
                    nodes[p].logicalBytes += node.logicalBytes
                    nodes[p].allocatedBytes += node.allocatedBytes
                    nodes[p].unknownLogical += node.unknownLogical
                    nodes[p].unknownAllocated += node.unknownAllocated
                    nodes[p].pendingDirectories += node.pendingDirectories
                    nodes[p].issueCount += node.issueCount
                    nodes[p].descendantCount += 1
                    cursor = nodes[p].parent
                }
            case .closed(let id):
                var cursor: NodeID? = id
                while let p = cursor { nodes[p].pendingDirectories -= 1; cursor = nodes[p].parent }
            case .problem(let id, let message):
                nodes[id].issue = message
                var cursor: NodeID? = id
                while let p = cursor { nodes[p].issueCount += 1; cursor = nodes[p].parent }
            }
        }
    }
}

public enum ByteFormatting {
    public static func string(_ bytes: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
        var n = Double(bytes), unit = 0
        while n >= 1000 && unit < units.count - 1 { n /= 1000; unit += 1 }
        return unit == 0 ? "\(bytes) bytes" : String(format: n >= 100 ? "%.0f %@" : "%.1f %@", n, units[unit])
    }
}
